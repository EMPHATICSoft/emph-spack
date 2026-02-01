# Copyright 2013-2024 Lawrence Livermore National Security, LLC and other
# Spack Project Developers. See the top-level COPYRIGHT file for details.
#
# SPDX-License-Identifier: (Apache-2.0 OR MIT)

from spack_repo.builtin.build_systems.cmake import CMakePackage

from spack.package import *


class Emphaticsoft(CMakePackage):
    """EMPHATIC offline code repository."""

    homepage = "https://github.com/EMPHATICSoft/emphaticsoft"
    git = "git@github.com:EMPHATICSoft/emphaticsoft.git"

    maintainers("gavinsdavies")
    license("Apache-2.0")

    version("main", branch="main")
    version("spack-dev", branch="spack-dev")

    variant(
        "cxxstd",
        default="17",
        values=("14", "17", "20"),
        multi=False,
        description="Use the specified C++ standard when building.",
    )

    depends_on("c", type="build")
    depends_on("cxx", type="build")

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
        # Ensure we can find executables.
        env.prepend_path("PATH", prefix.bin)
        # Ensure we can ROOT include files.
        env.prepend_path("ROOT_INCLUDE_PATH", prefix.include)
        # Ensure we can find fhicl files
        env.prepend_path("FHICL_FILE_PATH", "{0}/fcl".format(prefix))
        # Ensure we can find GDML files
        env.prepend_path("FW_SEARCH_PATH", "{0}/gdml".format(prefix))
        