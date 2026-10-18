#!/usr/bin/env bash
# Build an EMPHATIC Spack environment and push it to a signed buildcache.
#
# Adapted from DUNE/dune-release-configs bin/build-dune-environment.sh. This is the
# body of the Jenkins job emph-spack-build (a freestyle job, like dune-spack-build):
#
#   wget -O build-emph-environment.sh \
#     https://raw.githubusercontent.com/EMPHATICSoft/emph-spack/refs/heads/$EMPH_SPACK_REF/bin/build-emph-environment.sh
#   bash ./build-emph-environment.sh -w "$WORKSPACE" -r "$EMPH_SPACK_REF" -e "$EMPH_ENV" \
#     -s "$SPACK_VERSION" -k "$EMPH_GPG_KEY" ${WITHOUT:+--without "$WITHOUT"}
#
# with artifacts env/**, bc/**, timing.txt. It runs the same way by hand on any
# AlmaLinux 9 host (or the emphatic-el9-spack image), from a checkout or standalone.
#
# Everything goes in the workspace:
#   emph-spack/  recipes and environments at --emph-spack-ref (standalone runs only)
#   spack/       throwaway fnal-vX instance, bootstrapped --with_padding
#   env/         spack.yaml, spack.lock, BUILD-INFO, install-specs.txt   (artifacts)
#   bc/          signed buildcache                                       (artifact)
#   timing.txt   seconds per step                                        (artifact)
#
# --without emphaticsoft builds the dependencies-only release: the environment is
# concretized with emphaticsoft, so every dependency has the version and variants
# emphaticsoft needs, but emphaticsoft itself is not built, pushed or published.
#
# --upstream adds an existing install tree (on CVMFS) as a Spack upstream. Specs
# installed there are reused, not pushed, and the publish script adds the same
# upstream to the CVMFS instance. An environment can list its upstreams, one per
# line, in environments/<env>/upstreams.txt: the release environment uses LArSoft's
# spack-fnal-v1.1.1 tree for py-torch and CUDA (+ml), about 7 GB we do not copy.
#
# --recipes-from (default: the EMPHATIC CVMFS instance) checks out every recipe repo
# of the new instance (builtin, fnal_art, ...) at the commit the same repo has
# there. The bootstrap clones them at branch heads, which move: on 2026-10-16
# fermi-spack-tools switched builtin from spack-packages fnal-v2026.03.0 to
# fnal-v2026.10.0, which changed every hash and would rebuild the art stack. The
# instance also runs its own copies of these recipes at `spack load`, so the build
# must match them. --recipes-from none keeps the branch heads.
#
# A release can be built on top of an earlier one: environments/<env>/base-lock.txt
# names the earlier release's spack.lock. The environment is then created from that
# lock and only the roots listed after the path (default emphaticsoft) are solved
# again, with their specs from spack.yaml. Re-solving the whole spack.yaml never
# reproduces the base (the solver breaks ties differently and rebuilds parts of the
# art stack), while from the lock everything else keeps its hash.
#
# Publishing on CVMFS is a separate step: bin/publish-emph-environment.sh.
set -euo pipefail

