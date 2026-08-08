# Luau Binary Serializer

Luau Binary Serializer compresses your Roblox data tables into compact, lightweight binary streams. Built entirely on Roblox's native `buffer` API, this module provides a fast, bandwidth-friendly alternative to standard JSON formatting.

You can use this tool to optimize network payloads sent over `RemoteEvents` or to reduce character usage when saving data to `DataStores`.

## Features

* **Native Buffer Implementation:** Bypasses table-generation overhead by reading and writing bytes directly.
* **Smart Numeric Packing:** Automatically selects the smallest numeric representation (u8, i16, i32, or f64) based on the value to minimize file size.
* **Varint Support:** Uses Variable-length Quantity encoding to represent string lengths and table indices using the fewest bytes possible.
* **Roblox Type Support:** Serializes `nil`, `boolean`, `number`, `string`, `table`, `Vector3`, and `CFrame` values natively.
* **Integrated Base64 Utilities:** Encodes binary buffers to safe ASCII strings for direct compatibility with Roblox DataStores.

## Installation

### Manual Installation

1. Copy the source code from `src/BinarySerializer.luau`.
2. Create a `ModuleScript` inside `ReplicatedStorage` and name it `BinarySerializer`.
3. Paste the code directly into that script.

### Rojo Setup

Place the `src` folder inside your project directory and map it in your `default.project.json` file:

```json
"ReplicatedStorage": {
  "BinarySerializer": {
    "$path": "src/BinarySerializer.luau"
  }
}
```

# API Reference

This document provides a detailed technical overview of the functions available in the `BinarySerializer` module.

## Core Functions

### `Serializer.serialize`

```luau
function Serializer.serialize(value: any, initialCapacity: number?): buffer
```

Serializes any supported Luau data type into a binary buffer.

* **Arguments:**
  * `value`: The data to serialize. Supported types include `nil`, `boolean`, `number`, `string`, `table`, `Vector3`, and `CFrame`.
  * `initialCapacity` *(Optional)*: A finite, non-negative byte count for the initial buffer. Providing a size close to your final payload size improves performance by preventing dynamic buffer reallocations. Values below `16` are raised to `16`. Defaults to `128` bytes.
* **Returns:**
  * `buffer`: A Luau buffer containing your serialized binary data, sized exactly to the payload.
* **Raises:**
  * Raises an error if the value contains unsupported types (e.g., Instances, functions), if table nesting exceeds `32` levels (which is also what stops cyclic references), or if `initialCapacity` is negative, `NaN`, or infinite.

---

### `Serializer.deserialize`

```luau
function Serializer.deserialize(buf: buffer): any
```

Restores a payload previously produced by `Serializer.serialize`.

* **Arguments:**
  * `buf`: The binary Luau buffer containing the serialized data.
* **Returns:**
  * `any`: The restored data payload (e.g., table, string, Vector3).
* **Raises:**
  * Raises an error if the argument is not a buffer, or if the buffer is truncated, corrupted, or contains unrecognized type tags.

Deserialization is safe to point at untrusted input, such as buffers arriving from a client. Declared table sizes and string lengths are validated against the bytes that actually remain, nesting is capped at the same `32` levels as the writer, and malformed input always raises rather than hanging or over-allocating. Wrap the call in `pcall` and validate the resulting shape before use.

---

## Base64 Utilities

Use these utility functions to prepare your binary payloads for storage engines like Roblox `DataStoreService` that accept only string formats.

### `Serializer.toBase64`

```luau
function Serializer.toBase64(buf: buffer): string
```

Encodes a binary buffer as standard Base64 (alphabet `A-Za-z0-9+/`, `=` padding).

* **Arguments:**
  * `buf`: The binary buffer to encode.
* **Returns:**
  * `string`: The Base64 representation, always a multiple of four characters.

---

### `Serializer.fromBase64`

```luau
function Serializer.fromBase64(s: string): buffer
```

* **Arguments:**
  * `s`: The Base64 string to decode. Trailing `=` padding is optional; any other character, including whitespace and `=` in the middle of the string, is rejected.
* **Returns:**
  * `buffer`: The reconstructed binary buffer, ready for `Serializer.deserialize`.
* **Raises:**
  * Raises an error if the argument is not a string, contains a character outside the Base64 alphabet, or has a length that cannot occur in valid Base64.

---

## Diagnostics

### `Serializer.selfTest`

```luau
function Serializer.selfTest(): boolean
```

Runs a diagnostic suite on the module using a predefined dataset containing mixed types (numbers, nested tables, Vector3, and CFrames), plus numeric boundaries, sparse arrays, Base64 padding cases, and malformed input that must be rejected.

* **Returns:**
  * `true` if every check passes.
* **Behavior:**
  * Prints the payload and Base64 sizes to the output console. Raises an assertion error naming the first check that fails.
