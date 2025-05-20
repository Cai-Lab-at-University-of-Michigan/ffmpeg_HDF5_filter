package com.cailab.hdf5compression;

import java.io.IOException;

import org.apache.commons.io.output.ByteArrayOutputStream;

import hdf.hdf5lib.H5;
import hdf.hdf5lib.HDF5Constants;
import hdf.hdf5lib.exceptions.HDF5DataspaceInterfaceException;
import hdf.hdf5lib.exceptions.HDF5LibraryException;
import ij.ImagePlus;
import ij.WindowManager;
import ij.process.ImageProcessor;

import com.cailab.hdf5.NativeLibraryLoader;

public class CompressThread implements Runnable {
	private MainWindow mw;
	private String filename;
	private int encoderId;
	private int decoderId;
	private int presetId;
	private int tuneType;
	private int crf;
	private int filmGrain;
	private ImagePlus imp;

	static {
        try {
            NativeLibraryLoader.initialize();
        } catch (Exception e) {
			throw new HDF5LibraryException("Failed to load FFmpeg HDF5 filter native library");
        }
    }

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

	public int getImageStackType(ImagePlus imp) {
		int nChannels = imp.getNChannels();
		int nFrames = imp.getNFrames();
		int nSlices = imp.getNSlices();
		int stackType = 0;
		// (width, height, nChannels, nSlices, nFrames)
		if (nChannels > 1) {
			if (nFrames > 1 && nSlices > 1) {
				stackType = Constants.IMAGE_CTZYX;
			} else if (nFrames > 1 && nSlices == 1) {
				stackType = Constants.IMAGE_CTYX;
			} else if (nSlices > 1 && nFrames == 1) {
				stackType = Constants.IMAGE_CZYX;
			} else {
				stackType = Constants.IMAGE_CYX;
			}
		} else {
			if (nFrames > 1 && nSlices > 1) {
				stackType = Constants.IMAGE_TZYX;
			} else if (nFrames > 1 && nSlices == 1) {
				stackType = Constants.IMAGE_TYX;
			} else if (nSlices > 1 && nFrames == 1) {
				stackType = Constants.IMAGE_ZYX;
			} else {
				throw new IllegalArgumentException("Unknown image stack type for " + "nChannels: " + nChannels
						+ " nFrames: " + nFrames + " nSlices: " + nSlices);
			}
		}

		return stackType;
	}

	public long prepareMemorySpace(ImagePlus imp) {
		int nChannels = imp.getNChannels();
		int nFrames = imp.getNFrames();
		int nSlices = imp.getNSlices();
		int nRows = imp.getHeight();
		int nCols = imp.getWidth();

		long space;

		int stackType = getImageStackType(imp);

		switch (stackType) {
			case Constants.IMAGE_ZYX:
				space = H5.H5Screate_simple(3, new long[] { nSlices, nRows, nCols }, null);
				break;
			case Constants.IMAGE_TYX:
				space = H5.H5Screate_simple(3, new long[] { nFrames, nRows, nCols }, null);
				break;
			case Constants.IMAGE_CYX:
				space = H5.H5Screate_simple(3, new long[] { nChannels, nRows, nCols }, null);
				break;
			case Constants.IMAGE_CZYX:
				space = H5.H5Screate_simple(4, new long[] { nChannels, nSlices, nRows, nCols }, null);
				break;
			case Constants.IMAGE_CTYX:
				space = H5.H5Screate_simple(4, new long[] { nChannels, nFrames, nRows, nCols }, null);
				break;
			case Constants.IMAGE_TZYX:
				space = H5.H5Screate_simple(4, new long[] { nFrames, nSlices, nRows, nCols }, null);
				break;
			case Constants.IMAGE_CTZYX:
				space = H5.H5Screate_simple(5, new long[] { nChannels, nFrames, nSlices, nRows, nCols }, null);
				break;

			default:
				throw new HDF5DataspaceInterfaceException("unable to create data space, check the data layout");
		}

		return space;
	}

