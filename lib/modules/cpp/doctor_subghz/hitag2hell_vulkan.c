// Vulkan GPU path for our Hitag2Hell engine — the compute twin of
// hitag2hell_metal.m. It runs the exact same bitslice search as the iOS Metal
// kernel (generated from the shared hitag2hell_kernel.inc), tiled across the
// layer-0 candidates, with the same bidirectional meet-in-the-middle assist:
// the GPU climbs candidates from the bottom while a small CPU pool descends
// from the top. Whichever front hits the winning candidate first records the
// key and stops the other side.
//
// The GLSL kernel is pure 32-bit (no shaderInt64), so the 48-bit candidate is
// uploaded as a (low32, high16) uint pair and each 48-bit match comes back as a
// (lo, hi) uint pair that we reassemble here before verifying on the host.
#if defined(__ANDROID__) || defined(_WIN32)

#include "hitag2hell.h"

#include "doctor_vulkan.h"
#include "hitag2hell_spirv.h"

#if defined(_WIN32)
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#endif
#if defined(_WIN32) && !defined(__MINGW32__)
#include "../hardnested/pthread_shim.h"
#else
#include <pthread.h>
#endif
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>
#if defined(_WIN32)
#include <windows.h>
#else
#include <unistd.h>
#endif

typedef struct {
    uint32_t candidate_index_base;
    uint32_t count;
    uint32_t matches_cap;
} Hitag2VkPush;

/* Verify one raw kernel state against the request (host side). Tries both uid
 * and ~uid (the Hitag2 complement ambiguity). Twin of the Metal driver's. */
static int hitag2hell_verify_state(
    const Hitag2HellRequest* req,
    uint64_t raw_state,
    uint64_t* key_out,
    uint64_t* init_out,
    uint32_t* uid_out) {
    const uint32_t uids[2] = {req->uid, ~req->uid};
    const uint64_t init = hitag2hell_finish_state(raw_state);
    for(int u = 0; u < 2; u++) {
        const uint64_t key = hitag2hell_equiv_key(init, uids[u], req->cnt, req->btn);
        if(hitag2hell_authenticator(key, uids[u], req->cnt, req->btn) != req->hop) {
            continue;
        }
        if(req->has_second &&
           hitag2hell_authenticator(
               key, uids[u], req->cnt2, req->btn2 ? req->btn2 : req->btn) != req->hop2) {
            continue;
        }
        *key_out = key;
        *init_out = init;
        *uid_out = uids[u];
        return 1;
    }
    return 0;
}

/* Shared state for the bidirectional search: GPU rises from 0 (gpu_upto), CPU
 * workers fall from ncand (cpu_cursor). They meet in the middle. */
typedef struct {
    const Hitag2HellRequest* req;
    const uint16_t* packed; /* 3 uint16 per candidate, for the CPU kernel */
    const uint32_t* keystream; /* 32 bitsliced words */
    uint32_t ncand;

    _Atomic uint32_t cpu_cursor;
    _Atomic uint32_t gpu_upto;
    _Atomic int found;
    _Atomic uint32_t states_tested;
    _Atomic uint32_t keys_tried;
    _Atomic int active_workers;

    pthread_mutex_t grab_lock;
    pthread_mutex_t result_lock;
    Hitag2HellResult* out;

    volatile int* external_cancel;
} Hitag2HellShared;

static int hitag2hell_cancelled(const Hitag2HellShared* sh) {
    return (sh->external_cancel && *sh->external_cancel) ? 1 : 0;
}

static void hitag2hell_report(
    Hitag2HellShared* sh, uint64_t key, uint64_t init, uint32_t uid) {
    pthread_mutex_lock(&sh->result_lock);
    if(!atomic_load_explicit(&sh->found, memory_order_relaxed)) {
        sh->out->key = key;
        sh->out->state = init;
        sh->out->uid = uid;
        atomic_store_explicit(&sh->found, 1, memory_order_release);
    }
    pthread_mutex_unlock(&sh->result_lock);
}

/* CPU worker: claims blocks of candidates from the top and searches downward,
 * meeting the GPU climbing from the bottom. Uses the same 32-way bitslice
 * kernel as the GPU (hitag2hell_find_state_cpu). */
