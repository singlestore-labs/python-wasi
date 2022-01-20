#!/bin/bash

#set -x

WASI_SDK_PATH=/opt/wasi-sdk
PYTHON_DIR=cpython
WASIX_DIR=wasix
PROJECT_DIR=$(pwd)

if [[ ! -d "${PYTHON_DIR}" ]]; then
    git clone https://github.com/python/cpython.git
    PYTHON_DIR=cpython
fi

if [[ ! -d "${WASIX_DIR}" ]]; then
    git clone https://github.com/singlestore-labs/wasix
    WASIX_DIR=wasix
    cd "${WASIX_DIR}" && make
    cd "${PROJECT_DIR}"
fi

if [[ ! -d "${WASI_SDK_PATH}" ]]; then
    echo "ERROR: Could not find WASI SDK: ${WASI_SDK_PATH}"
    exit 1 
fi

# Get absolute paths of all components.
WASI_SDK_PATH=$(cd "${WASI_SDK_PATH}"; pwd)
PYTHON_DIR=$(cd "${PYTHON_DIR}"; pwd)
WASIX_DIR=$(cd "${WASIX_DIR}"; pwd)

# Determine Python version.
PYTHON_VER=$(grep '^VERSION=' "${PYTHON_DIR}/configure" | cut -d= -f2)

# Build Python for the build host first. This is required for various
# steps in the Makefile for cross-compiling.
PYTHON_VER=$(grep '^VERSION=' "${PYTHON_DIR}/configure" | cut -d= -f2)
if [[ ! -f "${PYTHON_DIR}/python${PYTHON_VER}" ]]; then
    cd "${PYTHON_DIR}"
    rm -f Modules/Setup.local
    ./configure --disable-test-modules && \
        make clean && \
        make && \
        cp python "python${PYTHON_VER}" && \
        make clean
    cd "${PROJECT_DIR}"
fi

# Configure Python build
cp "Setup-${PYTHON_VER}.local" "${PYTHON_DIR}/Modules/Setup.local"
export CONFIG_SITE="${PROJECT_DIR}/config.site"

cd ${PYTHON_DIR}

#!!!
# WIP: This needs to be fixed in WASI.
$(cd ${WASI_SDK_PATH}/lib/clang/13.0.0/include && patch -p1 -N -r- < ${PROJECT_DIR}/patches/stddef.h.patch)
$(cd ${WASI_SDK_PATH}/share/wasi-sysroot/include && patch -p1 -N -r- < ${PROJECT_DIR}/patches/sockaddr_un.h.patch)
#!!!

#!!!
# WIP: Fixes for adding wasi to builds, test for missing attributes, and fix 
#      function signature in _zoneinfo.c.
patch -p1 -N -r- < ${PROJECT_DIR}/patches/configure.ac.patch
patch -p1 -N -r- < ${PROJECT_DIR}/patches/subprocess.py.patch
patch -p1 -N -r- < ${PROJECT_DIR}/patches/test_posix.py.patch
patch -p1 -N -r- < ${PROJECT_DIR}/patches/_zoneinfo.c.patch
#!!!

# Set compiler flags
export CC="clang --target=wasm32-wasi"
export CFLAGS="-g -D_WASI_EMULATED_GETPID -D_WASI_EMULATED_SIGNAL -I/opt/include -isystem ${WASIX_DIR}/include"
export LIBS="-Wl,--stack-first -Wl,-z,stack-size=83886080 -L/opt/lib -L${WASIX_DIR} -lwasix -lwasi-emulated-signal"
export PATH=${PYTHON_DIR}:${PATH}

# Configure and build
cp ${WASI_SDK_PATH}/share/misc/config.sub . && \
   cp ${WASI_SDK_PATH}/share/misc/config.guess . && \
   autoconf -f && \
   ./configure --host=wasm32-wasi --build=x86_64-pc-linux-gnu \
               --with-build-python=./python${PYTHON_VER} \
               --disable-ipv6 --enable-big-digits=30 --with-suffix=.wasm \
               --with-freeze-module=./build/Programs/_freeze_module \
	       --prefix=/ --exec-prefix=/ && \
   make clean && \
   make -j

rm "${PYTHON_DIR}/Modules/Setup.local"

cd ${PROJECT_DIR}

# This is needed when running unit tests.
mkdir -p tmp

# Reality check it
wasmtime run --mapdir=/::cpython --env PYTHONHOME=/ --env PYTHONPATH=/Lib --env PATH=/ \
	     -- cpython/python.wasm -V
