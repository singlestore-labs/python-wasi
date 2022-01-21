#!/bin/bash

cd cpython && git checkout Modules/_zoneinfo.c \
                           configure \
                           configure.ac
