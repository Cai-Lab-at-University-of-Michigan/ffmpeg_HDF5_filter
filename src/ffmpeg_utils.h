/*
 * FFMPEG HDF5 filter
 *
 * Author: Bin Duan <duanb@umich.edu>
 * Created: 2024
 *
 */

#ifndef FFMPEG_UTILS_H
#define FFMPEG_UTILS_H

#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <errno.h>

#include <libavcodec/avcodec.h>
#include <libswscale/swscale.h>
#include <libavformat/avformat.h>
#include <libavutil/opt.h>
#include <libavutil/imgutils.h>
#include <libavutil/log.h>

#include "ffmpeg_h5filter.h"

#ifdef _WIN32
// Windows doesn't have stpcpy, so we provide our own implementation
static inline char *stpcpy(char *dest, const char *src)
{
    while ((*dest++ = *src++))
        ;
    return dest - 1;
}
#endif

#define EXPECTED_CS_RATIO 30

#define FFMPEG_FLAG_COMPRESS 0x0000

void raise_ffmpeg_error(const char *msg);

size_t read_from_buffer(uint8_t *buf, int buf_size, unsigned char **data, int *data_size);

void find_encoder_name(int c_id, char *codec_name);

void find_decoder_name(int c_id, char *codec_name);

void find_preset(int p_id, char *preset);

void find_tune(int t_id, char *tune);

void encode(AVCodecContext *enc_ctx, AVFrame *frame, AVPacket *pkt,
                   size_t *out_size, uint8_t **out_data, size_t *expected_size);

void decode(AVCodecContext *dec_ctx, AVFrame *src_frame, AVPacket *pkt,
                   struct SwsContext *sws_context, AVFrame *dst_frame,
                   size_t *out_size, uint8_t *out_data, size_t frame_size); 

#endif // FFMPEG_UTILS_H