local Serializer = {}

local TAG_NIL = 0
local TAG_FALSE = 1
local TAG_TRUE = 2
local TAG_U8 = 3
local TAG_I16 = 4
local TAG_I32 = 5
local TAG_F64 = 6
local TAG_STRING = 7
local TAG_TABLE = 8
local TAG_VECTOR3 = 9
local TAG_CFRAME = 10

local MAX_DEPTH = 32
local MAX_VARINT_BYTES = 5
local DEFAULT_CAPACITY = 128
local MIN_CAPACITY = 16

type Writer = { buf: buffer, cursor: number, capacity: number }

local function writerNew(initialCapacity: number?): Writer
	local cap = DEFAULT_CAPACITY
	if initialCapacity ~= nil then
		if
			type(initialCapacity) ~= "number"
			or initialCapacity ~= initialCapacity
			or initialCapacity < 0
			or initialCapacity == math.huge
		then
			error("BinarySerializer: initialCapacity must be a finite non-negative number")
		end
		cap = math.max(MIN_CAPACITY, math.floor(initialCapacity))
	end
	return { buf = buffer.create(cap), cursor = 0, capacity = cap }
end

local function writerEnsure(w: Writer, bytes: number)
	local needed = w.cursor + bytes
	if needed <= w.capacity then
		return
	end
	local newCap = w.capacity * 2
	if newCap < needed then
		newCap = needed
	end
	local newBuf = buffer.create(newCap)
	buffer.copy(newBuf, 0, w.buf, 0, w.cursor)
	w.buf = newBuf
	w.capacity = newCap
end

local function writeU8(w: Writer, v: number)
	writerEnsure(w, 1)
	buffer.writeu8(w.buf, w.cursor, v)
	w.cursor += 1
end

local function writeI16(w: Writer, v: number)
	writerEnsure(w, 2)
	buffer.writei16(w.buf, w.cursor, v)
	w.cursor += 2
end

local function writeI32(w: Writer, v: number)
	writerEnsure(w, 4)
	buffer.writei32(w.buf, w.cursor, v)
	w.cursor += 4
end

local function writeF32(w: Writer, v: number)
	writerEnsure(w, 4)
	buffer.writef32(w.buf, w.cursor, v)
	w.cursor += 4
end

local function writeF64(w: Writer, v: number)
	writerEnsure(w, 8)
	buffer.writef64(w.buf, w.cursor, v)
	w.cursor += 8
end

local function writeVarint(w: Writer, v: number)
	while v >= 0x80 do
		writeU8(w, bit32.bor(bit32.band(v, 0x7F), 0x80))
		v = bit32.rshift(v, 7)
	end
	writeU8(w, v)
end

local function writeString(w: Writer, s: string)
	local len = #s
	writeVarint(w, len)
	writerEnsure(w, len)
	buffer.writestring(w.buf, w.cursor, s)
	w.cursor += len
end

type Reader = { buf: buffer, cursor: number, len: number, depth: number }

local function readU8(r: Reader): number
	local at = r.cursor
	r.cursor = at + 1
	return buffer.readu8(r.buf, at)
end

local function readI16(r: Reader): number
	local at = r.cursor
	r.cursor = at + 2
	return buffer.readi16(r.buf, at)
end

local function readI32(r: Reader): number
	local at = r.cursor
	r.cursor = at + 4
	return buffer.readi32(r.buf, at)
end

local function readF32(r: Reader): number
	local at = r.cursor
	r.cursor = at + 4
	return buffer.readf32(r.buf, at)
end

local function readF64(r: Reader): number
	local at = r.cursor
	r.cursor = at + 8
	return buffer.readf64(r.buf, at)
end

local function readVarint(r: Reader): number
	local b = readU8(r)
	if b < 0x80 then
		return b
	end

	local result = b - 0x80
	local shift = 7
	for _ = 2, MAX_VARINT_BYTES do
		b = readU8(r)
		if shift == 28 and b > 0x0F then
			error(`BinarySerializer: varint overflows 32 bits at offset {r.cursor - 1}`)
		end
		result = bit32.bor(result, bit32.lshift(bit32.band(b, 0x7F), shift))
		if b < 0x80 then
			return result
		end
		shift += 7
	end
	error(`BinarySerializer: malformed varint at offset {r.cursor - MAX_VARINT_BYTES}`)
