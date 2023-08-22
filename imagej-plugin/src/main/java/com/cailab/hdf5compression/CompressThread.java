package com.cailab.hdf5compression;

import org.apache.commons.io.output.ByteArrayOutputStream;

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
			imp.lock(); // lock image

			int nChannels = imp.getNChannels();
			int nFrames = imp.getNFrames();
			int nSlices = imp.getNSlices();
			int nRows = imp.getHeight();
			int nCols = imp.getWidth();
			long[] dimensions;
			long space;
			final int[] CHUNK_SIZES = { nCols, nRows, 100 };

			System.out.println("nChannels: " + nChannels + " nFrames: " + nFrames + " nSlices: " + nSlices + " Height: "
					+ nRows + " Width : " + nCols);

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
			cd_values[2] = CHUNK_SIZES[0];
			cd_values[3] = CHUNK_SIZES[1];
			cd_values[4] = CHUNK_SIZES[2];
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
				long[] chunkshape = { 1, CHUNK_SIZES[2], CHUNK_SIZES[1], CHUNK_SIZES[0] };
				r = H5.H5Pset_chunk(plist, 4, chunkshape);
			} else { // single-channel
				long[] chunkshape = { CHUNK_SIZES[2], CHUNK_SIZES[1], CHUNK_SIZES[0] };
				r = H5.H5Pset_chunk(plist, 3, chunkshape);
			}

			if (r >= 0) {
				System.out.println("Chunking set successfully, chunkSize: " + CHUNK_SIZES[2] + "x" + CHUNK_SIZES[1]
						+ "x" + CHUNK_SIZES[0]);
			} else {
				System.out.println("Error: " + r);
				return;
			}

			// Create 8 bit dataset
			ds = H5.H5Dcreate(fid, "data", HDF5Constants.H5T_NATIVE_UINT8, space, HDF5Constants.H5P_DEFAULT, plist,
					HDF5Constants.H5P_DEFAULT);

			byte[] pixels = null;
			ImageProcessor imageProcessor = null;
			int slice = 1;

			long targetSpace = H5.H5Scopy(space);
			long memSpace = H5.H5Screate_simple(3, new long[] { CHUNK_SIZES[2], nRows, nCols }, null);
			ByteArrayOutputStream outputStream = new ByteArrayOutputStream();

			for (int c = 0; c < Math.max(nChannels, nFrames); c++) {
				for (int i = 1; i <= nSlices; i++) {
					// get slice for channel and coordinates
					if (nFrames > 0) {
						slice = imp.getStackIndex(0, i, c);
					} else {
						slice = imp.getStackIndex(c, i, 0);
					}

					// convert input image to 8 bit
					imageProcessor = imp.getStack().getProcessor(slice).convertToByte(true);
					pixels = (byte[]) imageProcessor.getPixels();
					outputStream.write(pixels);
					
					// write one chunk at a time
					if (i % CHUNK_SIZES[2] == 0) {
						// Select target space
						if (nChannels > 1 || nFrames > 1) {
							H5.H5Sselect_hyperslab(targetSpace, HDF5Constants.H5S_SELECT_SET,
									new long[] { c, i - CHUNK_SIZES[2], 0, 0 },
									new long[] { 1, 1, 1, 1 }, new long[] { 1, 1, 1, 1 },
									new long[] { 1, CHUNK_SIZES[2], nRows, nCols });
						} else {
							H5.H5Sselect_hyperslab(targetSpace, HDF5Constants.H5S_SELECT_SET,
									new long[] { i - CHUNK_SIZES[2], 0, 0 },
									new long[] { 1, 1, 1 }, new long[] { 1, 1, 1 },
									new long[] { CHUNK_SIZES[2], nRows, nCols });
						}

						// Write to dataset and update GUI
						H5.H5Dwrite(ds, HDF5Constants.H5T_NATIVE_UINT8, memSpace, targetSpace,
								HDF5Constants.H5P_DEFAULT, outputStream.toByteArray());
						mw.updateProgress((int) Math
								.floor((c * nSlices + i) / (float) (Math.max(nChannels, nFrames) * nSlices) * 100));
						// clear out outputStream
						outputStream.close();
						outputStream = new ByteArrayOutputStream();
					}
				}

				// write the rest data to h5 file
				if (nSlices % CHUNK_SIZES[2] > 0) {
					int rest = nSlices % CHUNK_SIZES[2];
					int start = nSlices - (nSlices % CHUNK_SIZES[2]);
					memSpace = H5.H5Screate_simple(3, new long[] { rest, nRows, nCols }, null);
					if (nChannels > 1 || nFrames > 1) {
						H5.H5Sselect_hyperslab(targetSpace, HDF5Constants.H5S_SELECT_SET, new long[] { c, start, 0, 0 },
								new long[] { 1, 1, 1, 1 }, new long[] { 1, 1, 1, 1 },
								new long[] { 1, rest, nRows, nCols });
					} else {
						H5.H5Sselect_hyperslab(targetSpace, HDF5Constants.H5S_SELECT_SET, new long[] { start, 0, 0 },
								new long[] { 1, 1, 1 }, new long[] { 1, 1, 1 }, new long[] { rest, nRows, nCols });
					}

					// Write to dataset and update GUI
					H5.H5Dwrite(ds, HDF5Constants.H5T_NATIVE_UINT8, memSpace, targetSpace, HDF5Constants.H5P_DEFAULT,
							outputStream.toByteArray());
					mw.updateProgress(100);
					// close outputStream
					outputStream.close();
				}
			}

			// Cleanup
			H5.H5Dclose(ds);
			H5.H5Fflush(fid, HDF5Constants.H5F_SCOPE_LOCAL);
			H5.H5Fclose(fid);
			System.out.println("File closed");
			mw.onCompressionComplete();
			imp.unlock(); // unlock image stack
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
