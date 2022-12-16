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

#define EXPECTED_CS_RATIO 100

#define PUSH_ERR(func, minor, str) \
    H5Epush(H5E_DEFAULT, __FILE__, func, __LINE__, H5E_ERR_CLS, H5E_PLINE, minor, str)

static size_t read_from_buffer(uint8_t *buf, int buf_size, unsigned char **data, int *data_size);

static void find_encoder_name(int c_id, char *codec_name);

static void find_decoder_name(int c_id, char *codec_name);

static void find_preset(int p_id, char *preset);

static void find_tune(int t_id, char *tune);

static void encode(AVCodecContext *enc_ctx, AVFrame *frame, AVPacket *pkt,
                   size_t *out_size, uint8_t **out_data, size_t *expected_size);

static void decode(AVCodecContext *dec_ctx, AVFrame *src_frame, AVPacket *pkt,
                   struct SwsContext *sws_context, AVFrame *dst_frame,
                   size_t *out_size, uint8_t *out_data, size_t frame_size);

size_t ffmpeg_h5_filter(unsigned flags, size_t cd_nelmts, const unsigned int cd_values[], size_t nbytes,
                        size_t *buf_size, void **buf);

/* Define enums */
enum EncoderCodec
{
    FFH5_ENC_MPEG4 = 0,
    FFH5_ENC_XVID = 1,
    FFH5_ENC_X264 = 2,
    FFH5_ENC_H264_NV = 3,
    FFH5_ENC_X265 = 4,
    FFH5_ENC_HEVC_NV = 5,
    FFH5_ENC_SVTAV1 = 6,
    FFH5_ENC_RAV1E = 7,
};
enum DecoderCodec
{
    FFH5_DEC_MPEG4 = 0,
    FFH5_DEC_H264 = 1,
    FFH5_DEC_H264_CUVID = 2,
    FFH5_DEC_HEVC = 3,
    FFH5_DEC_HEVC_CUVID = 4,
    FFH5_DEC_AOMAV1 = 5,
    FFH5_DEC_DAV1D = 6,
};
enum PresetID
{
    /* no preset */
    FFH5_PRESET_NONE = 0,
    /* libx264 */
    FFH5_PRESET_X264_ULTRAFAST = 10,
    FFH5_PRESET_X264_SUPERFAST = 11,
    FFH5_PRESET_X264_VERYFAST = 12,
    FFH5_PRESET_X264_FASTER = 13,
    FFH5_PRESET_X264_FAST = 14,
    FFH5_PRESET_X264_MEDIUM = 15,
    FFH5_PRESET_X264_SLOW = 16,
    FFH5_PRESET_X264_SLOWER = 17,
    FFH5_PRESET_X264_VERYSLOW = 18,
    /* h264_nvenc */
    FFH5_PRESET_H264_VERYFAST = 100,
    FFH5_PRESET_H264_FASTER = 101,
    FFH5_PRESET_H264_FAST = 102,
    FFH5_PRESET_H264_MEDIUM = 103,
    FFH5_PRESET_H264_SLOW = 104,
    FFH5_PRESET_H264_SLOWER = 105,
    FFH5_PRESET_H264_VERYSLOW = 106,
    /* x265 */
    FFH5_PRESET_X265_ULTRAFAST = 200,
    FFH5_PRESET_X265_SUPERFAST = 201,
    FFH5_PRESET_X265_VERYFAST = 202,
    FFH5_PRESET_X265_FASTER = 203,
    FFH5_PRESET_X265_FAST = 204,
    FFH5_PRESET_X265_MEDIUM = 205,
    FFH5_PRESET_X265_SLOW = 206,
    FFH5_PRESET_X265_SLOWER = 207,
    FFH5_PRESET_X265_VERYSLOW = 208,
    /* hevc_nvenc */
    FFH5_PRESET_HEVC_VERYFAST = 300,
    FFH5_PRESET_HEVC_FASTER = 301,
    FFH5_PRESET_HEVC_FAST = 302,
    FFH5_PRESET_HEVC_MEDIUM = 303,
    FFH5_PRESET_HEVC_SLOW = 304,
    FFH5_PRESET_HEVC_SLOWER = 305,
    FFH5_PRESET_HEVC_VERYSLOW = 306,
    /* svtav1 */
    FFH5_PRESET_SVTAV1_ULTRAFAST = 400,
    FFH5_PRESET_SVTAV1_SUPERFAST = 401,
    FFH5_PRESET_SVTAV1_VERYFAST = 402,
    FFH5_PRESET_SVTAV1_MUCHFASTER = 403,
    FFH5_PRESET_SVTAV1_FASTER = 404,
    FFH5_PRESET_SVTAV1_FAST = 405,
    FFH5_PRESET_SVTAV1_LESSFAST = 406,
    FFH5_PRESET_SVTAV1_MEDIUM = 407,
    FFH5_PRESET_SVTAV1_LESSSLOW = 408,
    FFH5_PRESET_SVTAV1_SLOW = 409,
    FFH5_PRESET_SVTAV1_SLOWER = 410,
    FFH5_PRESET_SVTAV1_MUCHSLOWER = 411,
    FFH5_PRESET_SVTAV1_VERYSLOW = 412,
    FFH5_PRESET_SVTAV1_SUPERSLOW = 413,
    /* rav1e */
    FFH5_PRESET_RAV1E_MUCHFASTER = 500,
    FFH5_PRESET_RAV1E_FASTER = 501,
    FFH5_PRESET_RAV1E_FAST = 502,
    FFH5_PRESET_RAV1E_LESSFAST = 503,
    FFH5_PRESET_RAV1E_MEDIUM = 504,
    FFH5_PRESET_RAV1E_LESSSLOW = 505,
    FFH5_PRESET_RAV1E_SLOW = 506,
    FFH5_PRESET_RAV1E_SLOWER = 507,
    FFH5_PRESET_RAV1E_MUCHSLOWER = 508,
    FFH5_PRESET_RAV1E_VERYSLOW = 509,
    FFH5_PRESET_RAV1E_SUPERSLOW = 510,
};
enum TuneType
{
    /* no tune */
    FFH5_TUNE_NONE = 0,
    /* libx264 */
    FFH5_TUNE_X264_PSNR = 10,
    FFH5_TUNE_X264_SSIM = 11,
    FFH5_TUNE_X264_GRAIN = 12,
    FFH5_TUNE_X264_FASTDECODE = 13,
    FFH5_TUNE_X264_ZEROLATENCY = 14,
    FFH5_TUNE_X264_ANIMATION = 15,
    FFH5_TUNE_X264_FILM = 16,
    FFH5_TUNE_X264_STILLIMAGE = 17,
    /* h264_nvenc */
    FFH5_TUNE_H264_HQ = 100,
    FFH5_TUNE_H264_ll = 101,
    FFH5_TUNE_H264_ULL = 102,
    FFH5_TUNE_H264_LOSSLESS = 103,
    /* x265 */
    FFH5_TUNE_X265_PSNR = 200,
    FFH5_TUNE_X265_SSIM = 201,
    FFH5_TUNE_X265_GRAIN = 202,
    FFH5_TUNE_X265_FASTDECODE = 203,
    FFH5_TUNE_X265_ZEROLATENCY = 204,
    FFH5_TUNE_X265_ANIMATION = 205,
    /* hevc_nvenc */
    FFH5_TUNE_HEVC_HQ = 300,
    FFH5_TUNE_HEVC_ll = 301,
    FFH5_TUNE_HEVC_ULL = 302,
    FFH5_TUNE_HEVC_LOSSLESS = 303,
    /* svtav1 */
    FFH5_TUNE_SVTAV1_VQ = 400,
    FFH5_TUNE_SVTAV1_PSNR = 401,
    FFH5_TUNE_SVTAV1_FASTDECODE = 402,
    /* rav1e */
    FFH5_TUNE_RAV1E_PSNR = 500,
    FFH5_TUNE_RAV1E_PSYCHOVISUAL = 501,
};

