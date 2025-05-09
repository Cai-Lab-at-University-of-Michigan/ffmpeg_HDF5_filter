package ch.psi.imagej.hdf5;

import java.lang.reflect.Array;
import java.util.ArrayList;
import java.util.logging.Level;
import java.util.logging.Logger;

import hdf.object.Dataset;
import hdf.object.h5.H5File;
import ij.IJ;
import ij.process.ByteProcessor;
import ij.process.ColorProcessor;
import ij.process.FloatProcessor;
import ij.process.ImageProcessor;
import ij.process.ShortProcessor;

public class VirtualStackHDF5 extends BufferedVirtualStack {

	private static final Logger logger = Logger.getLogger(VirtualStackHDF5.class.getName());

	private int bitDepth = 0;
	private Dataset dataset;
	private H5File file;

	private int zChunkPreLoad = 0;

	public VirtualStackHDF5(H5File file, Dataset dataset) {
		// super((int) dataset.getDims()[2], (int) dataset.getDims()[1]);
		this.dataset = dataset;
		this.file = file;
		// simply run getChunkSize() will return null,
		// needs to run getMetadata() first;
		try {
			dataset.getMetadata();
		} // get chunking and compression info
		catch (Exception ex) {
			logger.info("get chunking and compression info:" + ex);
		}
		long[] chunks = dataset.getChunkSize();
		String sizeStr;
		if (chunks != null) {
			sizeStr = String.valueOf(chunks[0]);
			for (int i = 1; i < dataset.getRank(); i++) {
				sizeStr += "x" + chunks[i];
			}
			System.out.println("chunkSize: " + sizeStr);
		}
		this.zChunkPreLoad = 2 * (int) chunks[0];
	}

	/** Does noting. */
	public void addSlice(String sliceLabel, Object pixels) {
	}

	/** Does nothing.. */
	public void addSlice(String sliceLabel, ImageProcessor ip) {
	}

	/** Does noting. */
	public void addSlice(String sliceLabel, ImageProcessor ip, int n) {
	}

	/** Does noting. */
	public void deleteSlice(int n) {
	}

	/** Does noting. */
	public void deleteLastSlice() {
	}

	/**  */
	public Object getChunks(int slice) {
		try {
			long[] dimensions = dataset.getDims();

			// Select what to readout
			long[] selected = dataset.getSelectedDims();
			selected[0] = zChunkPreLoad;
			selected[1] = dimensions[1];
			selected[2] = dimensions[2];

			long[] start = dataset.getStartDims();
			start[0] = (slice - 1) / zChunkPreLoad * zChunkPreLoad; // Indexing at image J starts at 1

			if ((start[0] + zChunkPreLoad) > dimensions[0]){
				selected[0] = dimensions[0] - start[0];
			}

			Object wholeDataset = dataset.read();

			if (wholeDataset instanceof byte[]) {
				return (byte[]) wholeDataset;
			} else if (wholeDataset instanceof short[]) {
				return (short[]) wholeDataset;
			} else if (wholeDataset instanceof int[]) {
				return HDF5Utilities.convertToFloat((int[]) wholeDataset);
			} else if (wholeDataset instanceof long[]) {
				return HDF5Utilities.convertToFloat((long[]) wholeDataset);
			} else if (wholeDataset instanceof float[]) {
				return (float[]) wholeDataset;
			} else if (wholeDataset instanceof double[]) {
				return HDF5Utilities.convertToFloat((double[]) wholeDataset);
			} else {
				logger.warning("Datatype not supported");
			}
		} catch (OutOfMemoryError | Exception e) {
			logger.log(Level.WARNING, "Unable to open slice", e);
		}

		return null;
	}

	/**
	 * Assigns a pixel array to the specified slice, were 1<=n<=nslices.
	 */
	public void setPixels(Object pixels, int n) {
	}

