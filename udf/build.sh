#!/bin/bash

export WASI_SDK_PATH=/opt/wasi-sdk
export PYTHON_ROOT=/opt/wasi-python
export PYTHON_VERSION=3.10
export WASI_ROOT=/opt
export PROJECT_DIR=$(pwd)
export PYTHON="/tmp/wasi-build-python${PYTHON_VERSION}/bin/python3"

${WASI_SDK_PATH}/bin/clang --target=wasm32-unknown-wasi \
      -mexec-model=reactor \
      -g \
      -D_WASI_EMULATED_GETPID \
      -D_WASI_EMULATED_SIGNAL \
      -D_WASI_EMULATED_PROCESS_CLOCKS \
      -I. \
      -I${WASI_ROOT}/include \
      -I../cpython/Include \
      -I../cpython \
      -isystem ${WASI_ROOT}/include \
      -Wl,--stack-first \
      -Wl,-z,stack-size=83886080 \
      -L${WASI_ROOT}/lib \
      -lwasix \
      -lwasi_vfs \
      -lwasi-emulated-signal \
      -lpthread -lm -luuid -lsqlite3 -lbz2 -lz -llzma -lm \
      udf.c udf_impl.c \
      ../cpython/libpython${PYTHON_VERSION}.a \
      -o udf-python${PYTHON_VERSION}.wasm

# Download packaged libraries
export SITE_PACKAGES="/tmp/wasi-udf-python${PYTHON_VERSION}"
mkdir -p "${SITE_PACKAGES}"
$PYTHON -m pip install --prefix "${SITE_PACKAGES}" msgpack

# Compile lib directory files
${PYTHON} -m compileall "${SITE_PACKAGES}"
${PYTHON} ../clear-uncompiled-pys.py "${SITE_PACKAGES}"

# Add lib, app, and standard library files
wasi-vfs pack udf-python${PYTHON_VERSION}.wasm \
    --mapdir "${PYTHON_ROOT}/lib/python${PYTHON_VERSION}::${PYTHON_ROOT}/lib/python${PYTHON_VERSION}" \
    --mapdir "${PYTHON_ROOT}/lib/python${PYTHON_VERSION}/site-packages::${SITE_PACKAGES}/lib/python${PYTHON_VERSION}/site-packages" \
    --mapdir "/app::./app" \
    --output s2-udf-python${PYTHON_VERSION}.wasm

