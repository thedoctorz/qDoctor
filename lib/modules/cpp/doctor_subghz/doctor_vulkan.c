#if defined(__ANDROID__) || defined(_WIN32)

#include "doctor_vulkan.h"

#include <stdlib.h>
#include <string.h>

#if defined(_WIN32)
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>

#define DVK_PFN(name) static PFN_##name name
DVK_PFN(vkGetInstanceProcAddr);
DVK_PFN(vkGetDeviceProcAddr);
DVK_PFN(vkCreateInstance);
DVK_PFN(vkDestroyInstance);
DVK_PFN(vkEnumeratePhysicalDevices);
DVK_PFN(vkGetPhysicalDeviceProperties);
DVK_PFN(vkGetPhysicalDeviceQueueFamilyProperties);
DVK_PFN(vkGetPhysicalDeviceMemoryProperties);
DVK_PFN(vkCreateDevice);
DVK_PFN(vkDestroyDevice);
DVK_PFN(vkGetDeviceQueue);
DVK_PFN(vkDeviceWaitIdle);
DVK_PFN(vkCreateCommandPool);
DVK_PFN(vkDestroyCommandPool);
DVK_PFN(vkAllocateCommandBuffers);
DVK_PFN(vkCreateFence);
DVK_PFN(vkDestroyFence);
DVK_PFN(vkCreateBuffer);
DVK_PFN(vkDestroyBuffer);
DVK_PFN(vkGetBufferMemoryRequirements);
DVK_PFN(vkAllocateMemory);
DVK_PFN(vkFreeMemory);
DVK_PFN(vkBindBufferMemory);
DVK_PFN(vkMapMemory);
DVK_PFN(vkCreateShaderModule);
DVK_PFN(vkDestroyShaderModule);
DVK_PFN(vkCreateDescriptorSetLayout);
DVK_PFN(vkDestroyDescriptorSetLayout);
DVK_PFN(vkCreatePipelineLayout);
DVK_PFN(vkDestroyPipelineLayout);
DVK_PFN(vkCreateComputePipelines);
DVK_PFN(vkDestroyPipeline);
DVK_PFN(vkCreateDescriptorPool);
DVK_PFN(vkDestroyDescriptorPool);
DVK_PFN(vkAllocateDescriptorSets);
DVK_PFN(vkUpdateDescriptorSets);
DVK_PFN(vkResetCommandBuffer);
DVK_PFN(vkBeginCommandBuffer);
DVK_PFN(vkEndCommandBuffer);
DVK_PFN(vkCmdBindPipeline);
DVK_PFN(vkCmdBindDescriptorSets);
DVK_PFN(vkCmdPushConstants);
DVK_PFN(vkCmdDispatch);
DVK_PFN(vkCmdPipelineBarrier);
DVK_PFN(vkResetFences);
DVK_PFN(vkQueueSubmit);
DVK_PFN(vkWaitForFences);
#undef DVK_PFN

static HMODULE dvk_mod;

static int dvk_bind(const char* name, void** slot, VkInstance inst, VkDevice dev) {
    PFN_vkVoidFunction fn = NULL;
    if(dev && vkGetDeviceProcAddr) {
        fn = vkGetDeviceProcAddr(dev, name);
    }
    if(!fn && vkGetInstanceProcAddr) {
        fn = vkGetInstanceProcAddr(inst, name);
    }
    if(!fn && dvk_mod) {
        fn = (PFN_vkVoidFunction)(void*)GetProcAddress(dvk_mod, name);
    }
    if(!fn) {
        return -1;
    }
    *slot = (void*)fn;
    return 0;
}