static void* hitag2hell_cpu_worker(void* arg) {
    Hitag2HellShared* sh = (Hitag2HellShared*)arg;
    const uint32_t block = 64;
    uint64_t states[256];

    for(;;) {
        if(atomic_load_explicit(&sh->found, memory_order_acquire)) {
            break;
        }
        if(hitag2hell_cancelled(sh)) {
            break;
        }

        pthread_mutex_lock(&sh->grab_lock);
        uint32_t g = atomic_load_explicit(&sh->gpu_upto, memory_order_relaxed);
        uint32_t top = atomic_load_explicit(&sh->cpu_cursor, memory_order_relaxed);
        if(top <= g) {
            pthread_mutex_unlock(&sh->grab_lock);
            break; /* fronts met */
        }
        uint32_t start = (top > block) ? (top - block) : 0u;
        if(start < g) {
            start = g;
        }
        atomic_store_explicit(&sh->cpu_cursor, start, memory_order_relaxed);
        pthread_mutex_unlock(&sh->grab_lock);

        uint32_t local_states = 0;
        uint32_t local_keys = 0;
        for(uint32_t cc = start; cc < top; cc++) {
            if(atomic_load_explicit(&sh->found, memory_order_acquire)) {
                break;
            }
            if(hitag2hell_cancelled(sh)) {
                break;
            }
            uint32_t n = 0;
            for(uint32_t i1 = 0; i1 < HITAG2HELL_I1_SPAN; i1++) {
                hitag2hell_find_state_cpu(
                    sh->keystream, &sh->packed[3U * cc], states, &n, 0, 0, i1, 256);
            }
            if(n > 256) {
                n = 256;
            }
            local_states += n;
            for(uint32_t j = 0; j < n; j++) {
                uint64_t key, init;
                uint32_t uid;
                local_keys += 2;
                if(hitag2hell_verify_state(sh->req, states[j], &key, &init, &uid)) {
                    hitag2hell_report(sh, key, init, uid);
                    break;
                }
            }
        }
        atomic_fetch_add_explicit(&sh->states_tested, local_states, memory_order_relaxed);
        atomic_fetch_add_explicit(&sh->keys_tried, local_keys, memory_order_relaxed);
    }
    atomic_fetch_sub_explicit(&sh->active_workers, 1, memory_order_release);
    return NULL;
}

static void hitag2hell_sleep_ms(unsigned ms) {
#if defined(_WIN32)
    Sleep(ms);
#else
    usleep((useconds_t)ms * 1000u);
#endif
}

int hitag2hell_vulkan_available(void) {
    return dvk_available();
}

