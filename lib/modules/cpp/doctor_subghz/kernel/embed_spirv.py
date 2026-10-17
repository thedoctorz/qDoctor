#!/usr/bin/env python3
"""Compile the .comp shaders to SPIR-V and embed them as committed C headers.

We commit the SPIR-V (like hitag2hell_shader.h commits the Metal source) so the
Android build needs no shader toolchain: hitag2hell_vulkan.c / psabf_vulkan.c
just #include the generated uint32 arrays. Regenerate after editing a shader:

    python3 gen_hitag2hell_comp.py            # if hitag2hell.comp changed
    python3 embed_spirv.py                     # compile + embed both

glslc is taken from $GLSLC, else the newest Android NDK shader-tools install.
"""
import glob
import os
import struct
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))

SHADERS = [
    ("hitag2hell.comp", "hitag2hell_spirv.h", "HITAG2HELL_VULKAN_SPIRV"),
    ("psabf.comp", "psabf_spirv.h", "PSABF_VULKAN_SPIRV"),
]


def find_glslc():
    env = os.environ.get("GLSLC")
    if env and os.path.exists(env):
        return env
    from shutil import which

    tool = which("glslc")
    if tool:
        return tool
    homes = []
    sdk = os.environ.get("ANDROID_SDK_ROOT") or os.path.expanduser(
        "~/Library/Android/sdk"
    )
    homes += sorted(glob.glob(os.path.join(sdk, "ndk", "*")), reverse=True)
    ndk = os.environ.get("ANDROID_NDK_HOME") or os.environ.get("ANDROID_NDK")
    if ndk:
        homes.insert(0, ndk)
    for host in ("darwin-x86_64", "linux-x86_64", "windows-x86_64"):
        for home in homes:
            cand = os.path.join(home, "shader-tools", host, "glslc")
            if os.path.exists(cand):
                return cand
            if os.path.exists(cand + ".exe"):
                return cand + ".exe"
    sys.exit(
        "glslc not found. Set $GLSLC or install the Android NDK shader-tools."
    )


def emit_header(spv_path, header_path, symbol):
    data = open(spv_path, "rb").read()
    assert len(data) % 4 == 0, "SPIR-V must be a whole number of words"
    words = struct.unpack(f"<{len(data) // 4}I", data)
    lines = [
        f"// Auto-generated from {os.path.basename(spv_path).replace('.spv', '.comp')}"
        " by embed_spirv.py. Do not edit.",
        "#pragma once",
        "#include <stdint.h>",
        f"static const uint32_t {symbol}[] = {{",
    ]
    for i in range(0, len(words), 8):
        chunk = ", ".join(f"0x{w:08x}u" for w in words[i : i + 8])
        lines.append("    " + chunk + ",")
    lines.append("};")
    lines.append(f"static const uint32_t {symbol}_SIZE = sizeof({symbol});")
    lines.append("")
    with open(header_path, "w") as f:
        f.write("\n".join(lines))


def main():
    glslc = find_glslc()
    print(f"glslc: {glslc}")
    for comp, header, symbol in SHADERS:
        comp_path = os.path.join(HERE, comp)
        spv_path = os.path.join(HERE, comp.replace(".comp", ".spv"))
        header_path = os.path.join(HERE, "..", header)
        subprocess.run(
            [glslc, "-O", "-fshader-stage=compute", comp_path, "-o", spv_path],
            check=True,
        )
        emit_header(spv_path, header_path, symbol)
        print(f"embedded {comp} -> {os.path.normpath(header_path)}")


if __name__ == "__main__":
    main()