#define DVK_BIND(name, inst, dev)                                  \
    do {                                                           \
        if(dvk_bind(#name, (void**)&(name), (inst), (dev)) != 0) { \
            return -1;                                             \
        }                                                          \
    } while(0)

static int dvk_load_loader(void) {
    if(dvk_mod) {
        return 0;
    }
    dvk_mod = LoadLibraryW(L"vulkan-1.dll");
    if(!dvk_mod) {
        return -1;
    }
    vkGetInstanceProcAddr =
        (PFN_vkGetInstanceProcAddr)(void*)GetProcAddress(dvk_mod, "vkGetInstanceProcAddr");
    if(!vkGetInstanceProcAddr) {
        FreeLibrary(dvk_mod);
        dvk_mod = NULL;
        return -1;
    }
    return 0;
}

static int dvk_load_instance(VkInstance inst) {
    DVK_BIND(vkDestroyInstance, inst, NULL);
    DVK_BIND(vkEnumeratePhysicalDevices, inst, NULL);
    DVK_BIND(vkGetPhysicalDeviceProperties, inst, NULL);
    DVK_BIND(vkGetPhysicalDeviceQueueFamilyProperties, inst, NULL);
    DVK_BIND(vkGetPhysicalDeviceMemoryProperties, inst, NULL);
    DVK_BIND(vkCreateDevice, inst, NULL);
    DVK_BIND(vkGetDeviceProcAddr, inst, NULL);
    return 0;
}

static int dvk_load_device(VkInstance inst, VkDevice dev) {
    DVK_BIND(vkDestroyDevice, inst, dev);
    DVK_BIND(vkGetDeviceQueue, inst, dev);
    DVK_BIND(vkDeviceWaitIdle, inst, dev);
    DVK_BIND(vkCreateCommandPool, inst, dev);
    DVK_BIND(vkDestroyCommandPool, inst, dev);
    DVK_BIND(vkAllocateCommandBuffers, inst, dev);
    DVK_BIND(vkCreateFence, inst, dev);
    DVK_BIND(vkDestroyFence, inst, dev);
    DVK_BIND(vkCreateBuffer, inst, dev);
    DVK_BIND(vkDestroyBuffer, inst, dev);
    DVK_BIND(vkGetBufferMemoryRequirements, inst, dev);
    DVK_BIND(vkAllocateMemory, inst, dev);
    DVK_BIND(vkFreeMemory, inst, dev);
    DVK_BIND(vkBindBufferMemory, inst, dev);
    DVK_BIND(vkMapMemory, inst, dev);
    DVK_BIND(vkCreateShaderModule, inst, dev);
    DVK_BIND(vkDestroyShaderModule, inst, dev);
    DVK_BIND(vkCreateDescriptorSetLayout, inst, dev);
    DVK_BIND(vkDestroyDescriptorSetLayout, inst, dev);
    DVK_BIND(vkCreatePipelineLayout, inst, dev);
    DVK_BIND(vkDestroyPipelineLayout, inst, dev);
    DVK_BIND(vkCreateComputePipelines, inst, dev);
    DVK_BIND(vkDestroyPipeline, inst, dev);
    DVK_BIND(vkCreateDescriptorPool, inst, dev);
    DVK_BIND(vkDestroyDescriptorPool, inst, dev);
    DVK_BIND(vkAllocateDescriptorSets, inst, dev);
    DVK_BIND(vkUpdateDescriptorSets, inst, dev);
    DVK_BIND(vkResetCommandBuffer, inst, dev);
    DVK_BIND(vkBeginCommandBuffer, inst, dev);
    DVK_BIND(vkEndCommandBuffer, inst, dev);
    DVK_BIND(vkCmdBindPipeline, inst, dev);
    DVK_BIND(vkCmdBindDescriptorSets, inst, dev);
    DVK_BIND(vkCmdPushConstants, inst, dev);
    DVK_BIND(vkCmdDispatch, inst, dev);
    DVK_BIND(vkCmdPipelineBarrier, inst, dev);
    DVK_BIND(vkResetFences, inst, dev);
    DVK_BIND(vkQueueSubmit, inst, dev);
    DVK_BIND(vkWaitForFences, inst, dev);
    return 0;
}
#endif /* _WIN32 */

#define DVK_CHECK(x)              \
    do {                          \
        if((x) != VK_SUCCESS) {   \
            return -1;            \
        }                         \
    } while(0)

static uint32_t dvk_find_memory_type(
    const VkPhysicalDeviceMemoryProperties* mp,
    uint32_t type_bits,
    VkMemoryPropertyFlags required,
    VkMemoryPropertyFlags preferred) {
    /* First pass: satisfy required + preferred (DEVICE_LOCAL when the GPU
     * exposes host-visible device memory, i.e. an integrated/shared heap). */
    for(uint32_t i = 0; i < mp->memoryTypeCount; i++) {
        if(!(type_bits & (1u << i))) {
            continue;
        }
        const VkMemoryPropertyFlags f = mp->memoryTypes[i].propertyFlags;
        if((f & (required | preferred)) == (required | preferred)) {
            return i;
        }
    }
    for(uint32_t i = 0; i < mp->memoryTypeCount; i++) {
        if(!(type_bits & (1u << i))) {
            continue;
        }
        if((mp->memoryTypes[i].propertyFlags & required) == required) {
            return i;
        }
    }
    return UINT32_MAX;
}

static int dvk_pick_device(DvkContext* c) {
    uint32_t n = 0;
    if(vkEnumeratePhysicalDevices(c->instance, &n, NULL) != VK_SUCCESS || n == 0) {
        return -1;
    }
    VkPhysicalDevice* devs = calloc(n, sizeof(VkPhysicalDevice));
    if(!devs) {
        return -1;
    }
    if(vkEnumeratePhysicalDevices(c->instance, &n, devs) != VK_SUCCESS) {
        free(devs);
        return -1;
    }

    /* Prefer a discrete/integrated GPU; fall back to whatever exposes a
     * compute-capable queue family. */
    int best = -1;
    uint32_t best_family = 0;
    int best_score = -1;
    for(uint32_t i = 0; i < n; i++) {
        VkPhysicalDeviceProperties props;
        vkGetPhysicalDeviceProperties(devs[i], &props);

        uint32_t qn = 0;
        vkGetPhysicalDeviceQueueFamilyProperties(devs[i], &qn, NULL);
        if(qn == 0) {
            continue;
        }
        VkQueueFamilyProperties* qf = calloc(qn, sizeof(VkQueueFamilyProperties));
        if(!qf) {
            continue;
        }
        vkGetPhysicalDeviceQueueFamilyProperties(devs[i], &qn, qf);
        int family = -1;
        for(uint32_t q = 0; q < qn; q++) {
            if(qf[q].queueCount > 0 && (qf[q].queueFlags & VK_QUEUE_COMPUTE_BIT)) {
                family = (int)q;
                break;
            }
        }
        free(qf);
        if(family < 0) {
            continue;
        }
        int score = 1;
        if(props.deviceType == VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU) {
            score = 3;
        } else if(props.deviceType == VK_PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU) {
            score = 2;
        }
        if(score > best_score) {
            best_score = score;
            best = (int)i;
            best_family = (uint32_t)family;
        }
    }

    if(best < 0) {
        free(devs);
        return -1;
    }
    c->phys = devs[best];
    c->queue_family = best_family;
    vkGetPhysicalDeviceMemoryProperties(c->phys, &c->mem_props);
    free(devs);
    return 0;
}

int dvk_init(DvkContext* c) {
    memset(c, 0, sizeof(*c));

#if defined(_WIN32)
    if(dvk_load_loader() != 0) {
        return -1;
    }
    DVK_BIND(vkCreateInstance, NULL, NULL);
#endif

    VkApplicationInfo app = {0};
    app.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO;
    app.pApplicationName = "doctor_subghz";
    app.applicationVersion = VK_MAKE_VERSION(1, 0, 0);
    app.pEngineName = "doctor_subghz";
    app.engineVersion = VK_MAKE_VERSION(1, 0, 0);
    app.apiVersion = VK_API_VERSION_1_1;

    VkInstanceCreateInfo ici = {0};
    ici.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
    ici.pApplicationInfo = &app;
    if(vkCreateInstance(&ici, NULL, &c->instance) != VK_SUCCESS) {
        c->instance = VK_NULL_HANDLE;
        return -1;
    }

#if defined(_WIN32)
    if(dvk_load_instance(c->instance) != 0) {
        vkDestroyInstance(c->instance, NULL);
        c->instance = VK_NULL_HANDLE;
        return -1;
    }
#endif

    if(dvk_pick_device(c) != 0) {
        vkDestroyInstance(c->instance, NULL);
        c->instance = VK_NULL_HANDLE;
        return -1;
    }

    const float prio = 1.0f;
    VkDeviceQueueCreateInfo qci = {0};
    qci.sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;
    qci.queueFamilyIndex = c->queue_family;
    qci.queueCount = 1;
    qci.pQueuePriorities = &prio;

    VkDeviceCreateInfo dci = {0};
    dci.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO;
    dci.queueCreateInfoCount = 1;
    dci.pQueueCreateInfos = &qci;
    if(vkCreateDevice(c->phys, &dci, NULL, &c->device) != VK_SUCCESS) {
        vkDestroyInstance(c->instance, NULL);
        c->instance = VK_NULL_HANDLE;
        return -1;
    }
#if defined(_WIN32)
    if(dvk_load_device(c->instance, c->device) != 0) {
        vkDestroyDevice(c->device, NULL);
        c->device = VK_NULL_HANDLE;
        vkDestroyInstance(c->instance, NULL);
        c->instance = VK_NULL_HANDLE;
        return -1;
    }
#endif
    vkGetDeviceQueue(c->device, c->queue_family, 0, &c->queue);

    VkCommandPoolCreateInfo pci = {0};
    pci.sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO;
    pci.flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT;
    pci.queueFamilyIndex = c->queue_family;
    if(vkCreateCommandPool(c->device, &pci, NULL, &c->pool) != VK_SUCCESS) {
        goto fail_device;
    }

    VkCommandBufferAllocateInfo cbi = {0};
    cbi.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
    cbi.commandPool = c->pool;
    cbi.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
    cbi.commandBufferCount = 1;
    if(vkAllocateCommandBuffers(c->device, &cbi, &c->cmd) != VK_SUCCESS) {
        goto fail_pool;
    }

    VkFenceCreateInfo fci = {0};
    fci.sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO;
    if(vkCreateFence(c->device, &fci, NULL, &c->fence) != VK_SUCCESS) {
        goto fail_pool;
    }
    return 0;

fail_pool:
    vkDestroyCommandPool(c->device, c->pool, NULL);
    c->pool = VK_NULL_HANDLE;
fail_device:
    vkDestroyDevice(c->device, NULL);
    c->device = VK_NULL_HANDLE;
    vkDestroyInstance(c->instance, NULL);
    c->instance = VK_NULL_HANDLE;
    return -1;
}

void dvk_shutdown(DvkContext* c) {
    if(c->device) {
        vkDeviceWaitIdle(c->device);
        if(c->fence) {
            vkDestroyFence(c->device, c->fence, NULL);
        }
        if(c->pool) {
            vkDestroyCommandPool(c->device, c->pool, NULL);
        }
        vkDestroyDevice(c->device, NULL);
    }
    if(c->instance) {
        vkDestroyInstance(c->instance, NULL);
    }
    memset(c, 0, sizeof(*c));
}

int dvk_available(void) {
    DvkContext c;
    if(dvk_init(&c) != 0) {
        return 0;
    }
    dvk_shutdown(&c);
    return 1;
}

int dvk_buffer_create(DvkContext* c, DvkBuffer* b, VkDeviceSize size) {
    memset(b, 0, sizeof(*b));
    if(size == 0) {
        size = 4;
    }
    b->size = size;

    VkBufferCreateInfo bci = {0};
    bci.sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO;
    bci.size = size;
    bci.usage = VK_BUFFER_USAGE_STORAGE_BUFFER_BIT;
    bci.sharingMode = VK_SHARING_MODE_EXCLUSIVE;
    DVK_CHECK(vkCreateBuffer(c->device, &bci, NULL, &b->buffer));

    VkMemoryRequirements req;
    vkGetBufferMemoryRequirements(c->device, b->buffer, &req);

    const uint32_t type = dvk_find_memory_type(
        &c->mem_props,
        req.memoryTypeBits,
        VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
        VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);
    if(type == UINT32_MAX) {
        vkDestroyBuffer(c->device, b->buffer, NULL);
        b->buffer = VK_NULL_HANDLE;
        return -1;
    }

    VkMemoryAllocateInfo mai = {0};
    mai.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
    mai.allocationSize = req.size;
    mai.memoryTypeIndex = type;
    if(vkAllocateMemory(c->device, &mai, NULL, &b->memory) != VK_SUCCESS) {
        vkDestroyBuffer(c->device, b->buffer, NULL);
        b->buffer = VK_NULL_HANDLE;
        return -1;
    }
    if(vkBindBufferMemory(c->device, b->buffer, b->memory, 0) != VK_SUCCESS ||
       vkMapMemory(c->device, b->memory, 0, VK_WHOLE_SIZE, 0, &b->mapped) != VK_SUCCESS) {
        dvk_buffer_destroy(c, b);
        return -1;
    }
    return 0;
}

void dvk_buffer_destroy(DvkContext* c, DvkBuffer* b) {
    if(b->memory) {
        vkFreeMemory(c->device, b->memory, NULL);
    }
    if(b->buffer) {
        vkDestroyBuffer(c->device, b->buffer, NULL);
    }
    memset(b, 0, sizeof(*b));
}

int dvk_pipeline_create(
    DvkContext* c,
    DvkPipeline* p,
    const uint32_t* spirv,
    size_t spirv_bytes,
    uint32_t nbuffers,
    uint32_t push_const_bytes) {
    memset(p, 0, sizeof(*p));
    p->nbuffers = nbuffers;

    VkShaderModuleCreateInfo smi = {0};
    smi.sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO;
    smi.codeSize = spirv_bytes;
    smi.pCode = spirv;
    DVK_CHECK(vkCreateShaderModule(c->device, &smi, NULL, &p->module));

    VkDescriptorSetLayoutBinding* binds =
        calloc(nbuffers, sizeof(VkDescriptorSetLayoutBinding));
    if(!binds) {
        vkDestroyShaderModule(c->device, p->module, NULL);
        return -1;
    }
    for(uint32_t i = 0; i < nbuffers; i++) {
        binds[i].binding = i;
        binds[i].descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
        binds[i].descriptorCount = 1;
        binds[i].stageFlags = VK_SHADER_STAGE_COMPUTE_BIT;
    }
    VkDescriptorSetLayoutCreateInfo dslci = {0};
    dslci.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO;
    dslci.bindingCount = nbuffers;
    dslci.pBindings = binds;
    VkResult r = vkCreateDescriptorSetLayout(c->device, &dslci, NULL, &p->dsl);
    free(binds);
    if(r != VK_SUCCESS) {
        vkDestroyShaderModule(c->device, p->module, NULL);
        return -1;
    }

    VkPushConstantRange pcr = {0};
    pcr.stageFlags = VK_SHADER_STAGE_COMPUTE_BIT;
    pcr.offset = 0;
    pcr.size = push_const_bytes;

    VkPipelineLayoutCreateInfo plci = {0};
    plci.sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO;
    plci.setLayoutCount = 1;
    plci.pSetLayouts = &p->dsl;
    if(push_const_bytes > 0) {
        plci.pushConstantRangeCount = 1;
        plci.pPushConstantRanges = &pcr;
    }
    if(vkCreatePipelineLayout(c->device, &plci, NULL, &p->layout) != VK_SUCCESS) {
        goto fail_dsl;
    }

    VkComputePipelineCreateInfo cpci = {0};
    cpci.sType = VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO;
    cpci.stage.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
    cpci.stage.stage = VK_SHADER_STAGE_COMPUTE_BIT;
    cpci.stage.module = p->module;
    cpci.stage.pName = "main";
    cpci.layout = p->layout;
    if(vkCreateComputePipelines(c->device, VK_NULL_HANDLE, 1, &cpci, NULL, &p->pipeline) !=
       VK_SUCCESS) {
        goto fail_layout;
    }

    VkDescriptorPoolSize dps = {0};
    dps.type = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
    dps.descriptorCount = nbuffers;
    VkDescriptorPoolCreateInfo dpci = {0};
    dpci.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO;
    dpci.maxSets = 1;
    dpci.poolSizeCount = 1;
    dpci.pPoolSizes = &dps;
    if(vkCreateDescriptorPool(c->device, &dpci, NULL, &p->dpool) != VK_SUCCESS) {
        goto fail_pipeline;
    }

    VkDescriptorSetAllocateInfo dsai = {0};
    dsai.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO;
    dsai.descriptorPool = p->dpool;
    dsai.descriptorSetCount = 1;
    dsai.pSetLayouts = &p->dsl;
    if(vkAllocateDescriptorSets(c->device, &dsai, &p->dset) != VK_SUCCESS) {
        goto fail_dpool;
    }
    return 0;

fail_dpool:
    vkDestroyDescriptorPool(c->device, p->dpool, NULL);
    p->dpool = VK_NULL_HANDLE;
fail_pipeline:
    vkDestroyPipeline(c->device, p->pipeline, NULL);
    p->pipeline = VK_NULL_HANDLE;
fail_layout:
    vkDestroyPipelineLayout(c->device, p->layout, NULL);
    p->layout = VK_NULL_HANDLE;
fail_dsl:
    vkDestroyDescriptorSetLayout(c->device, p->dsl, NULL);
    p->dsl = VK_NULL_HANDLE;
    vkDestroyShaderModule(c->device, p->module, NULL);
    p->module = VK_NULL_HANDLE;
    return -1;
}

void dvk_pipeline_destroy(DvkContext* c, DvkPipeline* p) {
    if(p->dpool) {
        vkDestroyDescriptorPool(c->device, p->dpool, NULL);
    }
    if(p->pipeline) {
        vkDestroyPipeline(c->device, p->pipeline, NULL);
    }
    if(p->layout) {
        vkDestroyPipelineLayout(c->device, p->layout, NULL);
    }
    if(p->dsl) {
        vkDestroyDescriptorSetLayout(c->device, p->dsl, NULL);
    }
    if(p->module) {
        vkDestroyShaderModule(c->device, p->module, NULL);
    }
    memset(p, 0, sizeof(*p));
}

void dvk_pipeline_bind_buffer(
    DvkContext* c, DvkPipeline* p, uint32_t binding, const DvkBuffer* b) {
    VkDescriptorBufferInfo dbi = {0};
    dbi.buffer = b->buffer;
    dbi.offset = 0;
    dbi.range = VK_WHOLE_SIZE;
    VkWriteDescriptorSet w = {0};
    w.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
    w.dstSet = p->dset;
    w.dstBinding = binding;
    w.descriptorCount = 1;
    w.descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
    w.pBufferInfo = &dbi;
    vkUpdateDescriptorSets(c->device, 1, &w, 0, NULL);
}

int dvk_dispatch(
    DvkContext* c,
    DvkPipeline* p,
    const void* push_const,
    uint32_t push_const_bytes,
    uint32_t gx,
    uint32_t gy,
    uint32_t gz) {
    DVK_CHECK(vkResetCommandBuffer(c->cmd, 0));

    VkCommandBufferBeginInfo bi = {0};
    bi.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
    bi.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
    DVK_CHECK(vkBeginCommandBuffer(c->cmd, &bi));

    vkCmdBindPipeline(c->cmd, VK_PIPELINE_BIND_POINT_COMPUTE, p->pipeline);
    vkCmdBindDescriptorSets(
        c->cmd, VK_PIPELINE_BIND_POINT_COMPUTE, p->layout, 0, 1, &p->dset, 0, NULL);
    if(push_const_bytes > 0) {
        vkCmdPushConstants(
            c->cmd, p->layout, VK_SHADER_STAGE_COMPUTE_BIT, 0, push_const_bytes, push_const);
    }
    vkCmdDispatch(c->cmd, gx, gy, gz);

    /* Make the shader's SSBO writes visible to a subsequent host read. */
    VkMemoryBarrier mb = {0};
    mb.sType = VK_STRUCTURE_TYPE_MEMORY_BARRIER;
    mb.srcAccessMask = VK_ACCESS_SHADER_WRITE_BIT;
    mb.dstAccessMask = VK_ACCESS_HOST_READ_BIT;
    vkCmdPipelineBarrier(
        c->cmd,
        VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT,
        VK_PIPELINE_STAGE_HOST_BIT,
        0,
        1,
        &mb,
        0,
        NULL,
        0,
        NULL);

    DVK_CHECK(vkEndCommandBuffer(c->cmd));

    VkSubmitInfo si = {0};
    si.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO;
    si.commandBufferCount = 1;
    si.pCommandBuffers = &c->cmd;

    DVK_CHECK(vkResetFences(c->device, 1, &c->fence));
    DVK_CHECK(vkQueueSubmit(c->queue, 1, &si, c->fence));
    DVK_CHECK(vkWaitForFences(c->device, 1, &c->fence, VK_TRUE, UINT64_MAX));
    return 0;
}

#endif /* __ANDROID__ || _WIN32 */
