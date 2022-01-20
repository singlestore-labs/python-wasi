#!/bin/bash

cd cpython &&
    git checkout Lib/subprocess.py \
                 Lib/test/test_posix.py \
		 Modules/_zoneinfo.c \
		 configure \
		 configure.ac
