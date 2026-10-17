// Vulkan GPU path for the PSA TEA bruteforce — the compute twin of
// psabf_metal.m. Two staged sweeps (BF1 then BF2) over the 2 x 16M counter
// space, dispatched in tiles with the same cancel/progress contract as Metal.
// Returns 1 = found, 0 = not found, -1 = cancelled, -2 = no usable Vulkan GPU
// (the bridge then falls back to the CPU oracle).
#if defined(__ANDROID__) || defined(_WIN32)

#include "psabf.h"

#include "doctor_vulkan.h"
#include "psabf_spirv.h"

#include <string.h>

typedef struct {
    uint32_t w0;
    uint32_t w1;
    uint32_t start;
    uint32_t count;
    uint32_t stage;
} PsaBfVkPush;

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

static int psa_bf_cancelled_v(const PsaBfVulkanOptions* opts) {
    return opts && opts->cancel && *opts->cancel;
}

static int psa_bf_dispatch_stage_vk(
    DvkContext* c,
    DvkPipeline* p,
    DvkBuffer* found_buf,
    DvkBuffer* out_buf,
    uint32_t w0,
    uint32_t w1,
    uint32_t stage,
    uint32_t range_start,
    uint32_t range_end,
    uint32_t progress_base,
    uint32_t progress_total,
    const PsaBfVulkanOptions* opts,
    uint32_t* out_v0,
    uint32_t* out_v1) {
    const uint32_t tile = 262144U; /* 256Ki counters per submit, like Metal */
    const uint32_t local = 64U;

    /* Reset the found gate + result for this stage. */
    *(uint32_t*)found_buf->mapped = 0u;
    memset(out_buf->mapped, 0, 3 * sizeof(uint32_t));

    for(uint32_t start = range_start; start < range_end; start += tile) {
        if(psa_bf_cancelled_v(opts)) {
            return -1;
        }
        if(*(volatile uint32_t*)found_buf->mapped) {
            break;
        }
        uint32_t count = tile;
        if(start + count > range_end) {
            count = range_end - start;
        }

        PsaBfVkPush push = {
            .w0 = w0,
            .w1 = w1,
            .start = start,
            .count = count,
            .stage = stage,
        };
        const uint32_t groups = (count + local - 1u) / local;
        if(dvk_dispatch(c, p, &push, (uint32_t)sizeof(push), groups, 1u, 1u) != 0) {
            return -2;
        }

        if(opts && opts->progress) {
            uint32_t done = progress_base + (start + count - range_start);
            if(done > progress_total) {
                done = progress_total;
            }
            opts->progress(done, progress_total, opts->ctx);
        }
    }

    if(*(volatile uint32_t*)found_buf->mapped) {
        const uint32_t* out = (const uint32_t*)out_buf->mapped;
        *out_v0 = out[0];
        *out_v1 = out[1];
        return 1;
    }
    return psa_bf_cancelled_v(opts) ? -1 : 0;
}

int psa_bf_recover_vulkan(
    const PsaBfRequest* req,
    PsaBfResult* out,
    const PsaBfVulkanOptions* opts) {
    if(!req || !out) {
        return 0;
    }
    memset(out, 0, sizeof(*out));

    DvkContext c;
    if(dvk_init(&c) != 0) {
        return -2;
    }

    DvkPipeline pipe;
    if(dvk_pipeline_create(
           &c,
           &pipe,
           PSABF_VULKAN_SPIRV,
           (size_t)PSABF_VULKAN_SPIRV_SIZE,
           4,
           (uint32_t)sizeof(PsaBfVkPush)) != 0) {
        dvk_shutdown(&c);
        return -2;
    }

    DvkBuffer s0_buf = {0}, s1_buf = {0}, found_buf = {0}, out_buf = {0};
    int rc = -2;
    int ok = dvk_buffer_create(&c, &s0_buf, 32 * sizeof(uint32_t)) == 0 &&
             dvk_buffer_create(&c, &s1_buf, 32 * sizeof(uint32_t)) == 0 &&
             dvk_buffer_create(&c, &found_buf, sizeof(uint32_t)) == 0 &&
             dvk_buffer_create(&c, &out_buf, 3 * sizeof(uint32_t)) == 0;
    if(!ok) {
        goto cleanup_buffers;
    }

    uint32_t s0[32];
    uint32_t s1[32];
    psa_bf_schedules(s0, s1);
    memcpy(s0_buf.mapped, s0, sizeof(s0));
    memcpy(s1_buf.mapped, s1, sizeof(s1));

    dvk_pipeline_bind_buffer(&c, &pipe, 0, &s0_buf);
    dvk_pipeline_bind_buffer(&c, &pipe, 1, &s1_buf);
    dvk_pipeline_bind_buffer(&c, &pipe, 2, &found_buf);
    dvk_pipeline_bind_buffer(&c, &pipe, 3, &out_buf);

    uint32_t w0 = 0;
    uint32_t w1 = 0;
    psa_bf_setup_cipher(req->key1_low, req->key1_high, req->key2_low, &w0, &w1);
    const uint32_t total =
        (PSA_BF_BF1_END - PSA_BF_BF1_START) + (PSA_BF_BF2_END - PSA_BF_BF2_START);

    uint32_t v0 = 0;
    uint32_t v1 = 0;
    rc = psa_bf_dispatch_stage_vk(
        &c,
        &pipe,
        &found_buf,
        &out_buf,
        w0,
        w1,
        1,
        PSA_BF_BF1_START,
        PSA_BF_BF1_END,
        0,
        total,
        opts,
        &v0,
        &v1);
    if(rc == 0) {
        rc = psa_bf_dispatch_stage_vk(
            &c,
            &pipe,
            &found_buf,
            &out_buf,
            w0,
            w1,
            2,
            PSA_BF_BF2_START,
            PSA_BF_BF2_END,
            PSA_BF_BF1_END - PSA_BF_BF1_START,
            total,
            opts,
            &v0,
            &v1);
    }

    if(rc == 1) {
        psa_bf_fill_result(v0, v1, out);
    }
    out->states_tried = total;

cleanup_buffers:
    dvk_buffer_destroy(&c, &s0_buf);
    dvk_buffer_destroy(&c, &s1_buf);
    dvk_buffer_destroy(&c, &found_buf);
    dvk_buffer_destroy(&c, &out_buf);
    dvk_pipeline_destroy(&c, &pipe);
    dvk_shutdown(&c);
    if(!ok) {
        return -2;
    }
    return rc;
}

#endif /* __ANDROID__ || _WIN32 */
