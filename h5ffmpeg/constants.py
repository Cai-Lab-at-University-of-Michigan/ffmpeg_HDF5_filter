"""
FFMPEG HDF5 filter constants and mappings.
"""

# Get version and derive header version
def get_current_header_version():
    """Get the current header version based on package version"""
    try:
        from ._version import __version__
        major_version = int(__version__.split(".")[0])
        return major_version
    except (ImportError, ValueError, IndexError):
        return 2 

# Filter constants
FFMPEG_ID = 32030
HEADER_VERSION = get_current_header_version()
METADATA_FIELDS = 11  # Keep all fields
METADATA_SIZE = METADATA_FIELDS * 4 + 8  # 11 * uint32 + 1 * uint64
HEADER_SIZE = 8  # metadata_size(uint32) + version(uint32)

# Encoder codec IDs
class EncoderCodec:
    """Encoder codec identifiers for FFMPEG HDF5 filter"""

    MPEG4 = 0
    XVID = 1
    X264 = 2
    H264_NVENC = 3
    X265 = 4
    HEVC_NVENC = 5
    SVTAV1 = 6
    RAV1E = 7
    AV1_NVENC = 8
    AV1_QSV = 9


# Decoder codec IDs
class DecoderCodec:
    """Decoder codec identifiers for FFMPEG HDF5 filter"""

    MPEG4 = 0
    H264 = 1
    H264_CUVID = 2
    HEVC = 3
    HEVC_CUVID = 4
    AOMAV1 = 5
    DAV1D = 6
    AV1_CUVID = 7
    AV1_QSV = 8


# Preset IDs
class Preset:
    """Preset identifiers for FFMPEG HDF5 filter"""

    NONE = 0

    # libx264 presets
    X264_ULTRAFAST = 10
    X264_SUPERFAST = 11
    X264_VERYFAST = 12
    X264_FASTER = 13
    X264_FAST = 14
    X264_MEDIUM = 15
    X264_SLOW = 16
    X264_SLOWER = 17
    X264_VERYSLOW = 18

    # h264_nvenc presets
    H264NV_FASTEST = 100
    H264NV_FASTER = 101
    H264NV_FAST = 102
    H264NV_MEDIUM = 103
    H264NV_SLOW = 104
    H264NV_SLOWER = 105
    H264NV_SLOWEST = 106

    # x265 presets
    X265_ULTRAFAST = 200
    X265_SUPERFAST = 201
    X265_VERYFAST = 202
    X265_FASTER = 203
    X265_FAST = 204
    X265_MEDIUM = 205
    X265_SLOW = 206
    X265_SLOWER = 207
    X265_VERYSLOW = 208

    # hevc_nvenc presets
    HEVCNV_FASTEST = 300
    HEVCNV_FASTER = 301
    HEVCNV_FAST = 302
    HEVCNV_MEDIUM = 303
    HEVCNV_SLOW = 304
    HEVCNV_SLOWER = 305
    HEVCNV_SLOWEST = 306

    # svtav1 presets
    SVTAV1_ULTRAFAST = 400
    SVTAV1_SUPERFAST = 401
    SVTAV1_VERYFAST = 402
    SVTAV1_MUCHFASTER = 403
    SVTAV1_FASTER = 404
    SVTAV1_FAST = 405
    SVTAV1_LESSFAST = 406
    SVTAV1_MEDIUM = 407
    SVTAV1_LESSSLOW = 408
    SVTAV1_SLOW = 409
    SVTAV1_SLOWER = 410
    SVTAV1_MUCHSLOWER = 411
    SVTAV1_VERYSLOW = 412
    SVTAV1_SUPERSLOW = 413

    # rav1e presets
    RAV1E_MUCHFASTER = 500
    RAV1E_FASTER = 501
    RAV1E_FAST = 502
    RAV1E_LESSFAST = 503
    RAV1E_MEDIUM = 504
    RAV1E_LESSSLOW = 505
    RAV1E_SLOW = 506
    RAV1E_SLOWER = 507
    RAV1E_MUCHSLOWER = 508
    RAV1E_VERYSLOW = 509
    RAV1E_SUPERSLOW = 510

    # av1_nvenc presets
    AV1NV_FASTEST = 600
    AV1NV_FASTER = 601
    AV1NV_FAST = 602
    AV1NV_MEDIUM = 603
    AV1NV_SLOW = 604
    AV1NV_SLOWER = 605
    AV1NV_SLOWEST = 606

    # av1_qsv presets
    AV1QSV_FASTEST = 700
    AV1QSV_FASTER = 701
    AV1QSV_FAST = 702
    AV1QSV_MEDIUM = 703
    AV1QSV_SLOW = 704
    AV1QSV_SLOWER = 705
    AV1QSV_SLOWEST = 706


