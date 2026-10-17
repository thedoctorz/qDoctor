#ifdef __APPLE__

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#include "hitag2hell.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <pthread.h>
#include <pthread/qos.h>
#include <stdatomic.h>

static NSString* hitag2hell_load_shader_source(NSError** error) {
    NSArray<NSString*>* candidates = @[
        @"tools/hitag2hell-metal/kernel/hitag2hell_standalone.metal",
        @"kernel/hitag2hell_standalone.metal",
        [[NSBundle mainBundle] pathForResource:@"hitag2hell_standalone" ofType:@"metal"] ?: @"",
        @"tools/hitag2hell-metal/kernel/hitag2hell.metal",
        @"kernel/hitag2hell.metal",
    ];
    for(NSString* path in candidates) {
        if(path.length == 0) {
            continue;
        }
        NSString* src = [NSString stringWithContentsOfFile:path
                                                 encoding:NSUTF8StringEncoding
                                                    error:nil];
        if(src.length) {
            return src;
        }
    }
    if(error) {
        *error = [NSError errorWithDomain:@"hitag2hell"
                                     code:1
                                 userInfo:@{NSLocalizedDescriptionKey : @"missing hitag2hell.metal"}];
    }
    return nil;
}

/* Verify one raw kernel state against the request. On success fills key/init/uid
 * and returns 1. Tries both uid and ~uid (the known Hitag2 complement
 * ambiguity). Shared by the GPU validation and the CPU workers. */
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

/* State shared between the GPU driver (this thread) and the CPU workers.
 * The candidate range [0, ncand) is covered from both ends: the GPU claims
 * tiles rising from 0 (gpu_upto), the CPU workers claim blocks falling from
 * ncand (cpu_cursor). They stop when the two fronts meet or the key is found. */
typedef struct {
    const Hitag2HellRequest* req;
    const uint16_t* packed; /* 3 uint16 per candidate */
    const uint32_t* keystream; /* 32 bitsliced words */
    uint32_t ncand;

    _Atomic uint32_t cpu_cursor; /* exclusive top of the CPU-unclaimed region */
    _Atomic uint32_t gpu_upto; /* candidates covered from the bottom by the GPU */
    _Atomic int found;
    _Atomic uint32_t states_tested;
    _Atomic uint32_t keys_tried;

    pthread_mutex_t grab_lock; /* serializes CPU cursor reservations */
    pthread_mutex_t result_lock; /* first finder writes the result */
    Hitag2HellResult* out;

    volatile int* external_cancel;
} Hitag2HellShared;

static int hitag2hell_cancelled(const Hitag2HellShared* sh) {
    return (sh->external_cancel && *sh->external_cancel) ? 1 : 0;
}

/* First writer wins. Records the key and flips `found` so both sides stop. */
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
 * meeting the GPU which climbs from the bottom. Uses the same 32-way bitslice
 * kernel as the GPU (`hitag2hell_find_state_cpu`). */
