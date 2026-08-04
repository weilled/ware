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
  * `initialCapacity` *(Optional)*: An integer specifying the initial size of the buffer in bytes. Providing a size close to your final payload size improves performance by preventing dynamic buffer reallocations. Defaults to `128` bytes.
* **Returns:**
  * `buffer`: A read-only Luau buffer containing your serialized binary data.
* **Raises:**
  * Raises an error if the value contains unsupported types (e.g., Instances, functions) or exceeds the maximum nested table depth of `32`.

---

### `Serializer.deserialize`

```luau
function Serializer.deserialize(buf: buffer): any
```

* **Arguments:**
  * `buf`: The binary Luau buffer containing the serialized data.
* **Returns:**
  * `any`: The restored data payload (e.g., table, string, Vector3).
* **Raises:**
  * Raises an error if the buffer contains corrupted data or unrecognized type tags.

---

## Base64 Utilities

Use these utility functions to prepare your binary payloads for storage engines like Roblox `DataStoreService` that accept only string formats.

### `Serializer.toBase64`

```luau
function Serializer.toBase64(buf: buffer): string
```

### `Serializer.fromBase64`

```luau
function Serializer.fromBase64(s: string): buffer
```

* **Arguments:**
  * `s`: The Base64 string to decode.
* **Returns:**
  * `buffer`: The reconstructed binary buffer, ready for `Serializer.deserialize`.

---

## Diagnostics

### `Serializer.selfTest`

```luau
function Serializer.selfTest(): boolean
```

Runs a diagnostic suite on the module using a predefined dataset containing mixed types (numbers, nested tables, Vector3, and CFrames).

* **Returns:**
  * `true` if all serialization, deserialization, and Base64 tests pass successfully.
* **Behavior:**
  * Prints diagnostic information to the output console, including final byte sizes compared with an equivalent JSON representation. Raises an assertion error if any validation step fails.
