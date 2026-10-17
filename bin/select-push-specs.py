# Print "/<hash>" for the specs to push to the buildcache from the active
# environment: the specs in install-specs.txt and all their dependencies (as
# `buildcache push --with-build-dependencies` would take), except externals and
# specs installed in an upstream. Those come from the upstream at publish time.
#
#   spack -e <env> python bin/select-push-specs.py <env>/install-specs.txt
import sys
import spack.environment as ev
import spack.traverse as traverse

with open(sys.argv[1]) as f:
    hashes = {line.split()[1] for line in f if line.strip()}
env = ev.active_environment()
roots = [s for s in env.all_specs() if s.dag_hash() in hashes]
for s in traverse.traverse_nodes(roots, deptype="all", key=traverse.by_dag_hash):
    if not s.external and not s.installed_upstream:
        print("/" + s.dag_hash())
