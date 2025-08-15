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
        cmd = "export HDF5_PLUGIN_PATH=" + lib_path;
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
