/*
 * FFMPEG HDF5 filter
 *
 * Author: Bin Duan <bduan2@hawk.iit.edu>
 * Created: 2022
 *
 */


#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <error.h>

#include <libavcodec/avcodec.h>
#include <libswscale/swscale.h>
#include <libavformat/avformat.h>

#include "ffmpeg_h5filter.h"

#define INBUF_SIZE 4096

#define PUSH_ERR(func, minor, str)                                      \
    H5Epush(H5E_DEFAULT, __FILE__, func, __LINE__, H5E_ERR_CLS, H5E_PLINE, minor, str)

static size_t read_from_buffer(uint8_t *buf, int buf_size, unsigned char **data, int *data_size);

static void find_encoder_name(int c_id, char *name);

static void find_decoder_name(int c_id, char *name);

static void encode(AVCodecContext *enc_ctx, AVFrame *frame, AVPacket *pkt, size_t *out_size, uint8_t **out_data);

static void decode(AVCodecContext *dec_ctx, AVFrame *src_frame, AVPacket *pkt,
                   struct SwsContext *sws_context, AVFrame *dst_frame,
                   size_t *out_size, uint8_t **out_data, int color_mode);

size_t ffmpeg_h5_filter(unsigned flags, size_t cd_nelmts, const unsigned int cd_values[], size_t nbytes,
                        size_t *buf_size, void **buf);

static size_t read_from_buffer(uint8_t *buf, int buf_size, unsigned char **data, int *data_size) {
    size_t read_size = NULL;

    if (*data_size > 0) {
        read_size = (*data_size - buf_size >= 0) ? buf_size : *data_size;
        memcpy(buf, *data, read_size);
        *data += read_size;
        *data_size -= read_size;
    }

    return read_size;
}

// ffv1, mpeg4, libxvid, libvpx, libvpx-vp9, libx264, h264_nvenc, libx265, hevc_nvenc, libaom-av1, libsvtav1, librav1e
static void find_encoder_name(int c_id, char *name) {
    switch (c_id) {
        /* encoders */
        case 0:
            strcpy(name, "ffv1");
            break;
        case 1:
            strcpy(name, "mpeg4");
            break;
        case 2:
            strcpy(name, "libxvid");
            break;
        case 3:
            strcpy(name, "libvpx");
            break;
        case 4:
            strcpy(name, "libvpx-vp9");
            break;
        case 5:
            strcpy(name, "libx264");
            break;
        case 6:
            strcpy(name, "h264_nvenc");
            break;
        case 7:
            strcpy(name, "libx265");
            break;
        case 8:
            strcpy(name, "hevc_nvenc");
            break;
        case 9:
            strcpy(name, "libaom-av1");
            break;
        case 10:
            strcpy(name, "libsvtav1");
            break;
        case 11:
            strcpy(name, "librav1e");
            break;

        default:
            strcpy(name, "ffv1");
            break;
    }
}

// ffv1, mpeg4, libvpx, libvpx-vp9, h264, h264_cuvid, hevc, hevc_cuvid, libaom-av1, libdav1d
static void find_decoder_name(int c_id, char *name) {
    switch (c_id) {
        /* decoders */
        case 0:
            strcpy(name, "ffv1");
            break;
        case 1:
            strcpy(name, "mpeg4");
            break;
        case 2:
            strcpy(name, "libvpx");
            break;
        case 3:
            strcpy(name, "libvpx-vp9");
            break;
        case 4:
            strcpy(name, "h264");
            break;
        case 5:
            strcpy(name, "h264_cuvid");
            break;
        case 6:
            strcpy(name, "hevc");
            break;
        case 7:
            strcpy(name, "hevc_cuvid");
            break;
        case 8:
            strcpy(name, "libaom-av1");
            break;
        case 9:
            strcpy(name, "libdav1d");
            break;

        default:
            strcpy(name, "ffv1");
            break;
    }
}