/*
 * Function:  read_from_buffer
 * --------------------
 * reads data portion from buffer
 *
 *  *buf: buf to store data portion
 *  buf_size: maximum size to be read from the buffer
 *  **data: ptr of data buffer
 *  *data_size: remain size of the data buffer
 *
 *  returns: size of the size of the reading data portion
 *
 */
static size_t read_from_buffer(uint8_t *buf, int buf_size, unsigned char **data, int *data_size)
{
    if (*data_size <= 0)
        return 0;

    size_t read_size = (*data_size - buf_size >= 0) ? buf_size : *data_size;
    memcpy(buf, *data, read_size);
    *data += read_size;
    *data_size -= read_size;

    return read_size;
}

/*
 * Function:  find_encoder_name
 * --------------------
 * map id used in hdf5 params to real encoders name in ffmpeg
 *
 *  c_id : integer used in hdf5 auxiliary parameters
 *  *codec_name : encoder name
 *
 */
static void find_encoder_name(int c_id, char *codec_name)
{
    switch (c_id)
    {
    case FFH5_ENC_MPEG4:
        strcpy(codec_name, "mpeg4");
        break;
    case FFH5_ENC_XVID:
        strcpy(codec_name, "libxvid");
        break;
    case FFH5_ENC_X264:
        strcpy(codec_name, "libx264");
        break;
    case FFH5_ENC_H264_NV:
        strcpy(codec_name, "h264_nvenc");
        break;
    case FFH5_ENC_X265:
        strcpy(codec_name, "libx265");
        break;
    case FFH5_ENC_HEVC_NV:
        strcpy(codec_name, "hevc_nvenc");
        break;
    case FFH5_ENC_SVTAV1:
        strcpy(codec_name, "libsvtav1");
        break;
    case FFH5_ENC_RAV1E:
        strcpy(codec_name, "librav1e");
        break;

    default:
        strcpy(codec_name, "libx264");
        break;
    }
}

