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
-- Tested on little-endian 32 bit platforms.  Modify
-- the Size_t type to be a 64 bit integer to make it work
-- for 64 bit systems, and set BIG_ENDIAN = true for
-- big-endian systems.
local string, table, math = string, table, math
local ipairs, setmetatable, type, assert = ipairs, setmetatable, type, assert
local _ = __END_OF_GLOBALS__
local string_char, string_byte, string_sub = string.char, string.byte, string.sub
local table_concat = table.concat
local math_abs, math_ldexp, math_frexp = math.abs, math.ldexp, math.frexp
local Inf = math.huge
local Nan = Inf - Inf

local BIG_ENDIAN = false	--twiddle this for your platform.

local function construct (class, ...)
    return class.new(class, ...)
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

local int32 = uint32{
    unpack = function (self, bytes, ix)
		 local val, ix = uint32:unpack(bytes, ix)
		 return val < 2^32 and val or (val - 2^31), ix
	     end
}

local Byte = uint8
local Size_t = uint32
local Integer = int32

-- Opaque types:
local Number = char(8)
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
	    local len, ix = Integer:unpack(bytes, ix)
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
		return Integer:pack(0)
	    end
	    return Integer:pack(#val+1) .. val .. "\000"
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

local Chunk = Struct{
    ChunkHeader{name = "header"},
    Function{name = "body"}
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