# default arguments
SPACK_VERSION=fnal-v1.1.1
ENV_NAME=emph-v1.1.1
EMPH_SPACK_REPO=${EMPH_SPACK_REPO:-https://github.com/EMPHATICSoft/emph-spack.git}
JOBS=
EMPH_GIT=
RECIPES_FROM=/cvmfs/emphatic.opensciencegrid.org/spack/v1.1.1
# Jenkins exports job parameters as environment variables, so a WITHOUT parameter
# counts even if the shell step does not pass --without. Resetting it here used to
# drop it silently and build emphaticsoft anyway (emph-spack-build #4).
WITHOUT=${WITHOUT:-}
UPSTREAMS=${UPSTREAMS:-}

USAGE="Usage: $0 -w|--workspace <path> [-k|--gpg-key <secret key file>]
          [-r|--emph-spack-ref <branch, tag or commit>] [-e|--env <environments/ dir>]
          [-s|--spack-version <fnal-vX>] [--without <package>] [-j|--jobs <n>]
          [-u|--upstream <install tree>] [--recipes-from <instance>|none]
          [--emphaticsoft-git <url>]

  --gpg-key           exported private key to sign with (Jenkins credential file).
                      Without it the build runs but nothing is pushed.
  --emph-spack-ref    clone emph-spack at this ref into the workspace. Default: use
                      the checkout this script is in, or main if run standalone.
  --without           concretize with this root but do not build it (repeatable).
  --upstream          reuse this install tree as a Spack upstream (repeatable);
                      what is installed there is not built or pushed.
  --recipes-from      Spack instance whose recipe repo commits to use (default
                      $RECIPES_FROM), or none.
  --emphaticsoft-git  fetch emphaticsoft from this URL instead of the recipe's,
                      e.g. file:///path/to/clone to build unpushed commits."
while [[ $# -gt 0 ]]; do
  case "$1" in
    -w|--workspace)      WORKSPACE=$2; shift 2 ;;
    -s|--spack-version)  SPACK_VERSION=$2; shift 2 ;;
    -k|--gpg-key)        GPG_KEY=$2; shift 2 ;;
    -r|--emph-spack-ref) EMPH_SPACK_REF=$2; shift 2 ;;
    -e|--env)            ENV_NAME=$2; shift 2 ;;
    -j|--jobs)           JOBS=$2; shift 2 ;;
    --without)           WITHOUT="$WITHOUT $2"; shift 2 ;;
    -u|--upstream)       UPSTREAMS="$UPSTREAMS $2"; shift 2 ;;
    --emphaticsoft-git)  EMPH_GIT=$2; shift 2 ;;
    --recipes-from)      RECIPES_FROM=$2; shift 2 ;;
    -h|--help)           echo "$USAGE"; exit 0 ;;
    *)                   echo "Unknown option: $1"; echo "$USAGE"; exit 1 ;;
  esac
done

# --without may repeat a package that $WITHOUT already names
WITHOUT=$(printf '%s\n' $WITHOUT | sort -u | paste -sd' ')
echo "Building environments/$ENV_NAME with $SPACK_VERSION${WITHOUT:+, without $WITHOUT}"

if [[ ! -v WORKSPACE ]]; then
  echo "Error: workspace directory not specified!"
  echo "$USAGE"
  exit 1
fi
mkdir -p "$WORKSPACE"
WORKSPACE=$(realpath "$WORKSPACE")

# Recipes: the checkout this script is in, unless a ref is asked for or the script
# was fetched on its own (the Jenkins job wgets it, as DUNE's does).
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
if [[ ! -v EMPH_SPACK_REF && -d $HERE/spack_repo/emph ]]; then
  EMPH_SPACK_DIR=$HERE
else
  EMPH_SPACK_DIR=$WORKSPACE/emph-spack
  rm -rf "$EMPH_SPACK_DIR"
  git clone -q "$EMPH_SPACK_REPO" "$EMPH_SPACK_DIR"
  git -C "$EMPH_SPACK_DIR" checkout -q "${EMPH_SPACK_REF:-main}"
fi
if [[ ! -f $EMPH_SPACK_DIR/environments/$ENV_NAME/spack.yaml ]]; then
  echo "Error: no environments/$ENV_NAME/spack.yaml in $EMPH_SPACK_DIR"
  exit 1
fi
if [[ -f $EMPH_SPACK_DIR/environments/$ENV_NAME/upstreams.txt ]]; then
  UPSTREAMS="$UPSTREAMS $(grep -v '^ *#' "$EMPH_SPACK_DIR/environments/$ENV_NAME/upstreams.txt" || true)"
fi
UPSTREAMS=$(printf '%s\n' $UPSTREAMS | sort -u | paste -sd' ')
for u in $UPSTREAMS; do
  echo "Upstream: $u"
  if [[ ! -f $u/.spack-db/index.json ]]; then
    echo "Error: upstream $u has no Spack database (is CVMFS mounted?)"
    exit 1
  fi
done

