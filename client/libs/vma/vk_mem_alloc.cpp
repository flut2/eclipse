#define VMA_IMPLEMENTATION

#ifndef VMA_USAGE_H_
#define VMA_USAGE_H_

#ifdef _WIN32

#if !defined(NOMINMAX)
    #define NOMINMAX
#endif

#if !defined(WIN32_LEAN_AND_MEAN)
    #define WIN32_LEAN_AND_MEAN
#endif

#include <windows.h>
#if !defined(VK_USE_PLATFORM_WIN32_KHR)
    #define VK_USE_PLATFORM_WIN32_KHR
#endif // #if !defined(VK_USE_PLATFORM_WIN32_KHR)

#endif  // #ifdef _WIN32

#ifdef _MSVC_LANG

//#define VMA_HEAVY_ASSERT(expr) assert(expr)
//#define VMA_DEDICATED_ALLOCATION 0
//#define VMA_DEBUG_MARGIN 16
//#define VMA_DEBUG_DETECT_CORRUPTION 1
//#define VMA_DEBUG_MIN_BUFFER_IMAGE_GRANULARITY 256
//#define VMA_USE_STL_SHARED_MUTEX 0
//#define VMA_MEMORY_BUDGET 0
//#define VMA_STATS_STRING_ENABLED 0
//#define VMA_MAPPING_HYSTERESIS_ENABLED 0
//#define VMA_KHR_MAINTENANCE5 0

#define VMA_VULKAN_VERSION 1002000 // Vulkan 1.2

/*
#define VMA_DEBUG_LOG(format, ...) do { \
        printf(format, __VA_ARGS__); \
        printf("\n"); \
    } while(false)
*/

#pragma warning(push, 4)
#pragma warning(disable: 4127) // conditional expression is constant
#pragma warning(disable: 4100) // unreferenced formal parameter
#pragma warning(disable: 4189) // local variable is initialized but not referenced
#pragma warning(disable: 4324) // structure was padded due to alignment specifier
#pragma warning(disable: 4820) // 'X': 'N' bytes padding added after data member 'X'

#endif  // #ifdef _MSVC_LANG

#ifdef __clang__
    #pragma clang diagnostic push
    #pragma clang diagnostic ignored "-Wtautological-compare" // comparison of unsigned expression < 0 is always false
    #pragma clang diagnostic ignored "-Wunused-private-field"
    #pragma clang diagnostic ignored "-Wunused-parameter"
    #pragma clang diagnostic ignored "-Wmissing-field-initializers"
    #pragma clang diagnostic ignored "-Wnullability-completeness"
#endif

#include "vk_mem_alloc.h"

#ifdef __clang__
    #pragma clang diagnostic pop
#endif

#ifdef _MSVC_LANG
    #pragma warning(pop)
#endif

#endif