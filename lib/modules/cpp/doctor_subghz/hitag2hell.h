#pragma once

#include <stddef.h>
#include <stdint.h>
#include "hitag2bcm.h"

#ifdef __cplusplus
extern "C" {
#endif

#define HITAG2HELL_LAYER0_MASK     0x5806B4A2D16CULL
#define HITAG2HELL_I1_SPAN         1024U
#define HITAG2HELL_MAX_STATES      131072U

typedef struct {
    uint32_t hop;
    uint32_t uid;
    uint32_t cnt;
    uint8_t btn;
    uint32_t hop2;
    uint32_t cnt2;
    uint8_t btn2;
    int has_second;
} Hitag2HellRequest;

typedef struct {
    uint64_t key;
    uint64_t state;
    uint32_t uid;
    uint32_t states_tested;
    uint32_t keys_tried;
} Hitag2HellResult;

/* Pack the 20 f20-tap bits of a 48-bit state into a 20-bit index. */
uint64_t hitag2hell_expand_taps(uint32_t index20);

/* Layer-0 prefixes whose f20 matches the MSB of hop. Returns count. */
uint32_t hitag2hell_layer0(uint32_t hop, uint64_t* candidates46, uint32_t cap);

void hitag2hell_pack_candidate(uint64_t candidate46, uint16_t out[3]);
void hitag2hell_bitslice_keystream(uint32_t hop, uint32_t keystream[32]);

uint64_t hitag2hell_lfsr_inv(uint64_t state);
uint64_t hitag2hell_finish_state(uint64_t state_from_kernel);

uint64_t hitag2hell_equiv_key(uint64_t init_state, uint32_t uid, uint32_t cnt, uint8_t btn);
uint32_t hitag2hell_authenticator(uint64_t key, uint32_t uid, uint32_t cnt, uint8_t btn);

/* CPU twin of the Metal 32-way kernel. gid0 indexes candidates, gid1 is i1. */
void hitag2hell_find_state_cpu(
    const uint32_t keystream[32],
    const uint16_t* candidates,
    uint64_t* matches,
    uint32_t* matches_found,
    uint32_t candidate_index_base,
    uint32_t gid0,
    uint32_t gid1,
    uint32_t matches_cap);

/* Search one layer-0 candidate across all 1024 i1 values. */
uint32_t hitag2hell_search_one_candidate_cpu(
    uint32_t hop,
    uint64_t candidate46,
    uint64_t* states,
    uint32_t cap);

/* Full CPU search (slow). Optional second hop filters the inverted key. */
int hitag2hell_recover_cpu(const Hitag2HellRequest* req, Hitag2HellResult* out);

/* Same search, with abort + a Dart-polled (pct<<56)|done cell. Either extra
 * pointer may be NULL. 1 = found, 0 = not found, -1 = cancelled / alloc fail. */
int hitag2hell_recover_cpu_ex(
    const Hitag2HellRequest* req,
    Hitag2HellResult* out,
    volatile int32_t* cancel,
    uint64_t* progress_out);

#ifdef __APPLE__
typedef struct {
    const char* shader_source; /* Metal source string; NULL -> file/bundle fallback */
    const char* library_path;  /* precompiled .metallib path; preferred over shader_source */
    void (*progress)(uint32_t done, uint32_t total, void* ctx);
    volatile int* cancel; /* set non-zero to abort between tiles */
    void* ctx;
    /* CPU worker threads that search candidates from the top down while the GPU
     * climbs from the bottom (bidirectional meet-in-the-middle). 0 = auto (a
     * small performance-core-biased pool); negative is treated as auto. */
    int cpu_threads;
} Hitag2HellMetalOptions;

int hitag2hell_recover_metal(
    const Hitag2HellRequest* req,
    Hitag2HellResult* out,
    const Hitag2HellMetalOptions* opts);
#endif

#if defined(__ANDROID__) || defined(_WIN32)
typedef struct {
    void (*progress)(uint32_t done, uint32_t total, void* ctx);
    volatile int* cancel; /* set non-zero to abort between tiles */
    void* ctx;
    /* CPU worker threads assisting the GPU (bidirectional meet-in-the-middle).
     * 0 = auto (a small pool); negative is treated as auto. */
    int cpu_threads;
} Hitag2HellVulkanOptions;

/* Vulkan GPU search (Android + Windows). Same contract as
 * hitag2hell_recover_metal: 1 = found, 0 = not found, -1 = cancelled / no
 * usable Vulkan GPU (the bridge then falls back to the CPU oracle). */
int hitag2hell_recover_vulkan(
    const Hitag2HellRequest* req,
    Hitag2HellResult* out,
    const Hitag2HellVulkanOptions* opts);

/* 1 if a compute-capable Vulkan device is present, else 0. */
int hitag2hell_vulkan_available(void);
#endif

#ifdef __cplusplus
}
#endif
