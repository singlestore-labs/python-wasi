#!/usr/bin/env python3

import glob
import os
import shutil
import sys

for root, dirs, files in os.walk(sys.argv[1]):
    for f in files:
        if not f.endswith('.py'):
            continue
        basename = os.path.splitext(f)[0]
        if glob.glob(os.path.join(root, '__pycache__', basename + '.cpython-*.pyc')):
            for g in glob.glob(os.path.join(root, '__pycache__', basename + '.cpython-*.opt-*.pyc')):
                shutil.move(g, os.path.join(root, f + 'c'))
            for g in glob.glob(os.path.join(root, '__pycache__', basename + '.cpython-*.pyc')):
                shutil.move(g, os.path.join(root, f + 'c'))
            if os.path.isfile(os.path.join(root, f)) and os.path.isfile(os.path.join(root, f + 'c')):
                os.remove(os.path.join(root, f))
