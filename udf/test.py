#!/usr/bin/env python3

import msgpack
import wasmtime
from bindings import Udf

store = wasmtime.Store()

module = wasmtime.Module(store.engine, open('s2-udf-python3.10.wasm', 'rb').read())

linker = wasmtime.Linker(store.engine)
linker.define_wasi()

wasi = wasmtime.WasiConfig()
wasi.inherit_stdin()
wasi.inherit_stdout()
wasi.inherit_stderr()
wasi.env = [('PYTHONDONTWRITEBYTECODE', 'x')]
store.set_wasi(wasi)

udf = Udf(store, linker, module)

# You *must* call _initialize for wasi to work
udf.instance.exports(store)['_initialize'](store)

out = udf.exec(store, 'import sys; print(sys.path)')
print(out)

out = udf.call(store, 'math.sqrt', msgpack.packb([2]))
print(out)
print(msgpack.unpackb(out))

out = udf.call(store, 'main.foo', msgpack.packb(['hi there']))
print(out)
print(msgpack.unpackb(out))
