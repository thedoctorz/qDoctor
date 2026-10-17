// Apple (CocoaPods) unity build for doctor_subghz. Podspecs can't reference
// sources outside their own tree, so this forwarder #includes the shared C
// core + the Metal host (one level up) into a single Objective-C translation
// unit (same approach ARF's pods use). The CMake platforms compile the .c
// files individually instead; this file is Apple-only.
#include "../hitag2hell_common.c"
#include "../hitag2hell_cpu_kernel.c"
#include "../hitag2bcm.c"
#import "../hitag2hell_metal.m"
#include "../hitag2_bridge.c"
#include "../psabf.c"
#import "../psabf_metal.m"
#include "../psa_bridge.c"
