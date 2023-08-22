package com.cailab.hdf5compression;

public class Constants {
    static final int FILTER_ID = 32027;

    // Image stack layout
    static final int IMAGE_ZYX = 0;
    static final int IMAGE_TYX = 1;
    static final int IMAGE_CYX = 2;
    static final int IMAGE_CZYX = 3;
    static final int IMAGE_CTYX = 4;
    static final int IMAGE_TZYX = 5;    
    static final int IMAGE_CTZYX = 6;


    // ENCODERS
    static final int FFH5_ENC_MPEG4 = 0;
    static final int FFH5_ENC_XVID = 1;
    static final int FFH5_ENC_X264 = 2;
    static final int FFH5_ENC_H264_NV = 3;
    static final int FFH5_ENC_X265 = 4;
    static final int FFH5_ENC_HEVC_NV = 5;
    static final int FFH5_ENC_SVTAV1 = 6;
    static final int FFH5_ENC_RAV1E = 7;
    static final int FFH5_ENC_AV1_NV = 8;
    static final int FFH5_ENC_AV1_QSV = 9;
    
    // DECODERS
    static final int FFH5_DEC_MPEG4 = 0;
    static final int FFH5_DEC_H264 = 1;
    static final int FFH5_DEC_H264_CUVID = 2;
    static final int FFH5_DEC_HEVC = 3;
    static final int FFH5_DEC_HEVC_CUVID = 4;
    static final int FFH5_DEC_AOMAV1 = 5;
    static final int FFH5_DEC_DAV1D = 6;
    static final int FFH5_DEC_AV1_CUVID = 7;
    static final int FFH5_DEC_AV1_QSV = 8;

    // PRESETS
    /*
     * no preset
     * /* means default preset is using depends on codecs
     */
    static final int FFH5_PRESET_NONE = 0;
    /* libx264 */
    static final int FFH5_PRESET_X264_ULTRAFAST = 10;
    static final int FFH5_PRESET_X264_SUPERFAST = 11;
    static final int FFH5_PRESET_X264_VERYFAST = 12;
    static final int FFH5_PRESET_X264_FASTER = 13;
    static final int FFH5_PRESET_X264_FAST = 14;
    static final int FFH5_PRESET_X264_MEDIUM = 15;
    static final int FFH5_PRESET_X264_SLOW = 16;
    static final int FFH5_PRESET_X264_SLOWER = 17;
    static final int FFH5_PRESET_X264_VERYSLOW = 18;
    /* h264_nvenc */
    static final int FFH5_PRESET_H264NV_FASTEST = 100;
    static final int FFH5_PRESET_H264NV_FASTER = 101;
    static final int FFH5_PRESET_H264NV_FAST = 102;
    static final int FFH5_PRESET_H264NV_MEDIUM = 103;
    static final int FFH5_PRESET_H264NV_SLOW = 104;
    static final int FFH5_PRESET_H264NV_SLOWER = 105;
    static final int FFH5_PRESET_H264NV_SLOWEST = 106;
    /* x265 */
    static final int FFH5_PRESET_X265_ULTRAFAST = 200;
    static final int FFH5_PRESET_X265_SUPERFAST = 201;
    static final int FFH5_PRESET_X265_VERYFAST = 202;
    static final int FFH5_PRESET_X265_FASTER = 203;
    static final int FFH5_PRESET_X265_FAST = 204;
    static final int FFH5_PRESET_X265_MEDIUM = 205;
    static final int FFH5_PRESET_X265_SLOW = 206;
    static final int FFH5_PRESET_X265_SLOWER = 207;
    static final int FFH5_PRESET_X265_VERYSLOW = 208;
    /* hevc_nvenc */
    static final int FFH5_PRESET_HEVCNV_FASTEST = 300;
    static final int FFH5_PRESET_HEVCNV_FASTER = 301;
    static final int FFH5_PRESET_HEVCNV_FAST = 302;
    static final int FFH5_PRESET_HEVCNV_MEDIUM = 303;
    static final int FFH5_PRESET_HEVCNV_SLOW = 304;
    static final int FFH5_PRESET_HEVCNV_SLOWER = 305;
    static final int FFH5_PRESET_HEVCNV_SLOWEST = 306;
    /* svtav1 */
    static final int FFH5_PRESET_SVTAV1_ULTRAFAST = 400;
    static final int FFH5_PRESET_SVTAV1_SUPERFAST = 401;
    static final int FFH5_PRESET_SVTAV1_VERYFAST = 402;
    static final int FFH5_PRESET_SVTAV1_MUCHFASTER = 403;
    static final int FFH5_PRESET_SVTAV1_FASTER = 404;
    static final int FFH5_PRESET_SVTAV1_FAST = 405;
    static final int FFH5_PRESET_SVTAV1_LESSFAST = 406;
    static final int FFH5_PRESET_SVTAV1_MEDIUM = 407;
    static final int FFH5_PRESET_SVTAV1_LESSSLOW = 408;
    static final int FFH5_PRESET_SVTAV1_SLOW = 409;
    static final int FFH5_PRESET_SVTAV1_SLOWER = 410;
    static final int FFH5_PRESET_SVTAV1_MUCHSLOWER = 411;
    static final int FFH5_PRESET_SVTAV1_VERYSLOW = 412;
    static final int FFH5_PRESET_SVTAV1_SUPERSLOW = 413;
    /* rav1e */
    static final int FFH5_PRESET_RAV1E_MUCHFASTER = 500;
    static final int FFH5_PRESET_RAV1E_FASTER = 501;
    static final int FFH5_PRESET_RAV1E_FAST = 502;
    static final int FFH5_PRESET_RAV1E_LESSFAST = 503;
    static final int FFH5_PRESET_RAV1E_MEDIUM = 504;
    static final int FFH5_PRESET_RAV1E_LESSSLOW = 505;
    static final int FFH5_PRESET_RAV1E_SLOW = 506;
    static final int FFH5_PRESET_RAV1E_SLOWER = 507;
    static final int FFH5_PRESET_RAV1E_MUCHSLOWER = 508;
    static final int FFH5_PRESET_RAV1E_VERYSLOW = 509;
    static final int FFH5_PRESET_RAV1E_SUPERSLOW = 510;
    /* av1_nvenc */
    static final int FFH5_PRESET_AV1NV_FASTEST = 600;
    static final int FFH5_PRESET_AV1NV_FASTER = 601;
    static final int FFH5_PRESET_AV1NV_FAST = 602;
    static final int FFH5_PRESET_AV1NV_MEDIUM = 603;
    static final int FFH5_PRESET_AV1NV_SLOW = 604;
    static final int FFH5_PRESET_AV1NV_SLOWER = 605;
    static final int FFH5_PRESET_AV1NV_SLOWEST = 606;
    /* av1 intel qsv */
    static final int FFH5_PRESET_AV1QSV_FASTEST = 700;
    static final int FFH5_PRESET_AV1QSV_FASTER = 701;
    static final int FFH5_PRESET_AV1QSV_FAST = 702;
    static final int FFH5_PRESET_AV1QSV_MEDIUM = 703;
    static final int FFH5_PRESET_AV1QSV_SLOW = 704;
    static final int FFH5_PRESET_AV1QSV_SLOWER = 705;
    static final int FFH5_PRESET_AV1QSV_SLOWEST = 706;

