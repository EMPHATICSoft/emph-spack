# Copyright Spack Project Developers. See COPYRIGHT file for details.
#
# SPDX-License-Identifier: (Apache-2.0 OR MIT)

from spack_repo.builtin.packages.millepede.package import Millepede as BuiltinMillepede

from spack.package import *


class Millepede(BuiltinMillepede):
    """Millepede II, with the Mille C++ writer that EMPHATIC links against.

    The builtin recipe installs only pede. emphaticsoft's Alignment module also
    needs millepede_ii/Mille.h and libmille.a, which the UPS millepede_ii
    product shipped (Modules/Findmillepede_ii.cmake looks for exactly those).
    """

    # The version UPS millepede_ii v04_17_05 was built from.
    version("04-17-05", sha256="90adb61a3e784672d3288a286ab7d2e42aa29d9445f2c9f74bd4d506c4f3d3d6")

    variant(
        "buffer_size",
        default="50000",
        description="Mille::myBufferSize. The UPS product raised it from 5000 to "
        "50000 for EMPHATIC's SSD alignment.",
    )

    def edit(self, spec, prefix):
        filter_file(
            r"enum \{myBufferSize = \d+\};",
            "enum {{myBufferSize = {0}}};".format(spec.variants["buffer_size"].value),
            "Mille.h",
        )

    def build(self, spec, prefix):
        make()
        cxx = Executable(spack_cxx)
        cxx("-O2", "-fPIC", "-c", "Mille.cc", "-o", "Mille.o")
        Executable("ar")("rcs", "libmille.a", "Mille.o")

    def install(self, spec, prefix):
        super().install(spec, prefix)
        mkdirp(prefix.include.millepede_ii)
        install("Mille.h", prefix.include.millepede_ii)
        mkdirp(prefix.lib)
        install("libmille.a", prefix.lib)
