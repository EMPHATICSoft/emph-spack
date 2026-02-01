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
    depends_on("cetmodules", type="build")
    depends_on("cmake", type="build")

    # Boost with specific components required by emphaticsoft
    # Components needed: iostreams, math, serialization
    # TODO: Verify if all these components are needed
    depends_on("boost+iostreams+math+serialization")

    # art dependencies
    depends_on("art")
    depends_on("art_root_io")
    depends_on("canvas_root_io")
    depends_on("cetlib")
    depends_on("cetlib-except")
    depends_on("fhicl-cpp")
    depends_on("messagefacility")

    # DAQ dependencies
    depends_on("artdaq")
    depends_on("artdaq_core")

    # ROOT with specific components required by emphaticsoft
    # Components needed: 
    # Core, EG, Eve, Geom, Gdml, Gpad, Graf, Graf3d,
    # Gui, Hist, Matrix, MathCore, MathMore, Minuit
    # Minuit2, Net, Physics, RIO, Spectrum, TMVA,
    # Thread, Tree, TreePlayer, X3d, XMLIO
    # TODO: Verify if all these components are needed
    depends_on("root+gdml+minuit+spectrum+tmva+x+xml+threads")
    # Simulation dependencies
    depends_on("geant4")

    # Data Handline & Database dependencies
    depends_on("ifdh_art")
    depends_on("ifbeam")
    depends_on("nucondb")

    # Other dependencies
    depends_on("milliepede-ii")
    depends_on("libtorch")
    depends_on("protobuf")
    depends_on("nlohmann-json")
    
    # Python dependencies
    depends_on("python")

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
        