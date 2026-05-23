#pragma once
#include <stdint.h>
#include <stddef.h>

int rawInflate(const uint8_t *input, size_t inputLen,
               uint8_t *output, size_t *outputLen);

int rawDeflate(const uint8_t *input, size_t inputLen,
               uint8_t *output, size_t *outputLen);

uint32_t crc32ForData(const uint8_t *data, size_t length);
