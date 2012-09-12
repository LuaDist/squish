
local cs = require "minichunkspy"

local function ___adjust_chunk(chunk, newname, lineshift)
	local c = cs.disassemble(string.dump(chunk));
	c.body.name = newname;

	lineshift = -c.body.line;
	local function shiftlines(c)
		c.line = c.line + lineshift;
		c.last_line = c.last_line + lineshift;
		for i, line in ipairs(c.source_lines) do
			c.source_lines[i] = line+lineshift;
		end
		for i, f in ipairs(c.prototypes) do
			shiftlines(f);
		end
	end
	shiftlines(c.body);

	return assert(loadstring(cs.assemble(c), newname))();
end
