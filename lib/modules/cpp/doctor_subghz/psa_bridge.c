// Platform bridge for our PSA TEA bruteforce — canonical interface for the
// app's Dart FFI, mirroring the iOS `PsaBf.recover`. Metal GPU on Apple,
// Vulkan GPU on Android and Windows (both fall back to the CPU oracle on
// -2/no-GPU), CPU (with progress + cancel) elsewhere. Returns the full
// recovered field set incl. Seed + CRC. Progress/cancel are shared memory.

#include <stdint.h>
#include <string.h>
#include "psabf.h"

#if defined(_WIN32)
#define DOCTOR_EXPORT __declspec(dllexport)
#else
#define DOCTOR_EXPORT __attribute__((visibility("default")))
#endif

#ifdef __APPLE__
#include "psabf_shader.h" // PSABF_METAL_SHADER (embedded MSL)
#endif

void doctor_engine_lock(void);
void doctor_engine_unlock(void);

static void doctor_psa_progress(uint32_t done, uint32_t total, void* ctx) {
    uint64_t* cell = (uint64_t*)ctx;
    if (!cell) return;
    uint32_t pct = total ? (uint32_t)(((uint64_t)done * 100u) / total) : 0u;
    if (pct > 100u) pct = 100u;
    *cell = ((uint64_t)pct << 56) | ((uint64_t)done & 0x00FFFFFFFFFFFFFFULL);
}

// rc == 1 => found. key1/key2 are the two 8-byte cipher halves (big-endian, as
// read from the .sub Key/Key_2). Mirrors PsaBf.recoverSync's field mapping.
DOCTOR_EXPORT int doctor_psa_recover(
    const uint8_t* key1, const uint8_t* key2,
    uint8_t* out_button, uint32_t* out_serial, uint32_t* out_counter,
    uint16_t* out_crc, uint32_t* out_seed, uint8_t* out_type,
    int32_t* found, uint64_t* progress_out, volatile int32_t* cancel) {
    PsaBfRequest req;
    memset(&req, 0, sizeof(req));
    req.key1_high = ((uint32_t)key1[0] << 24) | ((uint32_t)key1[1] << 16) |
                    ((uint32_t)key1[2] << 8) | (uint32_t)key1[3];
    req.key1_low = ((uint32_t)key1[4] << 24) | ((uint32_t)key1[5] << 16) |
                   ((uint32_t)key1[6] << 8) | (uint32_t)key1[7];
    req.key2_low = (uint16_t)(((uint16_t)key2[6] << 8) | (uint16_t)key2[7]);

    PsaBfResult out;
    memset(&out, 0, sizeof(out));

    doctor_engine_lock();
    int rc;
#ifdef __APPLE__
    PsaBfMetalOptions mopts;
    memset(&mopts, 0, sizeof(mopts));
    mopts.shader_source = PSABF_METAL_SHADER;
    mopts.library_path = NULL;
    mopts.progress = doctor_psa_progress;
    mopts.ctx = progress_out;
    mopts.cancel = (volatile int*)cancel;
    mopts.cpu_threads = 0;
    rc = psa_bf_recover_metal(&req, &out, &mopts);
    if (rc == -2) { // no Metal device -> CPU
        PsaBfOptions opts;
        memset(&opts, 0, sizeof(opts));
        opts.progress = doctor_psa_progress;
        opts.ctx = progress_out;
        opts.cancel = (volatile int*)cancel;
        opts.cpu_threads = 0;
        rc = psa_bf_recover_cpu(&req, &out, &opts);
    }
#elif defined(__ANDROID__) || defined(_WIN32)
    PsaBfVulkanOptions vopts;
    memset(&vopts, 0, sizeof(vopts));
    vopts.progress = doctor_psa_progress;
    vopts.ctx = progress_out;
    vopts.cancel = (volatile int*)cancel;
    vopts.cpu_threads = 0;
    rc = psa_bf_recover_vulkan(&req, &out, &vopts);
    if (rc == -2) { // no usable Vulkan GPU -> CPU
        PsaBfOptions opts;
        memset(&opts, 0, sizeof(opts));
        opts.progress = doctor_psa_progress;
        opts.ctx = progress_out;
        opts.cancel = (volatile int*)cancel;
        opts.cpu_threads = 0;
        rc = psa_bf_recover_cpu(&req, &out, &opts);
    }
#else
    PsaBfOptions opts;
    memset(&opts, 0, sizeof(opts));
    opts.progress = doctor_psa_progress;
    opts.ctx = progress_out;
    opts.cancel = (volatile int*)cancel;
    opts.cpu_threads = 0;
    rc = psa_bf_recover_cpu(&req, &out, &opts);
#endif
    doctor_engine_unlock();

    if (found) *found = (rc == 1) ? 1 : 0;
    if (rc == 1) {
        if (out_button) *out_button = out.button;
        if (out_serial) *out_serial = out.serial;
        if (out_counter) *out_counter = out.counter;
        if (out_crc) *out_crc = out.crc;
        if (out_seed) *out_seed = out.seed;
        if (out_type) *out_type = out.type;
    }
    return rc;
}

// Sample-vector encoder: builds the two 8-byte cipher halves from known
// fields (firmware `psa_build_buffer_mode36`), so the UI can offer a one-tap
// "load sample" that recovers back to those fields.
DOCTOR_EXPORT void doctor_psa_encode_mode36(
    uint32_t serial, uint8_t button, uint32_t counter, uint16_t crc,
    uint8_t* out_key1, uint8_t* out_key2) {
    uint32_t k1_high = 0, k1_low = 0;
    uint16_t k2_low = 0;
    psa_bf_encode_mode36(serial, button, counter, crc, &k1_high, &k1_low,
                         &k2_low);
    out_key1[0] = (uint8_t)((k1_high >> 24) & 0xFF);
    out_key1[1] = (uint8_t)((k1_high >> 16) & 0xFF);
    out_key1[2] = (uint8_t)((k1_high >> 8) & 0xFF);
    out_key1[3] = (uint8_t)(k1_high & 0xFF);
    out_key1[4] = (uint8_t)((k1_low >> 24) & 0xFF);
    out_key1[5] = (uint8_t)((k1_low >> 16) & 0xFF);
    out_key1[6] = (uint8_t)((k1_low >> 8) & 0xFF);
    out_key1[7] = (uint8_t)(k1_low & 0xFF);
    for (int i = 0; i < 8; i++) out_key2[i] = 0;
    out_key2[6] = (uint8_t)((k2_low >> 8) & 0xFF);
    out_key2[7] = (uint8_t)(k2_low & 0xFF);
}
