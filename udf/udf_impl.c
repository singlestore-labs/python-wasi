#define PY_SSIZE_T_CLEAN
#include <Python.h>
#include "udf.h"
#include <stddef.h>

static PyObject *main_mod;
static PyObject *msgpack_mod;
static PyObject *pack;
static PyObject *unpack;

int find_func_name(char *path, int path_l)
//
// Find the last '.' in the given path
//
// Parameters
// ----------
// path : string
//     Period-delimited string containing the absolute path to
//     a Python function
// path_l : int
//     The length of `path`
//
// Returns
// -------
// int : the position of the last '.' in the string, or zero if
//       there is no '.'
//
{
    for (int i = path_l - 1; i > 0; i--)
    {
        if (path[i] == '.')
        {
            return i + 1;
        }
    }
    return 0;
}

static int initialize()
//
// Initialize the Python interpreter
//
// Returns
// -------
// int : 0 for success, -1 for error
//
{
    int rc = 0;
    PyObject *py_msgpack_str = NULL;
    PyObject *py_main_str = NULL;

    if (Py_IsInitialized()) return 0;

    Py_SetProgramName(Py_DecodeLocale("python", NULL));
    Py_Initialize();

    // Add /lib and /app to PYTHONPATH
    const char *c = "import sys\n"
                    "sys.path.insert(0, '/app')\n";
    rc = PyRun_SimpleString(c);
    if (rc) goto error;

    py_msgpack_str = PyUnicode_FromString("msgpack");
    if (!py_msgpack_str) goto error;

    msgpack_mod = PyImport_Import(py_msgpack_str);
    if (!msgpack_mod) goto error;

    pack = PyObject_GetAttrString(msgpack_mod, "packb");
    if (!pack) goto error;

    unpack = PyObject_GetAttrString(msgpack_mod, "unpackb");
    if (!pack) goto error;

    py_main_str = PyUnicode_FromString("__main__");
    if (!py_main_str) goto error;

    main_mod = PyImport_Import(py_main_str);
    if (!main_mod) goto error;

exit:
    Py_XDECREF(py_msgpack_str);
    Py_XDECREF(py_main_str);

    return rc;

error:
    if (PyErr_Occurred())
    {
        PyErr_Print();
    }
    rc = -1;
    goto exit;
}

int udf_exec(udf_string_t *code)
//
// Execute arbitrary code
//
// Parameters
// ----------
// code : string
//     The code to execute
//
// Returns
// -------
// int : 0 for success, -1 for error
//
{
    int rc = 0;
    char *c = malloc(code->len + 1);
    memcpy(c, code->ptr, code->len);
    c[code->len] = '\0';

    if (initialize()) goto error;

    rc = PyRun_SimpleString(c);

exit:
    if (c) free(c);
    return rc;

error:
    if (PyErr_Occurred())
    {
        PyErr_Print();
    }
    rc = -1;
    goto exit;
}

void udf_call(udf_string_t *name, udf_list_u8_t *args, udf_list_u8_t *ret)
//
// Call a function with the given arguments
//
// Parameters
// ----------
// name : string
//     Absolute path to a function. For example, `urllib.parse.urlparse`.
// args : bytes
//     MessagePack blob of function arguments
//
// Returns
// -------
// ret : MessagePack blob of function return values
//
{
    PyObject *py_func_pkg_str = NULL;
    PyObject *py_func_pkg = NULL;
    PyObject *py_func_str = NULL;
    PyObject *py_func = NULL;
    PyObject *py_func_args = NULL;
    PyObject *py_func_args_tuple = NULL;
    PyObject *py_args_bytes = NULL;
    PyObject *py_result = NULL;
    PyObject *py_out = NULL;
    PyObject *py_list = NULL;

    if (initialize()) goto error;

    if (!pack || !unpack) 
    {
        fprintf(stderr, "msgpack is not available\n");
        goto error;
    }

    // Import function module and function
    int pos = find_func_name(name->ptr, name->len);
    if (pos > 0)
    {
        py_func_pkg_str = PyUnicode_FromStringAndSize((char*)name->ptr, pos - 1);
        if (!py_func_pkg_str) goto error;
        py_func_pkg = PyImport_Import(py_func_pkg_str);
        if (!py_func_pkg) goto error;
        py_func_str = PyUnicode_FromStringAndSize((char*)name->ptr + pos, name->len - pos);
        if (!py_func_str) goto error;
    }
    else
    {
        py_func_pkg = main_mod;
    }

    // Convert raw args to Python bytes
    py_args_bytes = PyBytes_FromStringAndSize((char*)args->ptr, args->len);
    if (!py_args_bytes) goto error;

    // Unpack function arguments
    py_func_args = PyObject_CallOneArg(unpack, py_args_bytes);
    if (!py_func_args) goto error;

    // Look up the udf and call it
    py_func = PyObject_GetAttr(py_func_pkg, py_func_str);
    if (!py_func) goto error;

    // Call the function
    py_func_args_tuple = PyList_AsTuple(py_func_args);
    if (!py_func_args_tuple) goto error;
    py_result = PyObject_CallObject(py_func, py_func_args_tuple);
    if (!py_result) goto error;

    if (PyTuple_Check(py_result))
    {
        // Pack the result as multiple return values
        py_out = PyObject_CallOneArg(pack, py_result);
        if (!py_out) goto error;
    }
    else
    {
        py_list = PyList_New(1);
        PyList_SetItem(py_list, 0, py_result);
        py_result = NULL;
        // Pack the result as a single value
        py_out = PyObject_CallOneArg(pack, py_list);
        if (!py_out) goto error;
    }

    // Copy packed result to output
    ret->len = PyBytes_Size(py_out);
    ret->ptr = malloc(ret->len);
    if (!ret->ptr)
    {
        fprintf(stderr, "Could not allocate memory for return value\n");
        goto error;
    }
    memcpy(ret->ptr, PyBytes_AsString(py_out), ret->len);

exit:
    Py_XDECREF(py_func_pkg_str);
    Py_XDECREF(py_func_pkg);
    Py_XDECREF(py_func_str);
    Py_XDECREF(py_func);
    Py_XDECREF(py_args_bytes);
    Py_XDECREF(py_func_args);
    Py_XDECREF(py_func_args_tuple);
    Py_XDECREF(py_result);
    Py_XDECREF(py_out);
    Py_XDECREF(py_list);
    return;

error:
    if (PyErr_Occurred())
    {
        PyErr_Print();
    }
    ret->ptr = NULL;
    ret->len = 0;
    goto exit;
}
