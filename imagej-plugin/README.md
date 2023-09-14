# ImageJ Compression Plugin
## Build
To build, run `./gradlew fatJar`. You may need to set the JDK path in the `JAVA_HOME` environment variable. Java 8 is used for this plugin. The output jar file will be in the `build/libs` folder.

## Installation
Copy the built jar file into the `plugins` directory in your ImageJ installation. You will also need the HDF5 filter library in the `/plugins/hdf5-plugin` directory.
