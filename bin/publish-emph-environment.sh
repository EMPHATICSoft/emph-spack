#!/usr/bin/env bash
# Install an EMPHATIC release, built by emph-spack-build, into the CVMFS instance.
#
# Adapted from DUNE/dune-release-configs bin/publish-dune-environment.sh. Run on the
# CVMFS publisher inside an open transaction:
#
#   cvmfs_server transaction emphatic.opensciencegrid.org
#   bin/publish-emph-environment.sh -i 12 -e emph-deps-v08_00_00 -l emph-deps-env
#   cvmfs_server publish -m "emph-deps-v08_00_00 (emph-spack-build #12)" emphatic.opensciencegrid.org
#
# On failure: cvmfs_server abort -f emphatic.opensciencegrid.org
#
# Packages come only from the build's signed buildcache (--cache-only), so nothing
# is compiled on the publisher, and the buildcache must be signed with a key the
# instance trusts (bin/create-emph-instance.sh).
#
# If the build used upstreams (build-emph-environment.sh --upstream), they are added
# to the instance's etc/spack/upstreams.yaml, and the specs installed there are not
# copied. `spack subspack` copies that file, so developer areas see them too.
#
# --link points a fixed name (emph-deps-env) at the new environment, so users and
# docs can use one path for the current release while older ones stay installed.
set -euo pipefail

# default arguments
BUILD_INDEX=0
BUILD_PROCESS=emph-spack-build
SPACK_INSTANCE=/cvmfs/emphatic.opensciencegrid.org/spack/v1.1.1

USAGE="Usage: $0 -e|--env-name <name> (-i|--build-index <n> | -a|--artifacts <dir or url>)
          [-l|--link <name>] [-b|--build-process <jenkins job>] [-s|--spack-instance <path>]

  -i  Jenkins build number; artifacts are read from
      https://buildmaster.fnal.gov/buildmaster/job/<job>/<n>/artifact
  -a  artifact location (a directory holding env/ and bc/, or a URL) instead
  -l  make environments/<name> a symlink to the new environment (e.g. emph-deps-env)"
while [[ $# -gt 0 ]]; do
  case "$1" in
    -i|--build-index)    BUILD_INDEX=$2; shift 2 ;;
    -b|--build-process)  BUILD_PROCESS=$2; shift 2 ;;
    -a|--artifacts)      ARTIFACTS=$2; shift 2 ;;
    -e|--env-name)       ENV_NAME=$2; shift 2 ;;
    -l|--link)           LINK_NAME=$2; shift 2 ;;
    -s|--spack-instance) SPACK_INSTANCE=$2; shift 2 ;;
    -h|--help)           echo "$USAGE"; exit 0 ;;
    *)                   echo "Unknown option: $1"; echo "$USAGE"; exit 1 ;;
  esac
done

if [[ ! -v ENV_NAME ]]; then
  echo "Error: must name the installed environment"
  echo "$USAGE"
  exit 1
fi
if [[ ! $ENV_NAME =~ ^[A-Za-z0-9_][A-Za-z0-9_-]*$ ]]; then
  echo "Error: Spack environment names may only use letters, digits, _ and - (no dots)"
  exit 1
fi
if [[ -v LINK_NAME && ! $LINK_NAME =~ ^[A-Za-z0-9_][A-Za-z0-9_-]*$ ]]; then
  echo "Error: bad link name $LINK_NAME"
  exit 1
fi
if [[ ! -v ARTIFACTS ]]; then
  if (( BUILD_INDEX < 1 )); then
    echo "Error: give a Jenkins build index (-i) or an artifact location (-a)"
    exit 1
  fi
  ARTIFACTS=https://buildmaster.fnal.gov/buildmaster/job/$BUILD_PROCESS/$BUILD_INDEX/artifact
fi

# fetch <relative path> <dest>: copy one artifact from a directory or a URL
fetch() {
  case $ARTIFACTS in
    http*) curl -fsSL -o "$2" "$ARTIFACTS/$1" ;;
    *)     cp "$ARTIFACTS/$1" "$2" ;;
  esac
}
case $ARTIFACTS in
  http*) BC_URL=$ARTIFACTS/bc ;;
  *)     BC_URL=file://$(realpath "$ARTIFACTS")/bc ;;
