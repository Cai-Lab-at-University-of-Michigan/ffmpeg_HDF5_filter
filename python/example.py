""" This example runs a simple compression test on raw 3D tif

    Author: Bin Duan (bduan2@hawk.iit.edu)
    Created: 2022

"""

import json
import time

import h5py
import hdf5plugin as h5pl
import numpy as np
from tifffile import imread, imwrite
from utils.metric_utils import BenchmarkMeter

TEMPLATE = {
    'enc_elapsed_time': '',
    'dec_elapsed_time': '',
    # 'cpu_peak_memory': '',
    # 'gpu_peak_memory': '',
    'cs_ratio': '',
    'rmse': '',
    'psnr': '',
    'ssim': '',
}


def echo(mystr, file):
    print(mystr)
    with open(file, 'a+') as f:
        f.write('\n')
        f.write(mystr)
        f.write('\n')


def save_record_appending(record, file):
    print_record(record)
    with open(file, 'a+') as f:
        json.dump(record, f)


def print_record(record, indent=2):
    print(json.dumps(record, indent=indent))


def print_file(file):
    with open(file, 'r') as f:
        for line in f.readlines():
            if "{" in line:
                print_record(json.loads(line))
            else:
                print(line)


def multi_channel_main(raw_file, h5_file, rec_file, channel_first=False):
    raw_array = imread(raw_file)  # ZCYX

    assert raw_array.ndim == 4

    ch = raw_array.shape[1]

    if channel_first:
        raw_array = np.transpose(raw_array, (1, 0, 2, 3))

    raw_array = np.reshape(
        raw_array, (-1, raw_array.shape[2], raw_array.shape[3]))
    print(f'RAW SHAPE: {raw_array.shape}, RAW_DTYPE: {raw_array.dtype}')

    chunk_shape = raw_array.shape

    print(f'CHUNK SHAPE: {chunk_shape}')
    filter_parameters = (
        8, 7, raw_array.shape[2], raw_array.shape[1], raw_array.shape[0], 0)

    record = TEMPLATE

    # compressed to h5 file
    start_time = time.time()
    with h5py.File(h5_file, 'w') as f:
        f.create_dataset('data', raw_array.shape, raw_array.dtype, data=raw_array,
                         chunks=chunk_shape, **h5pl.FFMPEG(*filter_parameters))

    record['enc_elapsed_time'] = f'{time.time() - start_time:.4f} s'

    # decompressed back and store it
    start_time = time.time()
    with h5py.File(h5_file, 'r') as f:
        rec_array = np.array(f['data'])

    record['dec_elapsed_time'] = f'{time.time() - start_time:.4f} s'

    print(f'REC SHAPE: {rec_array.shape}')

    assert raw_array.shape == rec_array.shape, print(
        "Two images shape not matched")

    if channel_first:
        rec_array = np.reshape(
            rec_array, (ch, -1, raw_array.shape[1], raw_array.shape[2]))
        rec_array = np.transpose(rec_array, (1, 0, 2, 3))
    else:
        rec_array = np.reshape(
            rec_array, (-1, ch, raw_array.shape[1], raw_array.shape[2]))

    imwrite(rec_file, rec_array, imagej=True, metadata={'axes': 'ZCYX'})

    # metrics
    try:
        record = benchmark_meter(record, raw_file, h5_file, rec_file)
    except:
        print("Error happened")

    save_record_appending(record, log_file)


def rgb_main(raw_file, h5_file, rec_file):
    raw_array = imread(raw_file)  # ZCYX
    raw_array = np.transpose(raw_array, (0, 2, 3, 1))  # ZYXC
    print(f'RAW SHAPE: {raw_array.shape}, RAW_DTYPE: {raw_array.dtype}')

    chunk_shape = raw_array.shape

    print(f'CHUNK SHAPE: {chunk_shape}')
    filter_parameters = (
        8, 7, raw_array.shape[2], raw_array.shape[1], raw_array.shape[0], 1)

    record = TEMPLATE

    # compressed to h5 file
    start_time = time.time()
    with h5py.File(h5_file, 'w') as f:
        f.create_dataset('data', raw_array.shape, raw_array.dtype, data=raw_array,
                         chunks=chunk_shape, **h5pl.FFMPEG(*filter_parameters))

    record['enc_elapsed_time'] = f'{time.time() - start_time:.4f} s'

    # decompressed back and store it
    start_time = time.time()
    with h5py.File(h5_file, 'r') as f:
        rec_array = np.array(f['data'])

    record['dec_elapsed_time'] = f'{time.time() - start_time:.4f} s'

    print(f'REC SHAPE: {rec_array.shape}')

    assert raw_array.shape == rec_array.shape, print(
        "Two images shape not matched")

    rec_array = np.transpose(rec_array, (0, 3, 1, 2))

    imwrite(rec_file, rec_array, imagej=True, metadata={'axes': 'ZCYX'})

    # metrics
    try:
        record = benchmark_meter(record, raw_file, h5_file, rec_file)
    except:
        print("Error happened")

    save_record_appending(record, log_file)


