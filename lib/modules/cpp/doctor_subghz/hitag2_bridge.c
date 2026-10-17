// Platform bridge for our Hitag2Hell engine — the canonical interface used by
// the app's Dart FFI. Mirrors the iOS `Hitag2Hell.recover` contract exactly:
// GPU (our Metal shader) on Apple, GPU (our Vulkan compute kernel) on Android
// and Windows, our CPU oracle as the fallback everywhere else (and when no GPU
// is usable). Progress/cancel cross the FFI boundary as shared memory (a polled
// cell + an abort flag), never a Dart callback from a native thread.

#include <stdint.h>
#include <string.h>
#include "hitag2hell.h"

#if defined(_WIN32)
#include <windows.h>
static INIT_ONCE doctor_engine_once = INIT_ONCE_STATIC_INIT;
static CRITICAL_SECTION doctor_engine_cs;
static BOOL CALLBACK doctor_engine_init_cs(PINIT_ONCE once, PVOID param, PVOID* ctx) {
    (void)once;
    (void)param;
    (void)ctx;
    InitializeCriticalSection(&doctor_engine_cs);
    return TRUE;
}
void doctor_engine_lock(void) {
    InitOnceExecuteOnce(&doctor_engine_once, doctor_engine_init_cs, NULL, NULL);
    EnterCriticalSection(&doctor_engine_cs);
}
void doctor_engine_unlock(void) {
    LeaveCriticalSection(&doctor_engine_cs);
}
#else
#include <pthread.h>
static pthread_mutex_t doctor_engine_mutex = PTHREAD_MUTEX_INITIALIZER;
void doctor_engine_lock(void) {
    pthread_mutex_lock(&doctor_engine_mutex);
}
void doctor_engine_unlock(void) {
    pthread_mutex_unlock(&doctor_engine_mutex);
}
#endif

#if defined(_WIN32)
#define DOCTOR_EXPORT __declspec(dllexport)
#else
#define DOCTOR_EXPORT __attribute__((visibility("default")))
#endif

#ifdef __APPLE__
#include "hitag2hell_shader.h" // HITAG2HELL_METAL_SHADER (embedded MSL)
extern int hitag2hell_metal_available(void);
#endif

#if defined(__APPLE__) || defined(__ANDROID__) || defined(_WIN32)
// Pack (pct<<56)|done into the shared progress cell the Dart side polls. Used by
// the GPU paths (Metal on Apple, Vulkan on Android and Windows) to report tile
// progress.
static void doctor_hitag2_progress(uint32_t done, uint32_t total, void* ctx) {
    uint64_t* cell = (uint64_t*)ctx;
    if (!cell) return;
    uint32_t pct = total ? (uint32_t)(((uint64_t)done * 100u) / total) : 0u;
    if (pct > 100u) pct = 100u;
    *cell = ((uint64_t)pct << 56) | ((uint64_t)done & 0x00FFFFFFFFFFFFFFULL);
}
#endif

// rc == 1 => found (out_key = 48-bit key). progress_out: shared (pct<<56)|done
// cell. cancel: shared abort flag. Matches iOS recoverSync's rc contract.
DOCTOR_EXPORT int doctor_hitag2hell_recover(
    uint32_t hop, uint32_t uid, uint32_t cnt, uint8_t btn,
    uint32_t hop2, uint32_t cnt2, uint8_t btn2, int32_t has_second,
    uint64_t* out_key, int32_t* found,
    uint64_t* progress_out, volatile int32_t* cancel) {
    Hitag2HellRequest req;
    memset(&req, 0, sizeof(req));
    req.hop = hop;
    req.uid = uid;
    req.cnt = cnt;
    req.btn = btn;
    req.hop2 = hop2;
    req.cnt2 = cnt2;
    req.btn2 = btn2;
    req.has_second = has_second;

    Hitag2HellResult out;
    memset(&out, 0, sizeof(out));

    // One recovery at a time: overlapping Metal compiles / 8MB candidate
    // buffers jetsam the process when the user leaves and re-enters quickly.
    doctor_engine_lock();
    int rc;
#ifdef __APPLE__
    if (hitag2hell_metal_available()) {
        Hitag2HellMetalOptions opts;
        memset(&opts, 0, sizeof(opts));
        opts.shader_source = HITAG2HELL_METAL_SHADER;
        opts.library_path = NULL;
        opts.progress = doctor_hitag2_progress;
        opts.ctx = progress_out;
        opts.cancel = (volatile int*)cancel;
        opts.cpu_threads = 0;
        rc = hitag2hell_recover_metal(&req, &out, &opts);
    } else {
        rc = hitag2hell_recover_cpu_ex(&req, &out, cancel, progress_out);
    }
#elif defined(__ANDROID__) || defined(_WIN32)
    {
        Hitag2HellVulkanOptions opts;
        memset(&opts, 0, sizeof(opts));
        opts.progress = doctor_hitag2_progress;
        opts.ctx = progress_out;
        opts.cancel = (volatile int*)cancel;
        opts.cpu_threads = 0;
        rc = hitag2hell_recover_vulkan(&req, &out, &opts);
        // recover_vulkan returns -1 for a cancel (cancel flag set) but also when
        // there's no usable Vulkan GPU / it faulted before finding a key (flag
        // clear) -> fall back to the CPU oracle in that case.
        if (rc == -1 && !(cancel && *cancel)) {
            rc = hitag2hell_recover_cpu_ex(&req, &out, cancel, progress_out);
        }
    }
#else
    rc = hitag2hell_recover_cpu_ex(&req, &out, cancel, progress_out);
#endif
    doctor_engine_unlock();

    if (found) *found = (rc == 1) ? 1 : 0;
    if (rc == 1 && out_key) *out_key = out.key;
    return rc;
}

// Renault V1 BCM 18-bit seed pre-pass (fast, CPU-only). Tried before the Hell
// search: rc == 1 => found, out_seed is the 32-bit IV for the .sub Seed field.
DOCTOR_EXPORT int doctor_hitag2_bcm_recover(
    const uint8_t* frame, uint32_t* out_seed, int32_t* found) {
    Hitag2BcmResult out;
    memset(&out, 0, sizeof(out));
    int rc = hitag2bcm_recover(frame, &out);
    if (found) *found = (rc == 1) ? 1 : 0;
    if (rc == 1 && out_seed) *out_seed = out.seed;
    return rc;
}
