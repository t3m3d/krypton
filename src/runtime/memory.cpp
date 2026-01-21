#include <cstdlib>

void* k_alloc(size_t size) {
    return std::malloc(size);
}