int hitag2hell_recover_vulkan(
    const Hitag2HellRequest* req,
    Hitag2HellResult* out,
    const Hitag2HellVulkanOptions* opts) {
    memset(out, 0, sizeof(*out));
    int* diag = opts ? opts->diag : NULL;

    /* Bring up Vulkan first: if there is no usable GPU we return -1 immediately
     * (the bridge falls back to CPU) without wasting the layer-0 scan. */
    DvkContext c;
    if(dvk_init(&c) != 0) {
        return -1;
    }

    /* Layer-0 candidates (same as the CPU/Metal paths). */
    uint64_t* candidates46 = malloc(sizeof(uint64_t) * (1U << 20));
    if(!candidates46) {
        dvk_shutdown(&c);
        return -1;
    }
    const uint32_t ncand = hitag2hell_layer0(req->hop, candidates46, 1U << 20);
    if(ncand == 0) {
        free(candidates46);
        dvk_shutdown(&c);
        return 0;
    }

    /* Two candidate layouts: packed16 (3 uint16/cand) for the CPU kernel, and
     * cand2 (2 uint/cand: low32, high16) for the pure-32-bit GLSL kernel. */
    uint16_t* packed = malloc(sizeof(uint16_t) * 3U * ncand);
    uint32_t* cand2 = malloc(sizeof(uint32_t) * 2U * ncand);
    if(!packed || !cand2) {
        free(packed);
        free(cand2);
        free(candidates46);
        dvk_shutdown(&c);
        return -1;
    }
    for(uint32_t i = 0; i < ncand; i++) {
        hitag2hell_pack_candidate(candidates46[i], &packed[3U * i]);
        cand2[2U * i] = (uint32_t)(candidates46[i] & 0xFFFFFFFFULL);
        cand2[2U * i + 1] = (uint32_t)((candidates46[i] >> 32) & 0xFFFFFFFFULL);
    }

    uint32_t keystream[32];
    hitag2hell_bitslice_keystream(req->hop, keystream);

    DvkPipeline pipe;
    DvkBuffer ks_buf = {0}, cand_buf = {0}, match_buf = {0}, found_buf = {0};
    int pipe_ok = dvk_pipeline_create(
                      &c,
                      &pipe,
                      HITAG2HELL_VULKAN_SPIRV,
                      (size_t)HITAG2HELL_VULKAN_SPIRV_SIZE,
                      4,
                      (uint32_t)sizeof(Hitag2VkPush)) == 0;
    int buf_ok = pipe_ok &&
                 dvk_buffer_create(&c, &ks_buf, sizeof(keystream)) == 0 &&
                 dvk_buffer_create(&c, &cand_buf, sizeof(uint32_t) * 2U * ncand) == 0 &&
                 dvk_buffer_create(
                     &c, &match_buf, sizeof(uint32_t) * 2U * HITAG2HELL_MAX_STATES) == 0 &&
                 dvk_buffer_create(&c, &found_buf, sizeof(uint32_t)) == 0;
    if(!buf_ok) {
        dvk_buffer_destroy(&c, &ks_buf);
        dvk_buffer_destroy(&c, &cand_buf);
        dvk_buffer_destroy(&c, &match_buf);
        dvk_buffer_destroy(&c, &found_buf);
        if(pipe_ok) {
            dvk_pipeline_destroy(&c, &pipe);
        }
        dvk_shutdown(&c);
        free(packed);
        free(cand2);
        free(candidates46);
        return -1; /* fall back to CPU */
    }
    if(diag) {
        *diag |= HITAG2HELL_DIAG_GPU_INIT_OK;
    }

    memcpy(ks_buf.mapped, keystream, sizeof(keystream));
    memcpy(cand_buf.mapped, cand2, sizeof(uint32_t) * 2U * ncand);
    *(uint32_t*)found_buf.mapped = 0u;

    dvk_pipeline_bind_buffer(&c, &pipe, 0, &ks_buf);
    dvk_pipeline_bind_buffer(&c, &pipe, 1, &cand_buf);
    dvk_pipeline_bind_buffer(&c, &pipe, 2, &match_buf);
    dvk_pipeline_bind_buffer(&c, &pipe, 3, &found_buf);

    const uint32_t cap = HITAG2HELL_MAX_STATES;
    const uint32_t tile = 2048; /* candidates per submit, like Metal */
    const uint32_t local = 64;

    Hitag2HellShared sh;
    memset(&sh, 0, sizeof(sh));
    sh.req = req;
    sh.packed = packed;
    sh.keystream = keystream;
    sh.ncand = ncand;
    atomic_init(&sh.cpu_cursor, ncand);
    atomic_init(&sh.gpu_upto, 0);
    atomic_init(&sh.found, 0);
    atomic_init(&sh.states_tested, 0);
    atomic_init(&sh.keys_tried, 0);
    atomic_init(&sh.active_workers, 0);
    pthread_mutex_init(&sh.grab_lock, NULL);
    pthread_mutex_init(&sh.result_lock, NULL);
    sh.out = out;
    sh.external_cancel = (opts ? opts->cancel : NULL);

    /* Small, performance-biased CPU pool descending from the top. */
    int nworkers;
    if(opts && opts->cpu_threads > 0) {
        nworkers = opts->cpu_threads;
    } else {
#if defined(_WIN32)
        SYSTEM_INFO si;
        GetSystemInfo(&si);
        nworkers = (si.dwNumberOfProcessors >= 2) ? 2 : 1;
#else
        long n = sysconf(_SC_NPROCESSORS_ONLN);
        nworkers = (n >= 2) ? 2 : 1;
#endif
    }
    if(nworkers < 1) {
        nworkers = 1;
    }
    if(nworkers > 64) {
        nworkers = 64;
    }
    pthread_t* workers = calloc((size_t)nworkers, sizeof(pthread_t));
    int spawned = 0;
    if(workers) {
        for(int i = 0; i < nworkers; i++) {
            atomic_fetch_add_explicit(&sh.active_workers, 1, memory_order_relaxed);
            if(pthread_create(&workers[i], NULL, hitag2hell_cpu_worker, &sh) == 0) {
                spawned++;
            } else {
                atomic_fetch_sub_explicit(&sh.active_workers, 1, memory_order_relaxed);
                break;
            }
        }
    }

    /* GPU climbs from the bottom, one tile at a time. */
    uint32_t validated = 0;
    int gpu_error = 0;
    for(uint32_t base = 0; base < ncand; base += tile) {
        if(hitag2hell_cancelled(&sh)) {
            break;
        }
        if(atomic_load_explicit(&sh.found, memory_order_acquire)) {
            break;
        }
        if(base >= atomic_load_explicit(&sh.cpu_cursor, memory_order_relaxed)) {
            break; /* met the CPU front */
        }

        uint32_t count = tile;
        if(base + count > ncand) {
            count = ncand - base;
        }
        Hitag2VkPush push = {
            .candidate_index_base = base,
            .count = count,
            .matches_cap = cap,
        };
        const uint32_t groups_x = (count + local - 1u) / local;
        if(dvk_dispatch(
               &c,
               &pipe,
               &push,
               (uint32_t)sizeof(push),
               groups_x,
               HITAG2HELL_I1_SPAN,
               1u,
               sh.external_cancel) != 0) {
            gpu_error = 1;
            break;
        }

        atomic_store_explicit(
            &sh.gpu_upto, base + tile > ncand ? ncand : base + tile, memory_order_release);

        if(opts && opts->progress) {
            uint32_t reached = (base + tile > ncand) ? ncand : (base + tile);
            uint32_t cpu_done = ncand - atomic_load_explicit(&sh.cpu_cursor, memory_order_relaxed);
            uint32_t done = reached + cpu_done;
            if(done > ncand) {
                done = ncand;
            }
            opts->progress(done, ncand, opts->ctx);
        }

        /* Validate the states this tile added. */
        uint32_t found_now = *(volatile uint32_t*)found_buf.mapped;
        if(found_now > cap) {
            found_now = cap;
        }
        if(found_now > validated) {
            const uint32_t* matches = (const uint32_t*)match_buf.mapped;
            for(uint32_t i = validated; i < found_now; i++) {
                const uint64_t raw =
                    (uint64_t)matches[2U * i] | ((uint64_t)matches[2U * i + 1] << 32);
                uint64_t key, init;
                uint32_t uid;
                if(hitag2hell_verify_state(req, raw, &key, &init, &uid)) {
                    hitag2hell_report(&sh, key, init, uid);
                    break;
                }
            }
            atomic_fetch_add_explicit(
                &sh.states_tested, found_now - validated, memory_order_relaxed);
            atomic_fetch_add_explicit(
                &sh.keys_tried, (found_now - validated) * 2u, memory_order_relaxed);
            validated = found_now;
        }
        if(atomic_load_explicit(&sh.found, memory_order_acquire)) {
            break;
        }
    }

    /* If the GPU faulted mid-run, stop claiming GPU territory so the CPU pool
     * covers the remaining candidates (graceful degrade, not a hard failure). */
    if(gpu_error) {
        atomic_store_explicit(&sh.gpu_upto, 0, memory_order_release);
        if(diag && !hitag2hell_cancelled(&sh)) {
            *diag |= HITAG2HELL_DIAG_GPU_FAULT;
        }
    }

    while(atomic_load_explicit(&sh.active_workers, memory_order_acquire) > 0) {
        if(opts && opts->progress) {
            const uint32_t g = atomic_load_explicit(&sh.gpu_upto, memory_order_relaxed);
            const uint32_t cursor = atomic_load_explicit(&sh.cpu_cursor, memory_order_relaxed);
            const uint32_t cpu_done = (ncand >= cursor) ? (ncand - cursor) : 0u;
            uint32_t done = g + cpu_done;
            if(done > ncand) {
                done = ncand;
            }
            opts->progress(done, ncand, opts->ctx);
        }
        if(atomic_load_explicit(&sh.found, memory_order_acquire)) {
            break;
        }
        if(hitag2hell_cancelled(&sh)) {
            break;
        }
        hitag2hell_sleep_ms(100);
    }

    for(int i = 0; i < spawned; i++) {
        pthread_join(workers[i], NULL);
    }
    free(workers);

    const int ok = atomic_load_explicit(&sh.found, memory_order_acquire) ? 1 : 0;
    out->states_tested = atomic_load_explicit(&sh.states_tested, memory_order_relaxed);
    out->keys_tried = atomic_load_explicit(&sh.keys_tried, memory_order_relaxed);

    pthread_mutex_destroy(&sh.grab_lock);
    pthread_mutex_destroy(&sh.result_lock);

    dvk_buffer_destroy(&c, &ks_buf);
    dvk_buffer_destroy(&c, &cand_buf);
    dvk_buffer_destroy(&c, &match_buf);
    dvk_buffer_destroy(&c, &found_buf);
    dvk_pipeline_destroy(&c, &pipe);
    dvk_shutdown(&c);

    free(packed);
    free(cand2);
    free(candidates46);

    if(hitag2hell_cancelled(&sh) && !ok) {
        return -1;
    }
    return ok;
}

#endif /* __ANDROID__ || _WIN32 */
