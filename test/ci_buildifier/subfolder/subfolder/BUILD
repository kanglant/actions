# This BUILD file contains intentional formatting errors.

package(default_visibility = ["//visibility:public"])
licenses(["notice"])  # Apache 2.0
cc_library(
     name = "my_library",
    hdrs = [
        "my_library.h"
     ],
     srcs = [
         "my_library.cc",
    ],
    deps = [
        "//util:common_utils", #deps not sorted
        "//third_party/some_lib",
    ],
)
cc_binary(
    name = "my_binary",
    srcs = [
        "main.cc",
    ], deps = [":my_library", "//framework:base" ] # missing newline, extra space
)