/*
 * Function:  find_decoder_name
 * --------------------
 * map id used in hdf5 params to real decoders name in ffmpeg
 *
 *  c_id : integer used in hdf5 params
 *  *codec_name : decoder name
 *
 */
static void find_decoder_name(int c_id, char *codec_name)
{
    switch (c_id)
    {
    case FFH5_DEC_MPEG4:
        strcpy(codec_name, "mpeg4");
        break;
    case FFH5_DEC_H264:
        strcpy(codec_name, "h264");
        break;
    case FFH5_DEC_H264_CUVID:
        strcpy(codec_name, "h264_cuvid");
        break;
    case FFH5_DEC_HEVC:
        strcpy(codec_name, "hevc");
        break;
    case FFH5_DEC_HEVC_CUVID:
        strcpy(codec_name, "hevc_cuvid");
        break;
    case FFH5_DEC_AOMAV1:
        strcpy(codec_name, "libaom-av1");
        break;
    case FFH5_DEC_DAV1D:
        strcpy(codec_name, "libdav1d");
        break;

    default:
        strcpy(codec_name, "h264");
        break;
    }
}

/*
 * Function:  find_preset
 * --------------------
 * map id used in hdf5 params to preset in different codecs
 *
 *  p_id : integer used in hdf5 auxiliary parameters
 *  *preset : encoder preset
 *
 */
static void find_preset(int p_id, char *preset)
{
    switch (p_id)
    {
    /* x264 and x265 */
    case FFH5_PRESET_X264_ULTRAFAST:
    case FFH5_PRESET_X265_ULTRAFAST:
        strcpy(preset, "ultrafast");
        break;
    case FFH5_PRESET_X264_SUPERFAST:
    case FFH5_PRESET_X265_SUPERFAST:
        strcpy(preset, "superfast");
        break;
    case FFH5_PRESET_X264_VERYFAST:
    case FFH5_PRESET_X265_VERYFAST:
        strcpy(preset, "veryfast");
        break;
    case FFH5_PRESET_X264_FASTER:
    case FFH5_PRESET_X265_FASTER:
        strcpy(preset, "faster");
        break;
    case FFH5_PRESET_X264_FAST:
    case FFH5_PRESET_X265_FAST:
        strcpy(preset, "fast");
        break;
    case FFH5_PRESET_X264_MEDIUM:
    case FFH5_PRESET_X265_MEDIUM:
        strcpy(preset, "medium");
        break;
    case FFH5_PRESET_X264_SLOW:
    case FFH5_PRESET_X265_SLOW:
        strcpy(preset, "slow");
        break;
    case FFH5_PRESET_X264_SLOWER:
    case FFH5_PRESET_X265_SLOWER:
        strcpy(preset, "slower");
        break;
    case FFH5_PRESET_X264_VERYSLOW:
    case FFH5_PRESET_X265_VERYSLOW:
        strcpy(preset, "veryslow");
        break;
    /* h264 and hevc */
    case FFH5_PRESET_H264_VERYFAST:
    case FFH5_PRESET_HEVC_VERYFAST:
        strcpy(preset, "p1");
        break;
    case FFH5_PRESET_H264_FASTER:
    case FFH5_PRESET_HEVC_FASTER:
        strcpy(preset, "p2");
        break;
    case FFH5_PRESET_H264_FAST:
    case FFH5_PRESET_HEVC_FAST:
        strcpy(preset, "p3");
        break;
    case FFH5_PRESET_H264_MEDIUM:
    case FFH5_PRESET_HEVC_MEDIUM:
        strcpy(preset, "p4");
        break;
    case FFH5_PRESET_H264_SLOW:
    case FFH5_PRESET_HEVC_SLOW:
        strcpy(preset, "p5");
        break;
    case FFH5_PRESET_H264_SLOWER:
    case FFH5_PRESET_HEVC_SLOWER:
        strcpy(preset, "p6");
        break;
    case FFH5_PRESET_H264_VERYSLOW:
    case FFH5_PRESET_HEVC_VERYSLOW:
        strcpy(preset, "p7");
        break;
    /* svtav1 and rav1e */
    case FFH5_PRESET_SVTAV1_SUPERSLOW:
    case FFH5_PRESET_RAV1E_SUPERSLOW:
        strcpy(preset, "0");
        break;
    case FFH5_PRESET_SVTAV1_VERYSLOW:
    case FFH5_PRESET_RAV1E_VERYSLOW:
        strcpy(preset, "1");
        break;
    case FFH5_PRESET_SVTAV1_MUCHSLOWER:
    case FFH5_PRESET_RAV1E_MUCHSLOWER:
        strcpy(preset, "2");
        break;
    case FFH5_PRESET_SVTAV1_SLOWER:
    case FFH5_PRESET_RAV1E_SLOWER:
        strcpy(preset, "3");
        break;
    case FFH5_PRESET_SVTAV1_SLOW:
    case FFH5_PRESET_RAV1E_SLOW:
        strcpy(preset, "4");
        break;
    case FFH5_PRESET_SVTAV1_LESSSLOW:
    case FFH5_PRESET_RAV1E_LESSSLOW:
        strcpy(preset, "5");
        break;
    case FFH5_PRESET_SVTAV1_MEDIUM:
    case FFH5_PRESET_RAV1E_MEDIUM:
        strcpy(preset, "6");
        break;
    case FFH5_PRESET_SVTAV1_LESSFAST:
    case FFH5_PRESET_RAV1E_LESSFAST:
        strcpy(preset, "7");
        break;
    case FFH5_PRESET_SVTAV1_FAST:
    case FFH5_PRESET_RAV1E_FAST:
        strcpy(preset, "8");
        break;
    case FFH5_PRESET_SVTAV1_FASTER:
    case FFH5_PRESET_RAV1E_FASTER:
        strcpy(preset, "9");
        break;
    case FFH5_PRESET_SVTAV1_MUCHFASTER:
    case FFH5_PRESET_RAV1E_MUCHFASTER:
        strcpy(preset, "10");
        break;
    case FFH5_PRESET_SVTAV1_VERYFAST:
        strcpy(preset, "11");
        break;
    case FFH5_PRESET_SVTAV1_SUPERFAST:
        strcpy(preset, "12");
        break;
    case FFH5_PRESET_SVTAV1_ULTRAFAST:
        strcpy(preset, "13");
        break;

    default:
        printf("No such preset for this codec, default/no preset will be used\n");
        break;
    }
}