	public int setChunkShape(long plist, int[] chunkSize) {
		int stackType = getImageStackType(imp);
		int r;

		switch (stackType) {
			case Constants.IMAGE_ZYX:
			case Constants.IMAGE_TYX:
			case Constants.IMAGE_CYX:
				r = H5.H5Pset_chunk(plist, 3, new long[] { chunkSize[2], chunkSize[1], chunkSize[0] });
				break;
			case Constants.IMAGE_CZYX:
			case Constants.IMAGE_CTYX:
			case Constants.IMAGE_TZYX:
				r = H5.H5Pset_chunk(plist, 4, new long[] { 1, chunkSize[2], chunkSize[1], chunkSize[0] });
				break;
			case Constants.IMAGE_CTZYX:
				r = H5.H5Pset_chunk(plist, 5, new long[] { 1, 1, chunkSize[2], chunkSize[1], chunkSize[0] });
				break;

			default:
				r = -1;
				break;
		}
		return r;
	}

	public void writeThreeDDataset(long ds, long targetSpace, ImagePlus imp, int zChunk) {
		byte[] pixels = null;
		ImageProcessor imageProcessor;
		int slice = 1;

		long memSpace = -1;
		ByteArrayOutputStream outputStream = new ByteArrayOutputStream();
		int stackType = getImageStackType(imp);
		int nFirstDim = 1;

		int nRows = imp.getHeight();
		int nCols = imp.getWidth();

		switch (stackType) {
			case Constants.IMAGE_ZYX:
				nFirstDim = imp.getNSlices();
				break;
			case Constants.IMAGE_TYX:
				nFirstDim = imp.getNFrames();
				break;
			case Constants.IMAGE_CYX:
				nFirstDim = imp.getNChannels();
				break;
			default:
				break;
		}

		try {
			for (int i = 1; i <= nFirstDim; ++i) {
				switch (stackType) {
					case Constants.IMAGE_ZYX:
						slice = imp.getStackIndex(0, i, 0);
						break;
					case Constants.IMAGE_TYX:
						slice = imp.getStackIndex(0, 0, i);
						break;
					case Constants.IMAGE_CYX:
						slice = imp.getStackIndex(i, 0, 0);
						break;
					default:
						break;
				}
				// convert input image to 8 bit
				imageProcessor = imp.getStack().getProcessor(slice).convertToByte(true);
				pixels = (byte[]) imageProcessor.getPixels();
				outputStream.write(pixels);

				if (i % zChunk == 0) {
					H5.H5Sselect_hyperslab(targetSpace, HDF5Constants.H5S_SELECT_SET,
							new long[] { i - zChunk, 0, 0 },
							new long[] { 1, 1, 1 }, new long[] { 1, 1, 1 },
							new long[] { zChunk, nRows, nCols });
					memSpace = H5.H5Screate_simple(3, new long[] { zChunk, nRows, nCols }, null);
					// Write to dataset and update GUI
					H5.H5Dwrite(ds, HDF5Constants.H5T_NATIVE_UINT8, memSpace, targetSpace, HDF5Constants.H5P_DEFAULT,
							outputStream.toByteArray());
					mw.updateProgress((int) Math.floor((float) i / (float) (nFirstDim) * 100));
					// clear out outputStream
					outputStream.close();
					outputStream = new ByteArrayOutputStream();
				}
			}
			// write the rest data to h5 file
			if (nFirstDim % zChunk > 0) {
				int rest = nFirstDim % zChunk;
				int start = nFirstDim - (nFirstDim % zChunk);
				memSpace = H5.H5Screate_simple(3, new long[] { rest, nRows, nCols }, null);
				H5.H5Sselect_hyperslab(targetSpace, HDF5Constants.H5S_SELECT_SET, new long[] { start, 0, 0 },
						new long[] { 1, 1, 1 }, new long[] { 1, 1, 1 }, new long[] { rest, nRows, nCols });

				// Write to dataset and update GUI
				H5.H5Dwrite(ds, HDF5Constants.H5T_NATIVE_UINT8, memSpace, targetSpace, HDF5Constants.H5P_DEFAULT,
						outputStream.toByteArray());
				mw.updateProgress(100);
				// close outputStream
				outputStream.close();
			}
		} catch (OutOfMemoryError | IOException e) {
			e.printStackTrace();
		}
	}

