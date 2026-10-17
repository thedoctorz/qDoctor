#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define HITAG2BCM_CANDIDATES 0x40000U

typedef struct {
    uint32_t seed;
    uint8_t iv[4];
} Hitag2BcmResult;

/* 18-bit Renault V1 BCM seed search (firmware hitag2_brute_force_run).
 * On hit, seed is the 32-bit IV written to the .sub Seed hex field. */
int hitag2bcm_recover(const uint8_t frame[11], Hitag2BcmResult* out);

void hitag2bcm_encrypt(
    uint32_t serial,
    uint32_t cnt,
    uint8_t btn,
    uint32_t seed,
    uint8_t out[11]);

uint32_t hitag2bcm_cnt16_from_seed(uint32_t seed);

/* Encoder next-press check: cnt16(seed)+1, same button. */
int hitag2bcm_next_matches(
    const uint8_t frame[11],
    const uint8_t next[11],
    uint32_t seed);

#ifdef __cplusplus
}
#endif