esac

# shellcheck disable=SC1091
source "$SPACK_INSTANCE/setup-env.sh"
ENVS=$SPACK_INSTANCE/var/spack/environments
if [[ -e $ENVS/$ENV_NAME ]]; then
  echo "Error: environment $ENV_NAME already exists in $SPACK_INSTANCE"
  exit 1
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"; spack mirror remove --scope site emph-release >/dev/null 2>&1 || true' EXIT
fetch env/spack.lock "$TMP/spack.lock"
fetch env/spack.yaml "$TMP/spack.yaml"
fetch env/BUILD-INFO "$TMP/BUILD-INFO"
fetch env/install-specs.txt "$TMP/install-specs.txt"

# Move the instance's recipes to the commit the release was built with: binaries
# come from the buildcache, but spack load still runs the recipes' setup code.
EMPH_SPACK_COMMIT=$(awk '/^emph-spack:/ {print $2}' "$TMP/BUILD-INFO")
if grep -q '(dirty)' "$TMP/BUILD-INFO"; then
  echo "Error: the build used uncommitted emph-spack changes; not publishing it"
  exit 1
fi
REPO=$SPACK_INSTANCE/var/spack/repos/emph-spack
git -C "$REPO" fetch -q origin
git -C "$REPO" checkout -q "$EMPH_SPACK_COMMIT"

# Upstreams the build reused from: add any the instance lacks, before Spack reads
# its configuration for the install.
UPSTREAMS_FILE=$SPACK_INSTANCE/etc/spack/upstreams.yaml
for u in $(awk '/^upstreams:/ {for (i = 2; i <= NF; i++) if ($i != "none") print $i}' "$TMP/BUILD-INFO"); do
  # The build may have used this instance's own install tree as an upstream.
  [[ $u == "$SPACK_INSTANCE"/* ]] && continue
  if [[ ! -f $u/.spack-db/index.json ]]; then
    echo "Error: upstream $u has no Spack database (is CVMFS mounted?)"
    exit 1
  fi
  if ! grep -qs "install_tree: $u\$" "$UPSTREAMS_FILE"; then
    [[ -s $UPSTREAMS_FILE ]] || echo "upstreams:" > "$UPSTREAMS_FILE"
    printf '  %s:\n    install_tree: %s\n' "$(echo "$u" | tr -c 'A-Za-z0-9\n' _)" "$u" >> "$UPSTREAMS_FILE"
    echo "Added upstream $u to $UPSTREAMS_FILE"
  fi
done

spack env create "$ENV_NAME" "$TMP/spack.lock"
ENV_DIR=$(spack location --env "$ENV_NAME")
spack mirror add --scope site --type binary emph-release "$BC_URL"
# Only what the build pushed: for a dependencies-only release (built --without
# emphaticsoft) the emphaticsoft root stays in the environment, not installed.
mapfile -t INSTALL_SPECS < <(awk '{print "/" $2}' "$TMP/install-specs.txt")
spack -e "$ENV_NAME" install --cache-only --include-build-deps "${INSTALL_SPECS[@]}"

# Keep the release definition next to the lock for reference. It is not the
# environment's spack.yaml: that one is generated from the lock and has no git
# includes to fetch on a read-only file system.
cp "$TMP/spack.yaml" "$ENV_DIR/spack.yaml.release"
cp "$TMP/BUILD-INFO" "$TMP/install-specs.txt" "$ENV_DIR/"
echo "artifacts:  $ARTIFACTS" >> "$ENV_DIR/BUILD-INFO"
touch "$ENV_DIR/.cvmfscatalog"

if [[ -v LINK_NAME ]]; then
  if [[ -e $ENVS/$LINK_NAME && ! -L $ENVS/$LINK_NAME ]]; then
    echo "Error: $ENVS/$LINK_NAME exists and is not a symlink; not replacing it"
    exit 1
  fi
  ln -sfn "$ENV_NAME" "$ENVS/$LINK_NAME"
  echo "$LINK_NAME -> $ENV_NAME"
fi

GNUPGHOME=$SPACK_INSTANCE/opt/spack/gpg gpgconf --kill gpg-agent || true
echo "Installed $ENV_NAME in $SPACK_INSTANCE. Now: cvmfs_server publish"
