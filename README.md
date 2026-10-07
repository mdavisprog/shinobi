Shinobi is a library and program to convert 'build.ninja' files into 'build.zig' files. The purpose of this is to remove the need to translate native C++ build scripts such as CMake or Meson files into a 'build.zig' file by hand. This is done by running the appropriate C++ build system to generate the 'build.ninja' file, then Shinobi will translate this file into a 'build.zig' file.

# Usage
Shinobi can be used in two methods, as a standalone program or imported into a zig project. This section describes how they can be used in each method. In order to properly use Shinobi, two other dependencies must be installed on the host system, the native build system such as CMake, and Ninja.

## Program
A standalone program can be used to generate the 'build.zig' files which can be used in zig projects. The program is a command-line application that takes in arguments to control how the build file is generated.

The first argument is required, and is the path argument. This can be an already generated 'build.zig' file or a directory. If the path is a directory, Shinobi will first look to find a 'build.ninja' file. If one does not exist, Shinobi will look for the appropriate native build file and run the associated tool to generate the 'build.ninja' file. Currently, only CMake is supported.

There are also other options that can be specified:

* --cmake-bin-path - Specifies the path the 'cmake' executable is located if this path is not in the system's environment variables.
* --print-summary - Prints a summary of what was parsed from the ninja file.

## Library
TBD