end

local function readString(r: Reader): string
	local len = readVarint(r)
	local at = r.cursor
	if at + len > r.len then
		error(
			`BinarySerializer: string of {len} bytes at offset {at} exceeds the buffer `
				.. `({r.len - at} bytes remain)`
		)
	end
	r.cursor = at + len
	return buffer.readstring(r.buf, at, len)
end

local writeValue

local function writeNumber(w: Writer, n: number)
	if n % 1 == 0 then
		if n >= 0 and n <= 255 then
			writeU8(w, TAG_U8)
			writeU8(w, n)
			return
		elseif n >= -32768 and n <= 32767 then
			writeU8(w, TAG_I16)
			writeI16(w, n)
			return
		elseif n >= -2147483648 and n <= 2147483647 then
			writeU8(w, TAG_I32)
			writeI32(w, n)
			return
		end
	end
	writeU8(w, TAG_F64)
	writeF64(w, n)
end

local function writeTable(w: Writer, t: { [any]: any }, depth: number)
	if depth > MAX_DEPTH then
		error(`BinarySerializer: table nesting exceeds {MAX_DEPTH} levels (cyclic reference?)`)
	end

	local arrayLen = 0
	while t[arrayLen + 1] ~= nil do
		arrayLen += 1
	end

	local dictCount = 0
	for k in pairs(t) do
		if type(k) ~= "number" or k % 1 ~= 0 or k < 1 or k > arrayLen then
			dictCount += 1
		end
	end

	writeU8(w, TAG_TABLE)
	writeVarint(w, arrayLen)
	writeVarint(w, dictCount)

	for i = 1, arrayLen do
		writeValue(w, t[i], depth)
	end

	for k, v in pairs(t) do
		if type(k) ~= "number" or k % 1 ~= 0 or k < 1 or k > arrayLen then
			writeValue(w, k, depth)
			writeValue(w, v, depth)
		end
	end
end

writeValue = function(w: Writer, v: any, depth: number)
	local t = typeof(v)

	if t == "nil" then
		writeU8(w, TAG_NIL)
	elseif t == "boolean" then
		writeU8(w, if v then TAG_TRUE else TAG_FALSE)
	elseif t == "number" then
		writeNumber(w, v)
	elseif t == "string" then
		writeU8(w, TAG_STRING)
		writeString(w, v)
	elseif t == "table" then
		writeTable(w, v, depth + 1)
	elseif t == "Vector3" then
		writeU8(w, TAG_VECTOR3)
		writeF32(w, v.X)
		writeF32(w, v.Y)
		writeF32(w, v.Z)
	elseif t == "CFrame" then
		writeU8(w, TAG_CFRAME)
		local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = v:GetComponents()
		writeF32(w, x)
		writeF32(w, y)
		writeF32(w, z)
		writeF32(w, r00)
		writeF32(w, r01)
		writeF32(w, r02)
		writeF32(w, r10)
		writeF32(w, r11)
		writeF32(w, r12)
		writeF32(w, r20)
		writeF32(w, r21)
		writeF32(w, r22)
	else
		error(`BinarySerializer: unsupported type "{t}"`)
	end
end

local readValue

local function readTable(r: Reader): { [any]: any }
	local depth = r.depth + 1
	if depth > MAX_DEPTH then
		error(`BinarySerializer: table nesting exceeds {MAX_DEPTH} levels at offset {r.cursor}`)
	end
	r.depth = depth

	local arrayLen = readVarint(r)
	local dictCount = readVarint(r)

	local available = r.len - r.cursor
	if arrayLen + dictCount * 2 > available then
		error(
			`BinarySerializer: table header declares {arrayLen} array and {dictCount} dictionary entries `
				.. `but only {available} bytes remain at offset {r.cursor}`
		)
	end

	local t: { [any]: any } = table.create(arrayLen)

	for i = 1, arrayLen do
		t[i] = readValue(r)
	end

	for _ = 1, dictCount do
		local k = readValue(r)
		local v = readValue(r)
		if k == nil then
			error(`BinarySerializer: nil table key at offset {r.cursor}`)
		elseif k ~= k then
			error(`BinarySerializer: NaN table key at offset {r.cursor}`)
		end
		t[k] = v
	end

	r.depth = depth - 1
	return t
