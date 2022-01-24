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
PYTHON_MAJOR=$(echo $PYTHON_VER | cut -d. -f1)
PYTHON_MINOR=$(echo $PYTHON_VER | cut -d. -f2)

# Build Python for the build host first. This is required for various
# steps in the Makefile for cross-compiling.
PYTHON_VER=$(grep '^VERSION=' "${PYTHON_DIR}/configure" | cut -d= -f2)
if [[ ! -d "${PYTHON_DIR}/inst/${PYTHON_VER}" ]]; then
    cd "${PYTHON_DIR}"
    rm -f Modules/Setup.local
    ./configure --disable-test-modules \
	        --with-ensurepip=no \
	        --prefix="${PYTHON_DIR}/inst/${PYTHON_VER}" \
	        --exec-prefix="${PYTHON_DIR}/inst/${PYTHON_VER}" && \
        make clean && \
        make && \
	make install
    cd "${PROJECT_DIR}"
fi

# Configure Python build. Python 3.11+ autodetects modules.
export CONFIG_SITE="${PROJECT_DIR}/config.site"
if [[ ("$PYTHON_MAJOR" -ge "3") && ("$PYTHON_MINOR" -ge "11") ]]; then
    rm -f "${PYTHON_DIR}/Modules/Setup.local"
else
    cp "Setup.local" "${PYTHON_DIR}/Modules/Setup.local"
fi

cd ${PYTHON_DIR}

# Apply patches
patch -p1 -N -r- < ${PROJECT_DIR}/patches/configure.ac.patch

if [[ -f "${PYTHON_DIR}/Modules/_zoneinfo.c" ]]; then
    patch -p1 -N -r- < ${PROJECT_DIR}/patches/_zoneinfo.c.patch
fi

if [[ ("$PYTHON_MAJOR" -eq "3") && ("$PYTHON_MINOR" -le "8") ]]; then
    sed -i 's/_zoneinfo/#_zoneinfo/' "${PYTHON_DIR}/Modules/Setup.local"
    sed -i 's/_decimal/#_decimal/' "${PYTHON_DIR}/Modules/Setup.local"
fi

# Set compiler flags
export CC="clang --target=wasm32-wasi"
export CFLAGS="-g -D_WASI_EMULATED_GETPID -D_WASI_EMULATED_SIGNAL -I/opt/include -I${WASIX_DIR}/include -isystem ${WASIX_DIR}/include"
export LIBS="-Wl,--stack-first -Wl,-z,stack-size=83886080 -L/opt/lib -L${WASIX_DIR} -lwasix -lwasi-emulated-signal"
export PATH=${PYTHON_DIR}/inst/${PYTHON_VER}/bin:${PATH}

# Configure and build
cp ${WASI_SDK_PATH}/share/misc/config.sub . && \
   cp ${WASI_SDK_PATH}/share/misc/config.guess . && \
   autoconf -f && \
   ./configure --host=wasm32-wasi --build=x86_64-pc-linux-gnu \
               --with-build-python=${PYTHON_DIR}/inst/${PYTHON_VER}/bin/python${PYTHON_VER} \
               --disable-ipv6 --enable-big-digits=30 --with-suffix=.wasm \
               --with-freeze-module=./build/Programs/_freeze_module \
	       --prefix=/ --exec-prefix=/ && \
   make clean && \
   rm -f python.wasm && \
   make -j

rm -f "${PYTHON_DIR}/Modules/Setup.local"

cd ${PROJECT_DIR}

# This is needed when running unit tests.
mkdir -p tmp

# Reality check it
wasmtime run --mapdir=/::cpython --env PYTHONHOME=/ --env PYTHONPATH=/Lib --env PATH=/ \
	     -- cpython/python.wasm -V
