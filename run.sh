#!/bin/bash

#set -x

WASI_SDK_PATH="${WASI_SDK_PATH:-/opt/wasi-sdk}"
PYTHON_DIR=cpython
WASIX_DIR=wasix
PROJECT_DIR=$(pwd)
INSTALL_PREFIX=$(pwd)/opt

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

cd ${PYTHON_DIR}

# Configure Python build. Python 3.11+ autodetects modules.
export CONFIG_SITE="${PROJECT_DIR}/config.site"
if [[ ("$PYTHON_MAJOR" -ge "3") && ("$PYTHON_MINOR" -ge "11") ]]; then
    rm -f "${PYTHON_DIR}/Modules/Setup.local"
    patch -p1 -N -r- < ${PROJECT_DIR}/patches/getpath.py.patch
else
    export LIBS="-Wl,--stack-first -Wl,-z,stack-size=83886080"

    cp "${PROJECT_DIR}/Setup.local" "${PYTHON_DIR}/Modules/Setup.local"

    # Apply patches
    patch -p1 -N -r- < ${PROJECT_DIR}/patches/configure.ac.patch

    if [[ -f "${PYTHON_DIR}/Modules/_zoneinfo.c" ]]; then
        patch -p1 -N -r- < ${PROJECT_DIR}/patches/_zoneinfo.c.patch
    fi

    if [[ ("$PYTHON_MAJOR" -eq "3") && ("$PYTHON_MINOR" -le "8") ]]; then
        sed -i 's/_zoneinfo/#_zoneinfo/' "${PYTHON_DIR}/Modules/Setup.local"
        sed -i 's/_decimal/#_decimal/' "${PYTHON_DIR}/Modules/Setup.local"
    fi
fi

# Set compiler flags
export CC="clang --target=wasm32-wasi"
export CFLAGS="-g -D_WASI_EMULATED_GETPID -D_WASI_EMULATED_SIGNAL -D_WASI_EMULATED_PROCESS_CLOCKS -I/opt/include -I${WASIX_DIR}/include -isystem ${WASIX_DIR}/include -I${WASI_SDK_PATH}/share/wasi-sysroot/include -I${PROJECT_DIR}/docker/include --sysroot=${WASI_SDK_PATH}/share/wasi-sysroot"
export CPPFLAGS="${CFLAGS}"
export LIBS="${LIBS} -L/opt/lib -L${WASIX_DIR} -lwasix -L${WASI_SDK_PATH}/share/wasi-sysroot/lib/wasm32-wasi -lwasi-emulated-signal -L${PROJECT_DIR}/docker/lib --sysroot=${WASI_SDK_PATH}/share/wasi-sysroot"
export PATH=${PYTHON_DIR}/inst/${PYTHON_VER}/bin:${PROJECT_DIR}/build/bin:${PATH}

# Override ld. This is called to build _ctype_test as a "shared module" which isn't supported.
mkdir -p "${PROJECT_DIR}/build/bin"
echo "wasm-ld ${LIBS} --no-entry \$*" > "${PROJECT_DIR}/build/bin/ld"
chmod +x "${PROJECT_DIR}/build/bin/ld"
echo "$(echo "$(which clang)" | xargs dirname)/readelf" > "${PROJECT_DIR}/build/bin/wasm32-wasi-readelf"
chmod +x "${PROJECT_DIR}/build/bin/wasm32-wasi-readelf"

# Configure and build
cp ${WASI_SDK_PATH}/share/misc/config.sub . && \
   cp ${WASI_SDK_PATH}/share/misc/config.guess . && \
   autoconf -f && \
   ./configure --host=wasm32-wasi --build=x86_64-pc-linux-gnu \
               --with-build-python=${PYTHON_DIR}/inst/${PYTHON_VER}/bin/python${PYTHON_VER} \
               --with-ensurepip=no \
               --disable-ipv6 --enable-big-digits=30 --with-suffix=.wasm \
               --with-freeze-module=./build/Programs/_freeze_module \
	       --prefix=${INSTALL_PREFIX}/wasi-python && \
   make clean && \
   rm -f python.wasm && \
   make -j && \
   make install

rm -f "${PYTHON_DIR}/Modules/Setup.local"

cd ${PROJECT_DIR}

# Package wasi-python and wasix libraries
if [[ -f "${INSTALL_PREFIX}/wasi-python/bin/python${PYTHON_VER}.wasm" ]]; then
    tar zcvf ${PROJECT_DIR}/wasi-python.tgz ${INSTALL_PREFIX}/wasi-python

    mkdir -p ${INSTALL_PREFIX}/wasix/lib && \
        cp -R ${WASIX_DIR}/include ${INSTALL_PREFIX}/wasix/. && \
        cp ${WASIX_DIR}/libwasix.a ${INSTALL_PREFIX}/wasix/lib/. && \
        tar zcvf ${PROJECT_DIR}/wasix.tgz ${INSTALL_PREFIX}/wasix

    # Reality check it
    wasmtime run --mapdir=${INSTALL_PREFIX}/wasi-python::${INSTALL_PREFIX}/wasi-python \
    	         --env PATH=${INSTALL_PREFIX}/wasi-python/bin \
    	         -- ${INSTALL_PREFIX}/wasi-python/bin/python${PYTHON_VER}.wasm -V
else
    echo "ERROR: No Python build was found."
fi