end

readValue = function(r: Reader): any
	local tag = readU8(r)

	if tag == TAG_NIL then
		return nil
	elseif tag == TAG_FALSE then
		return false
	elseif tag == TAG_TRUE then
		return true
	elseif tag == TAG_U8 then
		return readU8(r)
	elseif tag == TAG_I16 then
		return readI16(r)
	elseif tag == TAG_I32 then
		return readI32(r)
	elseif tag == TAG_F64 then
		return readF64(r)
	elseif tag == TAG_STRING then
		return readString(r)
	elseif tag == TAG_TABLE then
		return readTable(r)
	elseif tag == TAG_VECTOR3 then
		local x = readF32(r)
		local y = readF32(r)
		local z = readF32(r)
		return Vector3.new(x, y, z)
	elseif tag == TAG_CFRAME then
		local x = readF32(r)
		local y = readF32(r)
		local z = readF32(r)
		local r00 = readF32(r)
		local r01 = readF32(r)
		local r02 = readF32(r)
		local r10 = readF32(r)
		local r11 = readF32(r)
		local r12 = readF32(r)
		local r20 = readF32(r)
		local r21 = readF32(r)
		local r22 = readF32(r)
		return CFrame.new(x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22)
	end

	error(`BinarySerializer: unknown type tag {tag} at offset {r.cursor - 1}`)
end

function Serializer.serialize(value: any, initialCapacity: number?): buffer
	local w = writerNew(initialCapacity)
	writeValue(w, value, 0)
	if w.cursor == w.capacity then
		return w.buf
	end
	local out = buffer.create(w.cursor)
	buffer.copy(out, 0, w.buf, 0, w.cursor)
	return out
end

function Serializer.deserialize(buf: buffer): any
	if typeof(buf) ~= "buffer" then
		error(`BinarySerializer: deserialize expects a buffer, got {typeof(buf)}`)
	end
	local r: Reader = { buf = buf, cursor = 0, len = buffer.len(buf), depth = 0 }
	return readValue(r)
end

local B64_CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64_PAD = string.byte("=")
local B64_INVALID = 255

local B64_ENCODE = buffer.fromstring(B64_CHARS)

local B64_DECODE = buffer.create(256)
buffer.fill(B64_DECODE, 0, B64_INVALID)
for i = 1, 64 do
	buffer.writeu8(B64_DECODE, string.byte(B64_CHARS, i), i - 1)
end

function Serializer.toBase64(buf: buffer): string
	local len = buffer.len(buf)
	local out = buffer.create(math.ceil(len / 3) * 4)
	local i = 0
	local o = 0

	while i + 3 <= len do
		local n = buffer.readu8(buf, i) * 65536 + buffer.readu8(buf, i + 1) * 256 + buffer.readu8(buf, i + 2)
		buffer.writeu8(out, o, buffer.readu8(B64_ENCODE, bit32.rshift(n, 18)))
		buffer.writeu8(out, o + 1, buffer.readu8(B64_ENCODE, bit32.band(bit32.rshift(n, 12), 63)))
		buffer.writeu8(out, o + 2, buffer.readu8(B64_ENCODE, bit32.band(bit32.rshift(n, 6), 63)))
		buffer.writeu8(out, o + 3, buffer.readu8(B64_ENCODE, bit32.band(n, 63)))
		i += 3
		o += 4
	end

	local rest = len - i
	if rest == 1 then
		local n = buffer.readu8(buf, i) * 65536
		buffer.writeu8(out, o, buffer.readu8(B64_ENCODE, bit32.rshift(n, 18)))
		buffer.writeu8(out, o + 1, buffer.readu8(B64_ENCODE, bit32.band(bit32.rshift(n, 12), 63)))
		buffer.writeu8(out, o + 2, B64_PAD)
		buffer.writeu8(out, o + 3, B64_PAD)
	elseif rest == 2 then
		local n = buffer.readu8(buf, i) * 65536 + buffer.readu8(buf, i + 1) * 256
		buffer.writeu8(out, o, buffer.readu8(B64_ENCODE, bit32.rshift(n, 18)))
		buffer.writeu8(out, o + 1, buffer.readu8(B64_ENCODE, bit32.band(bit32.rshift(n, 12), 63)))
		buffer.writeu8(out, o + 2, buffer.readu8(B64_ENCODE, bit32.band(bit32.rshift(n, 6), 63)))
		buffer.writeu8(out, o + 3, B64_PAD)
	end

	return buffer.tostring(out)
