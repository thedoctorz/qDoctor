/* Portable bitsliced Hitag-2 filter. Same boolean form as recoverkey.c / WOOT'18. */

#ifndef MAX_BITSLICES
#define MAX_BITSLICES 32
#endif
#ifndef KEYSTREAM_LENGTH
#define KEYSTREAM_LENGTH 32
#endif

#define f_a_bs(a, b, c, d) (~(((a | b) & c) ^ (a | d) ^ b))
#define f_b_bs(a, b, c, d) (~(((d | c) & (a ^ b)) ^ (d | a | b)))
#define f_c_bs(a, b, c, d, e) \
    (~((((((c ^ e) | d) & a) ^ b) & (c ^ b)) ^ (((d ^ e) | a) & ((d ^ b) | c))))

#define lfsr_bs(i)                                                                         \
    (state[-2 + (i) + 0] ^ state[-2 + (i) + 2] ^ state[-2 + (i) + 3] ^ state[-2 + (i) + 6] ^ \
     state[-2 + (i) + 7] ^ state[-2 + (i) + 8] ^ state[-2 + (i) + 16] ^                      \
     state[-2 + (i) + 22] ^ state[-2 + (i) + 23] ^ state[-2 + (i) + 26] ^                     \
     state[-2 + (i) + 30] ^ state[-2 + (i) + 41] ^ state[-2 + (i) + 42] ^                     \
     state[-2 + (i) + 43] ^ state[-2 + (i) + 46] ^ state[-2 + (i) + 47])

HITAG2HELL_INLINE void bitslice(bitslice_t* HITAG2HELL_RESTRICT b, ulong x, const uchar n) {
    for(uchar i = 0; i < n; ++i) {
        b[i] = HITAG2HELL_NEGBOOL(x & 1u);
        x >>= 1;
    }
}

HITAG2HELL_INLINE ulong unbitslice(const bitslice_t* HITAG2HELL_RESTRICT b, const uchar s, const uchar n) {
    const bitslice_t mask = ((bitslice_t)1) << s;
    ulong result = 0;
    for(int i = (int)n - 1; i >= 0; --i) {
        result <<= 1;
        result |= (ulong)((b[i] & mask) != 0);
    }
    return result;
}
