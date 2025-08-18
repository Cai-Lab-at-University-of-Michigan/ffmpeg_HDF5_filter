macro "AutoRun" {
    imagej_dir = getDirectory("imagej");
    os = getInfo("os.name");
    os_lower = toLowerCase(os);

    if (indexOf(os_lower, "mac") >= 0) {
        lib_path = imagej_dir + "lib/macosx";
    } else if (indexOf(os_lower, "win") >= 0) {
        lib_path = imagej_dir + "lib\\win64";
    } else {
        lib_path = imagej_dir + "lib/linux64";
    }

    print("Operating System: " + os);
    print("Library Path: " + lib_path);

    call("java.lang.System.setProperty", "HDF5_PLUGIN_PATH", lib_path);

    if (indexOf(os_lower, "mac") >= 0) {
        cmd = "launchctl setenv HDF5_PLUGIN_PATH " + lib_path;
        exec("sh", "-c", cmd);
    } else if (indexOf(os_lower, "win") >= 0) {
        cmd = "setx HDF5_PLUGIN_PATH \"" + lib_path + "\"";
        exec("cmd", "/c", cmd);
    } else {
        cmd = "mkdir -p ~/.config/environment.d && "
        + "if ! grep -q 'HDF5_PLUGIN_PATH=' ~/.config/environment.d/hdf5.conf 2>/dev/null; then "
        + "echo 'HDF5_PLUGIN_PATH=" + lib_path + "' >> ~/.config/environment.d/hdf5.conf; fi && "
        + "systemctl --user import-environment HDF5_PLUGIN_PATH";
        exec("sh", "-c", cmd);
    }

    env_check = call("java.lang.System.getProperty", "HDF5_PLUGIN_PATH");
    if (env_check != "") {
        print("HDF5_PLUGIN_PATH set to: " + env_check);
    } else {
        print("Warning: Could not verify setting");
    }

    print("HDF5 Plugin setup complete!");
}
