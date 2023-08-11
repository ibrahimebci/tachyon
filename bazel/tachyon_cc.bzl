load("@rules_cc//cc:defs.bzl", "cc_binary", "cc_library", "cc_test", "objc_library")
load("@local_config_cuda//cuda:build_defs.bzl", "cuda_library", "if_cuda")
load(
    "//bazel:tachyon.bzl",
    "if_has_exception",
    "if_has_matplotlib",
    "if_has_rtti",
    "if_static",
)

def tachyon_safe_code():
    return ["-Wall", "-Werror"]

def tachyon_warnings(safe_code):
    warnings = []
    if safe_code:
        warnings.extend(tachyon_safe_code())
    return warnings

def tachyon_hide_symbols():
    return if_static([], ["-fvisibility=hidden"])

def tachyon_exceptions(force_exceptions):
    return if_has_exception(["-fexceptions"], (["-fexceptions"] if force_exceptions else ["-fno-exceptions"]))

def tachyon_rtti(force_rtti):
    return if_has_rtti(["-frtti"], (["-frtti"] if force_rtti else ["-fno-rtti"]))

def tachyon_copts(safe_code = True):
    return tachyon_warnings(safe_code) + tachyon_hide_symbols()

def tachyon_cxxopts(safe_code = True, force_exceptions = False, force_rtti = False):
    return tachyon_copts(safe_code) + tachyon_exceptions(force_exceptions) + tachyon_rtti(force_rtti)

def tachyon_cuda_defines():
    return if_cuda(["TACHYON_CUDA"])

def tachyon_matplotlib_defines():
    return if_has_matplotlib(["TACHYON_HAS_MATPLOTLIB"])

def tachyon_defines(use_cuda = False):
    defines = tachyon_defines_c_shared_lib_build()
    if use_cuda:
        defines += tachyon_cuda_defines()
    return defines

def tachyon_defines_c_shared_lib_build():
    return if_static([], ["TACHYON_C_SHARED_LIB_BUILD"])

def tachyon_local_defines():
    return tachyon_local_defines_compile_library()

def tachyon_local_defines_compile_library():
    return if_static([], ["TACHYON_COMPILE_LIBRARY"])

def tachyon_cc_library(
        name,
        copts = [],
        defines = [],
        local_defines = [],
        alwayslink = True,
        safe_code = True,
        force_exceptions = False,
        force_rtti = False,
        **kwargs):
    cc_library(
        name = name,
        copts = copts + tachyon_cxxopts(safe_code = safe_code, force_exceptions = force_exceptions, force_rtti = force_rtti),
        defines = defines + tachyon_defines(),
        local_defines = local_defines + tachyon_local_defines(),
        alwayslink = alwayslink,
        **kwargs
    )

def tachyon_cc_binary(
        name,
        copts = [],
        defines = [],
        local_defines = [],
        safe_code = True,
        force_exceptions = False,
        force_rtti = False,
        **kwargs):
    cc_binary(
        name = name,
        copts = copts + tachyon_cxxopts(safe_code = safe_code, force_exceptions = force_exceptions, force_rtti = force_rtti),
        defines = defines + tachyon_defines(),
        local_defines = local_defines + tachyon_local_defines(),
        **kwargs
    )

def tachyon_cc_test(
        name,
        copts = [],
        defines = [],
        local_defines = [],
        linkstatic = True,
        deps = [],
        safe_code = True,
        force_exceptions = False,
        force_rtti = False,
        **kwargs):
    cc_test(
        name = name,
        copts = copts + tachyon_cxxopts(safe_code = safe_code, force_exceptions = force_exceptions, force_rtti = force_rtti),
        defines = defines + tachyon_defines(),
        local_defines = local_defines + tachyon_local_defines(),
        linkstatic = linkstatic,
        deps = deps + ["@com_google_googletest//:gtest_main"],
        **kwargs
    )

def tachyon_cc_benchmark(
        name,
        copts = [],
        defines = [],
        local_defines = [],
        tags = [],
        linkstatic = True,
        deps = [],
        safe_code = True,
        force_exceptions = False,
        force_rtti = False,
        **kwargs):
    cc_test(
        name = name,
        copts = copts + tachyon_cxxopts(safe_code = safe_code, force_exceptions = force_exceptions, force_rtti = force_rtti),
        defines = defines + tachyon_defines(),
        local_defines = local_defines + tachyon_local_defines(),
        tags = tags + ["benchmark"],
        deps = deps + ["@com_github_google_benchmark//:benchmark_main"],
        linkstatic = linkstatic,
        **kwargs
    )

