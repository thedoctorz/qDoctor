#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define PSA_BF_STATUS_IDLE      0
#define PSA_BF_STATUS_RUNNING   1
#define PSA_BF_STATUS_FOUND     2
#define PSA_BF_STATUS_NOT_FOUND 3
#define PSA_BF_STATUS_CANCELLED  4

#define PSA_BF_TYPE_XOR  0x23
#define PSA_BF_TYPE_TEA   0x36

#define PSA_BF_BF1_START 0x23000000U
#define PSA_BF_BF1_END   0x24000000U
#define PSA_BF_BF2_START 0xF3000000U
#define PSA_BF_BF2_END   0xF4000000U

typedef struct {
    uint32_t key1_low;
    uint32_t key1_high;
    uint16_t key2_low;
} PsaBfRequest;

typedef struct {
    uint8_t button;
    uint32_t serial;
    uint32_t counter;
    uint16_t crc;
    uint32_t seed;
    uint8_t type;
    uint32_t states_tried;
} PsaBfResult;

typedef struct {
    void (*progress)(uint32_t done, uint32_t total, void* ctx);
    volatile int* cancel;
    void* ctx;
    int cpu_threads;
} PsaBfOptions;

#ifdef __APPLE__
typedef struct {
    const char* shader_source;
    const char* library_path;
    void (*progress)(uint32_t done, uint32_t total, void* ctx);
    volatile int* cancel;
    void* ctx;
    int cpu_threads;
} PsaBfMetalOptions;
#endif

/* 1 = found, 0 = not found, -1 = cancelled. */
int psa_bf_recover_cpu(
    const PsaBfRequest* req,
    PsaBfResult* out,
    const PsaBfOptions* opts);

#ifdef __APPLE__
/* 1 = found, 0 = not found, -1 = cancelled, -2 = no Metal. */
int psa_bf_recover_metal(
    const PsaBfRequest* req,
    PsaBfResult* out,
    const PsaBfMetalOptions* opts);
#endif

#if defined(__ANDROID__) || defined(_WIN32)
typedef struct {
    void (*progress)(uint32_t done, uint32_t total, void* ctx);
    volatile int* cancel;
    void* ctx;
    int cpu_threads;
} PsaBfVulkanOptions;

/* Vulkan GPU search (Android + Windows). 1 = found, 0 = not found,
 * -1 = cancelled, -2 = no usable Vulkan GPU (the bridge then falls back to
 * the CPU oracle). */
int psa_bf_recover_vulkan(
    const PsaBfRequest* req,
    PsaBfResult* out,
    const PsaBfVulkanOptions* opts);
#endif

/* Firmware encoder `psa_build_buffer_mode36` (no preserved header bytes). */
void psa_bf_encode_mode36(
    uint32_t serial,
    uint8_t button,
    uint32_t counter,
    uint16_t crc,
    uint32_t* key1_high,
    uint32_t* key1_low,
    uint16_t* key2_low);

void psa_bf_setup_cipher(
    uint32_t key1_low,
    uint32_t key1_high,
    uint16_t key2_low,
    uint32_t* w0,
    uint32_t* w1);

void psa_bf_fill_result(uint32_t v0, uint32_t v1, PsaBfResult* out);

#ifdef __cplusplus
}
#endif
