#!/bin/bash

#
# Environment variables for build configuration:
#
# WASI_SDK_PATH - The path to the WASI SDK tree.
# INSTALL_PREFIX - The path to install the WASI Python build.
# BUILD_PYTHON_DIR - The path to install the native Python build used by
#                    the build process. The default is to create a directory
#                    in /tmp/.
# INCLUDE_STDLIB - Should the standard library be included in the WASM file?
#                  This makes the WASM file more portable, but also increases
#                  the file size dramatically. If the stdlib is not included,
#                  you need to map the stdlib directory in the runtime
#                  environment so that Python has access to it when it runs.
# COMPILE_STDLIB - Should all of the files in the standard library be compiled
#                  before adding to the WASI Python binary? If these files are
#                  not compiled, you will need to specify the -B option when
#                  invoking WASM Python or use PYTHONDONTWRITEBYTECODE=1.
#

#set -x

WASI_SDK_PATH="${WASI_SDK_PATH:-/opt/wasi-sdk}"
PYTHON_DIR=cpython
WASI_ROOT=/opt
PROJECT_DIR=$(pwd)
INSTALL_PREFIX=/opt

if [[ ! -d "${PYTHON_DIR}" ]]; then
    git clone https://github.com/python/cpython.git
    PYTHON_DIR=cpython
fi

if [[ ! -d "${WASI_SDK_PATH}" ]]; then
    echo "ERROR: Could not find WASI SDK: ${WASI_SDK_PATH}"
    exit 1 
fi

# Get absolute paths of all components.
WASI_SDK_PATH=$(cd "${WASI_SDK_PATH}"; pwd)
PYTHON_DIR=$(cd "${PYTHON_DIR}"; pwd)
WASI_ROOT=$(cd "${WASI_ROOT}"; pwd)

# Check out Python version if requested
if [[ -n "${PYTHON_VER}" ]]; then
    $(cd "${PYTHON_DIR}" && git checkout "${PYTHON_VER}")
fi

# Determine Python version.
PYTHON_VER=$(grep '^VERSION=' "${PYTHON_DIR}/configure" | cut -d= -f2)
PYTHON_MAJOR=$(echo $PYTHON_VER | cut -d. -f1)
PYTHON_MINOR=$(echo $PYTHON_VER | cut -d. -f2)

BUILD_PYTHON_DIR="${BUILD_PYTHON_DIR:-/tmp/wasi-build-python${PYTHON_VER}}"

# Build Python for the build host first. This is required for various
# steps in the Makefile for cross-compiling.
PYTHON_VER=$(grep '^VERSION=' "${PYTHON_DIR}/configure" | cut -d= -f2)
if [[ ! -d "${BUILD_PYTHON_DIR}" ]]; then
    cd "${PYTHON_DIR}"
    rm -f Modules/Setup.local
    ./configure --disable-test-modules \
	        --with-ensurepip=yes \
	        --prefix="${BUILD_PYTHON_DIR}" \
	        --exec-prefix="${BUILD_PYTHON_DIR}" && \
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
    patch -p1 -N -r- < "${PROJECT_DIR}/patches/getpath.py.patch"
else
    export LIBS="-z stack-size=524288 -Wl,--stack-first -Wl,--initial-memory=10485760"

    cp "${PROJECT_DIR}/Setup.local" "${PYTHON_DIR}/Modules/Setup.local"

    # Apply patches
    patch -p1 -N -r- < ${PROJECT_DIR}/patches/configure.ac.patch

    if [[ -f "${PYTHON_DIR}/Modules/_zoneinfo.c" ]]; then
        patch -p1 -N -r- < "${PROJECT_DIR}/patches/_zoneinfo.c.patch"
    fi

    if [[ ("$PYTHON_MAJOR" -eq "3") && ("$PYTHON_MINOR" -le "8") ]]; then
        sed -i 's/_zoneinfo/#_zoneinfo/' "${PYTHON_DIR}/Modules/Setup.local"
        sed -i 's/_decimal/#_decimal/' "${PYTHON_DIR}/Modules/Setup.local"
    fi
fi