SPACK_ROOT=$WORKSPACE/spack
SPACK_ENV_DIR=$WORKSPACE/env
BUILDCACHE=$WORKSPACE/bc
TIMING=$WORKSPACE/timing.txt
# Spack clones git includes (art-release-configs, fife-release-configs) into
# $TMPDIR/$USER/includes and reuses them across runs even after the branch moves.
# DUNE's Jenkins job deletes /tmp/*/included_yaml for this reason; keeping TMPDIR in
# a workspace that starts empty does the same.
export TMPDIR=$WORKSPACE/tmp
rm -rf "$SPACK_ROOT" "$SPACK_ENV_DIR" "$BUILDCACHE" "$TMPDIR" "$TIMING"
mkdir -p "$TMPDIR"
cd "$WORKSPACE"

# step <name> <command...>: run a step and record how long it took
step() {
  local name=$1; shift
  local t0=$SECONDS
  echo "=== $(date '+%F %T') $name"
  "$@"
  printf '%-14s %6d s\n' "$name" $((SECONDS - t0)) | tee -a "$TIMING"
}

bootstrap() {
  curl -fsSL -o bootstrap \
    "https://github.com/FNALssi/fermi-spack-tools/raw/refs/heads/$SPACK_VERSION/bin/bootstrap"
  bash ./bootstrap --with_padding "$SPACK_ROOT"
}