    // TUNE
    static final int FFH5_TUNE_NONE = 0;
    /* libx264 */
    static final int FFH5_TUNE_X264_PSNR = 10;
    static final int FFH5_TUNE_X264_SSIM = 11;
    static final int FFH5_TUNE_X264_GRAIN = 12;
    static final int FFH5_TUNE_X264_FASTDECODE = 13;
    static final int FFH5_TUNE_X264_ZEROLATENCY = 14;
    static final int FFH5_TUNE_X264_ANIMATION = 15;
    static final int FFH5_TUNE_X264_FILM = 16;
    static final int FFH5_TUNE_X264_STILLIMAGE = 17;
    /* h264_nvenc */
    static final int FFH5_TUNE_H264NV_HQ = 100;
    static final int  FFH5_TUNE_H264NV_LL = 101;
    static final int FFH5_TUNE_H264NV_ULL = 102;
    static final int FFH5_TUNE_H264NV_LOSSLESS = 103;
    /* x265 */
    static final int  FFH5_TUNE_X265_PSNR = 200;
    static final int FFH5_TUNE_X265_SSIM = 201;
    static final int FFH5_TUNE_X265_GRAIN = 202;
    static final int FFH5_TUNE_X265_FASTDECODE = 203;
    static final int FFH5_TUNE_X265_ZEROLATENCY = 204;
    static final int FFH5_TUNE_X265_ANIMATION = 205;
    /* hevc_nvenc */
    static final int FFH5_TUNE_HEVCNV_HQ = 300;
    static final int FFH5_TUNE_HEVCNV_LL = 301;
    static final int FFH5_TUNE_HEVCNV_ULL = 302;
    static final int FFH5_TUNE_HEVCNV_LOSSLESS = 303;
    /* svtav1 */
    static final int FFH5_TUNE_SVTAV1_VQ = 400;
    static final int FFH5_TUNE_SVTAV1_PSNR = 401;
    static final int FFH5_TUNE_SVTAV1_FASTDECODE = 402;
    /* rav1e */
    static final int FFH5_TUNE_RAV1E_PSNR = 500;
    static final int FFH5_TUNE_RAV1E_PSYCHOVISUAL = 501;
    /* av1_nvenc */
    static final int FFH5_TUNE_AV1NV_HQ = 600;
    static final int FFH5_TUNE_AV1NV_LL = 601;
    static final int FFH5_TUNE_AV1NV_ULL = 602;
    static final int FFH5_TUNE_AV1NV_LOSSLESS = 603;
    /* av1_qsv */
    static final int FFH5_TUNE_AV1QSV_UNKNOWN = 700;
    static final int FFH5_TUNE_AV1QSV_DISPLAYREMOTING = 701;
    static final int FFH5_TUNE_AV1QSV_VIDEOCONFERENCE = 702;
    static final int FFH5_TUNE_AV1QSV_ARCHIVE = 703;
    static final int FFH5_TUNE_AV1QSV_LIVESTREAMING = 704;
    static final int FFH5_TUNE_AV1QSV_CAMERACAPTURE = 705;
    static final int FFH5_TUNE_AV1QSV_VIDEOSURVEILLANCE = 706;
    static final int FFH5_TUNE_AV1QSV_GAMESTREAMING = 707;
    static final int FFH5_TUNE_AV1QSV_REMOTEGAMING = 708;
}
