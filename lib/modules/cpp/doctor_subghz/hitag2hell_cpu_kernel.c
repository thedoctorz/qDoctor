#include <stdbool.h>
#include <stdint.h>

typedef uint32_t bitslice_t;
typedef uint32_t uint;
typedef uint64_t ulong;
typedef uint16_t ushort;
typedef uint8_t uchar;

#define HITAG2HELL_KERNEL_PRELUDE 1
#define HITAG2HELL_INLINE static inline
#define HITAG2HELL_GLOBAL
#define HITAG2HELL_ATOMIC_UINT uint
#if defined(_MSC_VER)
#include <intrin.h>
#define HITAG2HELL_RESTRICT __restrict
static inline uint hitag2hell_clz32(uint32_t x) {
  unsigned long index;
  if (x == 0) {
    return 32u;
  }
  _BitScanReverse(&index, x);
  return (uint)(31u - index);
}
#define HITAG2HELL_CLZ(x) hitag2hell_clz32((uint32_t)(x))
#define HITAG2HELL_ATOMIC_INC(p) \
  ((uint32_t)_InterlockedExchangeAdd((volatile long *)(p), 1))
#else
#define HITAG2HELL_RESTRICT restrict
#define HITAG2HELL_ATOMIC_INC(p) __sync_fetch_and_add((p), 1u)
#define HITAG2HELL_CLZ(x) ((x) ? (uint)__builtin_clz(x) : 32u)
#endif
#define HITAG2HELL_NEGBOOL(c) ((bitslice_t)((c) ? 0xFFFFFFFFu : 0u))

#include "hitag2hell_f.inc"
#include "hitag2hell_kernel.inc"

void hitag2hell_find_state_cpu(
    const uint32_t keystream[32],
    const uint16_t* candidates,
    uint64_t* matches,
    uint32_t* matches_found,
    uint32_t candidate_index_base,
    uint32_t gid0,
    uint32_t gid1,
    uint32_t matches_cap) {
    hitag2hell_find_state(
        keystream,
        candidates,
        matches,
        matches_found,
        candidate_index_base,
        gid0,
        gid1,
        matches_cap);
}
