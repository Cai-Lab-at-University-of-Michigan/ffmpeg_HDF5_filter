package ch.psi.imagej.hdf5;

import ij.*;
import ij.process.*;
import java.util.*;
import java.util.concurrent.locks.Lock;
import java.util.concurrent.locks.ReentrantLock;

/**
 * This plugin opens a multi-page TIFF file as a virtual stack. It implements
 * the File/Import/TIFF Virtual Stack command.
 */
public class BufferedVirtualStack extends VirtualStack {

    protected BufferVirtualStackGUI gui;

    public Map<Integer, ImageProcessor> processor_buffer; // 300 * ~20MB -> ~6GB? 100 * ~30MB -> ~2GB?
    public int proc_buffer_MAX;
    public Queue<Integer> processor_fifo;
    public int buffer_clean_count;

    public Lock test_lock;

    /* Default constructor. */
    public BufferedVirtualStack() {
        this.test_lock = new ReentrantLock();
        this.proc_buffer_MAX = 100;
        this.buffer_clean_count = 0;
        this.processor_fifo = new LinkedList<>();
        this.processor_buffer = new HashMap<>();

        this.gui = new BufferVirtualStackGUI(this);
    }

    int getInt(Properties props, String key) {
        Double n = getNumber(props, key);
        return n != null ? (int) n.doubleValue() : 1;
    }

    Double getNumber(Properties props, String key) {
        String s = props.getProperty(key);
        if (s != null) {
            try {
                return Double.valueOf(s);
            } catch (NumberFormatException e) {
            }
        }
        return null;
    }

    boolean getBoolean(Properties props, String key) {
        String s = props.getProperty(key);
        return s != null && s.equals("true");
    }

    /**
     * Checks if a given 'n' is a valid processor index
     *
     * @param n a test index variable
     * @return (boolean) True if n is a valid processor, false otherwise
     */
    public boolean isOutOfRange(int n) {
        return n < 1 || n > getSize();
    }

    //ImagePlus.close();
}
