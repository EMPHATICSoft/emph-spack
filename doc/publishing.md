# Publishing a release to CVMFS

Releases live in the Spack instance at
`/cvmfs/emphatic.opensciencegrid.org/spack/v1.1.1`. Jenkins (`emph-spack-build`)
builds them; a person publishes them from the CVMFS publisher, `oasiscfs05`, as
`cvmfsemphatic`.

Names: the versioned environment is `emphaticsoft-vXX_YY_ZZ` (Spack environment
names cannot contain dots), and `emphaticsoft-env` is a symlink to the current
release. Pick the name before publishing. Once it is on CVMFS, people put it in
scripts and it cannot be taken back.

## 1. Check the Jenkins build

From the build's artifacts:

- `env/BUILD-INFO` names the emph-spack commit you expect, and not `(dirty)`.
- `env/install-specs.txt` lists only what is new. For a release built on the
  previous lock this is a handful of specs (#6: emphaticsoft, llvm-openmp,
  millepede). Dozens means the base was rebuilt, usually because `/cvmfs/emphatic`
  or `/cvmfs/larsoft` was not mounted on the Jenkins node.
- The build ran with `-k`, so the buildcache is signed. `--cache-only` rejects
  unsigned specs.

## 2. Install inside a transaction

Use the publish script from the commit you are releasing. The instance's own clone,
`$I/var/spack/repos/emph-spack/bin/`, is at the previous release's commit until this
publish moves it. Keep the scripts outside `/cvmfs`.

```bash
mkdir -p ~/emph-bin && cd ~/emph-bin
curl -4 -fLO https://raw.githubusercontent.com/EMPHATICSoft/emph-spack/main/bin/publish-emph-environment.sh
chmod +x publish-emph-environment.sh

cvmfs_server transaction emphatic.opensciencegrid.org
~/emph-bin/publish-emph-environment.sh -i <build> -e emphaticsoft-vXX_YY_ZZ -l emphaticsoft-env
```

`-4` because oasiscfs05's IPv6 connections to buildmaster are refused. The
`linkcount > 1 ... break up these hardlinks` warnings are harmless.

## 3. Test before publishing

Nothing is visible to clients until `cvmfs_server publish`, so test in the
transaction:

```bash
I=/cvmfs/emphatic.opensciencegrid.org/spack/v1.1.1
source $I/setup-env.sh
ls -l $I/var/spack/environments/      # the link points at the new environment
spack env activate emphaticsoft-env
spack find -l emphaticsoft
spack load emphaticsoft && art --print-available=module | grep -i arich
spack env deactivate
```

To change anything, including the name, abort and start again. Do not rename an
environment directory by hand: its view symlink holds an absolute path with the
name in it.

```bash
cd ~
cvmfs_server abort -f emphatic.opensciencegrid.org
```

## 4. Publish and tag

`publish` refuses to run while any shell has its working directory inside the
repository, so `cd ~` first.

```bash
cd ~
cvmfs_server publish -a emphaticsoft-vXX_YY_ZZ -m "emphaticsoft-vXX_YY_ZZ (emph-spack-build #<build>)" \
    emphatic.opensciencegrid.org
```

`-a` names the tag. Without it you get an automatic `generic-<date>` tag. To name a
revision that is already published, tag its root catalog hash (step 5), not its
revision number. In `cvmfs_server tag`, `-r` means remove, so `-a NAME -r 128` is
rejected as "Ambiguous parameters".

```bash
cvmfs_server tag -l emphatic.opensciencegrid.org                  # tags, newest first
cvmfs_server tag -i <tag> emphatic.opensciencegrid.org            # one tag's revision and hash
cvmfs_server tag -a <name> -h <root hash> -m "<message>" emphatic.opensciencegrid.org
```

Adding a tag publishes a new revision of the tag list, so the revision number goes
up by one.

## 5. Check the revision

On the publisher, `cvmfs_server tag -l` shows the revision of each tag. A stratum 1
gives its current revision (`S`) and root catalog hash (`C`) in its signed manifest:

```bash
for s in oasis-replica cvmfs-s1fnal; do
  echo -n "$s: "
  curl -s http://$s.opensciencegrid.org:8000/cvmfs/emphatic.opensciencegrid.org/.cvmfspublished \
    | strings | grep -m2 -E '^[SC]' | tr '\n' ' '; echo
done
```

`cvmfs-s1fnal` lags `oasis-replica` by a few minutes. On a client:

```bash
attr -qg revision /cvmfs/emphatic.opensciencegrid.org
cvmfs_talk -i emphatic.opensciencegrid.org revision
sudo cvmfs_talk -i emphatic.opensciencegrid.org remount   # pick up a new revision now
```

## Known failures

- `PANIC: ... sync_item.cc : 294 ... .cvmfscatalog is not a regular file`: a
  symlinked `.cvmfscatalog` in an environment view. LArSoft puts one in every
  package prefix, and the view links it in. The publish script deletes them since
  build #6. By hand, inside the open transaction:
  `find $I/var/spack/environments -name .cvmfscatalog ! -type f -delete`, then
  publish again. A failed sync leaves the transaction open; check with
  `cvmfs_server list`.
- `upstream not found` followed by builds from source: a CVMFS repository was not
  mounted yet. `ls` both `/cvmfs/emphatic.opensciencegrid.org` and
  `/cvmfs/larsoft.opensciencegrid.org` first.
- `publish` refuses to start: a shell is still `cd`'d inside `/cvmfs/emphatic...`.