/*
 * Function:  find_tune
 * --------------------
 * map id used in hdf5 params to tune in different codecs
 *
 *  t_id : integer used in hdf5 auxiliary parameters
 *  *tune : encoder tune parameter
 *
 */
static void find_tune(int t_id, char *tune)
{
    switch (t_id)
    {
    /* x264 and x265 */
    case FFH5_TUNE_X264_PSNR:
    case FFH5_TUNE_X265_PSNR:
        strcpy(tune, "psnr");
        break;
    case FFH5_TUNE_X264_SSIM:
    case FFH5_TUNE_X265_SSIM:
        strcpy(tune, "ssim");
        break;
    case FFH5_TUNE_X264_GRAIN:
    case FFH5_TUNE_X265_GRAIN:
        strcpy(tune, "grain");
        break;
    case FFH5_TUNE_X264_FASTDECODE:
    case FFH5_TUNE_X265_FASTDECODE:
        strcpy(tune, "fastdecode");
        break;
    case FFH5_TUNE_X264_ZEROLATENCY:
    case FFH5_TUNE_X265_ZEROLATENCY:
        strcpy(tune, "zerolatency");
        break;
    case FFH5_TUNE_X264_ANIMATION:
    case FFH5_TUNE_X265_ANIMATION:
        strcpy(tune, "animation");
        break;
    case FFH5_TUNE_X264_FILM:
        strcpy(tune, "film");
        break;
    case FFH5_TUNE_X264_STILLIMAGE:
        strcpy(tune, "stillimage");
        break;
    /* h264 and hevc */
    case FFH5_TUNE_H264_HQ:
    case FFH5_TUNE_HEVC_HQ:
        strcpy(tune, "hq");
        break;
    case FFH5_TUNE_H264_ll:
    case FFH5_TUNE_HEVC_ll:
        strcpy(tune, "ll");
        break;
    case FFH5_TUNE_H264_ULL:
    case FFH5_TUNE_HEVC_ULL:
        strcpy(tune, "ull");
        break;
    case FFH5_TUNE_H264_LOSSLESS:
    case FFH5_TUNE_HEVC_LOSSLESS:
        strcpy(tune, "lossless");
        break;
    /* svtav1 */
    case FFH5_TUNE_SVTAV1_VQ:
        strcpy(tune, "tune=0");
        break;
    case FFH5_TUNE_SVTAV1_PSNR:
        strcpy(tune, "tune=1");
        break;
    case FFH5_TUNE_SVTAV1_FASTDECODE:
        strcpy(tune, "fast-decode=1");
        break;
    /* rav1e */
    case FFH5_TUNE_RAV1E_PSNR:
        strcpy(tune, "tune=Psnr");
        break;
    case FFH5_TUNE_RAV1E_PSYCHOVISUAL:
        strcpy(tune, "tune=Psychovisual");
        break;

    default:
        printf("No such tune for this codec, default/no tune will be used\n");
        break;
    }
}

