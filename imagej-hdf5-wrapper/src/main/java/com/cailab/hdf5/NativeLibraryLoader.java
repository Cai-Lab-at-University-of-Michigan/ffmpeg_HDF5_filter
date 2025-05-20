package com.cailab.hdf5;

import java.io.*;
import java.lang.reflect.Field;
import java.nio.file.*;
import java.util.Locale;
import java.util.Map;

/**
 * Utility class for loading native libraries required by the HDF5 FFmpeg filter
 */
public class NativeLibraryLoader {
    private static boolean initialized = false;
    private static final String LIBRARY_NAME = "ffmpegh5filter";
    
    /**
     * Initialize the native library loader.
     * This method extracts and loads the appropriate native library for the current platform.
     */
    public static synchronized void initialize() {
        if (initialized) {
            return;
        }
        
        try {
            String os = detectOS();
            String libraryPath = extractNativeLibrary(os);
            
            // Set library path environment variable
            String libPathEnv = System.getProperty("java.library.path");
            if (libPathEnv == null || libPathEnv.isEmpty()) {
                libPathEnv = new File(libraryPath).getParent();
            } else {
                libPathEnv = new File(libraryPath).getParent() + File.pathSeparator + libPathEnv;
            }
            
            System.setProperty("java.library.path", libPathEnv);
            
            // Force JVM to acknowledge the updated library path
            resetJavaLibraryPath();
            
            // Load the native library
            System.load(libraryPath);
            
            initialized = true;
            System.out.println("Successfully loaded native library: " + libraryPath);
        } catch (Exception e) {
            throw new RuntimeException("Failed to load native HDF5 FFmpeg filter library", e);
        }
    }
    
    /**
     * Detects the operating system and architecture.
     * 
     * @return String identifier for the current OS/architecture
     */
    private static String detectOS() {
        String os = System.getProperty("os.name", "").toLowerCase(Locale.ENGLISH);
        
        if (os.contains("linux")) {
            return "linux";
        } else if (os.contains("windows")) {
            return "windows";
        } else if (os.contains("mac") || os.contains("darwin")) {
            return "macos";
        } else {
            throw new UnsupportedOperationException(
                "Unsupported operating system: " + os + 
                ". Supported platforms are: Windows, Linux, and macOS."
            );
        }
    }
    
    /**
     * Extracts the native library for the current platform to a temporary directory.
     * 
     * @param os The operating system identifier
     * @return The path to the extracted native library
     * @throws IOException If there's an error extracting the library
     */
    private static String extractNativeLibrary(String os) throws IOException {
        String libraryFileName;
        
        // Determine library file name based on OS
        if ("linux".equals(os)) {
            libraryFileName = "lib" + LIBRARY_NAME + ".so";
        } else if ("windows".equals(os)) {
            libraryFileName = LIBRARY_NAME + ".dll";
        } else if ("macos".equals(os)) {
            libraryFileName = "lib" + LIBRARY_NAME + ".dylib";
        } else {
            throw new IllegalArgumentException("Unsupported OS: " + os);
        }
        
        // Resource path within JAR
        String resourcePath = "/native/" + os + "/" + libraryFileName;
        
        // Create temporary directory to extract library
        Path tempDir = Files.createTempDirectory("hdf5-ffmpeg-native");
        tempDir.toFile().deleteOnExit();
        
        // Path for extracted library
        File extractedLib = new File(tempDir.toFile(), libraryFileName);
        extractedLib.deleteOnExit();
        
        // Extract library from resources
        try (InputStream in = NativeLibraryLoader.class.getResourceAsStream(resourcePath)) {
            if (in == null) {
                throw new FileNotFoundException("Native library not found: " + resourcePath);
            }
            
            Files.copy(in, extractedLib.toPath(), StandardCopyOption.REPLACE_EXISTING);
        }
        
        return extractedLib.getAbsolutePath();
    }
    
    /**
     * Uses reflection to reset the java.library.path system property,
     * forcing the JVM to reload the library path.
     */
    private static void resetJavaLibraryPath() {
        try {
            Field sysPathsField = ClassLoader.class.getDeclaredField("sys_paths");
            sysPathsField.setAccessible(true);
            sysPathsField.set(null, null);
        } catch (Exception e) {
            System.err.println("Warning: Failed to reset java.library.path: " + e.getMessage());
        }
    }
    
    /**
     * Sets an environment variable in the current process.
     * 
     * @param key The environment variable name
     * @param value The environment variable value
     */
    @SuppressWarnings({"unchecked"})
    private static void setEnv(String key, String value) {
        try {
            Map<String, String> env = System.getenv();
            Class<?> cl = env.getClass();
            Field field = cl.getDeclaredField("m");
            field.setAccessible(true);
            Map<String, String> writableEnv = (Map<String, String>) field.get(env);
            writableEnv.put(key, value);
        } catch (Exception e) {
            System.err.println("Warning: Failed to set environment variable " + key + ": " + e.getMessage());
        }
    }
}