	/**
	 * Returns an ImageProcessor for the specified slice, were 1<=n<=nslices.
	 * Returns null if the stack is empty.
	 */
	public ImageProcessor getProcessor(int slice) {
		int t0 = (int) System.currentTimeMillis();
		IJ.log("Getting processor, slice: " + slice);
		System.out.println("Getting processor, slice: " + slice);
		test_lock.lock();
		if (processor_fifo.size() > proc_buffer_MAX) {
			int to_remove = processor_fifo.remove();
			IJ.log("\tClearing Cache Item " + to_remove);
			processor_buffer.remove(to_remove);

			buffer_clean_count++;
			if (buffer_clean_count % 10 == 0) {
				System.gc();
				buffer_clean_count = 0;
			}
		}

		ImageProcessor to_return = null;
		if (processor_buffer.containsKey(slice)) {
			IJ.log("Cache HIT (" + slice + ") " + processor_buffer.size());
			to_return = processor_buffer.get(slice);
		} else {
			IJ.log("Cache MISS (" + slice + ")");
			ArrayList<ImageProcessor> ips;
			ips = getProcessor_internal(slice);
			for (int i = 1; i < ips.size() + 1; ++i) {
				processor_buffer.put((slice - 1) / zChunkPreLoad * zChunkPreLoad + i, ips.get(i - 1));
				processor_fifo.add((slice - 1) / zChunkPreLoad * zChunkPreLoad + i);
			}
			to_return = processor_buffer.get(slice);
		}

		this.gui.updateStatus();
		test_lock.unlock();

		IJ.log("Getting processor, slice: " + slice + " took " + ((int) System.currentTimeMillis() - t0) + "ms");

		// return to_return;

		if (to_return instanceof ByteProcessor) {
			ByteProcessor out = new ByteProcessor(to_return.getWidth(), to_return.getHeight(),
					(byte[]) to_return.getPixels(), to_return.getColorModel());
			return out;
		} else if (to_return instanceof ShortProcessor) {
			ShortProcessor out = new ShortProcessor(to_return.getWidth(), to_return.getHeight(),
					(short[]) to_return.getPixels(), to_return.getColorModel());
			return out;
		} else if (to_return instanceof FloatProcessor) {
			FloatProcessor out = new FloatProcessor(to_return.getWidth(), to_return.getHeight(),
					(float[]) to_return.getPixels(), to_return.getColorModel());
			return out;
		} else if (to_return instanceof ColorProcessor) {
			ColorProcessor out = new ColorProcessor(to_return.getWidth(), to_return.getHeight(),
					(int[]) to_return.getPixels());
			return out;
		}

		return to_return;
	}

	public ArrayList<ImageProcessor> getProcessor_internal(int n) {
		// IJ.log("Loading Processor " + n + "...");
		if (isOutOfRange(n)) {
			throw new IllegalArgumentException("Argument out of range: " + n);
		}

		long[] dimensions = dataset.getDims();
		long[] selected = dataset.getSelectedDims();

		final Object chunks = getChunks(n);
		final int size = (int) dimensions[2] * (int) dimensions[1];
		ArrayList<ImageProcessor> ips = new ArrayList<ImageProcessor>();

		// Todo support more ImageProcessor types
		for (int lec = 0; lec < selected[0]; ++lec) {
			ImageProcessor ip;
			int startIdx = lec * size;
			Object pixels = Array.newInstance(chunks.getClass().getComponentType(), size);
			System.arraycopy(chunks, startIdx, pixels, 0, size);

			if (pixels instanceof byte[]) {
				ip = new ByteProcessor((int) dimensions[2], (int) dimensions[1]);
			} else if (pixels instanceof short[]) {
				ip = new ShortProcessor((int) dimensions[2], (int) dimensions[1]);
			} else if (pixels instanceof int[]) {
				ip = new ColorProcessor((int) dimensions[2], (int) dimensions[1]);
			} else if (pixels instanceof float[]) {
				ip = new FloatProcessor((int) dimensions[2], (int) dimensions[1]);
			} else {
				throw new IllegalArgumentException("Unknown image type");
			}

			ip.setPixels(pixels);
			ips.add(ip);
		}

		return ips;
	}

	/** Returns the number of slices in this stack. */
	public int getSize() {
		return (int) this.dataset.getDims()[0];
	}

	/** Returns the label of the Nth image. */
	public String getSliceLabel(int slice) {
		return "Slice: " + slice;
	}

	/** Returns null. */
	public Object[] getImageArray() {
		return null;
	}

	/** Does nothing. */
	public void setSliceLabel(String label, int n) {
	}

	/** Always return true. */
	public boolean isVirtual() {
		return true;
	}

	/** Does nothing. */
	public void trim() {
	}

	/**
	 * Returns the bit depth (8, 16, 24 or 32), or 0 if the bit depth is not
	 * known.
	 */
	public int getBitDepth() {
		return bitDepth;
	}

	/**
	 * Close HDF5 file
	 */
	public void close() {
		logger.info("Closing HDF5 file");
		try {
			file.close();
		} catch (Exception e) {
			logger.log(Level.WARNING, "Unable to close HDF5 file", e);
		}

	}
}
