#!/usr/bin/env bash
# Build the EMPHATIC Spack release environment and push it to a signed buildcache.
#
# Adapted from DUNE/dune-release-configs bin/build-dune-environment.sh. This is the
# body of the Jenkins job emph-spack-build, and it runs the same way by hand on any
# AlmaLinux 9 host (or the emphatic-el9-spack image).
#
# Everything goes in the workspace:
#   spack/       throwaway fnal-vX instance, bootstrapped --with_padding
#   env/         spack.yaml + spack.lock       (Jenkins artifacts)
#   bc/          signed buildcache             (Jenkins artifact)
#   timing.txt   seconds per step              (Jenkins artifact)
#
# The recipes and the release environment come from the emph-spack checkout this
# script lives in, so the build matches whatever commit Jenkins checked out.
#
# Publishing on CVMFS is a separate step: bin/publish-emph-environment.sh.
set -euo pipefail

# default arguments
SPACK_VERSION=fnal-v1.1.1
ENV_NAME=emph-v1.1.1
EMPH_SPACK_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
JOBS=
EMPH_GIT=

USAGE="Usage: $0 -w|--workspace <path> [-k|--gpg-key <secret key file>]
          [-s|--spack-version <fnal-vX>] [-e|--env <environment dir name>]
          [-j|--jobs <n>] [--emphaticsoft-git <url>]

  --gpg-key           exported private key to sign with (Jenkins credential file).
                      Without it the build runs but nothing is pushed.
  --emphaticsoft-git  fetch emphaticsoft from this URL instead of the recipe's,
                      e.g. file:///path/to/clone to build unpushed commits."
while [[ $# -gt 0 ]]; do
  case "$1" in
    -w|--workspace)     WORKSPACE=$2; shift 2 ;;
    -s|--spack-version) SPACK_VERSION=$2; shift 2 ;;
    -k|--gpg-key)       GPG_KEY=$2; shift 2 ;;
    -e|--env)           ENV_NAME=$2; shift 2 ;;
    -j|--jobs)          JOBS=$2; shift 2 ;;
    --emphaticsoft-git) EMPH_GIT=$2; shift 2 ;;
    -h|--help)          echo "$USAGE"; exit 0 ;;
    *)                  echo "Unknown option: $1"; echo "$USAGE"; exit 1 ;;
  esac
done

if [[ ! -v WORKSPACE ]]; then
  echo "Error: workspace directory not specified!"
  echo "$USAGE"
  exit 1
fi
if [[ ! -f $EMPH_SPACK_DIR/environments/$ENV_NAME/spack.yaml ]]; then
  echo "Error: no environments/$ENV_NAME/spack.yaml in $EMPH_SPACK_DIR"
  exit 1
fi

SPACK_ROOT=$WORKSPACE/spack
SPACK_ENV_DIR=$WORKSPACE/env
BUILDCACHE=$WORKSPACE/bc
TIMING=$WORKSPACE/timing.txt
export TMPDIR=$WORKSPACE/tmp
mkdir -p "$WORKSPACE" "$TMPDIR"
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

configure() {
  spack mirror add --scope site --type source scisoft_mirror_source \
    https://scisoft.fnal.gov/scisoft/spack-mirror/spack-packages/sources
  spack repo add --scope site "$EMPH_SPACK_DIR/spack_repo/emph"

  mkdir -p "$SPACK_ENV_DIR"
  cp "$EMPH_SPACK_DIR/environments/$ENV_NAME/spack.yaml" "$SPACK_ENV_DIR/spack.yaml"
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
    echo "host:       $(hostname) $(. /etc/os-release && echo "$PRETTY_NAME")"
    echo "date:       $(date -u '+%F %T UTC')"
  } > "$SPACK_ENV_DIR/BUILD-INFO"
}

install() {
  spack -e "$SPACK_ENV_DIR" install --fail-fast ${JOBS:+-j "$JOBS"}
}

push() {
  spack gpg trust "$GPG_KEY"
  spack -e "$SPACK_ENV_DIR" buildcache push --signed --with-build-dependencies --private \
    ${JOBS:+-j "$JOBS"} "$BUILDCACHE"
  spack gpg publish -d "$BUILDCACHE" --update-index
  spack buildcache update-index "$BUILDCACHE"
  # gpg-agent outlives the build otherwise and keeps the Jenkins step (or container) open
  GNUPGHOME=$SPACK_ROOT/opt/spack/gpg gpgconf --kill gpg-agent || true
}

: > "$TIMING"
step bootstrap bootstrap
# shellcheck disable=SC1091
source "$SPACK_ROOT/setup-env.sh"
step configure configure
step concretize spack -e "$SPACK_ENV_DIR" --disable-locks concretize
spack -e "$SPACK_ENV_DIR" find -c > "$SPACK_ENV_DIR/concretized.txt" || true
step install install

if [[ ! -v GPG_KEY ]]; then
  echo "No GPG key specified, skipping the push to the buildcache"
  exit 0
fi
step push push
du -sh "$BUILDCACHE" | tee -a "$TIMING"