# Set compiler flags
export CC="clang --target=wasm32-wasi"
export CFLAGS="-g -D_WASI_EMULATED_GETPID -D_WASI_EMULATED_SIGNAL -D_WASI_EMULATED_PROCESS_CLOCKS -I/opt/include -I${WASI_ROOT}/include -isystem ${WASI_ROOT}/include -I${WASI_SDK_PATH}/share/wasi-sysroot/include -I${PROJECT_DIR}/docker/include --sysroot=${WASI_SDK_PATH}/share/wasi-sysroot"
export CPPFLAGS="${CFLAGS}"
export LIBS="${LIBS} -L/opt/lib -L${WASI_ROOT}/lib -lwasix -lwasi_vfs -L${WASI_SDK_PATH}/share/wasi-sysroot/lib/wasm32-wasi -lwasi-emulated-signal -L${PROJECT_DIR}/docker/lib --sysroot=${WASI_SDK_PATH}/share/wasi-sysroot"
export PATH=${BUILD_PYTHON_DIR}/bin:${PROJECT_DIR}/build/bin:${PATH}

# Override ld. This is called to build _ctype_test as a "shared module" which isn't supported.
mkdir -p "${PROJECT_DIR}/build/bin"
echo "wasm-ld ${LIBS} --no-entry \$*" > "${PROJECT_DIR}/build/bin/ld"
chmod +x "${PROJECT_DIR}/build/bin/ld"
echo "$(echo "$(which clang)" | xargs dirname)/readelf" > "${PROJECT_DIR}/build/bin/wasm32-wasi-readelf"
chmod +x "${PROJECT_DIR}/build/bin/wasm32-wasi-readelf"

# Configure and build
cp "${WASI_SDK_PATH}/share/misc/config.sub" . && \
   cp "${WASI_SDK_PATH}/share/misc/config.guess" . && \
   autoconf -f && \
   ./configure --host=wasm32-wasi --build=x86_64-pc-linux-gnu \
               --with-build-python="${BUILD_PYTHON_DIR}/bin/python${PYTHON_VER}" \
               --with-ensurepip=no \
               --disable-ipv6 --enable-big-digits=30 --with-suffix=.wasm \
               --with-freeze-module=./build/Programs/_freeze_module \
	       --prefix="${INSTALL_PREFIX}/wasi-python" && \
   make clean && \
   rm -f python.wasm && \
   make -j && \
   make install

rm -f "${PYTHON_DIR}/Modules/Setup.local"

cd ${PROJECT_DIR}

if [[ -f "${INSTALL_PREFIX}/wasi-python/bin/python${PYTHON_VER}.wasm" ]]; then
   if [[ -z "$INCLUDE_STDLIB" || "$INCLUDE_STDLIB" -eq "1" ]]; then
      echo "INCLUDING STDLIB"
      if [[ -z "$COMPILE_STDLIB" || "$COMPILE_STDLIB" -eq "1" ]]; then
         echo "COMPILING STDLIB"
         "${BUILD_PYTHON_DIR}/bin/python3" -m compileall "${INSTALL_PREFIX}/wasi-python/lib/python${PYTHON_VER}"
         "${BUILD_PYTHON_DIR}/bin/python3" "${PROJECT_DIR}/clear-uncompiled-pys.py" "${INSTALL_PREFIX}/wasi-python/lib/python${PYTHON_VER}"
      fi
      wasi-vfs pack "${INSTALL_PREFIX}/wasi-python/bin/python${PYTHON_VER}.wasm" --mapdir "${INSTALL_PREFIX}/wasi-python/lib/python${PYTHON_VER}::${INSTALL_PREFIX}/wasi-python/lib/python${PYTHON_VER}" --output "wasi-python${PYTHON_VER}.wasm"
   else
      ln -sf "${INSTALL_PREFIX}/wasi-python/bin/python${PYTHON_VER}.wasm" "wasi-python${PYTHON_VER}.wasm"
   fi
fi

# Test built package
if [[ -f "wasi-python${PYTHON_VER}.wasm" ]]; then
    # Reality check it
    wasmtime run -- "wasi-python${PYTHON_VER}.wasm" -V
else
    echo "ERROR: No Python build was found."
fi
