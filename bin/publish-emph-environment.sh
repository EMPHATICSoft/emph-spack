#!/usr/bin/env bash
# Install an EMPHATIC release, built by emph-spack-build, into the CVMFS instance.
#
# Adapted from DUNE/dune-release-configs bin/publish-dune-environment.sh. Run on the
# CVMFS publisher inside an open transaction:
#
#   cvmfs_server transaction emphatic.opensciencegrid.org
#   bin/publish-emph-environment.sh -i 12 -e emphaticsoft-v06_03_00
#   cvmfs_server publish -m "emphaticsoft-v06_03_00 (emph-spack-build #12)" emphatic.opensciencegrid.org
#
# On failure: cvmfs_server abort -f emphatic.opensciencegrid.org
#
# Packages come only from the build's signed buildcache (--cache-only), so nothing
# is compiled on the publisher, and the buildcache must be signed with a key the
# instance trusts (bin/create-emph-instance.sh).
set -euo pipefail

# default arguments
BUILD_INDEX=0
BUILD_PROCESS=emph-spack-build
SPACK_INSTANCE=/cvmfs/emphatic.opensciencegrid.org/spack/v1.1.1

USAGE="Usage: $0 -e|--env-name <name> (-i|--build-index <n> | -a|--artifacts <dir or url>)
          [-b|--build-process <jenkins job>] [-s|--spack-instance <path>]

  -i  Jenkins build number; artifacts are read from
      https://buildmaster.fnal.gov/buildmaster/job/<job>/<n>/artifact
  -a  artifact location (a directory holding env/ and bc/, or a URL) instead"
while [[ $# -gt 0 ]]; do
  case "$1" in
    -i|--build-index)    BUILD_INDEX=$2; shift 2 ;;
    -b|--build-process)  BUILD_PROCESS=$2; shift 2 ;;
    -a|--artifacts)      ARTIFACTS=$2; shift 2 ;;
    -e|--env-name)       ENV_NAME=$2; shift 2 ;;
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
if [[ -e $SPACK_INSTANCE/var/spack/environments/$ENV_NAME ]]; then
  echo "Error: environment $ENV_NAME already exists in $SPACK_INSTANCE"
  exit 1
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"; spack mirror remove --scope site emph-release >/dev/null 2>&1 || true' EXIT
fetch env/spack.lock "$TMP/spack.lock"
fetch env/spack.yaml "$TMP/spack.yaml"
fetch env/BUILD-INFO "$TMP/BUILD-INFO"

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

spack env create "$ENV_NAME" "$TMP/spack.lock"
ENV_DIR=$(spack location --env "$ENV_NAME")
spack mirror add --scope site --type binary emph-release "$BC_URL"
spack -e "$ENV_NAME" install --cache-only --include-build-deps

# Keep the release definition next to the lock for reference. It is not the
# environment's spack.yaml: that one is generated from the lock and has no git
# includes to fetch on a read-only file system.
cp "$TMP/spack.yaml" "$ENV_DIR/spack.yaml.release"
cp "$TMP/BUILD-INFO" "$ENV_DIR/BUILD-INFO"
echo "artifacts:  $ARTIFACTS" >> "$ENV_DIR/BUILD-INFO"
touch "$ENV_DIR/.cvmfscatalog"

GNUPGHOME=$SPACK_INSTANCE/opt/spack/gpg gpgconf --kill gpg-agent || true
echo "Installed $ENV_NAME in $SPACK_INSTANCE. Now: cvmfs_server publish"
