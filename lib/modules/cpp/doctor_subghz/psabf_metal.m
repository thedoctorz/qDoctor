#ifdef __APPLE__

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#include "psabf.h"

#include <stdio.h>
#include <string.h>
#include <unistd.h>

typedef struct {
    uint32_t w0;
    uint32_t w1;
    uint32_t start;
    uint32_t count;
    uint32_t stage;
    uint32_t pad0;
    uint32_t pad1;
    uint32_t pad2;
} PsaBfMetalParams;

static void psa_bf_schedules(uint32_t s0[32], uint32_t s1[32]) {
    const uint32_t key[4] = {
        0x4A434915U,
        0xD6743C2BU,
        0x1F29D308U,
        0xE6B79A64U,
    };
    const uint32_t delta = 0x9E3779B9U;
    for(int i = 0; i < 32; i++) {
        uint32_t sum0 = (uint32_t)((uint64_t)i * delta);
        uint32_t sum1 = (uint32_t)((uint64_t)(i + 1) * delta);
        s0[i] = key[sum0 & 3] + sum0;
        s1[i] = key[(sum1 >> 11) & 3] + sum1;
    }
}

static int psa_bf_cancelled_m(const PsaBfMetalOptions* opts) {
    return opts && opts->cancel && *opts->cancel;
}

static int psa_bf_dispatch_stage(
    id<MTLDevice> device,
    id<MTLCommandQueue> queue,
    id<MTLComputePipelineState> pso,
    id<MTLBuffer> s0Buf,
    id<MTLBuffer> s1Buf,
    uint32_t w0,
    uint32_t w1,
    uint32_t stage,
    uint32_t range_start,
    uint32_t range_end,
    uint32_t progress_base,
    uint32_t progress_total,
    const PsaBfMetalOptions* opts,
    uint32_t* out_v0,
    uint32_t* out_v1) {
    const uint32_t tile = 262144U;
    uint32_t zero = 0;
    id<MTLBuffer> foundBuf = [device newBufferWithBytes:&zero
                                                 length:sizeof(uint32_t)
                                                options:MTLResourceStorageModeShared];
    uint32_t outZero[3] = {0, 0, 0};
    id<MTLBuffer> outBuf = [device newBufferWithBytes:outZero
                                                length:sizeof(outZero)
                                               options:MTLResourceStorageModeShared];

    for(uint32_t start = range_start; start < range_end; start += tile) {
        if(psa_bf_cancelled_m(opts)) {
            return -1;
        }
        uint32_t* found = (uint32_t*)foundBuf.contents;
        if(found && *found) {
            break;
        }
        uint32_t count = tile;
        if(start + count > range_end) {
            count = range_end - start;
        }
        PsaBfMetalParams params = {
            .w0 = w0,
            .w1 = w1,
            .start = start,
            .count = count,
            .stage = stage,
        };
      @autoreleasepool {
        id<MTLBuffer> pBuf = [device newBufferWithBytes:&params
                                                length:sizeof(params)
                                               options:MTLResourceStorageModeShared];
        id<MTLCommandBuffer> cmd = [queue commandBuffer];
        if(!cmd) {
            usleep(100000);
            continue;
        }
        id<MTLComputeCommandEncoder> enc = [cmd computeCommandEncoder];
        if(!enc) {
            usleep(100000);
            continue;
        }
        [enc setComputePipelineState:pso];
        [enc setBuffer:pBuf offset:0 atIndex:0];
        [enc setBuffer:s0Buf offset:0 atIndex:1];
        [enc setBuffer:s1Buf offset:0 atIndex:2];
        [enc setBuffer:foundBuf offset:0 atIndex:3];
        [enc setBuffer:outBuf offset:0 atIndex:4];
        NSUInteger w = pso.threadExecutionWidth;
        if(w == 0) {
            w = 32;
        }
        MTLSize grid = MTLSizeMake(count, 1, 1);
        MTLSize tg = MTLSizeMake(w, 1, 1);
        [enc dispatchThreads:grid threadsPerThreadgroup:tg];
        [enc endEncoding];
        [cmd commit];
        [cmd waitUntilCompleted];
      }
        if(opts && opts->progress) {
            uint32_t done = progress_base + (start + count - range_start);
            if(done > progress_total) {
                done = progress_total;
            }
            opts->progress(done, progress_total, opts->ctx);
        }
    }

    uint32_t* found = (uint32_t*)foundBuf.contents;
    uint32_t* out = (uint32_t*)outBuf.contents;
    if(found && *found) {
        *out_v0 = out[0];
        *out_v1 = out[1];
        return 1;
    }
    return psa_bf_cancelled_m(opts) ? -1 : 0;
}

