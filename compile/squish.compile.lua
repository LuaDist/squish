
local cs = require "minichunkspy"

function compile_string(str, name)
	-- Strips debug info, if you're wondering :)
	local chunk = string.dump(loadstring(str, name));
	if ((not opts.debug) or opts.compile_strip) and opts.compile_strip ~= false then
		local c = cs.disassemble(chunk);
		local function strip_debug(c)
			c.source_lines, c.locals, c.upvalues = {}, {}, {};
			
			for i, f in ipairs(c.prototypes) do
				strip_debug(f);
			end
		end
		print_verbose("Stripping debug info...");
		strip_debug(c.body);
		return cs.assemble(c);
	end
	return chunk;
end

function compile_file(infile_fn, outfile_fn)
	local infile, err = io.open(infile_fn);
	if not infile then
		print_err("Can't open input file for reading: "..tostring(err));
		return;
	end
	
	local outfile, err = io.open(outfile_fn..".compiled", "w+");
	if not outfile then
		print_err("Can't open output file for writing: "..tostring(err));
		return;
	end
	
	local data = infile:read("*a");
	infile:close();
	
	local shebang, newdata = data:match("^(#.-\n)(.+)$");
	local code = newdata or data;
	if shebang then
		outfile:write(shebang)
	end

	outfile:write(compile_string(code, outfile_fn));
	
	os.rename(outfile_fn..".compiled", outfile_fn);
end

if opts.compile then
	print_info("Compiling "..out_fn.."...");
	compile_file(out_fn, out_fn);
	print_info("OK!");
end
