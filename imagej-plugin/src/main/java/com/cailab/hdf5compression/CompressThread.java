package com.cailab.hdf5compression;

import hdf.hdf5lib.H5;
import hdf.hdf5lib.HDF5Constants;
import ij.ImagePlus;
import ij.WindowManager;
import ij.process.ImageProcessor;

public class CompressThread implements Runnable {
	private MainWindow mw;
	private String filename;
	private int encoderId;
	private int decoderId;
	private int presetId;
	private int tuneType;
	private int crf;
	private int filmGrain;

	public CompressThread(MainWindow mw, String filename, int encoderId, int decoderId, int presetId, int tuneType,
			int crf, int filmGrain) {
		this.mw = mw;
		this.filename = filename;
		this.encoderId = encoderId;
		this.decoderId = decoderId;
		this.presetId = presetId;
		this.tuneType = tuneType;
		this.crf = crf;
		this.filmGrain = filmGrain;
	}

	@Override
	public void run() {
		long ds = -1;
		long fid = -1;

		try {
			// Register filter plugin with HDF5
			String pluginPath = System.getProperty("user.dir") + "/plugins/hdf5-plugin";
			System.out.println("Setting plugin with path: " + pluginPath);
			H5.H5PLappend(pluginPath);

			ImagePlus imp = WindowManager.getCurrentImage();

			int nChannels = imp.getNChannels();
			int nFrames = imp.getNFrames();
			int nSlices = imp.getNSlices();
			int nRows = imp.getHeight();
			int nCols = imp.getWidth();
			long[] dimensions;
			long space;

			if (nChannels > 1) { // Multi-channel
				dimensions = new long[] { nChannels, nSlices, nRows, nCols };
				space = H5.H5Screate_simple(4, dimensions, null);
			} else if (nFrames > 1) { // Multi-channel (frames)
				dimensions = new long[] { nFrames, nSlices, nRows, nCols };
				space = H5.H5Screate_simple(4, dimensions, null);
			} else { // Single-channel
				dimensions = new long[] { nSlices, nRows, nCols };
				space = H5.H5Screate_simple(3, dimensions, null);
			}

			long plist = H5.H5Pcreate(HDF5Constants.H5P_DATASET_CREATE);
			fid = H5.H5Fcreate(filename, HDF5Constants.H5F_ACC_TRUNC, HDF5Constants.H5P_DEFAULT,
					HDF5Constants.H5P_DEFAULT);

			int[] cd_values = new int[11];

			// Set filter parameters
			cd_values[0] = encoderId;
			cd_values[1] = decoderId;
			cd_values[2] = 64;
			cd_values[3] = 64;
			cd_values[4] = 8;
			cd_values[5] = 0;
			cd_values[6] = presetId;
			cd_values[7] = tuneType;
			cd_values[8] = crf;
			cd_values[9] = filmGrain;
			cd_values[10] = 0;

			if (H5.H5Zfilter_avail(Constants.FILTER_ID) <= 0) {
				System.out.println("Error: filter not available");
				return;
			}

			int r = H5.H5Pset_filter(plist, Constants.FILTER_ID, HDF5Constants.H5Z_FLAG_OPTIONAL, 11, cd_values);
			if (r < 0) {
				System.out.println("Error: " + r);
				return;
			} else {
				System.out.println("HDF5 filter set successfully");
			}

			System.out.println("Dimensions: " + dimensions[0] + " " + dimensions[1] + " " + dimensions[2]);

			// Set chunking
			if (nChannels > 1 || nFrames > 1) { // multi-channel
				long[] chunkshape = { 1, 8, 64, 64 };
				r = H5.H5Pset_chunk(plist, 4, chunkshape);
			} else { // single-channel
				long[] chunkshape = { 8, 64, 64 };
				r = H5.H5Pset_chunk(plist, 3, chunkshape);
			}

			if (r >= 0) {
				System.out.println("Chunking set successfully");
			} else {
				System.out.println("Error: " + r);
				return;
			}

			// Create 8 bit dataset
			ds = H5.H5Dcreate(fid, "dset", HDF5Constants.H5T_NATIVE_UINT8, space, HDF5Constants.H5P_DEFAULT, plist,
					HDF5Constants.H5P_DEFAULT);

			long targetSpace = H5.H5Scopy(space);
			long memSpace = H5.H5Screate_simple(2, new long[] { nRows, nCols }, null);

			for (int c = 0; c < Math.max(nChannels, nFrames); c++) {
				for (int i = 1; i <= nSlices; i++) {
					// Select subset of target dataset to write to
					if (nChannels > 1 || nFrames > 1) {
						H5.H5Sselect_hyperslab(targetSpace, HDF5Constants.H5S_SELECT_SET, new long[] { c, i - 1, 0, 0 },
								new long[] { 1, 1, 1, 1 }, new long[] { 1, 1, 1, 1 },
								new long[] { 1, 1, nRows, nCols });
					} else {
						H5.H5Sselect_hyperslab(targetSpace, HDF5Constants.H5S_SELECT_SET, new long[] { i - 1, 0, 0 },
								new long[] { 1, 1, 1 }, new long[] { 1, 1, 1 }, new long[] { 1, nRows, nCols });
					}

					// get slice for channel and coordinates
					int slice;
					if (nFrames > 0) {
						slice = imp.getStackIndex(0, i, c);
					} else {
						slice = imp.getStackIndex(c, i, 0);
					}

					// convert input image to 8 bit
					ImageProcessor imageProcessor = imp.getStack().getProcessor(slice).convertToByte(true);
					byte[] pixels = (byte[]) imageProcessor.getPixels();

					// Write to dataset and update GUI
					H5.H5Dwrite(ds, HDF5Constants.H5T_NATIVE_UINT8, memSpace, targetSpace, HDF5Constants.H5P_DEFAULT,
							pixels);
					mw.updateProgress((int) Math
							.floor((c * nSlices + i) / (float) (Math.max(nChannels, nFrames) * nSlices) * 100));
				}
			}

			// Cleanup
			H5.H5Dclose(ds);
			H5.H5Fflush(fid, HDF5Constants.H5F_SCOPE_LOCAL);
			H5.H5Fclose(fid);
			System.out.println("File closed");
			mw.onCompressionComplete();
		} catch (Exception e) {
			e.printStackTrace();
			try {
				if (ds != -1) {
					H5.H5Dclose(ds);
				}
				if (fid != -1) {
					H5.H5Fclose(fid);
				}
			} catch (Exception e2) {
				e2.printStackTrace();
			}
			mw.onCompressionError();
		}
	}
}