static void encode(AVCodecContext *enc_ctx, AVFrame *frame, AVPacket *pkt, size_t *out_size, uint8_t **out_data) {
    int ret;
    int offset = 0;

    /* send the frame to the encoder */
    if (frame) printf("Encode frame %3"PRId64"\n", frame->pts);

    ret = avcodec_send_frame(enc_ctx, frame);
    if (ret < 0) {
        fprintf(stderr, "Error sending a frame for encoding\n");
    }

    while (ret >= 0) {
        ret = avcodec_receive_packet(enc_ctx, pkt);
        if (ret == AVERROR(EAGAIN) || ret == AVERROR_EOF)
            return;
        if (ret < 0) {
            fprintf(stderr, "Error during encoding\n");
        }

        printf("Write packet %3"PRId64" (size=%5d)\n", pkt->pts, pkt->size);

        offset = *out_size;
        *out_data = realloc(*out_data, offset + pkt->size);

        if (*out_data == NULL) {
            fprintf(stderr, "Out of memory occurred during encoding\n");
        }
        memcpy(*out_data + offset, pkt->data, pkt->size);
        *out_size += pkt->size;
        av_packet_unref(pkt);
    }
}


static void decode(AVCodecContext *dec_ctx, AVFrame *src_frame, AVPacket *pkt,
                   struct SwsContext *sws_context, AVFrame *dst_frame,
                   size_t *out_size, uint8_t **out_data, int color_mode) {
    int ret;
    int offset = 0;
    int perchannelsize = 0;

    ret = avcodec_send_packet(dec_ctx, pkt);
//    printf("receiving packets %d\n", pkt->size);
    if (ret < 0) {
        fprintf(stderr, "Error sending a pkt for encoding, pkt size %d\n", pkt->size);
    }

    while (ret >= 0) {
        ret = avcodec_receive_frame(dec_ctx, src_frame);
        if (ret == AVERROR(EAGAIN) || ret == AVERROR_EOF)
            return;
        else if (ret < 0) {
            fprintf(stderr, "Error receiving a frame for encoding\n");
        }
//        printf("Decode frame %3d\n", dec_ctx->frame_number);

        /* do colorspace conversion */
        sws_scale_frame(sws_context, dst_frame, src_frame);

        /* put to buffer */
        offset = *out_size;

        perchannelsize = dst_frame->width * dst_frame->height;

        if (color_mode == 0) {
            *out_data = realloc(*out_data, *out_size + perchannelsize);
            memcpy(*out_data + offset, dst_frame->data[0], perchannelsize);
            *out_size += perchannelsize;
        } else {
            *out_data = realloc(*out_data, *out_size + perchannelsize * 3);
            memcpy(*out_data + offset, dst_frame->data[0], perchannelsize);
            memcpy(*out_data + offset + perchannelsize, dst_frame->data[1], perchannelsize);
            memcpy(*out_data + offset + perchannelsize * 2, dst_frame->data[2], perchannelsize);
            *out_size += perchannelsize * 3;
        }
    }
}


void pgm_save(unsigned char *buf, int wrap, int xsize, int ysize,
                     char *filename)
{
    FILE *f;
    int i;

    f = fopen(filename,"wb");
    fprintf(f, "P5\n%d %d\n%d\n", xsize, ysize, 255);
    for (i = 0; i < ysize; i++)
        fwrite(buf + i * wrap, 1, xsize, f);
    fclose(f);
}