# Tune IDs
class Tune:
    """Tune identifiers for FFMPEG HDF5 filter"""

    NONE = 0

    # libx264 tunes
    X264_PSNR = 10
    X264_SSIM = 11
    X264_GRAIN = 12
    X264_FASTDECODE = 13
    X264_ZEROLATENCY = 14
    X264_ANIMATION = 15
    X264_FILM = 16
    X264_STILLIMAGE = 17

    # h264_nvenc tunes
    H264NV_HQ = 100
    H264NV_LL = 101
    H264NV_ULL = 102
    H264NV_LOSSLESS = 103

    # x265 tunes
    X265_PSNR = 200
    X265_SSIM = 201
    X265_GRAIN = 202
    X265_FASTDECODE = 203
    X265_ZEROLATENCY = 204
    X265_ANIMATION = 205

    # hevc_nvenc tunes
    HEVCNV_HQ = 300
    HEVCNV_LL = 301
    HEVCNV_ULL = 302
    HEVCNV_LOSSLESS = 303

    # svtav1 tunes
    SVTAV1_VQ = 400
    SVTAV1_PSNR = 401
    SVTAV1_FASTDECODE = 402

    # rav1e tunes
    RAV1E_PSNR = 500
    RAV1E_PSYCHOVISUAL = 501

    # av1_nvenc tunes
    AV1NV_HQ = 600
    AV1NV_LL = 601
    AV1NV_ULL = 602
    AV1NV_LOSSLESS = 603

    # av1_qsv tunes
    AV1QSV_UNKNOWN = 700
    AV1QSV_DISPLAYREMOTING = 701
    AV1QSV_VIDEOCONFERENCE = 702
    AV1QSV_ARCHIVE = 703
    AV1QSV_LIVESTREAMING = 704
    AV1QSV_CAMERACAPTURE = 705
    AV1QSV_VIDEOSURVEILLANCE = 706
    AV1QSV_GAMESTREAMING = 707
    AV1QSV_REMOTEGAMING = 708


# Bit modes
class BitMode:
    """Bit depth modes for FFMPEG HDF5 filter"""

    BIT_8 = 0
    BIT_10 = 1
    BIT_12 = 2


# Mapping of codec names to encoder IDs
CODEC_TO_ENCODER = {
    "mpeg4": EncoderCodec.MPEG4,
    "libxvid": EncoderCodec.XVID,
    "libx264": EncoderCodec.X264,
    "h264_nvenc": EncoderCodec.H264_NVENC,
    "libx265": EncoderCodec.X265,
    "hevc_nvenc": EncoderCodec.HEVC_NVENC,
    "libsvtav1": EncoderCodec.SVTAV1,
    "librav1e": EncoderCodec.RAV1E,
    "av1_nvenc": EncoderCodec.AV1_NVENC,
    "av1_qsv": EncoderCodec.AV1_QSV,
}

# Mapping of codec names to decoder IDs
CODEC_TO_DECODER = {
    "mpeg4": DecoderCodec.MPEG4,
    "h264": DecoderCodec.H264,
    "h264_cuvid": DecoderCodec.H264_CUVID,
    "hevc": DecoderCodec.HEVC,
    "hevc_cuvid": DecoderCodec.HEVC_CUVID,
    "libaom-av1": DecoderCodec.AOMAV1,
    "libdav1d": DecoderCodec.DAV1D,
    "av1_cuvid": DecoderCodec.AV1_CUVID,
    "av1_qsv": DecoderCodec.AV1_QSV,
}

