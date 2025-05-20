package ch.psi.imagej.hdf5;

import java.util.ArrayList;
import java.util.List;

import hdf.object.Dataset;
import hdf.hdf5lib.exceptions.HDF5LibraryException;

import com.cailab.hdf5.NativeLibraryLoader;


public class DatasetSelection {

	private List<Dataset> datasets = new ArrayList<Dataset>();
	private boolean group = false;
	private Integer slice;
	// Intervall to read images
	private Integer modulo;
	private boolean virtualStack;

	static {
        try {
            NativeLibraryLoader.initialize();
        } catch (Exception e) {
			throw new HDF5LibraryException("Failed to load FFmpeg HDF5 filter native library");
        }
    }
	
	public List<Dataset> getDatasets() {
		return datasets;
	}
	public void setDatasets(List<Dataset> datasets) {
		this.datasets = datasets;
	}
	public boolean isGroup() {
		return group;
	}
	public void setGroup(boolean group) {
		this.group = group;
	}
	public void setSlice(Integer slice) {
		this.slice = slice;
	}
	public Integer getSlice() {
		return slice;
	}
	public void setModulo(Integer modulo) {
		this.modulo = modulo;
	}
	public Integer getModulo() {
		return modulo;
	}
	public void setVirtualStack(boolean virtualStack) {
		this.virtualStack = virtualStack;
	}
	public boolean isVirtualStack(){
		return this.virtualStack;
	}
}
