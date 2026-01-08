#include <stdlib.h>

void* (*mallocPtr)(size_t size) = NULL;
void* (*reallocPtr)(void* ptr, size_t size) = NULL;
void (*freePtr)(void* ptr) = NULL;

#define STBI_MALLOC(size) mallocPtr(size)
#define STBI_REALLOC(ptr, size) reallocPtr(ptr, size)
#define STBI_FREE(ptr) freePtr(ptr)

#define STB_IMAGE_IMPLEMENTATION
#include "stb_image.h"
