""" This example runs a simple compression test on raw 3D tif

    Author: Bin Duan (bduan2@hawk.iit.edu)
    Created: 2022

"""

import json
import os
import time

import h5py
import hdf5plugin as h5pl
import numpy as np
from tifffile import imread, imwrite
from utils.metric_utils import BenchmarkMeter

TEMPLATE = {
    'enc_elapsed_time': '',
    'dec_elapsed_time': '',
    'cpu_peak_memory': '',
    'gpu_peak_memory': '',
    'cs_ratio': '',
    'rmse': '',
    'psnr': '',
    'ssim': '',
}


def rgb_main(raw_file, h5_file, rec_file):
    raw_array = imread(raw_file)  # ZCYX
    raw_array = np.transpose(raw_array, (0, 2, 3, 1))  # ZYXC
    print(f'RAW SHAPE: {raw_array.shape}')

    chunk_shape = raw_array.shape

    print(f'CHUNK SHAPE: {chunk_shape}')
    filter_parameters = (1, 1, raw_array.shape[2],
                         raw_array.shape[1], raw_array.shape[0], 0)

    record = TEMPLATE

    # compressed to h5 file
    start_time = time.time()
    with h5py.File(hdf5_file, 'w') as f:
        f.create_dataset('data', raw_array.shape, raw_array.dtype, data=raw_array,
                         chunks=chunk_shape, **h5pl.FFMPEG(*filter_parameters))

    record['enc_elapsed_time'] = f'{time.time() - start_time:.4f} s'

    # decompressed back and store it
    start_time = time.time()
    with h5py.File(hdf5_file, 'r') as f:
        rec_array = np.array(f['data'])

    record['dec_elapsed_time'] = f'{time.time() - start_time:.4f} s'

    print(f'REC SHAPE: {rec_array.shape}')

    assert raw_array.shape == rec_array.shape

    imwrite(rec_file, rec_array)

    # metrics
    record = benchmark_meter(record, raw_file, h5_file)

    print(json.dumps(record, indent=2))


def gray_main(raw_file, h5_file, rec_file):
    raw_array = imread(raw_file)  # ZYX
    print(f'RAW SHAPE: {raw_array.shape}')

    assert raw_array.dtype == np.uint8

    chunk_shape = raw_array.shape

    print(f'CHUNK SHAPE: {chunk_shape}')
    filter_parameters = (
        10, 9, raw_array.shape[2], raw_array.shape[1], raw_array.shape[0], 0)

    record = TEMPLATE

    # compressed to h5 file
    start_time = time.time()
    with h5py.File(hdf5_file, 'w') as f:
        f.create_dataset('data', raw_array.shape, raw_array.dtype, data=raw_array,
                         chunks=chunk_shape, **h5pl.FFMPEG(*filter_parameters))

    record['enc_elapsed_time'] = f'{time.time() - start_time:.4f} s'

    # decompressed back and store it
    start_time = time.time()
    with h5py.File(hdf5_file, 'r') as f:
        rec_array = np.array(f['data'])

    record['dec_elapsed_time'] = f'{time.time() - start_time:.4f} s'

    print(f'REC SHAPE: {rec_array.shape}')

    assert raw_array.shape == rec_array.shape

    imwrite(rec_file, rec_array)

    # metrics
    record = benchmark_meter(record, raw_file, h5_file)

    print(json.dumps(record, indent=2))


if __name__ == '__main__':
    tif_file = '/home/binduan/Downloads/182725.tif'
    hdf5_file = '/home/binduan/Downloads/182725.h5'
    rec_tif_file = '/home/binduan/Downloads/Rec_182725.tif'
    benchmark_meter = BenchmarkMeter()

    gray_main(tif_file, hdf5_file, rec_tif_file)
