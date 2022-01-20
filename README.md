# CPython on wasm32-wasi

This project consists of utilities and libraries for building 
CPython sources for the [WebAssembly](https://webassembly.org)
platform using the [WASI SDK](https://github.com/WebAssembly/wasi-sdk).
The scripts here will configure and build various versions of CPython
(3.9, 3.10, 3.11). A Dockerfile is supplied to simplify the setup
of a build environment.

## Building the Docker Image

To build the Docker image, use the following command:

```
docker build -f docker/Dockerfile -t wasi-build:latest docker
```

Note that the `run.sh` script used below does patch a number of files
in the WASI SDK to alleviate problems in the Python build process.
If you are not using Docker, you may wish to make a note of the files
that get changed.

## Starting a Docker Container

To run the Docker image created above, use the following command:

```
docker run -it --rm -v /home/me:/home/me wasi-build:latest bash
```

The mount for your user directory should be changed accordingly.
You do not necessarily need to mount your user directory, just a
writable directory that has access to the files from this project.

## Build CPython

In the Docker container created in the previous step, run the
following command from this project directory. It will download the
CPython repository as well as the source for the
[wasix](https://github.com/singlestore-labs/wasix) project, patch
files in the WASI SDK and CPython source, then build CPython
for the WASI platform.

```
cd /path/to/python-wasi
./run.sh
```

### Building without Docker

It is possible to build without Docker if you have WASI SDK and the
other tools required to build CPython already installed. Note, however,
that currently the `run.sh` script will make changes to a small number
of files in the WASI SDK tree to fix issues that prevent CPython
from building. You will want to make a note of these changes in case
they need to be undone. It is hoped that these issues will be fixed
in the WASI SDK in the near future so that the patches are no longer
needed.


### Cloning CPython and/or wasix Manually

The paths to the CPython source and wasix source are configurable in the
`run.sh` script. You can clone them manually before running `run.sh`.
This method can be used to change the source branch used prior to running
the build.

## Running WASI CPython

The `run.sh` script will execute a smoke test of the resulting CPython
build using `wasmtime` which prints the version number of the CPython
interpreter that was just built. To run an interactive session of the
newly built CPython interpreter, use the following command:

```
wasmtime run --env PYTHONHOME=/ --env PYTHONPATH=/Lib --env PATH=/ \
             --mapdir=/::cpython -- cpython/python.wasm -i
```

If your CPython source is not located in the `cpython` directory, the above
`--mapdir=` option should reflect the appropriate location.

## Running Python Unit Tests

You can run the Python test suite with the following command. Many tests
are currently failing due to the fact that WASI does not have support
for threads, subprocesses, or sockets. As support is added for these features
in the future, more tests will pass.

```
wasmtime run --env PYTHONHOME=/ --env PYTHONPATH=/Lib --env PATH=/ \
             --mapdir=/::cpython -- cpython/python.wasm \
             cpython/Lib/test/test_runpy.py
```

## Resetting Files in the CPython Repository

Several CPython files get patched by the `run.sh` script to fix problems
in either the build or test process. The `reset-python-repo.sh` script
can be used to undo the changes made. This allows you to easily change
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

[Python](https://python.org) The Python programming language

[CPython](https://github.com/python/cpython) The CPython source repository

[WASI SDK](https://github.com/WebAssembly/wasi-sdk) The WASI SDK source repository

[wasix](https://github.com/singlestore-labs/wasix) The wasix library source repository
