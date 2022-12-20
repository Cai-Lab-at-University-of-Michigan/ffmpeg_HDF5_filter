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
    'index': '',
    'encoder': '',
    'preset': '',
    'tune': '',
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
        f.write('\n')


def print_record(record, indent=2):
    print(json.dumps(record, indent=indent))


def print_file(file):
    with open(file, 'r') as f:
        for line in f.readlines():
            if "{" in line:
                print_record(json.loads(line))
            else:
                print(line)


def params_gen(shape):
    # no preset and no tune
    for codec in range(8):
        if codec in [0, 1]:
            yield (codec, 0, *shape, 0, 0, 0)
        if codec == 2:
            yield (codec, 1, *shape, 0, 0, 0)
        if codec == 3:
            yield (codec, 2, *shape, 0, 0, 0)
        if codec == 4:
            yield (codec, 3, *shape, 0, 0, 0)
        if codec == 5:
            yield (codec, 4, *shape, 0, 0, 0)
        if codec == 6:
            yield (codec, 6, *shape, 0, 0, 0)
        if codec == 7:
            yield (codec, 6, *shape, 0, 0, 0)

    for codec in range(8):
        if codec == 2:
            for preset in range(10, 19):
                for tune in range(10, 18):
                    yield (codec, 1, *shape, 0, preset, tune)
        if codec == 3:
            for preset in range(100, 107):
                for tune in range(100, 104):
                    yield (codec, 2, *shape, 0, preset, tune)
        if codec == 4:
            for preset in range(200, 209):
                for tune in range(200, 206):
                    yield (codec, 3, *shape, 0, preset, tune)
        if codec == 5:
            for preset in range(300, 307):
                for tune in range(300, 304):
                    yield (codec, 4, *shape, 0, preset, tune)
        if codec == 6:
            for preset in range(400, 414):
                for tune in range(400, 403):
                    # Decoder speedup is only supported in presets M0-M10.
                    if tune == 402:
                        if not preset in [400, 401, 402]:
                            yield (codec, 6, *shape, 0, preset, tune)
                    else:
                        yield (codec, 6, *shape, 0, preset, tune)
        if codec == 7:
            for preset in range(500, 511):
                for tune in range(500, 502):
                    yield (codec, 6, *shape, 0, preset, tune)


def multi_channel_main(raw_file, h5_file, rec_file, filter_parameters, index, channel_first=True):
    raw_array = imread(raw_file)  # ZCYX

    assert raw_array.ndim == 4

    ch = raw_array.shape[1]

    if channel_first:
        raw_array = np.transpose(raw_array, (1, 0, 2, 3))

    raw_array = np.reshape(raw_array, (-1, raw_array.shape[2], raw_array.shape[3]))
    print(f'RAW SHAPE: {raw_array.shape}, RAW_DTYPE: {raw_array.dtype}')

    chunk_shape = raw_array.shape

    print(f'CHUNK SHAPE: {chunk_shape}')

    record = TEMPLATE
    record['index'] = index
    record['encoder'] = filter_parameters[0]
    record['preset'] = filter_parameters[-2]
    record['tune'] = filter_parameters[-1]

    # compressed to h5 file
    start_time = time.time()
    with h5py.File(h5_file, 'w') as f:
        f.create_dataset('data', raw_array.shape, raw_array.dtype, data=raw_array,
                         chunks=chunk_shape, **h5pl.FFMPEG(*filter_parameters))

    record['enc_elapsed_time'] = f'{time.time() - start_time:.4f}'

    # decompressed back and store it
    start_time = time.time()
    with h5py.File(h5_file, 'r') as f:
        rec_array = np.array(f['data'])

    record['dec_elapsed_time'] = f'{time.time() - start_time:.4f}'

    print(f'REC SHAPE: {rec_array.shape}')

    assert raw_array.shape == rec_array.shape, print("Two images shape not matched")

    if channel_first:
        rec_array = np.reshape(rec_array, (ch, -1, raw_array.shape[1], raw_array.shape[2]))
        rec_array = np.transpose(rec_array, (1, 0, 2, 3))
    else:
        rec_array = np.reshape(rec_array, (-1, ch, raw_array.shape[1], raw_array.shape[2]))

    imwrite(rec_file, rec_array, imagej=True, metadata={'axes': 'ZCYX'})

    # metrics
    try:
        record = benchmark_meter(record, raw_file, h5_file, rec_file)
    except:
        print("Error happened")

    save_record_appending(record, log_file)


def gray_main(raw_file, h5_file, rec_file, filter_parameters, index):
    """
    filter_parameters: (enc_id, dec_id, width, height, depth, color_mode, preset, tune)
    """
    raw_array = imread(raw_file)  # ZYX
    print(f'RAW SHAPE: {raw_array.shape}')

    assert raw_array.dtype == np.uint8

    chunk_shape = raw_array.shape

    print(f'CHUNK SHAPE: {chunk_shape}')

    record = TEMPLATE
    record['index'] = index
    record['encoder'] = filter_parameters[0]
    record['preset'] = filter_parameters[-2]
    record['tune'] = filter_parameters[-1]

    # compressed to h5 file
    start_time = time.time()
    with h5py.File(h5_file, 'w') as f:
        f.create_dataset('data', raw_array.shape, raw_array.dtype, data=raw_array,
                         chunks=chunk_shape, **h5pl.FFMPEG(*filter_parameters))

    record['enc_elapsed_time'] = f'{time.time() - start_time:.4f}'

    # decompressed back and store it
    start_time = time.time()
    with h5py.File(h5_file, 'r') as f:
        rec_array = np.array(f['data'])

    record['dec_elapsed_time'] = f'{time.time() - start_time:.4f}'

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
    benchmark_meter = BenchmarkMeter()
    filter_shape = (1344, 1984, 201)
    gen = params_gen(filter_shape)

    tif_file = '/home/binduan/Downloads/182725_201.tif'
    hdf5_file = '/home/binduan/Downloads/182725_201.h5'
    rec_tif_file = '/home/binduan/Downloads/Rec_182725_201.tif'

    idx = 1
    while True:
        try:
            params = next(gen)
            print(params)
            gray_main(tif_file, hdf5_file, rec_tif_file, params, idx)
            if idx % 10 == 1:
                print(f'idx: {idx}')
                print_file(log_file)
            idx += 1
        except StopIteration:
            break

    print(f'idx: {idx}')
    print_file(log_file)
