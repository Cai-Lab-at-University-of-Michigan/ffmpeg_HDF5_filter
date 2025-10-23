/*
 * FFMPEG HDF5 filter
 *
 * Author: Bin Duan <duanb@umich.edu>
 * Created: 2024
 *
 */

#include "ffmpeg_utils.h"

void raise_ffmpeg_error(const char *msg)
{
    fprintf(stderr, "\e[96;40m[HDF5_FILTER_FFMPEG]\e[91;40m %s\e[0m", msg);
    fflush(stderr);
}

size_t ffmpeg_native(unsigned flags, const unsigned int cd_values[], size_t buf_size, void **buf);

/*
 * Function:  ffmpeg_native
 * --------------------
 * The ffmpeg filter function
 *
 *  flags: 0-compress, 1-decompress
 *  cd_values: auxiliary parameters
 *  buf_size: valid data size
 *
 *  return: 0 (failed), otherwise size of buffer
 *
 */
size_t ffmpeg_native(unsigned flags, const unsigned int cd_values[], size_t buf_size, void **buf)
{
    void *out_buf = NULL;

    if (flags == FFMPEG_FLAG_COMPRESS)
    {
        /* Compress */
        /*
         * cd_values[0] = encoder_id
         * cd_values[1] = decoder_id
         * cd_values[2] = width
         * cd_values[3] = height
         * cd_values[4] = depth
         * cd_values[5] = bit_mode
         * cd_values[6] = preset
         * cd_values[7] = tune
         * cd_values[8] = crf
         * cd_values[9] = film_grain [for svt-av1 only]
         * cd_values[10] = gpu_id [for nvidia gpu only]
         */
        const AVCodec *codec;
        AVCodecContext *c = NULL;
        AVFrame *src_frame = NULL, *dst_frame = NULL;
        AVPacket *pkt;
        struct SwsContext *sws_context = NULL;
        // int thread_count = 16; // single thread

        char *codec_name, *preset, *tune;
        enum EncoderCodecEnum c_id;
        enum PresetIDEnum p_id;
        enum TuneTypeEnum t_id;

        int width, height, depth;
        int color_mode;
        int crf;
        int film_grain;
        int gpu_id;
        char film_grain_buffer[10];

        size_t expected_size = 0, frame_size = 0;
        uint8_t *out_data = NULL, *p_data = NULL;
        size_t out_size = 0;

        int i, ret;

        c_id = cd_values[0];
        width = cd_values[2];
        height = cd_values[3];
        depth = cd_values[4];
        color_mode = cd_values[5];
        p_id = cd_values[6];
        t_id = cd_values[7];
        crf = cd_values[8];
        film_grain = cd_values[9]; // for svt-av1 particularly
        gpu_id = cd_values[10];    // for nvenc only

        av_log_set_level(AV_LOG_ERROR);
        codec_name = calloc(1, 50);
        find_encoder_name(c_id, codec_name);

        preset = calloc(1, 50);
        tune = calloc(1, 100);
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
            raise_ffmpeg_error("Codec not found\n");
            goto CompressFailure;
        }

        c = avcodec_alloc_context3(codec);
        if (!c)
        {
            raise_ffmpeg_error("Could not allocate video codec context\n");
            goto CompressFailure;
        }

        pkt = av_packet_alloc();
        if (!pkt)
        {
            raise_ffmpeg_error("Could not allocate packet\n");
            goto CompressFailure;
        }

        /* set width and height */
        c->width = width;
        c->height = height;

        switch (c_id)
        {
        // list those who support 10bit encoding (actually using 16bit)
        case FFH5_ENC_X264:
        case FFH5_ENC_SVTAV1:
        case FFH5_ENC_RAV1E:
            c->pix_fmt = (color_mode == 0) ? AV_PIX_FMT_YUV420P : AV_PIX_FMT_YUV420P10;
            break;
        case FFH5_ENC_X265:
            switch (color_mode)
            {
            case 0: // 8bit
                c->pix_fmt = AV_PIX_FMT_YUV420P;
                break;
            case 1: // 10bit
                c->pix_fmt = AV_PIX_FMT_YUV420P10;
                break;
            case 2: // 12bit
                c->pix_fmt = AV_PIX_FMT_YUV420P12;
                break;
            default:
                c->pix_fmt = AV_PIX_FMT_YUV420P;
            }
            break;
        // We have to use NV12
        case FFH5_ENC_H264_NV:
        case FFH5_ENC_HEVC_NV:
        case FFH5_ENC_AV1_NV:
        case FFH5_ENC_AV1_QSV:
            c->pix_fmt = (color_mode == 0) ? AV_PIX_FMT_NV12 : AV_PIX_FMT_P010;
            break;
        default:
            // common supported pixel format 8bit (actually using 16bit)
            c->pix_fmt = AV_PIX_FMT_YUV420P;
        }

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

        /* Presets and Tunes and CRFS */
        switch (c_id)
        {
        case FFH5_ENC_X264:
        case FFH5_ENC_X265:
            if (strlen(preset) > 0)
                av_opt_set(c->priv_data, "preset", preset, 0);
            if (strlen(tune) > 0)
                av_opt_set(c->priv_data, "tune", tune, 0);
            if (crf < 52)
                av_opt_set_int(c->priv_data, "crf", crf, 0);
            av_opt_set(c->priv_data, "x265-params", "log-level=0", 0);
            break;
        case FFH5_ENC_H264_NV:
        case FFH5_ENC_HEVC_NV:
        case FFH5_ENC_AV1_NV:
            if (strlen(preset) > 0)
                av_opt_set(c->priv_data, "preset", preset, 0);
            if (strlen(tune) > 0)
                av_opt_set(c->priv_data, "tune", tune, 0);
            if (crf < 52)
            {
                /* we have to use constqp for Variable bitrate mode and set bit_rate to 0 (auto),
                /* otherwise the bitrate will be capped to ~2Mbs by NVENC
                /* instead of using cq mode, constqp is better to reflect different qps
                */
                av_opt_set(c->priv_data, "rc", "constqp", 0);
                c->bit_rate = 0;
                av_opt_set_int(c->priv_data, "qp", crf, 0);
            }

            av_opt_set_int(c->priv_data, "gpu", gpu_id, 0);
            break;
        case FFH5_ENC_SVTAV1:
            if (strlen(preset) > 0)
                av_opt_set_int(c->priv_data, "preset", atoi(preset), 0);

            /* By default, for SVT-AV1, the maximum value for film_grain parameter,
             * If we want to enable film_grain parameter value > 50,
             * we have to change the SVT-AV1 source code and recompile it.
             */
            // if (film_grain > 50)
            //     film_grain = 50;

            snprintf(film_grain_buffer, 10, "%d", film_grain);

            if (strlen(tune) > 0)
            {
                strcat(tune, ":film-grain=");
                strcat(tune, film_grain_buffer);
            }
            else
            {
                stpcpy(tune, "film-grain=");
                strcat(tune, film_grain_buffer);
            }
            if (film_grain > 0)
                strcat(tune, ":film-grain-denoise=1");
            strcat(tune, ":enable-tf=0");

            // removed in svt-av1 3.0+
            // if (color_mode == 1)
            //     strcat(tune, ":enable-hdr=1");

            av_opt_set(c->priv_data, "svtav1-params", tune, 0);
            if (crf < 64)
                av_opt_set_int(c->priv_data, "crf", crf, 0);
            break;
        case FFH5_ENC_RAV1E:
            if (strlen(preset) > 0)
                av_opt_set_int(c->priv_data, "speed", atoi(preset), 0);
            if (strlen(tune) > 0)
                av_opt_set(c->priv_data, "rav1e-params", tune, 0);
            if (crf < 255)
                av_opt_set_int(c->priv_data, "qp", crf, 0);
            break;
        case FFH5_ENC_AV1_QSV:
            if (strlen(preset) > 0)
                av_opt_set(c->priv_data, "preset", preset, 0);
            if (strlen(tune) > 0)
                av_opt_set(c->priv_data, "scenario", tune, 0);
            if (crf < 52)
                av_opt_set_int(c->priv_data, "global_quality", crf, 0);
            break;

        default:
            break;
        }

        /* open it */
        ret = avcodec_open2(c, codec, NULL);
        if (ret < 0)
        {
            raise_ffmpeg_error("Could not open codec\n");
            // printf(av_err2str(ret));
            goto CompressFailure;
        }

        dst_frame = av_frame_alloc();
        if (!dst_frame)
        {
            raise_ffmpeg_error("Could not allocate video dst_frame due to out of memory problem\n");
            goto CompressFailure;
        }

        dst_frame->format = c->pix_fmt;
        dst_frame->width = c->width;
        dst_frame->height = c->height;

        if ((av_frame_get_buffer(dst_frame, 0) < 0))
        {
            raise_ffmpeg_error("Could not allocate the video dst_frame data\n");
            goto CompressFailure;
        }

        src_frame = av_frame_alloc();
        if (!src_frame)
        {
            raise_ffmpeg_error("Could not allocate video src_frame due to out of memory problem\n");
            goto CompressFailure;
        }

        src_frame->format = (color_mode == 0) ? AV_PIX_FMT_GRAY8 : AV_PIX_FMT_GRAY10;
        src_frame->width = c->width;
        src_frame->height = c->height;

        if (av_frame_get_buffer(src_frame, 0) < 0)
        {
            raise_ffmpeg_error("Could not allocate the video src_frame data\n");
            goto CompressFailure;
        }

        p_data = (uint8_t *)*buf;

        frame_size = (color_mode == 0) ? width * height : width * height * 2;
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
            raise_ffmpeg_error("Could not initialize conversion context\n");
            goto CompressFailure;
        }

        /* real code for encoding buffer data */
        for (i = 0; i < depth; i++)
        {
            ret = av_frame_make_writable(src_frame);
            if (ret < 0)
            {
                raise_ffmpeg_error("Frame not writable\n");
                goto CompressFailure;
            }
            ret = av_frame_make_writable(dst_frame);
            if (ret < 0)
            {
                raise_ffmpeg_error("Frame not writable\n");
                goto CompressFailure;
            }
            /* put buffer data to frame and do colorspace conversion */
            av_image_fill_arrays(src_frame->data, src_frame->linesize, p_data, src_frame->format, width, height, 1);
            p_data += frame_size;

            ret = sws_scale_frame(sws_context, dst_frame, src_frame);
            if (ret < 0)
            {
                raise_ffmpeg_error("Could not do colorspace conversion\n");
                goto CompressFailure;
            }

            dst_frame->pts = i;
            dst_frame->quality = c->global_quality;

            /* encode the frame */
            encode(c, dst_frame, pkt, &out_size, &out_data, &expected_size);
        }

        /* flush the encoder */
        encode(c, NULL, pkt, &out_size, &out_data, &expected_size);

        out_buf = malloc(out_size);

        if (!out_buf)
        {
            raise_ffmpeg_error("Failed to allocate memory for image array\n");
            goto CompressFailure;
        }

        memcpy(out_buf, out_data, out_size);
        free(*buf);

        *buf = out_buf;

        goto CompressFinish;

    CompressFinish:
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
        if (codec_name)
            free(codec_name);
        if (preset)
            free(preset);
        if (tune)
            free(tune);
        if (out_data)
            free(out_data);
        return out_size;

    CompressFailure:
        raise_ffmpeg_error("Error compressing array\n");
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
        if (codec_name)
            free(codec_name);
        if (preset)
            free(preset);
        if (tune)
            free(tune);
        if (out_data)
            free(out_data);
        if (out_buf)
            free(out_buf);
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
         * cd_values[5] = bit_mode
         */
        const AVCodec *codec;
        AVCodecParserContext *parser;
        AVCodecContext *c = NULL;
        AVFrame *src_frame = NULL, *dst_frame = NULL;
        AVPacket *pkt;
        struct SwsContext *sws_context = NULL;
        // int thread_count = 1; // single thread

        const char *codec_name;
        enum DecoderCodecEnum c_id;

        int width, height, depth;
        int color_mode;

        size_t p_data_size = 0, frame_size = 0;
        uint8_t *out_data = NULL, *p_data = NULL;
        size_t out_size = 0;

        int ret, eof = 0;  // Initialize eof to prevent undefined behavior

        c_id = cd_values[1];
        width = cd_values[2];
        height = cd_values[3];
        depth = cd_values[4];
        color_mode = cd_values[5];

        av_log_set_level(AV_LOG_ERROR);

        pkt = av_packet_alloc();
        if (!pkt)
        {
            raise_ffmpeg_error("Could not allocate packet\n");
            goto DecompressFailure;
        }

        codec_name = calloc(1, 50);
        find_decoder_name(c_id, codec_name);

        codec = avcodec_find_decoder_by_name(codec_name);
        if (!codec)
        {
            raise_ffmpeg_error("Codec not found\n");
            goto DecompressFailure;
        }
        parser = av_parser_init(codec->id);
        if (!parser)
        {
            raise_ffmpeg_error("parser not found\n");
            goto DecompressFailure;
        }
        c = avcodec_alloc_context3(codec);
        if (!c)
        {
            raise_ffmpeg_error("Could not allocate video codec context\n");
            goto DecompressFailure;
        }

        /* Add single threading just for testing purpose */
        // c->thread_count = 16;

        /* For some codecs, such as msmpeg4 and mpeg4, width and height
           MUST be initialized there because this information is not
           available in the bitstream. */
        c->width = width;
        c->height = height;

        /* open it */
        if (avcodec_open2(c, codec, NULL) < 0)
        {
            raise_ffmpeg_error("Could not open codec\n");
            goto DecompressFailure;
        }
        src_frame = av_frame_alloc();
        if (!src_frame)
        {
            raise_ffmpeg_error("Could not allocate video frame due to out of memory problem\n");
            goto DecompressFailure;
        }
        switch (c_id)
        {
        // list those who support 10bit encoding
        case FFH5_DEC_H264:
        case FFH5_DEC_AOMAV1:
        case FFH5_DEC_DAV1D:
            src_frame->format = (color_mode == 0) ? AV_PIX_FMT_YUV420P : AV_PIX_FMT_YUV420P10;
            break;
        case FFH5_DEC_HEVC:
            switch (color_mode)
            {
            case 0: // 8bit
                src_frame->format = AV_PIX_FMT_YUV420P;
                break;
            case 1: // 10bit
                src_frame->format = AV_PIX_FMT_YUV420P10;
                break;
            case 2: // 12bit
                src_frame->format = AV_PIX_FMT_YUV420P12;
                break;
            default:
                src_frame->format = AV_PIX_FMT_YUV420P;
            }
            break;
        case FFH5_DEC_H264_CUVID:
        case FFH5_DEC_HEVC_CUVID:
        case FFH5_DEC_AV1_CUVID:
        case FFH5_DEC_AV1_QSV:
            src_frame->format = (color_mode == 0) ? AV_PIX_FMT_NV12 : AV_PIX_FMT_P010;
            break;
        default:
            // common supported pixel format 8bit
            src_frame->format = AV_PIX_FMT_YUV420P;
        }
        src_frame->width = c->width;
        src_frame->height = c->height;

        dst_frame = av_frame_alloc();
        if (!dst_frame)
        {
            raise_ffmpeg_error("Could not allocate video dst_frame due to out of memory problem\n");
            goto DecompressFailure;
        }

        dst_frame->format = (color_mode == 0) ? AV_PIX_FMT_GRAY8 : AV_PIX_FMT_GRAY10;
        dst_frame->width = c->width;
        dst_frame->height = c->height;

        p_data = (uint8_t *)*buf;
        p_data_size = buf_size;

        frame_size = (color_mode == 0) ? width * height : width * height * 2;
        out_data = calloc(1, frame_size * depth + AV_INPUT_BUFFER_PADDING_SIZE);

        if (out_data == NULL)
            raise_ffmpeg_error("Out of memory occurred during decoding\n");

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
                raise_ffmpeg_error("Packet not readable\n");
                goto DecompressFailure;
            }

            p_data += ret;
            p_data_size -= ret;

            if (pkt->size)
                decode(c, src_frame, pkt, sws_context, dst_frame, &out_size, out_data, frame_size);
            else if (eof)
                break;
            
            // Prevent infinite loop: if parser made no progress and no packet was generated
            if (ret == 0 && pkt->size == 0 && eof)
                break;
        }

        /* flush the decoder */
        pkt->data = NULL;
        pkt->size = 0;
        decode(c, src_frame, pkt, sws_context, dst_frame, &out_size, out_data, frame_size);

        out_buf = malloc(out_size);

        if (!out_buf)
        {
            raise_ffmpeg_error("Failed to allocate memory for image array\n");
            goto DecompressFailure;
        }
        memcpy(out_buf, out_data, out_size);

        free(*buf);
        *buf = out_buf;

        goto DecompressFinish; // success

    DecompressFinish:
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
        if (codec_name)
            free(codec_name);
        if (out_data)
            free(out_data);
        return out_size;

    DecompressFailure:
        raise_ffmpeg_error("Error decompressing packets\n");
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
        if (codec_name)
            free(codec_name);
        if (out_data)
            free(out_data);
        if (out_buf)
            free(out_buf);
        return 0;
    }
}