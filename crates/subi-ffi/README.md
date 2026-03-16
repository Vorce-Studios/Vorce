# subi-ffi

**SubI C/C++ Foreign Function Interface.**

`subi-ffi` provides C-compatible bindings for the SubI core, enabling integration with legacy C++ applications or other languages.

## Purpose

Originally designed to bridge the gap between the legacy Qt/C++ application and the new Rust core.
As the Rust rewrite (`subi`) becomes the primary application, this crate serves as an integration point for external systems.

## Features

- **C Header Generation:** Uses `cbindgen` to generate `subi.h`.
- **Stable ABI:** Exposes a C-compatible API for core functionality.
