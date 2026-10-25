Shinobi is a single file library and program to convert 'build.ninja' files into 'build.zig' files. The purpose of this is to remove the need to translate native C++ build scripts such as CMake or Meson files into a 'build.zig' file by hand. This is done by running the appropriate C++ build system to generate the 'build.ninja' file, then Shinobi will translate this file into a 'build.zig' file.

# Usage
Shinobi can be used in two methods, as a standalone program or imported into a zig project. This section describes how they can be used in each method. In order to properly use Shinobi, two other dependencies must be installed on the host system, the native build system such as CMake, and Ninja.

## Library
The library is a single 'shinobi.zig' file that can be copied into the same directory as the root 'build.zig' file. The library can then be imported into the project's 'build.zig' file and can be used to add the external directory containing the native C++ project. This is done by using the 'shinobi.add_directory' function, which will attempt to find the 'build.ninja' file associated with the dependency or create one through the native C++ build system if the file is not found. After the 'build.ninja' is parsed, shinobi will add all modules and executables to the given 'std.Build' object. The user can then grab the external module through the 'std.Build.modules' field.

This project comes with usage of this method in the 'examples' folder. Users can refer to the [build.zig](https://github.com/mdavisprog/shinobi/blob/main/examples/plutovg/build.zig) file in the 'plutovg' example.

## Program
A standalone program can be used to generate the 'build.zig' files which can be used in zig projects. The program is a command-line application that takes in arguments to control how the build file is generated.

The first argument is required, and is the path argument. This can be an already generated 'build.zig' file or a directory. If the path is a directory, Shinobi will first look to find a 'build.ninja' file. If one does not exist, Shinobi will look for the appropriate native build file and run the associated tool to generate the 'build.ninja' file. Currently, only CMake is supported.

There are also other options that can be specified:

* --cmake-bin-path - Specifies the path the 'cmake' executable is located if this path is not in the system's environment variables.
* --print-summary - Prints a summary of what was parsed from the ninja file.