	public void writeFourDDataset(long ds, long targetSpace, ImagePlus imp, int zChunk) {
		byte[] pixels = null;
		ImageProcessor imageProcessor;
		int slice = 1;

		long memSpace = -1;
		ByteArrayOutputStream outputStream = new ByteArrayOutputStream();
		int stackType = getImageStackType(imp);

		int nRows = imp.getHeight();
		int nCols = imp.getWidth();
		int nFirstDim = 1;
		int nSecondDim = 1;
		int counter = 1;

		switch (stackType) {
			case Constants.IMAGE_CZYX:
				nFirstDim = imp.getNChannels();
				nSecondDim = imp.getNSlices();
				break;
			case Constants.IMAGE_CTYX:
				nFirstDim = imp.getNChannels();
				nSecondDim = imp.getNFrames();
				break;
			case Constants.IMAGE_TZYX:
				nFirstDim = imp.getNFrames();
				nSecondDim = imp.getNSlices();
				break;
			default:
				break;
		}

		try {
			for (int c = 1; c <= nFirstDim; ++c) {
				for (int i = 1; i <= nSecondDim; ++i) {
					switch (stackType) {
						case Constants.IMAGE_CZYX:
							slice = imp.getStackIndex(c, i, 0);
							break;
						case Constants.IMAGE_CTYX:
							slice = imp.getStackIndex(c, 0, i);
							break;
						case Constants.IMAGE_TZYX:
							slice = imp.getStackIndex(0, i, c);
							break;
						default:
							break;
					}
					// convert input image to 8 bit
					imageProcessor = imp.getStack().getProcessor(slice).convertToByte(true);
					pixels = (byte[]) imageProcessor.getPixels();
					outputStream.write(pixels);

					++counter;

					if (i % zChunk == 0) {
						H5.H5Sselect_hyperslab(targetSpace, HDF5Constants.H5S_SELECT_SET,
								new long[] { c - 1, i - zChunk, 0, 0 },
								new long[] { 1, 1, 1, 1 }, new long[] { 1, 1, 1, 1 },
								new long[] { 1, zChunk, nRows, nCols });
						memSpace = H5.H5Screate_simple(4, new long[] { 1, zChunk, nRows, nCols }, null);
						// Write to dataset and update GUI
						H5.H5Dwrite(ds, HDF5Constants.H5T_NATIVE_UINT8, memSpace, targetSpace,
								HDF5Constants.H5P_DEFAULT, outputStream.toByteArray());
						mw.updateProgress((int) Math.floor((float) counter / (float) (nFirstDim * nSecondDim) * 100));
						// clear out outputStream
						outputStream.close();
						outputStream = new ByteArrayOutputStream();
					}
				}
				// write the rest data to h5 file
				if (nSecondDim % zChunk > 0) {
					int rest = nSecondDim % zChunk;
					int start = nSecondDim - (nSecondDim % zChunk);

					memSpace = H5.H5Screate_simple(4, new long[] { 1, rest, nRows, nCols }, null);
					H5.H5Sselect_hyperslab(targetSpace, HDF5Constants.H5S_SELECT_SET,
							new long[] { c - 1, start, 0, 0 },
							new long[] { 1, 1, 1, 1 },
							new long[] { 1, 1, 1, 1 },
							new long[] { 1, rest, nRows, nCols });

					// Write to dataset and update GUI
					H5.H5Dwrite(ds, HDF5Constants.H5T_NATIVE_UINT8, memSpace, targetSpace, HDF5Constants.H5P_DEFAULT,
							outputStream.toByteArray());
					mw.updateProgress((int) Math.floor((float) counter / (float) (nFirstDim * nSecondDim) * 100));
					// close outputStream
					outputStream.close();
				}
			}
		} catch (OutOfMemoryError | IOException e) {
			e.printStackTrace();
		}
	}

