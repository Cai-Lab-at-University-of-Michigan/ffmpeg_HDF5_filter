# evaluation relation utils
import glob
import os
import shutil
import subprocess

import cv2
import numpy as np
from PIL import Image
from tifffile import imread
import h5py
from skimage.metrics import normalized_root_mse, peak_signal_noise_ratio, structural_similarity
from skimage import img_as_float


# compression related
# video file characteristics
# file size
def get_size_in_bit(filestr):
    file_size = os.path.getsize(filestr)

    return file_size * 8


def get_size_in_byte(filestr):
    file_size = os.path.getsize(filestr)

    return file_size


def get_size_in_KB(filestr):
    file_size = get_size_in_byte(filestr)

    return file_size / 1024


def get_size_in_MB(filestr):
    file_size = get_size_in_KB(filestr)

    return file_size / 1024


def get_size_in_GB(filestr):
    file_size = get_size_in_MB(filestr)

    return file_size / 1024


def byte_to_bit(byte_):
    return byte_ * 8


def bit_to_byte(bit_):
    return bit_ / 8


# compressed ratio
def get_compression_ratio(src_file, comp_file):
    return get_size_in_byte(src_file) / get_size_in_byte(comp_file)


# fps
# def get_frame_rate_ffmpeg(filename):
#     if not os.path.exists(filename):
#         sys.stderr.write("ERROR: filename %r was not found!" % (filename,))
#         return -1
#     out = subprocess.check_output(
#         ["ffprobe", filename, "-v", "0", "-select_streams", "v", "-print_format", "flat", "-show_entries",
#          "stream=r_frame_rate"])
#     rate = out.split('=')[1].strip()[1:-1].split('/')
#     if len(rate) == 1:
#         return float(rate[0])
#     if len(rate) == 2:
#         return float(rate[0]) / float(rate[1])
#     return -1


def get_frame_rate(filestr):
    cap = cv2.VideoCapture(filestr)

    fps = cap.get(cv2.CV_CAP_PROP_FPS)

    cap.release()

    return fps


# bitrate
# def get_duration_ffmpeg(filename):
#     if not os.path.exists(filename):
#         sys.stderr.write("ERROR: filename %r was not found!" % (filename,))
#         return -1
#     out = subprocess.check_output(
#         ["ffprobe", "-i", filename, "-show_entries", "format=duration", "-v", "quiet", "-of", "csv=p=0"])
#     assert len(out) == 1
#     return float(out[0])


def get_duration(filestr):
    cap = cv2.VideoCapture(filestr)

    fps = cap.get(cv2.CAP_PROP_FPS)
    length = cap.get(cv2.CAP_PROP_FRAME_COUNT)
    print(f'filestr: {filestr}, fps: {fps}, length: {length}')

    cap.release()

    return length / fps


def get_bitrate(filestr):
    file_size = get_size_in_bit(filestr)
    duration = get_duration(filestr)

    return file_size / 1024 / duration


# images
def get_all_frames(filestr, dir_str, flag):
    cmd = f'ffmpeg -i {filestr} {dir_str}/{flag}-%6d.png'
    # cmd = 'export LD_LIBRARY_PATH="/home/binduan/ffmpeg_build/lib/:$LD_LIBRARY_PATH" && ' + cmd

    process = subprocess.Popen(cmd, shell=True)
    process.wait()

    imgs = sorted(glob.glob(f'{dir_str}/{flag}-*.png'))
    return imgs


def tifread(filestr):
    img = imread(filestr)  # ZCYX
    if img.ndim == 4:
        img = np.transpose(img, (0, 2, 3, 1))  # ZYXC

    return img


def h5read(filestr):
    with h5py.File(filestr, 'r') as f:
        data = np.array(f['data'])

    return data


class BenchmarkMeter(object):
    """docstring for BenchmarkMeter"""

    def __init__(self):
        super(BenchmarkMeter, self).__init__()

    def __call__(self, record_template: dict, src_file: str, cs_file: str, rec_file: str) -> dict:
        record_template['cs_ratio'] = f'{get_compression_ratio(src_file, cs_file):.4f}'

        src_imgs = tifread(src_file)  # ZYXC
        cs_imgs = tifread(rec_file)  # ZYXC

        assert len(src_imgs) == len(cs_imgs), print(f'src_file: {len(src_imgs)}, cs_file: {len(cs_imgs)}')

        rmse = []
        psnr = []
        ssim = []

        for (src_im, cs_im) in zip(src_imgs, cs_imgs):
            src_im = np.array(img_as_float(src_im))
            cs_im = np.array(img_as_float(cs_im))

            rmse.append(normalized_root_mse(src_im, cs_im))
            psnr.append(peak_signal_noise_ratio(src_im, cs_im))
            ssim.append(structural_similarity(src_im, cs_im, channel_axis=-1))

        rmse = np.array(rmse)
        psnr = np.array(psnr)
        ssim = np.array(ssim)

        rmse[np.isnan(rmse)] = 0
        rmse[np.isinf(rmse)] = 0
        psnr[np.isinf(psnr)] = 0

        record_template['rmse'] = f'{np.mean(rmse):.4f}'
        record_template['psnr'] = f'{np.mean(psnr):.4f}'
        record_template['ssim'] = f'{np.mean(ssim):.4f}'

        return record_template
