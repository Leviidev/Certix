#include "ZipCompression.h"
#include <zlib.h>
#include <stdlib.h>
#include <string.h>

int rawInflate(const uint8_t *input, size_t inputLen,
               uint8_t *output, size_t *outputLen) {
    z_stream strm;
    memset(&strm, 0, sizeof(strm));
    strm.next_in  = (Bytef *)input;
    strm.avail_in = (uInt)inputLen;

    if (inflateInit2(&strm, -15) != Z_OK) return -1;

    strm.next_out  = output;
    strm.avail_out = (uInt)(*outputLen);

    int ret = inflate(&strm, Z_FINISH);
    *outputLen = strm.total_out;
    inflateEnd(&strm);
    return (ret == Z_STREAM_END) ? 0 : -1;
}

int rawDeflate(const uint8_t *input, size_t inputLen,
               uint8_t *output, size_t *outputLen) {
    z_stream strm;
    memset(&strm, 0, sizeof(strm));
    strm.next_in  = (Bytef *)input;
    strm.avail_in = (uInt)inputLen;

    if (deflateInit2(&strm, 6, Z_DEFLATED, -15, 8, Z_DEFAULT_STRATEGY) != Z_OK) return -1;

    strm.next_out  = output;
    strm.avail_out = (uInt)(*outputLen);

    int ret = deflate(&strm, Z_FINISH);
    *outputLen = strm.total_out;
    deflateEnd(&strm);
    return (ret == Z_STREAM_END) ? 0 : -1;
}

uint32_t crc32ForData(const uint8_t *data, size_t length) {
    uLong crc = crc32(0L, Z_NULL, 0);
    return (uint32_t)crc32(crc, data, (uInt)length);
}
