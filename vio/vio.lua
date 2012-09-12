local vio = {};
vio.__index = vio; 
	
function vio.open(string)
	return setmetatable({ pos = 1, data = string }, vio);
end

function vio:read(format, ...)
	if self.pos >= #self.data then return; end
	if format == "*a" then
		local oldpos = self.pos;
		self.pos = #self.data;
		return self.data:sub(oldpos, self.pos);
	elseif format == "*l" then
		local data;
		data, self.pos = self.data:match("([^\r\n]*)\r?\n?()", self.pos)
		return data;
	elseif format == "*n" then
		local data;
		data, self.pos = self.data:match("(%d+)()", self.pos)
		return tonumber(data);	
	elseif type(format) == "number" then
		local oldpos = self.pos;
		self.pos = self.pos + format;
		return self.data:sub(oldpos, self.pos-1);
	end
end

function vio:seek(whence, offset)
	if type(whence) == "number" then
		whence, offset = "cur", whence;
	end
	offset = offset or 0;
	
	if whence == "cur" then
		self.pos = self.pos + offset;
	elseif whence == "set" then
		self.pos = offset + 1;
	elseif whence == "end" then
		self.pos = #self.data - offset;
	end
	
	return self.pos;
end

local function _readline(f) return f:read("*l"); end
function vio:lines()
	return _readline, self;
end

function vio:write(...)
	for i=1,select('#', ...) do
		local dat = tostring(select(i, ...));
		self.data = self.data:sub(1, self.pos-1)..dat..self.data:sub(self.pos+#dat, -1);
	end
end

function vio:close()
	self.pos, self.data = nil, nil;
end