/*
 * Function:  encode
 * --------------------
 * encode a ffmpeg frame
 *
 *  *enc_ctx: AVCodecContext
 *  *frame: frame to be encoded
 *  *pkt: pkt where data being compressed into
 *  *out_size: accumulated compressed pkts data size
 *  **out_data: compressed pkts data
 *  *expected_size: expected size of the compressed buffer
 *
 */
static void encode(AVCodecContext *enc_ctx, AVFrame *frame, AVPacket *pkt,
                   size_t *out_size, uint8_t **out_data, size_t *expected_size)
{
    int ret;
    size_t offset = 0;
    size_t updated_size = 0;

    /* send the frame to the encoder */
    // if (frame)
    //     printf("Encode frame %3" PRId64 "\n", frame->pts);

    ret = avcodec_send_frame(enc_ctx, frame);
    if (ret < 0)
        fprintf(stderr, "Error sending a frame for encoding\n");

    while (ret >= 0)
    {
        ret = avcodec_receive_packet(enc_ctx, pkt);
        if (ret == AVERROR(EAGAIN) || ret == AVERROR_EOF)
            return;
        if (ret < 0)
            fprintf(stderr, "Error during encoding\n");

        // printf("Encode/Write packet %3" PRId64 " (size=%9d)\n", pkt->pts, pkt->size);

        offset = *out_size;
        updated_size = *out_size + pkt->size;

        // each time exceeds memory block then realloc two times bigger block
        if (updated_size > *expected_size)
        {
            *out_data = realloc(*out_data, updated_size * 2);
            *expected_size = updated_size * 2;
        }

        if (*out_data == NULL)
            fprintf(stderr, "Out of memory occurred during encoding\n");

        memcpy(*out_data + offset, pkt->data, pkt->size);
        *out_size = updated_size;
        av_packet_unref(pkt);
    }
}

/*
 * Function:  decode
 * --------------------
 * decode a compressed pkt/pkts to frame/frames and convert colorspace of the frame/frames
 *
 *  *dec_ctx: AVCodecContext
 *  *src_frame: source frame where compressed pkt to be decoded
 *  *pkt: compressed pkt
 *  *sws_context: context of colorspace conversion
 *  *dst_frame: destination frame
 *  *out_size: accumulated destination frame data size
 *  *out_data: frame data took from destination frame
 *  frame_size: size of frame
 *
 */
static void decode(AVCodecContext *dec_ctx, AVFrame *src_frame, AVPacket *pkt,
                   struct SwsContext *sws_context, AVFrame *dst_frame,
                   size_t *out_size, uint8_t *out_data, size_t frame_size)
{
    int ret;
    size_t offset = 0;

    ret = avcodec_send_packet(dec_ctx, pkt);

    if (ret < 0)
        fprintf(stderr, "Error sending a pkt for encoding\n");

    // printf("receiving packets %d\n", pkt->size);

    while (ret >= 0)
    {
        ret = avcodec_receive_frame(dec_ctx, src_frame);
        if (ret == AVERROR(EAGAIN) || ret == AVERROR_EOF)
            return;
        else if (ret < 0)
            fprintf(stderr, "Error receiving a frame for encoding\n");

        // printf("Decode frame %3d\n", dec_ctx->frame_number);

        /* do colorspace conversion */
        sws_scale_frame(sws_context, dst_frame, src_frame);

        /* put to buffer */
        offset = *out_size;

        av_image_copy_to_buffer(out_data + offset,
                                frame_size,
                                (const uint8_t *const *)dst_frame->data,
                                dst_frame->linesize,
                                dst_frame->format,
                                dst_frame->width,
                                dst_frame->height,
                                1);
        *out_size += frame_size;
    }
}

/*
 * Function:  ffmpeg_h5_filter
 * --------------------
 * The ffmpeg filter function
 *
 *  flags:
 *  cd_nelmts: number of auxiliary parameters
 *  cd_values: auxiliary parameters
 *  nbytes: valid data size
 *  *buf_size: size of buffer
 *  **buf: buffer
 *
 *  return: 0 (failed), otherwise size of buffer
 *
 */
