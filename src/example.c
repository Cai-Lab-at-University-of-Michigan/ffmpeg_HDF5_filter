/*
 * Example program for FFMPEG HDF5 compression
 *
 * Author: Bin Duan <bduan2@hawk.iit.edu>
 * Created: 2022
 *
 */

#include <stdio.h>
#include <sys/stat.h>
#include "hdf5.h"
#include "ffmpeg_h5filter.h"

#define NX 1024
#define NY 1024
#define NZ 10
#define SIZE (NX * NY * NZ)
#define SHAPE      \
    {              \
        NZ, NY, NX \
    }
#define CHUNKSHAPE \
    {              \
        NZ, NY, NX \
    }

int DisplayHelp()
{
    printf("Usage :build/example <encoder id>\n");
    printf("\t<encoder id> : Which encoder to be used for compression? \n");
    printf("\t\t[0-9] mpeg4, libxvid, libx264, h264_nvenc, libx265, hevc_nvenc, libsvtav1, librav1e, nvenc_av1, qsv_av1\n");
    exit(1);
}

int adjust_decoder_by_encoder(int c_id)
{
    int decoder_id;

    switch (c_id)
    {
    /* encoders */
    case 0:
        decoder_id = 0;
        break;
    case 1:
        decoder_id = 0;
        break;
    case 2:
        decoder_id = 1;
        break;
    case 3:
        decoder_id = 2;
        break;
    case 4:
        decoder_id = 3;
        break;
    case 5:
        decoder_id = 4;
        break;
    case 6:
        decoder_id = 6;
        break;
    case 7:
        decoder_id = 6;
        break;
    case 8:
        decoder_id = 7;
        break;
    case 9:
        decoder_id = 8;
        break;

    default:
        decoder_id = c_id;
        break;
    }

    return decoder_id;
}

int main(int argc, const char *argv[])
{

    static unsigned char data[SIZE];
    static unsigned char data_out[SIZE];
    const hsize_t shape[] = SHAPE;
    const hsize_t chunkshape[] = CHUNKSHAPE;
    char *version, *date;
    int r, i;
    unsigned int cd_values[6];
    int return_code = 1;
    int num_diff = 0;
    double avg_diff = 0.;
    int encoder_id, decoder_id, preset_id, tune_type;
    hid_t fid, sid, dset, plist = 0;

    struct stat st;

    if (argc < 2)
        DisplayHelp();

    encoder_id = atoi(argv[1]);

    if (argc == 4)
        preset_id = atoi(argv[2]);
        tune_type = atoi(argv[3]);

    // adjusted according to encoder id
    decoder_id = adjust_decoder_by_encoder(encoder_id);

    for (i = 0; i < SIZE; i++)
        data[i] = i;

    /* Dynamically register the filter with the library */
    r = ffmpeg_register_h5filter();

    if (r < 0)
        goto failed;

    sid = H5Screate_simple(3, shape, NULL);
    if (sid < 0)
        goto failed;

    fid = H5Fcreate("example.h5", H5F_ACC_TRUNC, H5P_DEFAULT, H5P_DEFAULT);
    if (fid < 0)
        goto failed;

    plist = H5Pcreate(H5P_DATASET_CREATE);
    if (plist < 0)
        goto failed;

    /* Chunked layout required for filters */
    r = H5Pset_chunk(plist, 3, chunkshape);
    if (r < 0)
        goto failed;

    /* FFMPEG filter requires 8 parameters */
    cd_values[0] = encoder_id; /* Encoder id */
    cd_values[1] = decoder_id; /* Decoder id */
    cd_values[2] = NX;         /* Number of columns */
    cd_values[3] = NY;         /* Number of rows */
    cd_values[4] = NZ;         /* depth */
    cd_values[5] = 0;          /* Color mode (0=Mono, 1=RGB) */
    cd_values[6] = preset_id;  /* Preset for encoding codec */
    cd_values[7] = tune_type;  /* tuning for encoding codec */
    cd_values[8] = 0;
    cd_values[9] = 0;
    cd_values[10] = 0;

    /* Set the filter with 8 params */
    r = H5Pset_filter(plist, FFMPEG_H5FILTER, H5Z_FLAG_OPTIONAL, 11, cd_values);

    if (r < 0)
        goto failed;

#if H5_USE_16_API
    dset = H5Dcreate(fid, "dset", H5T_NATIVE_UINT8, sid, plist);
#else
    dset = H5Dcreate(fid, "dset", H5T_NATIVE_UINT8, sid, H5P_DEFAULT, plist, H5P_DEFAULT);
#endif
    if (dset < 0)
        goto failed;

    r = H5Dwrite(dset, H5T_NATIVE_UINT8, H5S_ALL, H5S_ALL, H5P_DEFAULT, &data);
    if (r < 0)
        goto failed;
    H5Dclose(dset);
    dset = 0;
    H5Sclose(sid);
    sid = 0;
    H5Pclose(plist);
    plist = 0;
    H5Fclose(fid);
    fid = 0;

    fid = H5Fopen("example.h5", H5F_ACC_RDONLY, H5P_DEFAULT);
    if (fid < 0)
        goto failed;

    dset = H5Dopen2(fid, "dset", H5P_DEFAULT);
    if (dset < 0)
        goto failed;

    r = H5Dread(dset, H5T_NATIVE_UINT8, H5S_ALL, H5S_ALL, H5P_DEFAULT, &data_out);
    if (r < 0)
        goto failed;
    for (i = 0; i < SIZE; i++)
    {
        if (data[i] != data_out[i])
        {
            num_diff++;
        }
        avg_diff += (double)abs(data[i] - data_out[i]);
    }

    avg_diff /= SIZE;

    printf("Success, %f percent of different elements, average difference is %f\n", 100. * (double)num_diff / SIZE, avg_diff);
    stat("example.h5", &st);
    printf("Success, compression ratio %f for %d bytes to %d bytes \n", (double)SIZE / (double)st.st_size, SIZE, st.st_size);

    return_code = 0;

failed:
    printf("FAILED\n");
    if (dset > 0)
        H5Dclose(dset);
    if (sid > 0)
        H5Sclose(sid);
    if (plist > 0)
        H5Pclose(plist);
    if (fid > 0)
        H5Fclose(fid);

    return return_code;
}