static void* hitag2hell_cpu_worker(void* arg) {
    Hitag2HellShared* sh = (Hitag2HellShared*)arg;
    pthread_set_qos_class_self_np(QOS_CLASS_USER_INITIATED, 0);

    const uint32_t block = 64;
    /* Per-candidate match scratch. Matches per candidate are tiny (total over
     * all candidates ~2^16 across 2^19 candidates), so this never fills. */
    uint64_t states[256];

    for(;;) {
        if(atomic_load_explicit(&sh->found, memory_order_acquire)) {
            break;
        }
        if(hitag2hell_cancelled(sh)) {
            break;
        }

        /* Reserve a block [start, top) from the descending cursor. */
        pthread_mutex_lock(&sh->grab_lock);
        uint32_t g = atomic_load_explicit(&sh->gpu_upto, memory_order_relaxed);
        uint32_t top = atomic_load_explicit(&sh->cpu_cursor, memory_order_relaxed);
        if(top <= g) {
            pthread_mutex_unlock(&sh->grab_lock);
            break; /* fronts met: everything is covered */
        }
        uint32_t start = (top > block) ? (top - block) : 0u;
        if(start < g) {
            start = g; /* don't dip into GPU-covered territory */
        }
        atomic_store_explicit(&sh->cpu_cursor, start, memory_order_relaxed);
        pthread_mutex_unlock(&sh->grab_lock);

        uint32_t local_states = 0;
        uint32_t local_keys = 0;
        for(uint32_t c = start; c < top; c++) {
            if(atomic_load_explicit(&sh->found, memory_order_acquire)) {
                break;
            }
            if(hitag2hell_cancelled(sh)) {
                break;
            }
            uint32_t n = 0;
            for(uint32_t i1 = 0; i1 < HITAG2HELL_I1_SPAN; i1++) {
                hitag2hell_find_state_cpu(
                    sh->keystream, &sh->packed[3U * c], states, &n, 0, 0, i1, 256);
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
    return NULL;
}

/* Compile the kernel once. Recompiling the embedded MSL on every start/cancel
 * is what OOM-kills the app when the user hammers enter/exit. */
static id<MTLDevice> gHitag2Device;
static id<MTLComputePipelineState> gHitag2Pso;

static id<MTLComputePipelineState> hitag2hell_cached_pso(
    const Hitag2HellMetalOptions* mopts, id<MTLDevice>* device_out) {
    if(gHitag2Pso && gHitag2Device) {
        *device_out = gHitag2Device;
        return gHitag2Pso;
    }

    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    if(!device) {
        NSArray<id<MTLDevice>>* devices = MTLCopyAllDevices();
        if(devices.count) {
            device = devices.firstObject;
        }
    }
    if(!device) {
        fprintf(stderr, "Metal: no device\n");
        return nil;
    }

    NSError* error = nil;
    id<MTLLibrary> library = nil;

    if(mopts && mopts->library_path && mopts->library_path[0]) {
        NSURL* url = [NSURL fileURLWithPath:[NSString stringWithUTF8String:mopts->library_path]];
        library = [device newLibraryWithURL:url error:&error];
    }

    if(!library) {
        NSString* source = nil;
        if(mopts && mopts->shader_source && mopts->shader_source[0]) {
            source = [NSString stringWithUTF8String:mopts->shader_source];
        }
        if(!source) {
            source = hitag2hell_load_shader_source(&error);
        }
        if(source) {
            MTLCompileOptions* opts = [MTLCompileOptions new];
            opts.languageVersion = MTLLanguageVersion2_4;
            library = [device newLibraryWithSource:source options:opts error:&error];
        }
    }

    if(!library) {
        fprintf(stderr, "Metal: could not load library: %s\n",
            error ? error.localizedDescription.UTF8String : "no metallib or source");
        return nil;
    }
    id<MTLFunction> fn = [library newFunctionWithName:@"hitag2hell_find_state_kernel"];
    if(!fn) {
        fprintf(stderr, "Metal: kernel symbol missing\n");
        return nil;
    }
    id<MTLComputePipelineState> pso =
        [device newComputePipelineStateWithFunction:fn error:&error];
    if(!pso) {
        fprintf(stderr, "Metal PSO failed: %s\n", error.localizedDescription.UTF8String);
        return nil;
    }
    gHitag2Device = device;
    gHitag2Pso = pso;
    *device_out = device;
    return pso;
}

int hitag2hell_recover_metal(
    const Hitag2HellRequest* req,
    Hitag2HellResult* out,
    const Hitag2HellMetalOptions* mopts) {
    memset(out, 0, sizeof(*out));

    id<MTLDevice> device = nil;
    id<MTLComputePipelineState> pso = hitag2hell_cached_pso(mopts, &device);
    if(!pso || !device) {
        return -1;
    }

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

    id<MTLCommandQueue> queue = [device newCommandQueue];
    id<MTLBuffer> ksBuf = [device newBufferWithBytes:keystream
                                              length:sizeof(keystream)
                                             options:MTLResourceStorageModeShared];
    id<MTLBuffer> candBuf = [device newBufferWithBytes:packed
                                                length:sizeof(uint16_t) * 3U * ncand
                                               options:MTLResourceStorageModeShared];
    id<MTLBuffer> matchBuf =
        [device newBufferWithLength:sizeof(uint64_t) * HITAG2HELL_MAX_STATES
                            options:MTLResourceStorageModeShared];
    uint32_t zero = 0;
    id<MTLBuffer> foundBuf = [device newBufferWithBytes:&zero
                                                 length:sizeof(uint32_t)
                                                options:MTLResourceStorageModeShared];

    const uint32_t cap = HITAG2HELL_MAX_STATES;
    const uint32_t tile = 2048;

    // Shared state for the bidirectional search: GPU rises from 0, CPU workers
    // fall from ncand, meeting in the middle. Whichever front reaches the
    // winning candidate first records the key and stops the other side.
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
    pthread_mutex_init(&sh.grab_lock, NULL);
    pthread_mutex_init(&sh.result_lock, NULL);
    sh.out = out;
    sh.external_cancel = (mopts ? mopts->cancel : NULL);

    // Spawn CPU workers descending from the top. A small, performance-core-
    // biased pool: on a thermally-limited phone a couple of workers deliver
    // most of the CPU assist with far less heat than saturating every core
    // (which just throttles the GPU that does the bulk of the work).
    int nworkers;
    if(mopts && mopts->cpu_threads > 0) {
        nworkers = mopts->cpu_threads;
    } else {
        long n = sysconf(_SC_NPROCESSORS_ONLN);
        nworkers = (n >= 2) ? 2 : 1;
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
            if(pthread_create(&workers[i], NULL, hitag2hell_cpu_worker, &sh) == 0) {
                spawned++;
            } else {
                break;
            }
        }
    }

    // GPU climbs from the bottom, one tile at a time.
    uint32_t validated = 0;
    for(uint32_t base = 0; base < ncand; base += tile) {
        if(hitag2hell_cancelled(&sh)) {
            break;
        }
        if(atomic_load_explicit(&sh.found, memory_order_acquire)) {
            break;
        }
        if(base >= atomic_load_explicit(&sh.cpu_cursor, memory_order_relaxed)) {
            break; // met the CPU front; the rest is covered from the top
        }

      @autoreleasepool {
        uint32_t count = tile;
        if(base + count > ncand) {
            count = ncand - base;
        }
        uint32_t base_copy = base;
        id<MTLBuffer> baseBuf = [device newBufferWithBytes:&base_copy
                                                    length:sizeof(uint32_t)
                                                   options:MTLResourceStorageModeShared];
        id<MTLBuffer> capBuf = [device newBufferWithBytes:&cap
                                                   length:sizeof(uint32_t)
                                                  options:MTLResourceStorageModeShared];

        for(;;) {
            if(hitag2hell_cancelled(&sh)) {
                break;
            }
            id<MTLCommandBuffer> cmd = [queue commandBuffer];
            if(!cmd) {
                usleep(250000);
                continue;
            }
            id<MTLComputeCommandEncoder> enc = [cmd computeCommandEncoder];
            if(!enc) {
                usleep(250000);
                continue;
            }
            [enc setComputePipelineState:pso];
            [enc setBuffer:ksBuf offset:0 atIndex:0];
            [enc setBuffer:candBuf offset:0 atIndex:1];
            [enc setBuffer:matchBuf offset:0 atIndex:2];
            [enc setBuffer:foundBuf offset:0 atIndex:3];
            [enc setBuffer:baseBuf offset:0 atIndex:4];
            [enc setBuffer:capBuf offset:0 atIndex:5];
            MTLSize grid = MTLSizeMake(count, HITAG2HELL_I1_SPAN, 1);
            NSUInteger w = pso.threadExecutionWidth;
            MTLSize tg = MTLSizeMake(w, 1, 1);
            [enc dispatchThreads:grid threadsPerThreadgroup:tg];
            [enc endEncoding];
            [cmd commit];
            [cmd waitUntilCompleted];
            if(cmd.status == MTLCommandBufferStatusCompleted) {
                break;
            }
            // Keep using Metal. If iOS interrupts a buffer, resubmit
            // this tile instead of aborting or falling back to CPU.
            usleep(50000);
        }
      } /* @autoreleasepool */

        atomic_store_explicit(&sh.gpu_upto,
            base + tile > ncand ? ncand : base + tile, memory_order_release);

        if(mopts && mopts->progress) {
            // Combined coverage: GPU from the bottom + CPU from the top.
            uint32_t reached = (base + tile > ncand) ? ncand : (base + tile);
            uint32_t cpu_done = ncand - atomic_load_explicit(&sh.cpu_cursor, memory_order_relaxed);
            uint32_t done = reached + cpu_done;
            if(done > ncand) {
                done = ncand;
            }
            mopts->progress(done, ncand, mopts->ctx);
        }

        // Validate the states this tile added (the winning state lands in a
        // random tile, so on average we stop after ~half the tiles). Route a
        // hit through the shared reporter so it races cleanly with the CPU.
        uint32_t found_now = *(const uint32_t*)foundBuf.contents;
        if(found_now > cap) {
            found_now = cap;
        }
        if(found_now > validated) {
            const uint64_t* matches = (const uint64_t*)matchBuf.contents;
            for(uint32_t i = validated; i < found_now; i++) {
                uint64_t key, init;
                uint32_t uid;
                if(hitag2hell_verify_state(req, matches[i], &key, &init, &uid)) {
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

    // The GPU is done dispatching. Wait for the CPU workers to drain their
    // in-flight blocks: they stop claiming new work once it is all below
    // gpu_upto (or on found/cancel), so a worker always finishes the block
    // that may contain the winner before exiting. No extra stop signal here.
    for(int i = 0; i < spawned; i++) {
        pthread_join(workers[i], NULL);
    }
    free(workers);

    const int ok = atomic_load_explicit(&sh.found, memory_order_acquire) ? 1 : 0;
    out->states_tested = atomic_load_explicit(&sh.states_tested, memory_order_relaxed);
    out->keys_tried = atomic_load_explicit(&sh.keys_tried, memory_order_relaxed);

    pthread_mutex_destroy(&sh.grab_lock);
    pthread_mutex_destroy(&sh.result_lock);

    free(packed);
    free(candidates46);
    return ok;
}

#endif

// C-callable Metal availability probe for the platform bridge (added for the
// DoctorMobile-doctor port). Real iOS devices always have a Metal device; the
// simulator without a GPU / headless CI returns nil, so the bridge can fall
// back to the CPU oracle.
int hitag2hell_metal_available(void) {
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    return device != nil ? 1 : 0;
}