/* The ffmpeg filter function */
size_t ffmpeg_h5_filter(unsigned flags, size_t cd_nelmts, const unsigned int cd_values[], size_t nbytes,
                        size_t *buf_size, void **buf) {

    size_t buf_size_out = 0;
    void *out_buf = NULL;

    if (!(flags & H5Z_FLAG_REVERSE)) {
        /* Compress */
        /*
        * cd_values[0] = encoder_id
        * cd_values[1] = decoder_id
        * cd_values[2] = width
        * cd_values[3] = height
        * cd_values[4] = depth
        * cd_values[5] = 0=Mono, 1=RGB
        */
        char *codec_name;
        const AVCodec *codec;
        AVCodecContext *c = NULL;
        AVFrame *dst_frame, *src_frame = NULL;
        AVPacket *pkt;
        struct SwsContext *sws_context;
        uint8_t endcode[] = { 0, 0, 1, 0xb7 };

        int c_id;
        int width, height, depth;
        int color_mode;
        size_t expected_size;

        size_t out_size = 0;
        int offset = 0;
        uint8_t *out_data = NULL;
        uint8_t *p_data = NULL;

        int i, j, ret;

        printf("I am in compressing\n");

        c_id = cd_values[0];
        width = cd_values[2];
        height = cd_values[3];
        depth = cd_values[4];
        color_mode = cd_values[5];

        /* Sanity check to make sure we have been passed a complete image */
        expected_size = width * height * depth;
        if (color_mode == 1) expected_size *= 3;
        if (expected_size != nbytes) {
            fprintf(stderr, "nbytes does not match image size");
            return 0;
        }
        codec_name = calloc(1, 50);
//        find_encoder_name(c_id, codec_name);
        stpcpy(codec_name, "mpeg1video");
        codec = avcodec_find_encoder_by_name(codec_name);
        if (!codec) {
            fprintf(stderr, "Codec not found");
            return 0;
        }

        c = avcodec_alloc_context3(codec);
        if (!c) {
            fprintf(stderr, "Could not allocate video codec context");
            return 0;
        }
        pkt = av_packet_alloc();
        if (!pkt) {
            fprintf(stderr, "Could not allocate packet");
            return 0;
        }

        /* set width and height */
        c->width = width;
        c->height = height;
        c->pix_fmt = AV_PIX_FMT_YUV420P;
        /* frames per second */
        c->time_base = (AVRational){1, 25};
        c->framerate = (AVRational){25, 1};

        /* emit one intra frame every ten frames
         * check frame pict_type before passing frame
         * to encoder, if frame->pict_type is AV_PICTURE_TYPE_I
         * then gop_size is ignored and the output of encoder
         * will always be I frame irrespective to gop_size
         */
        c->gop_size = 10;
        c->max_b_frames = 1;

        /* additional parameters (codec specific)
        * leave blank for now
        * example:
        *   c->bit_rate = 400000;
        *   if (codec->id == AV_CODEC_ID_H264)
        *       av_opt_set(c->priv_data, "preset", "slow", 0);
        */

        /* open it */
        ret = avcodec_open2(c, codec, NULL);
        if (ret < 0) {
            fprintf(stderr, "Could not open codec");
            printf(av_err2str(ret));
            return 0;
        }

        dst_frame = av_frame_alloc();
        if (!dst_frame) {
            fprintf(stderr, "Could not allocate video dst_frame due to out of memory problem");
            return 0;
        }

        dst_frame->format = c->pix_fmt;
        dst_frame->width = c->width;
        dst_frame->height = c->height;

        if ((av_frame_get_buffer(dst_frame, 0) < 0)) {
            fprintf(stderr, "Could not allocate the video dst_frame data");
            return 0;
        }

        src_frame = av_frame_alloc();
        if (!src_frame) {
            fprintf(stderr, "Could not allocate video src_frame due to out of memory problem");
            return 0;
        }

        src_frame->format = (color_mode == 0) ? AV_PIX_FMT_GRAY8 : AV_PIX_FMT_RGB24;
        src_frame->width = c->width;
        src_frame->height = c->height;

        if ((av_frame_get_buffer(src_frame, 0) < 0)) {
            fprintf(stderr, "Could not allocate the video src_frame data");
            return 0;
        }

        p_data = (uint8_t *) *buf;
        sws_context = sws_getContext(width,
                                     height,
                                     src_frame->format,
                                     width,
                                     height,
                                     dst_frame->format,
                                     SWS_BILINEAR,
                                     NULL,
                                     NULL,
                                     NULL);
        if (!sws_context) {
            fprintf(stderr, "Could not initialize conversion context");
            return 0;
        }

        /* real code for encoding buffer data */
        for (i = 0; i < depth; i++) {
            ret = av_frame_make_writable(src_frame);
            if (ret < 0) {
                fprintf(stderr, "Frame not writable");
                return 0;
            }
            ret = av_frame_make_writable(dst_frame);
            if (ret < 0) {
                fprintf(stderr, "Frame not writable");
                return 0;
            }
            /* put buffer data to frame and do colorspace conversion */
            if (color_mode == 1) {
                for (j = 0; j < 3; j++) {
                    memcpy(src_frame->data[j], p_data, width * height);
                    p_data += width * height;
                }
            } else {
                memcpy(src_frame->data[0], p_data, width * height);
                p_data += width * height;
            }

            printf("frame data %d\n", src_frame->data[0][10]);

            ret = sws_scale_frame(sws_context, dst_frame, src_frame);
            if (ret < 0) {
                fprintf(stderr, "Could not do colorspace conversion");
                return 0;
            }

            dst_frame->pts = i;

            /* encode the frame */
            encode(c, dst_frame, pkt, &out_size, &out_data);
        }

        printf("flush the encoder\n");
        /* flush the encoder */
        encode(c, NULL, pkt, &out_size, &out_data);

        // endcode
        offset = out_size;
        out_data = realloc(out_data, out_size + sizeof(endcode));
        memcpy(out_data + offset, endcode, sizeof(endcode));
        out_size += sizeof(endcode);

        avcodec_free_context(&c);
        av_frame_free(&src_frame);
        av_frame_free(&dst_frame);
        av_packet_free(&pkt);
        sws_freeContext(sws_context);
        if (codec_name) free(codec_name);

        buf_size_out = out_size;

        out_buf = H5allocate_memory(out_size, false);

        if (!out_buf) {
            fprintf(stderr, "Failed to allocate memory for image array");
            goto CompressFailure;
        }

        memcpy(out_buf, out_data, buf_size_out);

        H5free_memory(*buf);
        if (out_data) free(out_data);

        *buf = out_buf;
        *buf_size = buf_size_out;
        printf("buf size out %d\n", *buf_size);

        return buf_size_out;

    CompressFailure:
        fprintf(stderr, "Error compressing array");
        if (codec_name) free(codec_name);
        if (endcode) free(endcode);
        if (out_data) free(out_data);
        if (out_buf) H5free_memory(out_buf);
        if (c) avcodec_free_context(&c);
        if (src_frame) av_frame_free(&src_frame);
        if (dst_frame) av_frame_free(&dst_frame);
        if (pkt) av_packet_free(&pkt);
        if (sws_context) sws_freeContext(sws_context);
        return 0;

    } else {
        /* Decompress */
        /*
        * cd_values[0] = encoder_id
        * cd_values[1] = decoder_id
        * cd_values[2] = width
        * cd_values[3] = height
        * cd_values[4] = depth
        * cd_values[5] = 0=Mono, 1=RGB
        */
        const char *codec_name;
        const AVCodec *codec;
        AVCodecParserContext *parser;
        AVCodecContext *c = NULL;
        AVFrame *src_frame, *dst_frame = NULL;
        AVPacket *pkt;
        struct SwsContext *sws_context = NULL;

        int c_id;
        int width, height, depth;
        int color_mode;
        size_t expected_size;

        uint8_t inbuf[INBUF_SIZE + AV_INPUT_BUFFER_PADDING_SIZE];
        uint8_t *data;
        size_t out_size = 0;
        uint8_t *out_data = NULL;
        size_t data_buf_size;
        unsigned char *p_data = NULL;
        size_t p_data_size = 0;

        int i, ret, eof;

        c_id = cd_values[1];
        width = cd_values[2];
        height = cd_values[3];
        depth = cd_values[4];
        color_mode = cd_values[5];

        pkt = av_packet_alloc();
        if (!pkt) {
            fprintf(stderr, "Could not allocate packet");
            return 0;
        }

        /* padding the end of the buffer to 0 (this ensures that no overreading happens for damaged MPEG streams) */
        memset(inbuf + INBUF_SIZE, 0, AV_INPUT_BUFFER_PADDING_SIZE);

        codec_name = calloc(1, 50);
//        find_decoder_name(c_id, codec_name);
        stpcpy(codec_name, "mpeg1video");
        codec = avcodec_find_decoder_by_name(codec_name);
        if (!codec) {
            fprintf(stderr, "Codec not found");
            return 0;
        }
        parser = av_parser_init(codec->id);
        if (!parser) {
            fprintf(stderr, "parser not found");
            return 0;
        }
        c = avcodec_alloc_context3(codec);
        if (!c) {
            fprintf(stderr, "Could not allocate video codec context");
            return 0;
        }
        /* For some codecs, such as msmpeg4 and mpeg4, width and height
           MUST be initialized there because this information is not
           available in the bitstream. */
        c->width = width;
        c->height = height;

        /* open it */
        if (avcodec_open2(c, codec, NULL) < 0) {
            fprintf(stderr, "Could not open codec");
            return 0;
        }
        src_frame = av_frame_alloc();
        if (!src_frame) {
            fprintf(stderr, "Could not allocate video frame due to out of memory problem");
            return 0;
        }

        src_frame->format = AV_PIX_FMT_YUV420P;
        src_frame->width = c->width;
        src_frame->height = c->height;

        dst_frame = av_frame_alloc();
        if (!dst_frame) {
            fprintf(stderr, "Could not allocate video dst_frame due to out of memory problem");
            return 0;
        }

        dst_frame->format = (color_mode == 1) ? AV_PIX_FMT_RGB24 : AV_PIX_FMT_GRAY8;
        dst_frame->width = c->width;
        dst_frame->height = c->height;

        p_data = (unsigned char *) *buf;
        p_data_size = *buf_size;

        sws_context = sws_getContext(width,
                                     height,
                                     AV_PIX_FMT_YUV420P,
                                     width,
                                     height,
                                     (color_mode == 1) ? AV_PIX_FMT_RGB24 : AV_PIX_FMT_GRAY8,
                                     SWS_BILINEAR,
                                     NULL,
                                     NULL,
                                     NULL);

        /* real code for decoding buffer data */
        do {
            data_buf_size = read_from_buffer(inbuf, INBUF_SIZE, &p_data, &p_data_size);
            eof = !data_buf_size;

            /* use the parser to split the data into frames */
            data = inbuf;
            while (data_buf_size > 0 || eof) {
                ret = av_parser_parse2(parser, c, &pkt->data, &pkt->size,
                                       data, data_buf_size, AV_NOPTS_VALUE, AV_NOPTS_VALUE, 0);
                if (ret < 0) {
                    fprintf(stderr, "Packet not readable");
                    return 0;
                }

                data += ret;
                data_buf_size -= ret;

                if (pkt->size) {
                    /* decode packet */
                    decode(c, src_frame, pkt, sws_context, dst_frame, &out_size, &out_data, color_mode);
                }
                else if (eof)
                    break;
            }
        } while (!eof);

        /* flush the decoder */
        pkt->data = NULL;
        pkt->size = 0;
        decode(c, src_frame, pkt, sws_context, dst_frame, &out_size, &out_data, color_mode);

        /* Sanity check to make sure we have been passed a complete image */
        expected_size = (color_mode == 1) ? height * width * depth * 3 :height * width * depth;
        if (expected_size != out_size) {
            fprintf(stderr, "Decompressed image does not match image size\n");
            goto DecompressFailure;
        }

        av_parser_close(parser);
        avcodec_free_context(&c);
        av_frame_free(&src_frame);
        av_frame_free(&dst_frame);
        av_packet_free(&pkt);

        buf_size_out = out_size;

        out_buf = H5allocate_memory(buf_size_out, false);
        if (!out_buf) {
            fprintf(stderr, "Failed to allocate memory for image array");
            goto DecompressFailure;
        }
        memcpy(out_buf, out_data, buf_size_out);

        H5free_memory(*buf);
        if (codec_name) free(codec_name);
        if (out_data) free(out_data);
        if (sws_context) sws_freeContext(sws_context);
        *buf = out_buf;
        *buf_size = buf_size_out;
        return buf_size_out;

     DecompressFailure:
        fprintf(stderr, "Error decompressing packets\n");
        if (codec_name) free(codec_name);
        if (out_data) free(out_data);
        if (out_buf) H5free_memory(out_buf);
        if (parser) av_parser_close(parser);
        if (c) avcodec_free_context(&c);
        if (src_frame) av_frame_free(&src_frame);
        if (dst_frame) av_frame_free(&dst_frame);
        if (pkt) av_packet_free(&pkt);
        if (sws_context) sws_freeContext(sws_context);
        return 0;
    }
}


H5Z_class_t ffmpeg_H5Filter[1] = {{
      H5Z_CLASS_T_VERS,
      (H5Z_filter_t)(FFMPEG_H5FILTER),
      1, /* encode (compress) */
      1, /* decode (decompress) */
      "ffmpeg",
      NULL,
      NULL,
      (H5Z_func_t)(ffmpeg_h5_filter)
}};


int ffmpeg_register_h5filter(void) {
    int ret;

    ret = H5Zregister(ffmpeg_H5Filter);
    if (ret < 0) {
        PUSH_ERR("ffmpeg_register_h5filter", H5E_CANTREGISTER, "Can't register FFMPEG filter");
    }
    return ret;
}
