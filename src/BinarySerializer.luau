-- High-performance binary serializer based on the buffer API.
-- Supports: nil, boolean, number, string, table, Vector3, CFrame.
-- Plus toBase64 / fromBase64 utility functions for DataStores.

local Serializer = {}

local TAG_NIL     = 0
local TAG_FALSE   = 1
local TAG_TRUE    = 2
local TAG_U8      = 3
local TAG_I16     = 4
local TAG_I32     = 5
local TAG_F64     = 6
local TAG_STRING  = 7
local TAG_TABLE   = 8
local TAG_VECTOR3 = 9
local TAG_CFRAME  = 10

type Writer = { buf: buffer, cursor: number, capacity: number }

local function writerNew(initialCapacity: number?): Writer
	local cap = initialCapacity or 128
	return { buf = buffer.create(cap), cursor = 0, capacity = cap }
end

local function writerEnsure(w: Writer, bytes: number)
	local needed = w.cursor + bytes
	if needed <= w.capacity then return end
	local newCap = w.capacity
	repeat newCap *= 2 until newCap >= needed
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

type Reader = { buf: buffer, cursor: number }

local function readU8(r: Reader): number
	local v = buffer.readu8(r.buf, r.cursor)
	r.cursor += 1
	return v
end

local function readI16(r: Reader): number
	local v = buffer.readi16(r.buf, r.cursor)
	r.cursor += 2
	return v
end

local function readI32(r: Reader): number
	local v = buffer.readi32(r.buf, r.cursor)
	r.cursor += 4
	return v
end

local function readF32(r: Reader): number
	local v = buffer.readf32(r.buf, r.cursor)
	r.cursor += 4
	return v
end

local function readF64(r: Reader): number
	local v = buffer.readf64(r.buf, r.cursor)
	r.cursor += 8
	return v
end

local function readVarint(r: Reader): number
	local result = 0
	local shift = 0
	while true do
		local b = readU8(r)
		result = bit32.bor(result, bit32.lshift(bit32.band(b, 0x7F), shift))
		if bit32.band(b, 0x80) == 0 then break end
		shift += 7
	end
	return result
end

local function readString(r: Reader): string
	local len = readVarint(r)
	local s = buffer.readstring(r.buf, r.cursor, len)
	r.cursor += len
	return s
end

local writeValue

local function writeNumber(w: Writer, n: number)
	if n % 1 == 0 and n == n then
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
	if depth > 32 then
		error("BinarySerializer: maximum nesting depth exceeded (32)")
	end

	local arrayLen = 0
	for i in ipairs(t) do
		arrayLen = i
	end

	local dictCount = 0
	for k in pairs(t) do
		if not (type(k) == "number" and k % 1 == 0 and k >= 1 and k <= arrayLen) then
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
		if not (type(k) == "number" and k % 1 == 0 and k >= 1 and k <= arrayLen) then
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
		writeF32(w, x); writeF32(w, y); writeF32(w, z)
		writeF32(w, r00); writeF32(w, r01); writeF32(w, r02)
		writeF32(w, r10); writeF32(w, r11); writeF32(w, r12)
		writeF32(w, r20); writeF32(w, r21); writeF32(w, r22)
	else
		error(`BinarySerializer: unsupported type "{t}"`)
	end
end

local readValue

local function readTable(r: Reader): { [any]: any }
	local arrayLen = readVarint(r)
	local dictCount = readVarint(r)
	local t = table.create(arrayLen)

	for i = 1, arrayLen do
		t[i] = readValue(r)
	end

	for _ = 1, dictCount do
		local k = readValue(r)
		local v = readValue(r)
		t[k] = v
	end

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
		return Vector3.new(readF32(r), readF32(r), readF32(r))
	elseif tag == TAG_CFRAME then
		return CFrame.new(
			readF32(r), readF32(r), readF32(r),
			readF32(r), readF32(r), readF32(r),
			readF32(r), readF32(r), readF32(r),
			readF32(r), readF32(r), readF32(r)
		)
	else
		error(`BinarySerializer: unknown type tag {tag} (position {r.cursor - 1})`)
	end
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
	local r: Reader = { buf = buf, cursor = 0 }
	return readValue(r)
end

-- ---------- Base64 for DataStore ----------
local B64_CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

