# Copyright 2013-2024 Lawrence Livermore National Security, LLC and other
# Spack Project Developers. See the top-level COPYRIGHT file for details.
#
# SPDX-License-Identifier: (Apache-2.0 OR MIT)

from spack_repo.builtin.build_systems.cmake import CMakePackage

from spack.package import *


class Emphaticsoft(CMakePackage):
    """EMPHATIC offline code repository."""

    homepage = "https://github.com/EMPHATICSoft/emphaticsoft"
    git = "https://github.com/EMPHATICSoft/emphaticsoft.git"

    maintainers("gavinsdavies")
    license("Apache-2.0")

    # Version definitions
    version("develop", branch="develop")
    version("main", branch="main")
    version("spack-dev", branch="spack-dev", preferred=True)
    # Tagged releases (map UPS v06_02_00 → Spack 6.2.0)
    # version("6.2.0", tag="v06_02_00", commit="abc123def456")

    variant(
        "cxxstd",
        default="17",
        values=("17", "20"),
        multi=False,
        description="Use the specified C++ standard when building. UPS e26 builds "
        "emphaticsoft as C++17, and the v1.1.1 art suite and ROOT are C++17.",
    )

    # Subsystem boundaries (map 1:1 onto EMPH_* CMake options on the spack-dev branch)
    variant("daq", default=False, description="Enable DAQ/artdaq components")
    variant("beamdb", default=True, description="Enable beam and conditions DB support")
    variant("align", default=True, description="Enable Millepede-II alignment tooling")
    variant("ml", default=False, description="Enable libtorch-based ML components")
    variant("caen", default=False, description="Enable CAEN hardware support (build-only in UPS)")

    depends_on("c", type="build")
    depends_on("cxx", type="build")
    depends_on("cetmodules", type="build")
    depends_on("cmake", type="build")

    # Boost with specific components required by emphaticsoft
    # Components needed: iostreams, math, serialization
    # TODO: Verify if all these components are needed
    depends_on("boost+iostreams+math+serialization")

    # art dependencies
    # TODO: Re-enable when environment can resolve art packages
    depends_on("art")
    depends_on("art-root-io")
    depends_on("canvas-root-io")
    depends_on("cetlib")
    depends_on("cetlib-except")
    depends_on("fhicl-cpp")  # Package exists but has hyphen issues
    depends_on("messagefacility")

    # artdaq-core carries the raw-data product definitions used by offline
    # code (RawData); only the full artdaq stack is DAQ-gated.
    # v3_10 is the series UPS pairs with art 3.14 (v3_10_02 in v06_02_00).
    # ~bundle: +bundle pulls in an art-suite release instead of the art the
    # parent environment already has.
    depends_on("artdaq-core@v3_10: ~bundle")
    # TRACE: RawDataMerger. The raw data unpackers, RawDataMerger and WebDisplay
    # need only artdaq-core and TRACE and are always built.
    depends_on("trace")
    # +daq: the full artdaq stack, for the online components
    # (emphatic-artdaq/ArtModules, not built at present). artdaq pulls in
    # artdaq-mfextensions and with it qt@5.15+gui. Not needed offline.
    depends_on("artdaq", when="+daq")

    # ROOT with specific components required by emphaticsoft
    # Components needed: 
    # Core, EG, Eve, Geom, Gdml, Gpad, Graf, Graf3d,
    # Gui, Hist, Matrix, MathCore, MathMore, Minuit
    # Minuit2, Net, Physics, RIO, Spectrum, TMVA,
    # Thread, Tree, TreePlayer, X3d, XMLIO
    # TODO: Verify if all these components are needed
    # TOOD: Reinstate "threads" variant when supported
    depends_on("root+gdml+minuit+spectrum+tmva+x+xml+xrootd")
    # Simulation dependencies
    depends_on("geant4")
    # The v1.1.1 geant4-data@11.0.0 does not pull in G4NDL, so G4NEUTRONHPDATA
    # is unset and the HP physics in EMPHATIC's sim throws at the first event.
    # UPS sets it through g4neutron v4_6.
    depends_on("g4ndl@4.6", type="run")

    # Data Handling & Database dependencies
    # Recipes confirmed in FNALssi/fnal_art (spack_repo layout), Jun 2026
    depends_on("ifdh-art", when="+beamdb")
    depends_on("ifbeam", when="+beamdb")
    depends_on("nucondb", when="+beamdb")
    # libwda is core: ChannelState and RunHistory link wda::wda
    depends_on("libwda")

    # Alignment: Millepede-II. The emph repo's millepede extends the builtin recipe
    # with Mille.h and libmille.a, which Modules/Findmillepede_ii.cmake looks for.
    # 04-17-05 is the version of the UPS millepede_ii product.
    depends_on("millepede@04-17-05:", when="+align")

    # ML (TorchML, ARICHReco): libtorch from py-torch, as LArSoft's larrecodnn
    # does. py-torch puts torch/share/cmake on CMAKE_PREFIX_PATH, which is where
    # Modules/Findlibtorch.cmake looks for TorchConfig.cmake. UPS used libtorch 2.1.1.
    depends_on("py-torch", when="+ml")

    # TODO(+caen): caencomm/caendigitizer/caenvme were UPS build-only products;
    # no spack recipes known. Variant is a placeholder.

    depends_on("protobuf")
    depends_on("nlohmann-json")
    
    # Python dependencies
    depends_on("python")

    # Build configuration
    def cmake_args(self):
        args = [
            self.define_from_variant("CMAKE_CXX_STANDARD", "cxxstd"),
            self.define_from_variant("CMAKE_BUILD_TYPE", "build_type"),
            # EMPH_* options exist on the spack-dev branch (defaults OFF there)
            self.define_from_variant("EMPH_BUILD_DAQ", "daq"),
            self.define_from_variant("EMPH_BEAMDB", "beamdb"),
            self.define_from_variant("EMPH_ALIGN", "align"),
            self.define_from_variant("EMPH_BUILD_ML", "ml"),
            self.define_from_variant("EMPH_CAEN", "caen"),
        ]
        return args
    
    def setup_build_environment(self, env):
        env.set("CETMODULES_DIR", self.spec["cetmodules"].prefix)
        env.prepend_path("CMAKE_PREFIX_PATH", self.spec["cetmodules"].prefix)

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
        # Modules open their runtime data (ConstBase, calibrations, ...) through
        # $CETPKG_SOURCE, which only mrb sets. The package installs that data under
        # <prefix>/source with the source-tree layout.
        env.set("CETPKG_SOURCE", join_path(prefix, "source"))
        