# Check out each recipe repo of the new instance at the commit it has in $RECIPES_FROM.
pin_recipes() {
  local repo name commit
  for repo in "$SPACK_ROOT"/var/spack/repos/*/; do
    name=$(basename "$repo")
    [[ -d $repo/.git ]] || continue
    commit=$(git -c safe.directory='*' -C "$RECIPES_FROM/var/spack/repos/$name" rev-parse HEAD 2>/dev/null) || {
      echo "Error: no recipe repo $name in $RECIPES_FROM"
      return 1
    }
    git -C "$repo" fetch -q origin "$commit" 2>/dev/null || git -C "$repo" fetch -q origin
    git -C "$repo" checkout -q "$commit"
    printf 'recipes:    %s %s\n' "$name" "$commit" >> "$SPACK_ENV_DIR/BUILD-INFO.recipes"
  done
}

configure() {
  spack mirror add --scope site --type source scisoft_mirror_source \
    https://scisoft.fnal.gov/scisoft/spack-mirror/spack-packages/sources
  spack repo add --scope site "$EMPH_SPACK_DIR/spack_repo/emph"
  mkdir -p "$SPACK_ENV_DIR"
  if [[ $RECIPES_FROM != none ]]; then
    pin_recipes
  fi
  if [[ -n $UPSTREAMS ]]; then
    {
      echo "upstreams:"
      for u in $UPSTREAMS; do
        printf '  %s:\n    install_tree: %s\n' "$(echo "$u" | tr -c 'A-Za-z0-9\n' _)" "$u"
      done
    } > "$SPACK_ROOT/etc/spack/upstreams.yaml"
  fi

  mkdir -p "$SPACK_ENV_DIR"
  local release=$EMPH_SPACK_DIR/environments/$ENV_NAME
  if [[ -f $release/base-lock.txt ]]; then
    read -r BASE_LOCK RESOLVE < <(grep -v '^ *#' "$release/base-lock.txt" | head -1)
    RESOLVE=${RESOLVE:-emphaticsoft}
    spack env create -d "$SPACK_ENV_DIR" "$BASE_LOCK"
    cp "$release/spack.yaml" "$SPACK_ENV_DIR/spack.yaml.release"
  else
    cp "$release/spack.yaml" "$SPACK_ENV_DIR/spack.yaml"
  fi
  if [[ -n $EMPH_GIT ]]; then
    # From a file: `config add a:b:URL` would split the URL at its colons.
    printf 'packages:\n  emphaticsoft:\n    package_attributes:\n      git: "%s"\n' "$EMPH_GIT" \
      > "$TMPDIR/emphaticsoft-git.yaml"
    spack -e "$SPACK_ENV_DIR" config add -f "$TMPDIR/emphaticsoft-git.yaml"
  fi
  # Provenance, so the lock can be traced back to the recipes it was solved with.
  {
    echo "emph-spack: $(git -C "$EMPH_SPACK_DIR" rev-parse HEAD)$(git -C "$EMPH_SPACK_DIR" diff --quiet || echo ' (dirty)')"
    echo "spack:      $SPACK_VERSION $(git -C "$SPACK_ROOT" rev-parse HEAD)"
    echo "env:        environments/$ENV_NAME${WITHOUT:+, without $WITHOUT}"
    echo "upstreams:  ${UPSTREAMS:-none}"
    echo "recipes-from: $RECIPES_FROM"
    echo "base-lock:  ${BASE_LOCK:-none}${BASE_LOCK:+, re-solving $RESOLVE}"
    cat "$SPACK_ENV_DIR/BUILD-INFO.recipes" 2>/dev/null && rm -f "$SPACK_ENV_DIR/BUILD-INFO.recipes"
    echo "host:       $(hostname) $(. /etc/os-release && echo "$PRETTY_NAME")"
    echo "date:       $(date -u '+%F %T UTC')"
  } > "$SPACK_ENV_DIR/BUILD-INFO"
}

concretize() {
  if [[ -v BASE_LOCK ]]; then
    local specs
    mapfile -t specs < <(spack python "$EMPH_SPACK_DIR/bin/rebase-env.py" \
      "$SPACK_ENV_DIR/spack.yaml" "$SPACK_ENV_DIR/spack.yaml.release" $RESOLVE)
    [[ ${#specs[@]} -gt 0 ]] || return 1
    spack -e "$SPACK_ENV_DIR" remove $RESOLVE
    spack -e "$SPACK_ENV_DIR" --disable-locks concretize
    spack -e "$SPACK_ENV_DIR" add "${specs[@]}"
  fi
  spack -e "$SPACK_ENV_DIR" --disable-locks concretize
  spack -e "$SPACK_ENV_DIR" find -c > "$SPACK_ENV_DIR/concretized.txt" || true
  # What to install, push and publish, as "<name> <hash>" lines.
  WITHOUT=$WITHOUT spack -e "$SPACK_ENV_DIR" python "$EMPH_SPACK_DIR/bin/select-install-specs.py" \
    > "$SPACK_ENV_DIR/install-specs.txt"
  mapfile -t INSTALL_SPECS < <(awk '{print "/" $2}' "$SPACK_ENV_DIR/install-specs.txt")
}

# The specs to push: the install specs and all their dependencies, as
# --with-build-dependencies would give, minus externals and what the upstreams have.
push_specs() {
  spack -e "$SPACK_ENV_DIR" python "$EMPH_SPACK_DIR/bin/select-push-specs.py" \
    "$SPACK_ENV_DIR/install-specs.txt"
}

install() {
  spack -e "$SPACK_ENV_DIR" install --fail-fast ${JOBS:+-j "$JOBS"} "${INSTALL_SPECS[@]}"
}

push() {
  spack gpg trust "$GPG_KEY"
  mapfile -t PUSH_SPECS < <(push_specs)
  echo "Pushing ${#PUSH_SPECS[@]} specs"
  spack -e "$SPACK_ENV_DIR" buildcache push --signed --only package --private \
    ${JOBS:+-j "$JOBS"} "$BUILDCACHE" "${PUSH_SPECS[@]}"
  spack gpg publish -d "$BUILDCACHE" --update-index
  spack buildcache update-index "$BUILDCACHE"
  # gpg-agent outlives the build otherwise and keeps the Jenkins step (or container) open
  GNUPGHOME=$SPACK_ROOT/opt/spack/gpg gpgconf --kill gpg-agent || true
}

step bootstrap bootstrap
# shellcheck disable=SC1091
source "$SPACK_ROOT/setup-env.sh"
step configure configure
step concretize concretize
step install install

if [[ ! -v GPG_KEY ]]; then
  echo "No GPG key specified, skipping the push to the buildcache"
  exit 0
fi
step push push
du -sh "$BUILDCACHE" | tee -a "$TIMING"