function Serializer.toBase64(buf: buffer): string
	local len = buffer.len(buf)
	local parts = table.create(math.ceil(len / 3))
	for i = 0, len - 1, 3 do
		local b1 = buffer.readu8(buf, i)
		local b2 = if i + 1 < len then buffer.readu8(buf, i + 1) else 0
		local b3 = if i + 2 < len then buffer.readu8(buf, i + 2) else 0
		local n = b1 * 65536 + b2 * 256 + b3
		local c1 = bit32.rshift(n, 18) % 64
		local c2 = bit32.rshift(n, 12) % 64
		local c3 = bit32.rshift(n, 6) % 64
		local c4 = n % 64
		local chunk = string.sub(B64_CHARS, c1 + 1, c1 + 1)
			.. string.sub(B64_CHARS, c2 + 1, c2 + 1)
			.. (if i + 1 < len then string.sub(B64_CHARS, c3 + 1, c3 + 1) else "=")
			.. (if i + 2 < len then string.sub(B64_CHARS, c4 + 1, c4 + 1) else "=")
		table.insert(parts, chunk)
	end
	return table.concat(parts)
end

function Serializer.fromBase64(s: string): buffer
	s = string.gsub(s, "=", "")
	local outLen = math.floor(#s * 3 / 4)
	local buf = buffer.create(outLen)
	local pos = 0
	for i = 1, #s, 4 do
		local n = 0
		local count = 0
		for j = 0, 3 do
			local ch = string.sub(s, i + j, i + j)
			if ch ~= "" then
				n = n * 64 + (string.find(B64_CHARS, ch, 1, true) :: number - 1)
				count += 1
			else
				n = n * 64
			end
		end
		local bytes = count - 1
		if bytes >= 1 and pos < outLen then buffer.writeu8(buf, pos, bit32.rshift(n, 16) % 256); pos += 1 end
		if bytes >= 2 and pos < outLen then buffer.writeu8(buf, pos, bit32.rshift(n, 8) % 256); pos += 1 end
		if bytes >= 3 and pos < outLen then buffer.writeu8(buf, pos, n % 256); pos += 1 end
	end
	return buf
end

-- ---------- Self-Test ----------
function Serializer.selfTest()
	local sample = {
		name = "Player1",
		level = 42,
		hp = 99.5,
		bigNumber = 5e12,
		alive = true,
		dead = false,
		position = Vector3.new(10, 5.25, -3),
		spawn = CFrame.new(0, 10, 0) * CFrame.Angles(0, math.rad(90), 0),
		inventory = {
			"sword",
			"shield",
			{ id = 1001, rarity = "epic", stats = { atk = 15, def = -3 } },
		},
	}

	local buf = Serializer.serialize(sample)
	print(`[selfTest] Serialized data size: {buffer.len(buf)} bytes`)

	-- For comparison: size of the same data in JSON
	local HttpService = game:GetService("HttpService")
	local jsonOk, json = pcall(function()
		local copy = table.clone(sample)
		copy.position = nil
		copy.spawn = nil -- JSON does not support Vector3/CFrame at all
		return HttpService:JSONEncode(copy)
	end)
	if jsonOk then
		print(`[selfTest] For comparison, JSON (excluding Vector3/CFrame): {#json} bytes`)
	end

	local restored = Serializer.deserialize(buf)

	assert(restored.name == "Player1")
	assert(restored.level == 42)
	assert(restored.hp == 99.5)
	assert(restored.bigNumber == 5e12)
	assert(restored.alive == true and restored.dead == false)
	assert((restored.position - sample.position).Magnitude < 1e-4)
	assert(restored.inventory[1] == "sword")
	assert(restored.inventory[3].stats.def == -3)

	-- Base64 roundtrip verification
	local encoded = Serializer.toBase64(buf)
	local decoded = Serializer.fromBase64(encoded)
	assert(buffer.len(decoded) == buffer.len(buf), "base64: size mismatch")
	local roundtrip = Serializer.deserialize(decoded)
	assert(roundtrip.name == "Player1", "base64: data corrupted")
	print(`[selfTest] Base64 roundtrip: OK ({#encoded} characters)`)

	print("[selfTest] BinarySerializer: OK ")
	return true
end

return Serializer