	public void writeFiveDDataset(long ds, long targetSpace, ImagePlus imp, int zChunk) {
		byte[] pixels = null;
		ImageProcessor imageProcessor;
		int slice = 1;

		long memSpace = -1;
		ByteArrayOutputStream outputStream = new ByteArrayOutputStream();

		int nRows = imp.getHeight();
		int nCols = imp.getWidth();
		int nFirstDim = imp.getNChannels();
		int nSecondDim = imp.getNFrames();
		int nThirdDim = imp.getNSlices();
		int counter = 1;

		try {
			for (int c = 1; c <= nFirstDim; ++c) {
				for (int t = 1; t <= nSecondDim; ++t) {
					for (int i = 1; i <= nThirdDim; ++i) {

						slice = imp.getStackIndex(c, i, t);

						// convert input image to 8 bit
						imageProcessor = imp.getStack().getProcessor(slice).convertToByte(true);
						pixels = (byte[]) imageProcessor.getPixels();
						outputStream.write(pixels);

						++counter;

						if (i % zChunk == 0) {
							H5.H5Sselect_hyperslab(targetSpace, HDF5Constants.H5S_SELECT_SET,
									new long[] { c - 1, t - 1, i - zChunk, 0, 0 },
									new long[] { 1, 1, 1, 1, 1 }, new long[] { 1, 1, 1, 1, 1 },
									new long[] { 1, 1, zChunk, nRows, nCols });
							memSpace = H5.H5Screate_simple(5, new long[] { 1, 1, zChunk, nRows, nCols }, null);
							// Write to dataset and update GUI
							H5.H5Dwrite(ds, HDF5Constants.H5T_NATIVE_UINT8, memSpace, targetSpace,
									HDF5Constants.H5P_DEFAULT, outputStream.toByteArray());
							mw.updateProgress(
									(int) Math.floor(
											(float) counter / (float) (nFirstDim * nSecondDim * nThirdDim) * 100));
							// clear out outputStream
							outputStream.close();
							outputStream = new ByteArrayOutputStream();
						}
					}
					// write the rest data to h5 file
					if (nThirdDim % zChunk > 0) {
						int rest = nThirdDim % zChunk;
						int start = nThirdDim - (nThirdDim % zChunk);
						memSpace = H5.H5Screate_simple(5, new long[] { 1, 1, rest, nRows, nCols }, null);
						H5.H5Sselect_hyperslab(targetSpace, HDF5Constants.H5S_SELECT_SET,
								new long[] { c - 1, t - 1, start, 0, 0 },
								new long[] { 1, 1, 1, 1, 1 }, new long[] { 1, 1, 1, 1, 1 },
								new long[] { 1, 1, rest, nRows, nCols });

						// Write to dataset and update GUI
						H5.H5Dwrite(ds, HDF5Constants.H5T_NATIVE_UINT8, memSpace, targetSpace,
								HDF5Constants.H5P_DEFAULT, outputStream.toByteArray());
						mw.updateProgress(
								(int) Math.floor((float) counter / (float) (nFirstDim * nSecondDim * nThirdDim) * 100));
						// close outputStream
						outputStream.close();
					}
				}
			}
		} catch (OutOfMemoryError | IOException e) {
			e.printStackTrace();
		}
	}

	@Override
	public void run() {
		long ds = -1;
		long fid = -1;

		try {
			// Register filter plugin with HDF5
			// String pluginPath = System.getProperty("user.dir") + "/plugins/hdf5-plugin";
			// System.out.println("Setting plugin with path: " + pluginPath);
			// H5.H5PLappend(pluginPath);

			this.imp = WindowManager.getCurrentImage();
			imp.lock(); // lock image

			int nRows = imp.getHeight();
			int nCols = imp.getWidth();
			long space;
			final int[] CHUNK_SIZES = { nCols, nRows, 100 };
			int stackType = getImageStackType(imp);
			int zChunk = CHUNK_SIZES[2];

			space = prepareMemorySpace(imp);

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

			// Set chunking
			r = setChunkShape(plist, CHUNK_SIZES);

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
			long targetSpace = H5.H5Scopy(space);

			switch (stackType) {
				case Constants.IMAGE_ZYX:
				case Constants.IMAGE_TYX:
				case Constants.IMAGE_CYX:
					writeThreeDDataset(ds, targetSpace, imp, zChunk);
					break;
				case Constants.IMAGE_CZYX:
				case Constants.IMAGE_CTYX:
				case Constants.IMAGE_TZYX:
					writeFourDDataset(ds, targetSpace, imp, zChunk);
					break;
				case Constants.IMAGE_CTZYX:
					writeFiveDDataset(ds, targetSpace, imp, zChunk);
					break;

				default:
					break;
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
			imp.unlock();
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
