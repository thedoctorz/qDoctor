#!/usr/bin/env python3
"""Generate kernel/hitag2hell.comp (Vulkan GLSL) from hitag2hell_kernel.inc.

The Hitag2Hell bitslice search is shared between the CPU oracle
(hitag2hell_cpu_kernel.c) and the Metal GPU kernel (hitag2hell_shader.h). Both
express the algorithm through hitag2hell_kernel.inc + hitag2hell_f.inc using a
small macro prelude. GLSL has no pointers and (portably) no 64-bit ints, so we
cannot #include those verbatim. This script lifts the exact algorithm body out
of the .inc and rewrites the handful of non-GLSL constructs so the search stays
byte-for-byte identical to the CPU/Metal paths:

  * the 48-bit candidate arrives as a (low32, high16) uint pair instead of a
    packed ulong, unpacked inline where the .inc calls bitslice();
  * the 48-bit match is written as a (lo, hi) uint pair instead of a ulong,
    reassembled on the host (hitag2hell_vulkan.c);
  * `!resultsN` -> `resultsN == 0u`, C casts and `const` locals dropped, and
    integer literals given explicit `u` suffixes for GLSL's stricter typing.

Run from this directory:  python3 gen_hitag2hell_comp.py
"""
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
INC = os.path.join(HERE, "..", "hitag2hell_kernel.inc")
OUT = os.path.join(HERE, "hitag2hell.comp")

PRELUDE = """#version 450
/* AUTO-GENERATED from hitag2hell_kernel.inc by kernel/gen_hitag2hell_comp.py.
 * Do not edit by hand; edit the .inc (shared with the CPU/Metal kernels) and
 * regenerate. Vulkan compute twin of the iOS Metal hitag2hell kernel, kept
 * pure 32-bit so it runs on every Android GPU (Adreno/Mali/PowerVR/Xclipse)
 * without the shaderInt64 feature.
 *
 * Grid: x = candidate index (candidate_index_base + gid0), y = i1 in [0,1024).
 * Bindings (match hitag2hell_vulkan.c):
 *   0: keystream[32]      1: candidates[] (2 uint/candidate: low32, high16)
 *   2: matches[] (2 uint/slot: lo, hi)   3: matches_found (atomic uint)
 */

layout(local_size_x = 64, local_size_y = 1, local_size_z = 1) in;

#define bitslice_t uint
#define uchar uint
#define ushort uint
#define MAX_BITSLICES 32u
#define HITAG2HELL_NEGBOOL(c) (bool(c) ? 0xFFFFFFFFu : 0u)

/* Portable bitsliced Hitag-2 filter (same boolean form as hitag2hell_f.inc). */
#define f_a_bs(a, b, c, d) (~(((a | b) & c) ^ (a | d) ^ b))
#define f_b_bs(a, b, c, d) (~(((d | c) & (a ^ b)) ^ (d | a | b)))
#define f_c_bs(a, b, c, d, e) \\
    (~((((((c ^ e) | d) & a) ^ b) & (c ^ b)) ^ (((d ^ e) | a) & ((d ^ b) | c))))
#define lfsr_bs(i)                                                                          \\
    (state[-2 + (i) + 0] ^ state[-2 + (i) + 2] ^ state[-2 + (i) + 3] ^ state[-2 + (i) + 6] ^ \\
     state[-2 + (i) + 7] ^ state[-2 + (i) + 8] ^ state[-2 + (i) + 16] ^                      \\
     state[-2 + (i) + 22] ^ state[-2 + (i) + 23] ^ state[-2 + (i) + 26] ^                     \\
     state[-2 + (i) + 30] ^ state[-2 + (i) + 41] ^ state[-2 + (i) + 42] ^                     \\
     state[-2 + (i) + 43] ^ state[-2 + (i) + 46] ^ state[-2 + (i) + 47])

layout(std430, binding = 0) readonly buffer KeystreamBuf { uint keystream[]; };
layout(std430, binding = 1) readonly buffer CandidateBuf { uint candidates[]; };
layout(std430, binding = 2) buffer MatchBuf { uint matches[]; };
layout(std430, binding = 3) buffer FoundBuf { uint matches_found; };

layout(push_constant) uniform Params {
    uint candidate_index_base;
    uint count;
    uint matches_cap;
} pc;

void main() {
    uint gid0 = gl_GlobalInvocationID.x;
    uint gid1 = gl_GlobalInvocationID.y;
    if(gid0 >= pc.count) {
        return;
    }
    // 48-bit candidate as (low32, high16); set all state bits except lowest 2.
    uint cidx = 2u * (pc.candidate_index_base + gid0);
    uint clo = candidates[cidx];
    uint chi = candidates[cidx + 1u];
    uint state[78];
    for(uint bi = 0u; bi < 46u; bi++) {
        uint bit = (bi < 32u) ? ((clo >> bi) & 1u) : ((chi >> (bi - 32u)) & 1u);
        state[bi] = HITAG2HELL_NEGBOOL(bit);
    }
"""