size_t ffmpeg_h5_filter(unsigned flags, size_t cd_nelmts, const unsigned int cd_values[], size_t nbytes,
                        size_t *buf_size, void **buf)
{

    size_t buf_size_out = 0;
    void *out_buf = NULL;

    if (!(flags & H5Z_FLAG_REVERSE))
    {
        /* Compress */
        /*
         * cd_values[0] = encoder_id
         * cd_values[1] = decoder_id
         * cd_values[2] = width
         * cd_values[3] = height
         * cd_values[4] = depth
         * cd_values[5] = 0=Mono, 1=RGB
         * cd_values[6] = preset
         * cd_values[7] = tune
         */
        const AVCodec *codec;
        AVCodecContext *c = NULL;
        AVFrame *src_frame = NULL, *dst_frame = NULL;
        AVPacket *pkt;
        struct SwsContext *sws_context = NULL;

        char *codec_name, *preset, *tune;
        enum EncoderCodec c_id;
        enum PresetID p_id;
        enum TuneType t_id;

        int width, height, depth;
        int color_mode;

        size_t expected_size = 0, frame_size = 0;
        uint8_t *out_data = NULL, *p_data = NULL;
        size_t out_size = 0;

        int i, j, ret;

        c_id = cd_values[0];
        width = cd_values[2];
        height = cd_values[3];
        depth = cd_values[4];
        color_mode = cd_values[5];
        p_id = cd_values[6];
        t_id = cd_values[7];

        codec_name = calloc(1, 50);
        find_encoder_name(c_id, codec_name);

        preset = calloc(1, 50);
        tune = calloc(1, 50);
        if (c_id == FFH5_ENC_MPEG4 || c_id == FFH5_ENC_XVID)
        {
            p_id = FFH5_PRESET_NONE;
            t_id = FFH5_TUNE_NONE;
        }

        find_preset(p_id, preset);
        find_tune(t_id, tune);

        codec = avcodec_find_encoder_by_name(codec_name);
        if (!codec)
        {
            fprintf(stderr, "Codec not found\n");
            return 0;
        }

        c = avcodec_alloc_context3(codec);
        if (!c)
        {
            fprintf(stderr, "Could not allocate video codec context\n");
            return 0;
        }
        pkt = av_packet_alloc();
        if (!pkt)
        {
            fprintf(stderr, "Could not allocate packet\n");
            return 0;
        }

        /* set width and height */
        c->width = width;
        c->height = height;
        c->pix_fmt = (strstr(codec_name, "nvenc")) ? AV_PIX_FMT_NV12 : AV_PIX_FMT_YUV420P;

        /* frames per second */
        c->time_base = (AVRational){1, 25};
        c->framerate = (AVRational){25, 1};

        /* emit one intra frame every ten frames
         * check frame pict_type before passing frame
         * to encoder, if frame->pict_type is AV_PICTURE_TYPE_I
         * then gop_size is ignored and the output of encoder
         * will always be I frame irrespective to gop_size
         */

        // c->gop_size = 10;
        // c->max_b_frames = 1;

        /* Presets and Tunes */
        switch (c_id)
        {
        case FFH5_ENC_X264:
        case FFH5_ENC_X265:
        case FFH5_ENC_H264_NV:
        case FFH5_ENC_HEVC_NV:
            if (strlen(preset) > 0)
                av_opt_set(c->priv_data, "preset", preset, 0);
            if (strlen(tune) > 0)
                av_opt_set(c->priv_data, "tune", tune, 0);
            break;
        case FFH5_ENC_SVTAV1:
            if (strlen(preset) > 0)
                av_opt_set_int(c->priv_data, "preset", atoi(preset), 0);
            if (strlen(tune) > 0)
                av_opt_set(c->priv_data, "svtav1-params", tune, 0);
            break;
        case FFH5_ENC_RAV1E:
            if (strlen(preset) > 0)
                av_opt_set_int(c->priv_data, "speed", atoi(preset), 0);
            if (strlen(tune) > 0)
                av_opt_set(c->priv_data, "rav1e-params", tune, 0);
            break;

        default:
            break;
        }

        /* open it */
        ret = avcodec_open2(c, codec, NULL);
        if (ret < 0)
        {
            fprintf(stderr, "Could not open codec\n");
            printf(av_err2str(ret));
            return 0;
        }

        dst_frame = av_frame_alloc();
        if (!dst_frame)
        {
            fprintf(stderr, "Could not allocate video dst_frame due to out of memory problem\n");
            return 0;
        }

        dst_frame->format = c->pix_fmt;
        dst_frame->width = c->width;
        dst_frame->height = c->height;

        if ((av_frame_get_buffer(dst_frame, 0) < 0))
        {
            fprintf(stderr, "Could not allocate the video dst_frame data\n");
            return 0;
        }

        src_frame = av_frame_alloc();
        if (!src_frame)
        {
            fprintf(stderr, "Could not allocate video src_frame due to out of memory problem\n");
            return 0;
        }

        src_frame->format = (color_mode == 0) ? AV_PIX_FMT_GRAY8 : AV_PIX_FMT_RGB24;
        src_frame->width = c->width;
        src_frame->height = c->height;

        if (av_frame_get_buffer(src_frame, 0) < 0)
        {
            fprintf(stderr, "Could not allocate the video src_frame data\n");
            return 0;
        }

        p_data = (uint8_t *)*buf;

        frame_size = (color_mode == 0) ? width * height : width * height * 3;
        expected_size = frame_size * depth / EXPECTED_CS_RATIO;
        out_data = calloc(1, expected_size);

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
        if (!sws_context)
        {
            fprintf(stderr, "Could not initialize conversion context\n");
            return 0;
        }

        /* real code for encoding buffer data */
        for (i = 0; i < depth; i++)
        {
            ret = av_frame_make_writable(src_frame);
            if (ret < 0)
            {
                fprintf(stderr, "Frame not writable\n");
                return 0;
            }
            ret = av_frame_make_writable(dst_frame);
            if (ret < 0)
            {
                fprintf(stderr, "Frame not writable\n");
                return 0;
            }
            /* put buffer data to frame and do colorspace conversion */
            av_image_fill_arrays(src_frame->data, src_frame->linesize, p_data, src_frame->format, width, height, 1);
            p_data += frame_size;

            ret = sws_scale_frame(sws_context, dst_frame, src_frame);
            if (ret < 0)
            {
                fprintf(stderr, "Could not do colorspace conversion\n");
                return 0;
            }

            dst_frame->pts = i;

            /* encode the frame */
            encode(c, dst_frame, pkt, &out_size, &out_data, &expected_size);
        }

        /* flush the encoder */
        encode(c, NULL, pkt, &out_size, &out_data, &expected_size);

        avcodec_free_context(&c);
        av_frame_free(&src_frame);
        av_frame_free(&dst_frame);
        av_packet_free(&pkt);
        sws_freeContext(sws_context);
        if (codec_name)
            free(codec_name);
        if (preset)
            free(preset);
        if (tune)
            free(tune);

        buf_size_out = out_size;

        out_buf = H5allocate_memory(out_size, false);

        if (!out_buf)
        {
            fprintf(stderr, "Failed to allocate memory for image array\n");
            goto CompressFailure;
        }

        memcpy(out_buf, out_data, buf_size_out);
        H5free_memory(*buf);
        if (out_data)
            free(out_data);

        *buf = out_buf;
        *buf_size = buf_size_out;
        return buf_size_out;

    CompressFailure:
        fprintf(stderr, "Error compressing array\n");
        if (codec_name)
            free(codec_name);
        if (preset)
            free(preset);
        if (tune)
            free(tune);
        if (out_data)
            free(out_data);
        if (out_buf)
            H5free_memory(out_buf);
        if (c)
            avcodec_free_context(&c);
        if (src_frame)
            av_frame_free(&src_frame);
        if (dst_frame)
            av_frame_free(&dst_frame);
        if (pkt)
            av_packet_free(&pkt);
        if (sws_context)
            sws_freeContext(sws_context);
        return 0;
    }
    else
    {
        /* Decompress */
        /*
         * cd_values[0] = encoder_id
         * cd_values[1] = decoder_id
         * cd_values[2] = width
         * cd_values[3] = height
         * cd_values[4] = depth
         * cd_values[5] = 0=Mono, 1=RGB
         */
        const AVCodec *codec;
        AVCodecParserContext *parser;
        AVCodecContext *c = NULL;
        AVFrame *src_frame = NULL, *dst_frame = NULL;
        AVPacket *pkt;
        struct SwsContext *sws_context = NULL;

        const char *codec_name;
        enum DecoderCodec c_id;

        int width, height, depth;
        int color_mode;

        size_t p_data_size = 0, frame_size = 0;
        uint8_t *out_data = NULL, *p_data = NULL;
        size_t out_size = 0;

        int i, ret, eof;

        c_id = cd_values[1];
        width = cd_values[2];
        height = cd_values[3];
        depth = cd_values[4];
        color_mode = cd_values[5];

        pkt = av_packet_alloc();
        if (!pkt)
        {
            fprintf(stderr, "Could not allocate packet\n");
            return 0;
        }

        codec_name = calloc(1, 50);
        find_decoder_name(c_id, codec_name);

        codec = avcodec_find_decoder_by_name(codec_name);
        if (!codec)
        {
            fprintf(stderr, "Codec not found\n");
            return 0;
        }
        parser = av_parser_init(codec->id);
        if (!parser)
        {
            fprintf(stderr, "parser not found\n");
            return 0;
        }
        c = avcodec_alloc_context3(codec);
        if (!c)
        {
            fprintf(stderr, "Could not allocate video codec context\n");
            return 0;
        }
        /* For some codecs, such as msmpeg4 and mpeg4, width and height
           MUST be initialized there because this information is not
           available in the bitstream. */
        c->width = width;
        c->height = height;

        /* open it */
        if (avcodec_open2(c, codec, NULL) < 0)
        {
            fprintf(stderr, "Could not open codec\n");
            return 0;
        }
        src_frame = av_frame_alloc();
        if (!src_frame)
        {
            fprintf(stderr, "Could not allocate video frame due to out of memory problem\n");
            return 0;
        }

        src_frame->format = (strstr(codec_name, "cuvid")) ? AV_PIX_FMT_NV12 : AV_PIX_FMT_YUV420P;
        src_frame->width = c->width;
        src_frame->height = c->height;

        dst_frame = av_frame_alloc();
        if (!dst_frame)
        {
            fprintf(stderr, "Could not allocate video dst_frame due to out of memory problem\n");
            return 0;
        }

        dst_frame->format = (color_mode == 1) ? AV_PIX_FMT_RGB24 : AV_PIX_FMT_GRAY8;
        dst_frame->width = c->width;
        dst_frame->height = c->height;

        p_data = (uint8_t *)*buf;
        p_data_size = *buf_size;

        frame_size = (color_mode == 0) ? width * height : width * height * 3;
        out_data = calloc(1, frame_size * depth + AV_INPUT_BUFFER_PADDING_SIZE);

        if (out_data == NULL)
            fprintf(stderr, "Out of memory occurred during decoding\n");

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

        /* real code for decoding buffer data */
        while (p_data_size >= 0 || eof)
        {
            eof = !p_data_size;

            ret = av_parser_parse2(parser, c, &pkt->data, &pkt->size,
                                   p_data, p_data_size, AV_NOPTS_VALUE, AV_NOPTS_VALUE, 0);

            if (ret < 0)
            {
                fprintf(stderr, "Packet not readable\n");
                return 0;
            }

            p_data += ret;
            p_data_size -= ret;

            if (pkt->size)
                decode(c, src_frame, pkt, sws_context, dst_frame, &out_size, out_data, frame_size);
            else if (eof)
                break;
        }

        /* flush the decoder */
        pkt->data = NULL;
        pkt->size = 0;
        decode(c, src_frame, pkt, sws_context, dst_frame, &out_size, out_data, frame_size);

        av_parser_close(parser);
        avcodec_free_context(&c);
        av_frame_free(&src_frame);
        av_frame_free(&dst_frame);
        av_packet_free(&pkt);

        buf_size_out = out_size;

        out_buf = H5allocate_memory(buf_size_out, false);

        if (!out_buf)
        {
            fprintf(stderr, "Failed to allocate memory for image array\n");
            goto DecompressFailure;
        }
        memcpy(out_buf, out_data, buf_size_out);

        H5free_memory(*buf);
        if (codec_name)
            free(codec_name);
        if (out_data)
            free(out_data);
        if (sws_context)
            sws_freeContext(sws_context);
        *buf = out_buf;
        *buf_size = buf_size_out;

        return buf_size_out;

    DecompressFailure:
        fprintf(stderr, "Error decompressing packets\n");
        if (codec_name)
            free(codec_name);
        if (out_data)
            free(out_data);
        if (out_buf)
            H5free_memory(out_buf);
        if (parser)
            av_parser_close(parser);
        if (c)
            avcodec_free_context(&c);
        if (src_frame)
            av_frame_free(&src_frame);
        if (dst_frame)
            av_frame_free(&dst_frame);
        if (pkt)
            av_packet_free(&pkt);
        if (sws_context)
            sws_freeContext(sws_context);
        return 0;
    }
}

/* H5Z struct declaration */
H5Z_class_t ffmpeg_H5Filter[1] = {{H5Z_CLASS_T_VERS,
                                   (H5Z_filter_t)(FFMPEG_H5FILTER),
                                   1, /* encode (compress) */
                                   1, /* decode (decompress) */
                                   "ffmpeg see https://github.com/Cai-Lab-at-University-of-Michigan/ffmpeg_HDF5_filter",
                                   NULL,
                                   NULL,
                                   (H5Z_func_t)(ffmpeg_h5_filter)}};

/*
 * Function:  ffmpeg_register_h5filter
 * --------------------
 * register ffmpeg hdf5 filter
 *
 *  return: negative value (failed), otherwise success
 *
 */
int ffmpeg_register_h5filter(void)
{
    int ret;

    ret = H5Zregister(ffmpeg_H5Filter);
    if (ret < 0)
        PUSH_ERR("ffmpeg_register_h5filter", H5E_CANTREGISTER, "Can't register FFMPEG filter");

    return ret;
}