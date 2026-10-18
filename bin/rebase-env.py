# Turn an environment created from a base release's spack.lock into the new
# release: take the packages: settings of the release spack.yaml and solve roots
# separately (unify: false), so the base's concrete roots stay as they are. Print
# the release's spec for each package to re-solve, with %build_compiler expanded
# (an environment made from a lock has no includes, so no toolchains).
#
#   spack python bin/rebase-env.py <env>/spack.yaml <release spack.yaml> <package>...
import sys
import spack.util.spack_yaml as syaml

BUILD_COMPILER = ("%[when='%c'] c=gcc@12 %[when='%cxx'] cxx=gcc@12"
                  " %[when='%fortran'] fortran=gcc@12")

env_yaml, release_yaml, names = sys.argv[1], sys.argv[2], sys.argv[3:]
with open(release_yaml) as f:
    release = syaml.load(f)["spack"]
with open(env_yaml) as f:
    data = syaml.load(f)
data["spack"].setdefault("concretizer", {})["unify"] = False
data["spack"]["packages"] = release.get("packages", {})
with open(env_yaml, "w") as f:
    syaml.dump(data, f)
for name in names:
    specs = [s for s in release["specs"]
             if isinstance(s, str) and s.split("@")[0].split()[0] == name]
    if len(specs) != 1:
        sys.exit(f"Error: expected one {name} spec in {release_yaml}, found {len(specs)}")
    print(specs[0].replace("%build_compiler", BUILD_COMPILER))