SAVE_REPLACEMENT = """ uint match_index = 0u;
 // Save results: 48-bit state -> (lo, hi) uint pair; host reassembles + inverts.
 while((results8 != 0u) && (match_index < MAX_BITSLICES)){
   uint shift = uint(31 - findMSB(results8)) + 1u;
   match_index += shift;
   uint slot = atomicAdd(matches_found, 1u);
   if(slot < pc.matches_cap) {
     uint bmask = 1u << (MAX_BITSLICES - match_index);
     uint lo = 0u;
     uint hi = 0u;
     for(int bj = 31; bj >= 0; --bj) { lo = (lo << 1) | (((state[bj] & bmask) != 0u) ? 1u : 0u); }
     for(int bj = 47; bj >= 32; --bj) { hi = (hi << 1) | (((state[bj] & bmask) != 0u) ? 1u : 0u); }
     matches[2u * slot] = lo;
     matches[2u * slot + 1u] = hi;
   }
   results8 <<= shift;
 }"""


def main():
    src = open(INC, "r").read()

    # Lift the algorithm body: everything after the (pointer-based) candidate
    # unpack up to the function's closing brace `} // 1`.
    start_marker = "bitslice(&state[-2+2], candidate, 46);"
    start = src.index(start_marker) + len(start_marker)
    end = src.index("} // 1")
    body = src[start:end]

    # Replace the pointer/64-bit save block first (matches original tokens).
    body, nsub = re.subn(
        r"uchar match_index = 0;.*?results8 <<= shift;\s*\}",
        lambda _m: SAVE_REPLACEMENT,
        body,
        flags=re.DOTALL,
    )
    assert nsub == 1, f"save block not found/替换 (nsub={nsub})"

    # i1 comes from the grid, not a C cast.
    body = body.replace("ushort i1 = (ushort)gid1;", "uint i1 = gid1;")

    # `const` locals aren't compile-time constants in GLSL; drop the qualifier.
    body = re.sub(r"\bconst\s+", "", body)

    # `!resultsN` -> `(resultsN == 0u)`.
    body = re.sub(r"!(\bresults\d+\b)", r"(\1 == 0u)", body)

    # Loop counters: unsigned with u-suffixed bounds/inits.
    body = re.sub(r"for\(uchar (i\d) = 0;", r"for(uint \1 = 0u;", body)
    body = re.sub(r"\(1<<(\d+)\)", r"(1u<<\1)", body)

    # Explicit u-suffix on hex literals (GLSL won't implicitly type them).
    body = re.sub(r"0x([0-9a-fA-F]+)(?![0-9a-fA-Fu])", r"0x\1u", body)

    out = PRELUDE + body + "}\n"
    with open(OUT, "w") as f:
        f.write(out)
    print(f"wrote {OUT} ({len(out)} bytes)")


if __name__ == "__main__":
    main()
