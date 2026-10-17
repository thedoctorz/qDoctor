cmake_minimum_required(VERSION 3.13)
project(doctor_subghz LANGUAGES C)

# Our canonical Hitag2Hell engine (mirrors the iOS app). This CMake target is
# the Android / Linux / Windows build: the C core + platform bridge. Android
# and Windows also build the Vulkan compute GPU path (matching the iOS Metal
# kernel); Linux stays on the CPU path. The Metal GPU path
# (hitag2hell_metal.m) is Apple-only and built by the CocoaPods podspec
# (apple/doctor_subghz.podspec).
set(DOCTOR_SUBGHZ_SRC
  hitag2_bridge.c
  hitag2hell_common.c
  hitag2hell_cpu_kernel.c
  hitag2bcm.c
  psabf.c
  psa_bridge.c
)

# Vulkan GPU kernels. The SPIR-V is committed as generated headers
# (hitag2hell_spirv.h / psabf_spirv.h) — regenerate with kernel/embed_spirv.py
# — so the build needs no shader toolchain.
set(DOCTOR_SUBGHZ_VULKAN OFF)
if(ANDROID OR WIN32)
  set(DOCTOR_SUBGHZ_VULKAN ON)
  list(APPEND DOCTOR_SUBGHZ_SRC
    doctor_vulkan.c
    hitag2hell_vulkan.c
    psabf_vulkan.c
  )
endif()

add_library(doctor_subghz SHARED ${DOCTOR_SUBGHZ_SRC})
target_include_directories(doctor_subghz PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}")

if(ANDROID)
  # libvulkan ships with the platform since API 24; minSdk is 29.
  target_link_libraries(doctor_subghz PRIVATE vulkan)
elseif(WIN32 AND DOCTOR_SUBGHZ_VULKAN)
  # Headers only: vulkan-1.dll is loaded at runtime so a machine without a
  # Vulkan loader still loads this FFI library and falls back to CPU.
  target_compile_definitions(doctor_subghz PRIVATE VK_NO_PROTOTYPES)
  find_package(Vulkan QUIET)
  if(Vulkan_INCLUDE_DIR)
    target_include_directories(doctor_subghz PRIVATE "${Vulkan_INCLUDE_DIR}")
  else()
    include(FetchContent)
    # The headers' own CMake wants to build a C++20 module on recent MSVC;
    # we only need include/vulkan.
    set(VULKAN_HEADERS_ENABLE_MODULE OFF CACHE BOOL "" FORCE)
    set(VULKAN_HEADERS_ENABLE_TESTS OFF CACHE BOOL "" FORCE)
    set(VULKAN_HEADERS_ENABLE_INSTALL OFF CACHE BOOL "" FORCE)
    FetchContent_Declare(doctor_vulkan_headers
      URL https://github.com/KhronosGroup/Vulkan-Headers/archive/refs/tags/v1.3.296.tar.gz
    )
    FetchContent_MakeAvailable(doctor_vulkan_headers)
    if(TARGET Vulkan::Headers)
      target_link_libraries(doctor_subghz PRIVATE Vulkan::Headers)
    else()
      target_include_directories(doctor_subghz PRIVATE
        "${doctor_vulkan_headers_SOURCE_DIR}/include")
    endif()
  endif()
endif()
set_target_properties(doctor_subghz PROPERTIES
  C_STANDARD 11
  POSITION_INDEPENDENT_CODE ON
  C_VISIBILITY_PRESET hidden
)
if(NOT MSVC)
  target_compile_options(doctor_subghz PRIVATE -O3)
endif()

# Threads: real pthreads on Linux/Android/macOS/iOS and MinGW (winpthreads);
# clang-cl/MSVC use hardnested's pthread_shim.h (included from psabf.c).
if(NOT (WIN32 AND NOT MINGW))
  find_package(Threads REQUIRED)
  target_link_libraries(doctor_subghz PRIVATE Threads::Threads)
endif()

if(WIN32)
  target_compile_definitions(doctor_subghz PRIVATE _CRT_SECURE_NO_WARNINGS)
endif()

# psabf.c includes <stdatomic.h>. MSVC 14.51 still gates C atomics on this
# flag even with C11: without it, vcruntime_c11_stdatomic.h errors
# "C atomic support is not enabled" and the Windows release dies.
if(MSVC)
  target_compile_options(doctor_subghz PRIVATE "/std:c11" "/experimental:c11atomics")
endif()
