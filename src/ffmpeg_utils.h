/*
 * FFMPEG HDF5 filter
 *
 * Author: Bin Duan <bduan2@hawk.iit.edu>
 * Created: 2022
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
char *stpcpy(char *dest, const char *src)
{
    while ((*dest++ = *src++))
        ;
    return dest - 1;
}
#endif

#define EXPECTED_CS_RATIO 30

#define FFMPEG_FLAG_COMPRESS 0x0000

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
    case FFH5_ENC_AV1_NV:
        strcpy(codec_name, "av1_nvenc");
        break;
    case FFH5_ENC_AV1_QSV:
        strcpy(codec_name, "av1_qsv");
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
    case FFH5_DEC_AV1_CUVID:
        strcpy(codec_name, "av1_cuvid");
        break;
    case FFH5_DEC_AV1_QSV:
        strcpy(codec_name, "av1_qsv");
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
    /* h264, hevc, av1_nvenc */
    case FFH5_PRESET_H264NV_FASTEST:
    case FFH5_PRESET_HEVCNV_FASTEST:
    case FFH5_PRESET_AV1NV_FASTEST:
        strcpy(preset, "p1");
        break;
    case FFH5_PRESET_H264NV_FASTER:
    case FFH5_PRESET_HEVCNV_FASTER:
    case FFH5_PRESET_AV1NV_FASTER:
        strcpy(preset, "p2");
        break;
    case FFH5_PRESET_H264NV_FAST:
    case FFH5_PRESET_HEVCNV_FAST:
    case FFH5_PRESET_AV1NV_FAST:
        strcpy(preset, "p3");
        break;
    case FFH5_PRESET_H264NV_MEDIUM:
    case FFH5_PRESET_HEVCNV_MEDIUM:
    case FFH5_PRESET_AV1NV_MEDIUM:
        strcpy(preset, "p4");
        break;
    case FFH5_PRESET_H264NV_SLOW:
    case FFH5_PRESET_HEVCNV_SLOW:
    case FFH5_PRESET_AV1NV_SLOW:
        strcpy(preset, "p5");
        break;
    case FFH5_PRESET_H264NV_SLOWER:
    case FFH5_PRESET_HEVCNV_SLOWER:
    case FFH5_PRESET_AV1NV_SLOWER:
        strcpy(preset, "p6");
        break;
    case FFH5_PRESET_H264NV_SLOWEST:
    case FFH5_PRESET_HEVCNV_SLOWEST:
    case FFH5_PRESET_AV1NV_SLOWEST:
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
    /* av1_qsv */
    case FFH5_PRESET_AV1QSV_FASTEST:
        strcpy(preset, "veryfast");
        break;
    case FFH5_PRESET_AV1QSV_FASTER:
        strcpy(preset, "faster");
        break;
    case FFH5_PRESET_AV1QSV_FAST:
        strcpy(preset, "fast");
        break;
    case FFH5_PRESET_AV1QSV_MEDIUM:
        strcpy(preset, "medium");
        break;
    case FFH5_PRESET_AV1QSV_SLOW:
        strcpy(preset, "slow");
        break;
    case FFH5_PRESET_AV1QSV_SLOWER:
        strcpy(preset, "slower");
        break;
    case FFH5_PRESET_AV1QSV_SLOWEST:
        strcpy(preset, "veryslow");
        break;

    default:
        // printf("No such preset for this codec, default preset will be used\n");
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
    /* h264, hevc, av1_nvenc */
    case FFH5_TUNE_H264NV_HQ:
    case FFH5_TUNE_HEVCNV_HQ:
    case FFH5_TUNE_AV1NV_HQ:
        strcpy(tune, "hq");
        break;
    case FFH5_TUNE_H264NV_LL:
    case FFH5_TUNE_HEVCNV_LL:
    case FFH5_TUNE_AV1NV_LL:
        strcpy(tune, "ll");
        break;
    case FFH5_TUNE_H264NV_ULL:
    case FFH5_TUNE_HEVCNV_ULL:
    case FFH5_TUNE_AV1NV_ULL:
        strcpy(tune, "ull");
        break;
    case FFH5_TUNE_H264NV_LOSSLESS:
    case FFH5_TUNE_HEVCNV_LOSSLESS:
    case FFH5_TUNE_AV1NV_LOSSLESS:
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
    /* qsv_av1 */
    case FFH5_TUNE_AV1QSV_UNKNOWN:
        strcpy(tune, "unknown");
        break;
    case FFH5_TUNE_AV1QSV_DISPLAYREMOTING:
        strcpy(tune, "displayremoting");
        break;
    case FFH5_TUNE_AV1QSV_VIDEOCONFERENCE:
        strcpy(tune, "videoconference");
        break;
    case FFH5_TUNE_AV1QSV_ARCHIVE:
        strcpy(tune, "archive");
        break;
    case FFH5_TUNE_AV1QSV_LIVESTREAMING:
        strcpy(tune, "livestreaming");
        break;
    case FFH5_TUNE_AV1QSV_CAMERACAPTURE:
        strcpy(tune, "cameracapture");
        break;
    case FFH5_TUNE_AV1QSV_VIDEOSURVEILLANCE:
        strcpy(tune, "videosurveillance");
        break;
    case FFH5_TUNE_AV1QSV_GAMESTREAMING:
        strcpy(tune, "gamestreaming");
        break;
    case FFH5_TUNE_AV1QSV_REMOTEGAMING:
        strcpy(tune, "remotegaming");
        break;

    default:
        // printf("No such tune for this codec, default tune will be used\n");
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
        raise_ffmpeg_error("Error sending a frame for encoding\n");

    while (ret >= 0)
    {
        ret = avcodec_receive_packet(enc_ctx, pkt);
        if (ret == AVERROR(EAGAIN) || ret == AVERROR_EOF)
            return;
        if (ret < 0)
            raise_ffmpeg_error("Error during encoding\n");

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
            raise_ffmpeg_error("Out of memory occurred during encoding\n");

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
        raise_ffmpeg_error("Error sending a pkt for decoding\n");

    // printf("receiving packets %d\n", pkt->size);

    while (ret >= 0)
    {
        ret = avcodec_receive_frame(dec_ctx, src_frame);
        if (ret == AVERROR(EAGAIN) || ret == AVERROR_EOF)
            return;
        else if (ret < 0)
            raise_ffmpeg_error("Error receiving a frame for decoding\n");

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

#endif // FFMPEG_UTILS_H