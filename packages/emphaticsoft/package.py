# Copyright 2013-2024 Lawrence Livermore National Security, LLC and other
# Spack Project Developers. See the top-level COPYRIGHT file for details.
#
# SPDX-License-Identifier: (Apache-2.0 OR MIT)

from spack.package import *

def sanitize_environments(env, *vars):
    for var in vars:
        env.prune_duplicate_paths(var)
        env.deprioritize_system_paths(var)

class Emphaticsoft(CMakePackage):
    """EMPHATIC offline code repository."""

    homepage = "https://github.com/EMPHATICSoft/emphaticsoft"
    git = "git@github.com:EMPHAICSoft/emphaticsoft.git"

    maintainers("gavinsdavies")
    license("Apache-2.0")

    version("main", branch="main", "get_full_repo=True")

    depends_on("art")
    depends_on("art_root_io")
    depends_on("artdaq")
    depends_on("artdaq_core")
    depends_on("geant4")
    depends_on("ifbeam")
    depends_on("nucondb")
    depends_on("ifdh_art")
    depends_on("srproxy")
    depends_on("cetmodules", type="build")

    def setup_run_environment(self, env):
        prefix = self.prefix
        # Ensure we can find plugin libraries.
        env.prepend_path("CET_PLUGIN_PATH", prefix.lib)
        # Ensure we can find fhicl files
        env.prepend_path("FHICL_FILE_PATH", prefix + "/fcl")
        env.prepend_path("EMPH_SEARCH_PATH", prefix + "/fcl")
        # Ensure we can find data files
        env.prepend_path("EMPH_DATA_PATH", prefix + "/share")
        # Cleaup.
        sanitize_environments(env, "CET_PLUGIN_PATH", "FHICL_FILE_PATH", "EMPH_SEARCH_PATH", "EMPH_DATA_PATH")
        