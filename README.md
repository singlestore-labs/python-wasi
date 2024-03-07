# CPython on wasm32-wasi

**Attention**: The code in this repository is intended for experimental use only and is not fully tested, documented, or supported by SingleStore. Visit the [SingleStore Forums](https://www.singlestore.com/forum/) to ask questions about this repository.

This project consists of utilities and libraries for building 
CPython sources for the [WebAssembly](https://webassembly.org)
platform using the [WASI SDK](https://github.com/WebAssembly/wasi-sdk) (v15+).
The scripts here will configure and build various versions of CPython
(3.8, 3.9, 3.10, 3.11, 3.12). A Dockerfile is supplied to simplify the setup
of a build environment.

## Building the Docker Image

To build the Docker image, use the following command:

```
docker build -f docker/Dockerfile -t wasi-build:latest docker
```

## Starting a Docker Container

To run the Docker image created above, use the following command:

```
docker run -it --rm -v $(pwd):$(pwd) -w $(pwd) wasi-build:latest bash
```

The mount for your user directory should be changed accordingly.
You do not necessarily need to mount your user directory, just a
writable directory that has access to the files from this project.

## Build CPython

In the Docker container created in the previous step, run the
following command from this project directory. It will download the
CPython repository, patch
files in the CPython source (as needed per version), then build CPython
for the WASI platform.

```
./run.sh
```

### Building without Docker

It is possible to build without Docker if you have WASI SDK and the
other tools required to build CPython already installed.

### Cloning CPython Manually

The paths to the CPython source is configurable in the
`run.sh` script. You can clone them manually before running `run.sh`.
This method can be used to change the source branch used prior to running
the build.

## Running WASI CPython

The `run.sh` script will execute a smoke test of the resulting CPython
build using `wasmtime` which prints the version number of the CPython
interpreter that was just built. How the resulting build is executed
depends on some options.

### Default

The default behavior is to build WASI Python, compile all of the `.py`
files in the standard libray, then pack the standard library into the
WASM file using WASI VFS. This gives you a complete runnable Python
installation in one file, but it is also quite large (~150MB). To run
the file, you simply do:
```
wasmtime run -- wasi-python3.10.wasm
```

### Build without compiling standard library

You can still create a single binary that includes the entire installation
without compiling the standard library which cuts the resulting file
in roughly half. However, Python will not be able to compile the `.py`
files on-the-fly since the WASM file is read-only. To disable the compilation
of `.py` files, use the `-B` option or `PYTHONDONTWRITEBYTECODE=1`
environment variable.

To build in this manner, you set `COMPILE_STDLIB=0` when executing `run.sh`.
Running WASI Python is done as follows:
```
wasmtime run -- wasi-python3.10.wasm -B
```

### Build without packing standard library

The final method of running WASI Python is without including the standard
library in the WASM file. This method requires you to map a local directory
that contains those files. To build in this manner, you set
`INCLUDE_STDLIB=0` when executing `run.sh`. Running WASI Python in this
method is done as follows:
```
wasmtime run --mapdir=/opt/wasi-python/lib/python3.10::/opt/wasi-python/lib/python3.10 \
             -- wasi-python3.10.wasm
```

It is possible to relocate the WASI Python installation by putting it in
the desired directory and setting `PYTHONHOME` to that path. By default,
`PYTHONHOME` is set to `/opt/wasi-python`.

## Running Python Unit Tests

You can run the Python test suite with the following command. Many tests
are currently failing due to the fact that WASI does not have support
for threads, subprocesses, or sockets. As support is added for these features
in the future, more tests will pass. Note that you must put the correct
Python version number in the test file path.

```
wasmtime run --mapdir=/opt/wasi-python/lib/python3.10::/opt/wasi-python/lib/python3.10 \
             --mapdir=/tmp::/tmp \
             -- wasi-python3.10.wasm \
             /opt/wasi-python/lib/python3.10/test/test_runpy.py
```

## Resetting Files in the CPython Repository

A couple files from the CPython repo get patched by the `run.sh` script to
fix problems in the build and testing processes. The `reset-python-repo.sh`
script can be used to undo the changes made. This allows you to easily change
to another branch to build alternate versions of Python.

# ToDo

This project is in early development as well as WASM and the WASI SDK.
Many features expected in a POSIX-like environment are still not available.
This includes threads, sockets, subprocesses, dynamically linked libraries,
and file operations pertaining to file ownership and permissions. As 
more support is added in each of these areas, more capabalities will be
unlocked in the WASI build of CPython as well.

The highest priority features for this project are 1) threads and 2) dynamically
linked libraries since these are required for using many Python extension
modules.

# Resources

[Python](https://python.org) Python programming language

[CPython](https://github.com/python/cpython) CPython source repository

[WASI SDK](https://github.com/WebAssembly/wasi-sdk) WASI SDK source repository

[wasix](https://github.com/singlestore-labs/wasix) wasix library source repository

[WASI VFS](https://github.com/kateinoigakukun/wasi-vfs) Virtual file system