end

local function b64Value(s: string, index: number): number
	local v = buffer.readu8(B64_DECODE, string.byte(s, index))
	if v == B64_INVALID then
		error(`BinarySerializer: invalid Base64 character "{string.sub(s, index, index)}" at position {index}`)
	end
	return v
end

function Serializer.fromBase64(s: string): buffer
	if type(s) ~= "string" then
		error(`BinarySerializer: fromBase64 expects a string, got {typeof(s)}`)
	end

	local body = string.gsub(s, "=+$", "")
	local len = #body
	if len % 4 == 1 then
		error(`BinarySerializer: invalid Base64 length ({len} characters)`)
	end

	local out = buffer.create(math.floor(len * 3 / 4))
	local i = 1
	local o = 0

	while i + 3 <= len do
		local n = b64Value(body, i) * 262144
			+ b64Value(body, i + 1) * 4096
			+ b64Value(body, i + 2) * 64
			+ b64Value(body, i + 3)
		buffer.writeu8(out, o, bit32.rshift(n, 16))
		buffer.writeu8(out, o + 1, bit32.band(bit32.rshift(n, 8), 255))
		buffer.writeu8(out, o + 2, bit32.band(n, 255))
		i += 4
		o += 3
	end

	local rest = len - i + 1
	if rest == 2 then
		local n = b64Value(body, i) * 64 + b64Value(body, i + 1)
		buffer.writeu8(out, o, bit32.rshift(n, 4))
	elseif rest == 3 then
		local n = b64Value(body, i) * 4096 + b64Value(body, i + 1) * 64 + b64Value(body, i + 2)
		buffer.writeu8(out, o, bit32.rshift(n, 10))
		buffer.writeu8(out, o + 1, bit32.band(bit32.rshift(n, 2), 255))
	end

	return out
end

