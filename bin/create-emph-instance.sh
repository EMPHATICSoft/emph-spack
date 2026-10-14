#!/usr/bin/env bash
# Create the EMPHATIC Spack instance that releases get published into. Run once
# per Spack version, on the CVMFS publisher inside an open transaction:
#
#   cvmfs_server transaction emphatic.opensciencegrid.org
#   bin/create-emph-instance.sh -p /cvmfs/emphatic.opensciencegrid.org/spack/v1.1.1 \
#       -k emph-spack.pub
#   cvmfs_server publish -m "Spack fnal-v1.1.1 instance" emphatic.opensciencegrid.org
#
# The instance is a plain fnal-vX bootstrap (--with_padding, so binaries built in a
# Jenkins workspace relocate to it) plus the emph-spack recipe repo and the public
# key that release buildcaches are signed with. It has no upstream.
set -euo pipefail

SPACK_VERSION=fnal-v1.1.1
EMPH_SPACK_REPO=https://github.com/EMPHATICSoft/emph-spack.git
EMPH_SPACK_REF=main

USAGE="Usage: $0 -p|--prefix <instance dir> -k|--gpg-pubkey <public key file>
          [-s|--spack-version <fnal-vX>] [-r|--emph-spack-ref <branch, tag or commit>]
          [--emph-spack-repo <git url>]"
while [[ $# -gt 0 ]]; do
  case "$1" in
    -p|--prefix)        PREFIX=$2; shift 2 ;;
    -k|--gpg-pubkey)    GPG_PUBKEY=$2; shift 2 ;;
    -s|--spack-version) SPACK_VERSION=$2; shift 2 ;;
    -r|--emph-spack-ref) EMPH_SPACK_REF=$2; shift 2 ;;
    --emph-spack-repo)  EMPH_SPACK_REPO=$2; shift 2 ;;
    -h|--help)          echo "$USAGE"; exit 0 ;;
    *)                  echo "Unknown option: $1"; echo "$USAGE"; exit 1 ;;
  esac
done
if [[ ! -v PREFIX || ! -v GPG_PUBKEY ]]; then
  echo "$USAGE"
  exit 1
fi
if [[ -e $PREFIX/setup-env.sh ]]; then
  echo "Error: $PREFIX already holds a Spack instance"
  exit 1
fi
GPG_PUBKEY=$(realpath "$GPG_PUBKEY")

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
curl -fsSL -o "$TMP/bootstrap" \
  "https://github.com/FNALssi/fermi-spack-tools/raw/refs/heads/$SPACK_VERSION/bin/bootstrap"
bash "$TMP/bootstrap" --with_padding "$PREFIX"
# shellcheck disable=SC1091
source "$PREFIX/setup-env.sh"

spack mirror add --scope site --type source scisoft_mirror_source \
  https://scisoft.fnal.gov/scisoft/spack-mirror/spack-packages/sources

# Recipes: a clone inside the instance, so it is published with it. The publish
# script moves it to the commit each release was built with.
git clone -q "$EMPH_SPACK_REPO" "$PREFIX/var/spack/repos/emph-spack"
git -C "$PREFIX/var/spack/repos/emph-spack" checkout -q "$EMPH_SPACK_REF"
spack repo add --scope site "$PREFIX/var/spack/repos/emph-spack/spack_repo/emph"

spack gpg trust "$GPG_PUBKEY"
GNUPGHOME=$PREFIX/opt/spack/gpg gpgconf --kill gpg-agent || true

# Nested CVMFS catalogs: one for the install tree, one per environment.
mkdir -p "$PREFIX/opt/spack" "$PREFIX/var/spack/environments"
touch "$PREFIX/opt/spack/.cvmfscatalog" "$PREFIX/var/spack/environments/.cvmfscatalog"

spack gpg list
echo "Instance ready at $PREFIX. Now: cvmfs_server publish"
