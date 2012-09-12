-- Minichunkspy: Disassemble and reassemble chunks.
-- Copyright M Joonas Pihlaja 2009
-- MIT license
--
-- minichunkspy = require"minichunkspy"
--
-- chunk = string.dump(loadfile"blabla.lua")
-- disassembled_chunk = minichunkspy.disassemble(chunk)
-- chunk = minichunkspy.assemble(disassembled_chunk)
-- assert(minichunkspy.validate(<function or chunk>))
--
-- Tested on little-endian 32 and 64 bit platforms.
local string, table, math = string, table, math
local ipairs, setmetatable, type, assert = ipairs, setmetatable, type, assert
local _ = __END_OF_GLOBALS__
local string_char, string_byte, string_sub = string.char, string.byte, string.sub
local math_frexp, math_ldexp, math_abs = math.frexp, math.ldexp, math.abs
local table_concat = table.concat
local Inf = math.huge
local NaN = Inf - Inf

local BIG_ENDIAN = false
local SIZEOF_SIZE_T = 4
local SIZEOF_INT = 4
local SIZEOF_NUMBER = 8

local save_stack = {}

local function save()
    save_stack[#save_stack+1]
	= {BIG_ENDIAN, SIZEOF_SIZE_T, SIZEOF_INT, SIZEOF_NUMBER}
end
local function restore ()
    BIG_ENDIAN, SIZEOF_SIZE_T, SIZEOF_INT, SIZEOF_NUMBER
	= unpack(save_stack[#save_stack])
    save_stack[#save_stack] = nil
end

local function construct (class, self)
    return class.new(class, self)
end

local mt_memo = {}

local Field = construct{
    new =
	function (class, self)
	    local self = self or {}
	    local mt = mt_memo[class] or {
		__index = class,
		__call = construct
	    }
	    mt_memo[class] = mt
	    return setmetatable(self, mt)
	end,
}

local None = Field{
    unpack = function (self, bytes, ix) return nil, ix end,
    pack = function (self, val) return "" end
}

local char_memo = {}

local function char(n)
    local field = char_memo[n] or Field{
	unpack = function (self, bytes, ix)
		     return string_sub(bytes, ix, ix+n-1), ix+n
		 end,
	pack = function (self, val) return string_sub(val, 1, n) end
    }
    char_memo[n] = field
    return field
end

local uint8 = Field{
    unpack = function (self, bytes, ix)
		 return string_byte(bytes, ix, ix), ix+1
	     end,
    pack = function (self, val) return string_char(val) end
}

local uint32 = Field{
    unpack =
	function (self, bytes, ix)
	    local a,b,c,d = string_byte(bytes, ix, ix+3)
	    if BIG_ENDIAN then a,b,c,d = d,c,b,a end
	    return a + b*256 + c*256^2 + d*256^3, ix+4
	end,
    pack =
	function (self, val)
	    assert(type(val) == "number",
		   "unexpected value type to pack as an uint32")
	    local a,b,c,d
	    d = val % 2^32
	    a = d % 256; d = (d - a) / 256
	    b = d % 256; d = (d - b) / 256
	    c = d % 256; d = (d - c) / 256
	    if BIG_ENDIAN then a,b,c,d = d,c,b,a end
	    return string_char(a,b,c,d)
	end
}

local uint64 = Field{
    unpack =
	function (self, bytes, ix)
	    local a = uint32:unpack(bytes, ix)
	    local b = uint32:unpack(bytes, ix+4)
	    if BIG_ENDIAN then a,b = b,a end
	    return a + b*2^32, ix+8
	end,
    pack =
	function (self, val)
	    assert(type(val) == "number",
		   "unexpected value type to pack as an uint64")
	    local a = val % 2^32
	    local b = (val - a) / 2^32
	    if BIG_ENDIAN then a,b = b,a end
	    return uint32:pack(a) .. uint32:pack(b)
	end
}

local function explode_double(bytes, ix)
    local a = uint32:unpack(bytes, ix)
    local b = uint32:unpack(bytes, ix+4)
    if BIG_ENDIAN then a,b = b,a end --XXX: ARM mixed-endian

    local sig_hi = b % 2^20
    local sig_lo = a
    local significand = sig_lo + sig_hi*2^32

    b = (b - sig_hi) / 2^20

    local biased_exp = b % 2^11
    local sign = b <= biased_exp and 1 or -1

    --print(sign, significand, biased_exp, "explode")
    return sign, biased_exp, significand
end

local function implode_double(sign, biased_exp, significand)
    --print(sign, significand, biased_exp, "implode")
    local sig_lo = significand % 2^32
    local sig_hi = (significand - sig_lo) / 2^32

    local a = sig_lo
    local b = ((sign < 0 and 2^11 or 0) + biased_exp)*2^20 + sig_hi

    if BIG_ENDIAN then a,b = b,a end --XXX: ARM mixed-endian
    return uint32.pack(nil, a) .. uint32.pack(nil, b)
end

local function math_sign(x)
    if x ~= x then return x end	--sign of NaN is NaN
    if x == 0 then x = 1/x end	--extract sign of zero
    return x > 0 and 1 or -1
end

local SMALLEST_SUBNORMAL = math_ldexp(1, -1022 - 52)
local SMALLEST_NORMAL = SMALLEST_SUBNORMAL * 2^52
local LARGEST_SUBNORMAL = math_ldexp(2^52 - 1, -1022 - 52)
local LARGEST_NORMAL = math_ldexp(2^53 - 1, 1023 - 52)
assert(SMALLEST_SUBNORMAL ~= 0.0 and SMALLEST_SUBNORMAL / 2 == 0.0)
assert(LARGEST_NORMAL ~= Inf)
assert(LARGEST_NORMAL * 2 == Inf)

local double = Field{
    unpack =
	function (self, bytes, ix)
	    local sign, biased_exp, significand = explode_double(bytes, ix)

	    local val
	    if biased_exp == 0 then --subnormal
		val = math_ldexp(significand, -1022 - 52)
	    elseif biased_exp == 2047 then
		val = significand == 0 and Inf or NaN --XXX: loses NaN mantissa
	    else				      --normal
		val = math_ldexp(2^52 + significand, biased_exp - 1023 - 52)
	    end
	    val = sign*val
	    return val, ix+8
	end,

    pack =
	function (self, val)
	    if val ~= val then
		return implode_double(1,2047,2^52-1) --XXX: loses NaN mantissa
	    end

	    local sign = math_sign(val)
	    val = math_abs(val)

	    if val == Inf then return implode_double(sign, 2047, 0) end
	    if val == 0   then return implode_double(sign, 0, 0) end

	    local biased_exp, significand

	    if val <= LARGEST_SUBNORMAL then
		biased_exp = 0
		significand = val / SMALLEST_SUBNORMAL
	    else
		local frac, exp = math_frexp(val)
		significand = (2*frac - 1)*2^52
		biased_exp = exp + 1022
	    end
	    return implode_double(sign, biased_exp, significand)
	end
}

local Byte = uint8

local IntegralTypes = {
    [4] = uint32,
    [8] = uint64
}

local FloatTypes = {
    [4] = float,
    [8] = double
}

local Size_t = Field{
    unpack = function (self, bytes, ix)
		 return IntegralTypes[SIZEOF_SIZE_T]:unpack(bytes, ix)
	     end,
    pack = function (self, val)
	       return IntegralTypes[SIZEOF_SIZE_T]:pack(val)
	   end,
}

local Integer = Field{
    unpack = function (self, bytes, ix)
		 return IntegralTypes[SIZEOF_INT]:unpack(bytes, ix)
	     end,
    pack = function (self, val)
	       return IntegralTypes[SIZEOF_INT]:pack(val)
	   end,
}

local Number = Field{
    unpack = function (self, bytes, ix)
		 return FloatTypes[SIZEOF_NUMBER]:unpack(bytes, ix)
	     end,
    pack = function (self, val)
	       return FloatTypes[SIZEOF_NUMBER]:pack(val)
	   end,
}

-- Opaque types:
local Insn = char(4)

local Struct = Field{
    unpack =
	function (self, bytes, ix)
	    local val = {}
	    local i,j = 1,1
	    while self[i] do
		local field = self[i]
		local key = field.name
		if not key then key, j = j, j+1 end
		--print("unpacking struct field", key, " at index ", ix)
		val[key], ix = field:unpack(bytes, ix)
		i = i+1
	    end
	    return val, ix
	end,
    pack =
	function (self, val)
	    local data = {}
	    local i,j = 1,1
	    while self[i] do
		local field = self[i]
		local key = field.name
		if not key then key, j = j, j+1 end
		data[i] = field:pack(val[key])
		i = i+1
	    end
	    return table_concat(data)
	end
}

local List = Field{
    unpack =
	function (self, bytes, ix)
	    local len, ix = Integer:unpack(bytes, ix)
	    local vals = {}
	    local field = self.type
	    for i=1,len do
		--print("unpacking list field", i, " at index ", ix)
		vals[i], ix = field:unpack(bytes, ix)
	    end
	    return vals, ix
	end,
    pack =
	function (self, vals)
	    local len = #vals
	    local data = { Integer:pack(len) }
	    local field = self.type
	    for i=1,len do
		data[#data+1] = field:pack(vals[i])
	    end
	    return table_concat(data)
	end
}

local Boolean = Field{
    unpack =
	function (self, bytes, ix)
	    local val, ix = Integer:unpack(bytes, ix)
	    assert(val == 0 or val == 1,
		   "unpacked an unexpected value "..val.." for a Boolean")
	    return val == 1, ix
	end,
    pack =
	function (self, val)
	    assert(type(val) == "boolean",
		   "unexpected value type to pack as a Boolean")
	    return Integer:pack(val and 1 or 0)
	end
}

local String = Field{
    unpack =
	function (self, bytes, ix)
	    local len, ix = Size_t:unpack(bytes, ix)
	    local val = nil
	    if len > 0 then
		-- len includes trailing nul byte; ignore it
		local string_len = len - 1
		val = bytes:sub(ix, ix+string_len-1)
	    end
	    return val, ix + len
	end,
    pack =
	function (self, val)
	    assert(type(val) == "nil" or type(val) == "string",
		   "unexpected value type to pack as a String")
	    if val == nil then
		return Size_t:pack(0)
	    end
	    return Size_t:pack(#val+1) .. val .. "\000"
	end
}

local ChunkHeader = Struct{
    char(4){name = "signature"},
    Byte{name = "version"},
    Byte{name = "format"},
    Byte{name = "endianness"},
    Byte{name = "sizeof_int"},
    Byte{name = "sizeof_size_t"},
    Byte{name = "sizeof_insn"},
    Byte{name = "sizeof_Number"},
    Byte{name = "integral_flag"},
}

local ConstantTypes = {
    [0] = None,
    [1] = Boolean,
    [3] = Number,
    [4] = String,
}
local Constant = Field{
    unpack =
	function (self, bytes, ix)
	    local t, ix = Byte:unpack(bytes, ix)
	    local field = ConstantTypes[t]
	    assert(field, "unknown constant type "..t.." to unpack")
	    local v, ix = field:unpack(bytes, ix)
	    if t == 3 then
		assert(type(v) == "number")
	    end
	    return {
		type = t,
		value = v
	    }, ix
	end,
    pack =
	function (self, val)
	    local t, v = val.type, val.value
	    return Byte:pack(t) .. ConstantTypes[t]:pack(v)
	end
}

local Local = Struct{
    String{name = "name"},
    Integer{name = "startpc"},
    Integer{name = "endpc"}
}

local Function = Struct{
    String{name = "name"},
    Integer{name = "line"},
    Integer{name = "last_line"},
    Byte{name = "num_upvalues"},
    Byte{name = "num_parameters"},
    Byte{name = "is_vararg"},
    Byte{name = "max_stack_size"},
    List{name = "insns", type = Insn},
    List{name = "constants", type = Constant},
    List{name = "prototypes", type = nil}, --patch type below
    List{name = "source_lines", type = Integer},
    List{name = "locals", type = Local},
    List{name = "upvalues", type = String},
}
assert(Function[10].name == "prototypes",
       "missed the function prototype list")
Function[10].type = Function

local Chunk = Field{
    unpack =
	function (self, bytes, ix)
	    local chunk = {}
	    local header, ix = ChunkHeader:unpack(bytes, ix)
	    assert(header.signature == "\027Lua", "signature check failed")
	    assert(header.version == 81, "version mismatch")
	    assert(header.format == 0, "format mismatch")
	    assert(header.endianness == 0 or
		   header.endianness == 1, "endianness mismatch")
	    assert(IntegralTypes[header.sizeof_int], "int size unsupported")
	    assert(IntegralTypes[header.sizeof_size_t], "size_t size unsupported")
	    assert(header.sizeof_insn == 4, "insn size unsupported")
	    assert(FloatTypes[header.sizeof_Number], "number size unsupported")
	    assert(header.integral_flag == 0, "integral flag mismatch; only floats supported")

	    save()
		BIG_ENDIAN = header.endianness == 0
		SIZEOF_SIZE_T = header.sizeof_size_t
		SIZEOF_INT = header.sizeof_int
		SIZEOF_NUMBER = header.sizeof_Number
		chunk.header = header
		chunk.body, ix = Function:unpack(bytes, ix)
	    restore()
	    return chunk, ix
	end,

    pack =
	function (self, val)
	    local data
	    save()
		local header = val.header
		BIG_ENDIAN = header.endianness == 0
		SIZEOF_SIZE_T = header.sizeof_size_t
		SIZEOF_INT = header.sizeof_int
		SIZEOF_NUMBER = header.sizeof_Number
		data = ChunkHeader:pack(val.header) .. Function:pack(val.body)
	    restore()
	    return data
	end
}

local function validate(chunk)
    if type(chunk) == "function" then
	return validate(string.dump(chunk))
    end
    local f = Chunk:unpack(chunk, 1)
    local chunk2 = Chunk:pack(f)

    if chunk == chunk2 then return true end

    local i
    local len = math.min(#chunk, #chunk2)
    for i=1,len do
	local a = chunk:sub(i,i)
	local b = chunk:sub(i,i)
	if a ~= b then
	    return false, ("chunk roundtripping failed: "..
			   "first byte difference at index %d"):format(i)
	end
    end
    return false, ("chunk round tripping failed: "..
		   "original length %d vs. %d"):format(#chunk, #chunk2)
end

return {
    disassemble = function (chunk) return Chunk:unpack(chunk, 1) end,
    assemble = function (disassembled) return Chunk:pack(disassembled) end,
    validate = validate
}