# This is taken and modified from tf_cc_shared_object in tensorflow/tensorflow.bzl
def tachyon_cc_shared_library(
        name,
        user_link_flags = [],
        deps = [],
        linkstatic = False,
        soversion = None,
        visibility = ["//visibility:public"],
        **kwargs):
    cc_library_name = name + "_cclib"
    cc_library(
        name = cc_library_name,
        linkstatic = linkstatic,
        deps = deps,
    )

    if soversion != None:
        major_version = soversion.split(".")[0]

        for os in ["macos", "linux"]:
            native.genrule(
                name = "%s_sym_%s" % (name, os),
                outs = [("lib%s.dylib" if os == "macos" else "lib%s.so") % name],
                srcs = [":%s_%s_sym_%s" % (name, major_version, os)],
                output_to_bindir = True,
                cmd = "ln -sf $$(basename $<) $@",
            )

            native.genrule(
                name = "%s_%s_sym_%s" % (name, major_version, os),
                outs = [("lib%s.%s.dylib" if os == "macos" else "lib%s.so.%s") % (name, major_version)],
                srcs = [":" + name],
                output_to_bindir = True,
                cmd = "ln -sf $$(basename $<) $@",
            )

        native.cc_shared_library(
            name = name,
            shared_lib_name = select({
                "@platforms//os:macos": "lib%s.%s.dylib" % (name, soversion),
                "@platforms//os:windows": "%s.dll" % name,
                "//conditions:default": "lib%s.so.%s" % (name, soversion),
            }),
            user_link_flags = user_link_flags + select({
                "@platforms//os:macos": [
                    "-Wl,-install_name,@rpath/" + "lib%s.%s.dylib" % (name, major_version),
                ],
                "@platforms//os:windows": [],
                "//conditions:default": [
                    "-Wl,-soname," + "lib%s.so.%s" % (name, major_version),
                ],
            }),
            visibility = visibility,
            deps = [":" + cc_library_name],
            **kwargs
        )
    else:
        native.cc_shared_library(
            name = name,
            user_link_flags = user_link_flags,
            visibility = visibility,
            deps = [":" + cc_library_name],
            **kwargs
        )

def tachyon_objc_library(
        name,
        copts = [],
        defines = [],
        tags = [],
        alwayslink = True,
        safe_code = True,
        force_exceptions = False,
        force_rtti = False,
        **kwargs):
    objc_library(
        name = name,
        copts = copts + tachyon_cxxopts(safe_code = safe_code, force_exceptions = force_exceptions, force_rtti = force_rtti),
        defines = defines + tachyon_defines(),
        tags = tags + ["objc"],
        alwayslink = alwayslink,
        **kwargs
    )

def tachyon_cuda_library(
        name,
        copts = [],
        defines = [],
        local_defines = [],
        alwayslink = True,
        safe_code = True,
        force_exceptions = False,
        force_rtti = False,
        **kwargs):
    cuda_library(
        name = name,
        copts = copts + tachyon_cxxopts(safe_code = safe_code, force_exceptions = force_exceptions, force_rtti = force_rtti),
        defines = defines + tachyon_defines(use_cuda = True),
        local_defines = local_defines + tachyon_local_defines(),
        alwayslink = alwayslink,
        **kwargs
    )

def tachyon_cuda_binary(
        name,
        deps = [],
        **kwargs):
    lib_name = "{}_lib".format(name)
    tachyon_cuda_library(
        name = lib_name,
        deps = deps + if_cuda([
            "@local_config_cuda//cuda:cudart_static",
        ]),
        **kwargs
    )

    tachyon_cc_binary(
        name = name,
        deps = [":" + lib_name],
    )

def tachyon_cuda_test(
        name,
        deps = [],
        tags = [],
        **kwargs):
    lib_name = "{}_lib".format(name)
    tachyon_cuda_library(
        name = lib_name,
        deps = deps + if_cuda([
            "@local_config_cuda//cuda:cudart_static",
        ]) + [
            "@com_google_googletest//:gtest",
        ],
        testonly = True,
        **kwargs
    )

    tachyon_cc_test(
        name = name,
        tags = tags + ["cuda"],
        deps = [":" + lib_name],
    )

def _get_hdrs(hdrs, deps):
    return depset(
        hdrs,
        transitive = [
                         dep[CcInfo].compilation_context.headers
                         for dep in deps
                         if CcInfo in dep
                     ] +
                     [
                         dep[DefaultInfo].files
                         for dep in deps
                         if DefaultInfo in dep
                     ],
    )

def _collect_hdrs_impl(ctx):
    result = _get_hdrs(ctx.files.hdrs, ctx.attr.deps)
    return DefaultInfo(files = result)

collect_hdrs = rule(
    attrs = {
        "hdrs": attr.label_list(allow_files = [".h"]),
        "deps": attr.label_list(
            allow_rules = [
                "cc_library",
                "filegroup",
            ],
            providers = [[CcInfo], [DefaultInfo]],
        ),
    },
    implementation = _collect_hdrs_impl,
)