static id<MTLDevice> gPsaDevice;
static id<MTLComputePipelineState> gPsaPso;

static id<MTLComputePipelineState> psa_bf_cached_pso(
    const PsaBfMetalOptions* mopts, id<MTLDevice>* device_out) {
    if(gPsaPso && gPsaDevice) {
        *device_out = gPsaDevice;
        return gPsaPso;
    }

    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    if(!device) {
        NSArray<id<MTLDevice>>* devices = MTLCopyAllDevices();
        if(devices.count) {
            device = devices.firstObject;
        }
    }
    if(!device) {
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
        if(source) {
            MTLCompileOptions* copts = [MTLCompileOptions new];
            copts.languageVersion = MTLLanguageVersion2_4;
            library = [device newLibraryWithSource:source options:copts error:&error];
        }
    }
    if(!library) {
        return nil;
    }
    id<MTLFunction> fn = [library newFunctionWithName:@"psa_bf_search"];
    if(!fn) {
        return nil;
    }
    id<MTLComputePipelineState> pso =
        [device newComputePipelineStateWithFunction:fn error:&error];
    if(!pso) {
        return nil;
    }
    gPsaDevice = device;
    gPsaPso = pso;
    *device_out = device;
    return pso;
}

int psa_bf_recover_metal(
    const PsaBfRequest* req,
    PsaBfResult* out,
    const PsaBfMetalOptions* mopts) {
    if(!req || !out) {
        return 0;
    }
    memset(out, 0, sizeof(*out));

    id<MTLDevice> device = nil;
    id<MTLComputePipelineState> pso = psa_bf_cached_pso(mopts, &device);
    if(!pso || !device) {
        return -2;
    }
    id<MTLCommandQueue> queue = [device newCommandQueue];
    if(!queue) {
        return -2;
    }

    uint32_t s0[32];
    uint32_t s1[32];
    psa_bf_schedules(s0, s1);
    id<MTLBuffer> s0Buf = [device newBufferWithBytes:s0
                                              length:sizeof(s0)
                                             options:MTLResourceStorageModeShared];
    id<MTLBuffer> s1Buf = [device newBufferWithBytes:s1
                                              length:sizeof(s1)
                                             options:MTLResourceStorageModeShared];

    uint32_t w0 = 0;
    uint32_t w1 = 0;
    psa_bf_setup_cipher(req->key1_low, req->key1_high, req->key2_low, &w0, &w1);
    const uint32_t total =
        (PSA_BF_BF1_END - PSA_BF_BF1_START) + (PSA_BF_BF2_END - PSA_BF_BF2_START);

    uint32_t v0 = 0;
    uint32_t v1 = 0;
    int rc = psa_bf_dispatch_stage(
        device,
        queue,
        pso,
        s0Buf,
        s1Buf,
        w0,
        w1,
        1,
        PSA_BF_BF1_START,
        PSA_BF_BF1_END,
        0,
        total,
        mopts,
        &v0,
        &v1);
    if(rc == 1) {
        psa_bf_fill_result(v0, v1, out);
        out->states_tried = PSA_BF_BF1_END - PSA_BF_BF1_START;
        return 1;
    }
    if(rc < 0) {
        return rc;
    }
    rc = psa_bf_dispatch_stage(
        device,
        queue,
        pso,
        s0Buf,
        s1Buf,
        w0,
        w1,
        2,
        PSA_BF_BF2_START,
        PSA_BF_BF2_END,
        PSA_BF_BF1_END - PSA_BF_BF1_START,
        total,
        mopts,
        &v0,
        &v1);
    if(rc == 1) {
        psa_bf_fill_result(v0, v1, out);
        out->states_tried = total;
        return 1;
    }
    out->states_tried = total;
    return rc;
}

#endif
