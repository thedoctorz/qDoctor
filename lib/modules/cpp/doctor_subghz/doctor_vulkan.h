// Minimal Vulkan compute helper for the GPU path of our Sub-GHz engine.
// Wraps the boilerplate the hitag2hell / psabf drivers need: one compute queue,
// host-visible+coherent storage buffers (phones are integrated GPUs, so shared
// memory is the fast path — the moral equivalent of Metal's StorageModeShared;
// discrete Windows GPUs still work, just through a host-visible heap),
// a SPIR-V compute pipeline with N storage-buffer bindings + push constants,
// and a submit-and-wait dispatch. C-only so it links under ANDROID_STL=none.
//
// Android links libvulkan. Windows loads vulkan-1.dll at runtime so machines
// without a Vulkan loader still load this FFI library and fall back to CPU.
#pragma once

#if defined(__ANDROID__) || defined(_WIN32)

#if defined(_WIN32) && !defined(VK_NO_PROTOTYPES)
#define VK_NO_PROTOTYPES
#endif

#include <stddef.h>
#include <stdint.h>
#include <vulkan/vulkan.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    VkInstance instance;
    VkPhysicalDevice phys;
    VkDevice device;
    uint32_t queue_family;
    VkQueue queue;
    VkCommandPool pool;
    VkCommandBuffer cmd;
    VkFence fence;
    VkPhysicalDeviceMemoryProperties mem_props;
    int lost;
} DvkContext;

typedef struct {
    VkBuffer buffer;
    VkDeviceMemory memory;
    void* mapped; /* persistently mapped, host-coherent */
    VkDeviceSize size;
} DvkBuffer;

typedef struct {
    VkShaderModule module;
    VkDescriptorSetLayout dsl;
    VkPipelineLayout layout;
    VkPipeline pipeline;
    VkDescriptorPool dpool;
    VkDescriptorSet dset;
    uint32_t nbuffers;
} DvkPipeline;

/* 0 on success. Fails cleanly (returns non-zero) with no allocated state when
 * there is no Vulkan loader / no compute-capable device, so the caller can fall
 * back to the CPU oracle. */
int dvk_init(DvkContext* c);
void dvk_shutdown(DvkContext* c);

/* Cheap availability probe: create + tear down a context. */
int dvk_available(void);

int dvk_buffer_create(DvkContext* c, DvkBuffer* b, VkDeviceSize size);
void dvk_buffer_destroy(DvkContext* c, DvkBuffer* b);

int dvk_pipeline_create(
    DvkContext* c,
    DvkPipeline* p,
    const uint32_t* spirv,
    size_t spirv_bytes,
    uint32_t nbuffers,
    uint32_t push_const_bytes);
void dvk_pipeline_destroy(DvkContext* c, DvkPipeline* p);

/* Point descriptor `binding` at `b` (whole-buffer range). */
void dvk_pipeline_bind_buffer(
    DvkContext* c, DvkPipeline* p, uint32_t binding, const DvkBuffer* b);

int dvk_dispatch(
    DvkContext* c,
    DvkPipeline* p,
    const void* push_const,
    uint32_t push_const_bytes,
    uint32_t gx,
    uint32_t gy,
    uint32_t gz,
    volatile int* cancel);

#ifdef __cplusplus
}
#endif

#endif /* __ANDROID__ || _WIN32 */