function Serializer.selfTest(): boolean
	local inventory: { any } = {
		"sword",
		"shield",
		{ id = 1001, rarity = "epic", stats = { atk = 15, def = -3 } },
	}

	local sample = {
		name = "Player1",
		level = 42,
		small = -1234,
		hp = 99.5,
		bigNumber = 5e12,
		alive = true,
		dead = false,
		position = Vector3.new(10, 5.25, -3),
		spawn = CFrame.new(0, 10, 0) * CFrame.Angles(0, math.rad(90), 0),
		inventory = inventory,
	}

	local buf = Serializer.serialize(sample)
	local restored = Serializer.deserialize(buf)

	assert(restored.name == "Player1", "string mismatch")
	assert(restored.level == 42, "u8 mismatch")
	assert(restored.small == -1234, "i16 mismatch")
	assert(restored.hp == 99.5, "double mismatch")
	assert(restored.bigNumber == 5e12, "large integer mismatch")
	assert(restored.alive == true and restored.dead == false, "boolean mismatch")
	assert((restored.position - sample.position).Magnitude < 1e-4, "Vector3 mismatch")
	assert((restored.spawn.Position - sample.spawn.Position).Magnitude < 1e-4, "CFrame position mismatch")
	assert((restored.spawn.LookVector - sample.spawn.LookVector).Magnitude < 1e-4, "CFrame rotation mismatch")
	assert(#restored.inventory == 3, "array length mismatch")
	assert(restored.inventory[1] == "sword", "array element mismatch")
	assert(restored.inventory[3].stats.def == -3, "nested table mismatch")

	assert(Serializer.deserialize(Serializer.serialize(nil)) == nil, "nil roundtrip failed")
	assert(Serializer.deserialize(Serializer.serialize("")) == "", "empty string roundtrip failed")
	assert(Serializer.deserialize(Serializer.serialize(-2147483648)) == -2147483648, "i32 lower bound failed")
	assert(Serializer.deserialize(Serializer.serialize(2147483647)) == 2147483647, "i32 upper bound failed")
	assert(Serializer.deserialize(Serializer.serialize(2147483648)) == 2147483648, "i32 overflow fallback failed")
	assert(Serializer.deserialize(Serializer.serialize(-1e-9)) == -1e-9, "small double roundtrip failed")

	local long = string.rep("x", 5000)
	assert(Serializer.deserialize(Serializer.serialize(long)) == long, "multi-byte varint length failed")
	assert(buffer.len(Serializer.serialize({ 1, 2, 3 }, 0)) > 0, "zero initial capacity failed")

	local sparse: { any } = { 1, 2, nil, 4 }
	local holes = Serializer.deserialize(Serializer.serialize(sparse))
	assert(holes[1] == 1 and holes[2] == 2 and holes[3] == nil and holes[4] == 4, "sparse array roundtrip failed")

	for size = 0, 8 do
		local raw = buffer.create(size)
		for i = 0, size - 1 do
			buffer.writeu8(raw, i, (i * 37 + 11) % 256)
		end
		local decoded = Serializer.fromBase64(Serializer.toBase64(raw))
		assert(buffer.len(decoded) == size, `Base64 length mismatch for {size} bytes`)
		for i = 0, size - 1 do
			assert(buffer.readu8(decoded, i) == buffer.readu8(raw, i), `Base64 byte mismatch for {size} bytes`)
		end
	end

	local encoded = Serializer.toBase64(buf)
	assert(Serializer.deserialize(Serializer.fromBase64(encoded)).name == "Player1", "Base64 payload roundtrip failed")

	assert(not (pcall(Serializer.deserialize, "not a buffer" :: any)), "non-buffer input should error")
	assert(not (pcall(Serializer.deserialize, buffer.create(0))), "empty buffer should error")
	assert(not (pcall(Serializer.serialize, print)), "unsupported type should error")
	assert(not (pcall(Serializer.serialize, 1, -1)), "negative initial capacity should error")
	assert(not (pcall(Serializer.fromBase64, "A")), "invalid Base64 length should error")
	assert(not (pcall(Serializer.fromBase64, "A!==")), "invalid Base64 character should error")

	local unknownTag = buffer.create(1)
	buffer.writeu8(unknownTag, 0, 200)
	assert(not (pcall(Serializer.deserialize, unknownTag)), "unknown tag should error")

	local oversizedTableHeader = buffer.create(5)
	buffer.writeu8(oversizedTableHeader, 0, TAG_TABLE)
	buffer.writeu8(oversizedTableHeader, 1, 0xA0)
	buffer.writeu8(oversizedTableHeader, 2, 0x8D)
	buffer.writeu8(oversizedTableHeader, 3, 0x06)
	buffer.writeu8(oversizedTableHeader, 4, 0x00)
	assert(not (pcall(Serializer.deserialize, oversizedTableHeader)), "oversized table header should error")

	local nestedLevels = MAX_DEPTH + 2
	local deepBuffer = buffer.create(nestedLevels * 3 + 1)
	for level = 0, nestedLevels - 1 do
		local at = level * 3
		buffer.writeu8(deepBuffer, at, TAG_TABLE)
		buffer.writeu8(deepBuffer, at + 1, 1)
		buffer.writeu8(deepBuffer, at + 2, 0)
	end
	buffer.writeu8(deepBuffer, nestedLevels * 3, TAG_NIL)
	assert(not (pcall(Serializer.deserialize, deepBuffer)), "excessive nesting in stream should error")

	local deepTable: { [string]: any } = {}
	local node: { [string]: any } = deepTable
	for _ = 1, MAX_DEPTH + 8 do
		node.child = {}
		node = node.child
	end
	assert(not (pcall(Serializer.serialize, deepTable)), "excessive nesting should error")

	local cyclic: { [string]: any } = {}
	cyclic.self = cyclic
	assert(not (pcall(Serializer.serialize, cyclic)), "cyclic table should error")

	print(`[BinarySerializer] selfTest passed: {buffer.len(buf)} bytes, {#encoded} Base64 characters`)
	return true
end

return Serializer