# Mapping of preset names to preset IDs for each codec
PRESET_MAPPING = {
    "libx264": {
        "ultrafast": Preset.X264_ULTRAFAST,
        "superfast": Preset.X264_SUPERFAST,
        "veryfast": Preset.X264_VERYFAST,
        "faster": Preset.X264_FASTER,
        "fast": Preset.X264_FAST,
        "medium": Preset.X264_MEDIUM,
        "slow": Preset.X264_SLOW,
        "slower": Preset.X264_SLOWER,
        "veryslow": Preset.X264_VERYSLOW,
    },
    "h264_nvenc": {
        "p1": Preset.H264NV_FASTEST,
        "p2": Preset.H264NV_FASTER,
        "p3": Preset.H264NV_FAST,
        "p4": Preset.H264NV_MEDIUM,
        "p5": Preset.H264NV_SLOW,
        "p6": Preset.H264NV_SLOWER,
        "p7": Preset.H264NV_SLOWEST,
    },
    "libx265": {
        "ultrafast": Preset.X265_ULTRAFAST,
        "superfast": Preset.X265_SUPERFAST,
        "veryfast": Preset.X265_VERYFAST,
        "faster": Preset.X265_FASTER,
        "fast": Preset.X265_FAST,
        "medium": Preset.X265_MEDIUM,
        "slow": Preset.X265_SLOW,
        "slower": Preset.X265_SLOWER,
        "veryslow": Preset.X265_VERYSLOW,
    },
    "hevc_nvenc": {
        "p1": Preset.HEVCNV_FASTEST,
        "p2": Preset.HEVCNV_FASTER,
        "p3": Preset.HEVCNV_FAST,
        "p4": Preset.HEVCNV_MEDIUM,
        "p5": Preset.HEVCNV_SLOW,
        "p6": Preset.HEVCNV_SLOWER,
        "p7": Preset.HEVCNV_SLOWEST,
    },
    "libsvtav1": {
        "0": Preset.SVTAV1_ULTRAFAST,
        "1": Preset.SVTAV1_SUPERFAST,
        "2": Preset.SVTAV1_VERYFAST,
        "3": Preset.SVTAV1_MUCHFASTER,
        "4": Preset.SVTAV1_FASTER,
        "5": Preset.SVTAV1_FAST,
        "6": Preset.SVTAV1_LESSFAST,
        "7": Preset.SVTAV1_MEDIUM,
        "8": Preset.SVTAV1_LESSSLOW,
        "9": Preset.SVTAV1_SLOW,
        "10": Preset.SVTAV1_SLOWER,
        "11": Preset.SVTAV1_MUCHSLOWER,
        "12": Preset.SVTAV1_VERYSLOW,
        "13": Preset.SVTAV1_SUPERSLOW,
    },
    "librav1e": {
        "0": Preset.RAV1E_MUCHFASTER,
        "1": Preset.RAV1E_FASTER,
        "2": Preset.RAV1E_FAST,
        "3": Preset.RAV1E_LESSFAST,
        "4": Preset.RAV1E_MEDIUM,
        "5": Preset.RAV1E_LESSSLOW,
        "6": Preset.RAV1E_SLOW,
        "7": Preset.RAV1E_SLOWER,
        "8": Preset.RAV1E_MUCHSLOWER,
        "9": Preset.RAV1E_VERYSLOW,
        "10": Preset.RAV1E_SUPERSLOW,
    },
    "av1_nvenc": {
        "p1": Preset.AV1NV_FASTEST,
        "p2": Preset.AV1NV_FASTER,
        "p3": Preset.AV1NV_FAST,
        "p4": Preset.AV1NV_MEDIUM,
        "p5": Preset.AV1NV_SLOW,
        "p6": Preset.AV1NV_SLOWER,
        "p7": Preset.AV1NV_SLOWEST,
    },
    "av1_qsv": {
        "veryfast": Preset.AV1QSV_FASTEST,
        "faster": Preset.AV1QSV_FASTER,
        "fast": Preset.AV1QSV_FAST,
        "medium": Preset.AV1QSV_MEDIUM,
        "slow": Preset.AV1QSV_SLOW,
        "slower": Preset.AV1QSV_SLOWER,
        "veryslow": Preset.AV1QSV_SLOWEST,
    },
}

