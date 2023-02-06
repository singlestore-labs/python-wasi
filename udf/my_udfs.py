#!/usr/bin/env python

import sys
import difflib
import __main__ as main


def multiply(a: int, b: int, c: float) -> (float, int, float, str):
    """ Multiply inputs and return some other junk """
    return a * b * c, 1993, 120.12, 'Life, uh... finds a way.'


def unified_diff(a: str, b: str) -> str:
    """ Return a unified diff of the two input strings """
    return ''.join(difflib.unified_diff(
        a.splitlines(True), b.splitlines(True),
        fromfile='before', tofile='after', n=5))


def call_loaded():
    """ Call a function loaded globally """
    main.sneak_attack()
