FROM debian:bullseye

RUN apt-get update && apt-get install -y \
    wget \
    curl \
    lsb-release \
    software-properties-common \
    gnupg \
    vim \
    build-essential \
    libc6-dev \
    libtinfo5 \
    libxkbcommon-dev \
    m4 \
    zip \
    git \
    cmake \
    ninja-build

# WASI SDK
RUN cd /opt && \
    wget https://github.com/WebAssembly/wasi-sdk/releases/download/wasi-sdk-16/wasi-sdk-16.0-linux.tar.gz && \
    tar zxvf *.tar.gz && \
    rm *.tar.gz && \
    ln -s /opt/wasi-sdk-16.0 /opt/wasi-sdk

# Python checks for this, but doesn't seem to use it.
RUN touch /opt/wasi-sdk-16.0/bin/wasm32-wasi-readelf && \
    chmod +x /opt/wasi-sdk-16.0/bin/wasm32-wasi-readelf

# Autoconf
RUN cd /tmp && \
    wget http://ftp.gnu.org/gnu/autoconf/autoconf-2.71.tar.gz && \
    tar zxvf autoconf-*.tar.gz && \
    cd autoconf-* && \
    ./configure && make && make install

RUN cd /tmp && \
    wget http://ftp.gnu.org/gnu/automake/automake-1.16.tar.gz && \
    tar zxvf automake-*.tar.gz && \
    cd automake-* && \
    ./configure && make && make install

# WASM tools
RUN curl https://wasmtime.dev/install.sh -sSf | bash
RUN curl https://get.wasmer.io -sSfL | sh
RUN cd /opt && \
    git clone --recursive https://github.com/WebAssembly/wabt && \
    cd wabt && \
    git submodule update --init
RUN cd /opt/wabt && mkdir build && cd build && cmake .. && cmake --build .

RUN mkdir /opt/lib
RUN mkdir /opt/include

# WASI VFS
RUN cd /tmp && \
    wget https://github.com/kateinoigakukun/wasi-vfs/releases/download/v0.2.0/wasi-vfs-cli-x86_64-unknown-linux-gnu.zip && \
    unzip wasi-vfs-cli-x86_64-unknown-linux-gnu.zip && \
    mv wasi-vfs /usr/local/bin/wasi-vfs
RUN cd /tmp && \
    wget https://github.com/kateinoigakukun/wasi-vfs/releases/download/v0.2.0/libwasi_vfs-wasm32-unknown-unknown.zip && \
    unzip libwasi_vfs-wasm32-unknown-unknown.zip && \
    mv libwasi_vfs.a /opt/lib/libwasi_vfs.a

# Files for 3rd party Python modules.
COPY lib/* /opt/lib/
COPY include/* /opt/include/
RUN mkdir -p /opt/include/lzma
COPY include/lzma/* /opt/include/lzma/

ENV PATH=/opt/wasi-sdk/bin:/root/.wasmer/bin:/opt/wabt/build:${PATH}
ENV WASMTIME_BACKTRACE_DETAILS=1
ENV WASI_SDK_PATH=/opt/wasi-sdk