# Mapping of tune names to tune IDs for each codec
TUNE_MAPPING = {
    "libx264": {
        "psnr": Tune.X264_PSNR,
        "ssim": Tune.X264_SSIM,
        "grain": Tune.X264_GRAIN,
        "fastdecode": Tune.X264_FASTDECODE,
        "zerolatency": Tune.X264_ZEROLATENCY,
        "animation": Tune.X264_ANIMATION,
        "film": Tune.X264_FILM,
        "stillimage": Tune.X264_STILLIMAGE,
    },
    "h264_nvenc": {
        "hq": Tune.H264NV_HQ,
        "ll": Tune.H264NV_LL,
        "ull": Tune.H264NV_ULL,
        "lossless": Tune.H264NV_LOSSLESS,
    },
    "libx265": {
        "psnr": Tune.X265_PSNR,
        "ssim": Tune.X265_SSIM,
        "grain": Tune.X265_GRAIN,
        "fastdecode": Tune.X265_FASTDECODE,
        "zerolatency": Tune.X265_ZEROLATENCY,
        "animation": Tune.X265_ANIMATION,
    },
    "hevc_nvenc": {
        "hq": Tune.HEVCNV_HQ,
        "ll": Tune.HEVCNV_LL,
        "ull": Tune.HEVCNV_ULL,
        "lossless": Tune.HEVCNV_LOSSLESS,
    },
    "libsvtav1": {
        "vq": Tune.SVTAV1_VQ,
        "psnr": Tune.SVTAV1_PSNR,
        "fastdecode": Tune.SVTAV1_FASTDECODE,
    },
    "librav1e": {"psnr": Tune.RAV1E_PSNR, "psychovisual": Tune.RAV1E_PSYCHOVISUAL},
    "av1_nvenc": {
        "hq": Tune.AV1NV_HQ,
        "ll": Tune.AV1NV_LL,
        "ull": Tune.AV1NV_ULL,
        "lossless": Tune.AV1NV_LOSSLESS,
    },
    "av1_qsv": {
        "unknown": Tune.AV1QSV_UNKNOWN,
        "displayremoting": Tune.AV1QSV_DISPLAYREMOTING,
        "videoconference": Tune.AV1QSV_VIDEOCONFERENCE,
        "archive": Tune.AV1QSV_ARCHIVE,
        "livestreaming": Tune.AV1QSV_LIVESTREAMING,
        "cameracapture": Tune.AV1QSV_CAMERACAPTURE,
        "videosurveillance": Tune.AV1QSV_VIDEOSURVEILLANCE,
        "gamestreaming": Tune.AV1QSV_GAMESTREAMING,
        "remotegaming": Tune.AV1QSV_REMOTEGAMING,
    },
}

# Default decoder mapping for encoders
DEFAULT_DECODER = {
    EncoderCodec.MPEG4: DecoderCodec.MPEG4,
    EncoderCodec.XVID: DecoderCodec.MPEG4,
    EncoderCodec.X264: DecoderCodec.H264,
    EncoderCodec.H264_NVENC: DecoderCodec.H264,
    EncoderCodec.X265: DecoderCodec.HEVC,
    EncoderCodec.HEVC_NVENC: DecoderCodec.HEVC,
    # don't use AOMAV1 for decoding av1
    EncoderCodec.SVTAV1: DecoderCodec.DAV1D,
    EncoderCodec.RAV1E: DecoderCodec.DAV1D,
    EncoderCodec.AV1_NVENC: DecoderCodec.DAV1D,
    EncoderCodec.AV1_QSV: DecoderCodec.DAV1D,
}

# Default decoder mapping for GPU-based encoders
DEFAULT_GPU_DECODER = {
    EncoderCodec.H264_NVENC: DecoderCodec.H264_CUVID,
    EncoderCodec.HEVC_NVENC: DecoderCodec.HEVC_CUVID,
    EncoderCodec.AV1_NVENC: DecoderCodec.AV1_CUVID,
    EncoderCodec.AV1_QSV: DecoderCodec.AV1_QSV,
}