def gray_main(raw_file, h5_file, rec_file):
    raw_array = imread(raw_file)  # ZYX
    print(f'RAW SHAPE: {raw_array.shape}')

    assert raw_array.dtype == np.uint8

    chunk_shape = raw_array.shape

    print(f'CHUNK SHAPE: {chunk_shape}')
    filter_parameters = (
        8, 7, raw_array.shape[2], raw_array.shape[1], raw_array.shape[0], 0)

    record = TEMPLATE

    # compressed to h5 file
    start_time = time.time()
    with h5py.File(h5_file, 'w') as f:
        f.create_dataset('data', raw_array.shape, raw_array.dtype, data=raw_array,
                         chunks=chunk_shape, **h5pl.FFMPEG(*filter_parameters))

    record['enc_elapsed_time'] = f'{time.time() - start_time:.4f} s'

    # decompressed back and store it
    start_time = time.time()
    with h5py.File(h5_file, 'r') as f:
        rec_array = np.array(f['data'])

    record['dec_elapsed_time'] = f'{time.time() - start_time:.4f} s'

    print(f'REC SHAPE: {rec_array.shape}')

    assert raw_array.shape == rec_array.shape

    imwrite(rec_file, rec_array)

    # metrics
    try:
        record = benchmark_meter(record, raw_file, h5_file, rec_file)
    except:
        print("Error happened")

    save_record_appending(record, log_file)


if __name__ == '__main__':
    log_file = 'run.log'

    tif_file = '/home/binduan/Downloads/nTracer_sample.tif'
    hdf5_file = '/home/binduan/Downloads/nTracer_sample.h5'
    rec_tif_file = '/home/binduan/Downloads/Rec_nTracer_sample.tif'
    benchmark_meter = BenchmarkMeter()
    echo(f'Compressing {tif_file}, color_mode: 1 (rgb)', log_file)
    rgb_main(tif_file, hdf5_file, rec_tif_file)

    tif_file = '/home/binduan/Downloads/nTracer_sample_denoised.tif'
    hdf5_file = '/home/binduan/Downloads/nTracer_sample_denoised.h5'
    rec_tif_file = '/home/binduan/Downloads/Rec_nTracer_sample_denoised.tif'
    benchmark_meter = BenchmarkMeter()
    echo(f'Compressing {tif_file}, color_mode: 1 (rgb)', log_file)
    rgb_main(tif_file, hdf5_file, rec_tif_file)

    tif_file = '/home/binduan/Downloads/nTracer_sample_denoised.tif'
    hdf5_file = '/home/binduan/Downloads/nTracer_sample_denoised.h5'
    rec_tif_file = '/home/binduan/Downloads/Rec_nTracer_sample_denoised.tif'
    benchmark_meter = BenchmarkMeter()
    echo(
        f'Compressing {tif_file}, color_mode: 1 (rgb), channel_first: False', log_file)
    multi_channel_main(tif_file, hdf5_file, rec_tif_file, channel_first=False)

    tif_file = '/home/binduan/Downloads/nTracer_sample_denoised.tif'
    hdf5_file = '/home/binduan/Downloads/nTracer_sample_denoised.h5'
    rec_tif_file = '/home/binduan/Downloads/Rec_nTracer_sample_denoised.tif'
    benchmark_meter = BenchmarkMeter()
    echo(
        f'Compressing {tif_file}, color_mode: 1 (rgb), channel_first: True', log_file)
    multi_channel_main(tif_file, hdf5_file, rec_tif_file, channel_first=True)

    tif_file = '/home/binduan/Downloads/182725.tif'
    hdf5_file = '/home/binduan/Downloads/182725.h5'
    rec_tif_file = '/home/binduan/Downloads/Rec_182725.tif'
    benchmark_meter = BenchmarkMeter()
    echo(f'Compressing {tif_file}, color_mode: 0 (gray)', log_file)
    gray_main(tif_file, hdf5_file, rec_tif_file)

    print_file(log_file)
