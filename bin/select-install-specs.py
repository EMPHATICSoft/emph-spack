# Print "<name> <hash>" for the specs to install and push from the active environment:
# every root, except that a root named in $WITHOUT is replaced by its direct
# dependencies. Concretizing with emphaticsoft but installing without it gives a
# dependencies-only release whose versions and variants are the ones emphaticsoft
# asks for, so a developer build on top of it rebuilds only emphaticsoft.
#
#   WITHOUT=emphaticsoft spack -e <env> python bin/select-install-specs.py
import os
import spack.deptypes as dt
import spack.environment as ev

env = ev.active_environment()
without = set(os.environ.get("WITHOUT", "").split())
selected = {}
for root in env.concrete_roots():
    if root.name in without:
        for dep in root.dependencies(deptype=dt.ALL):
            if dep.name not in without:
                selected[dep.dag_hash()] = dep.name
    else:
        selected[root.dag_hash()] = root.name
for h, n in sorted(selected.items(), key=lambda x: x[1]):
    print(n, h)
