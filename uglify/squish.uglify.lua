local llex = require "llex"

local base_char = 128;
local keywords = { "and", "break", "do", "else", "elseif",
    "end", "false", "for", "function", "if",
        "in", "local", "nil", "not", "or", "repeat",
            "return", "then", "true", "until", "while" }

function uglify_file(infile_fn, outfile_fn)
	local infile, err = io.open(infile_fn);
	if not infile then
		print_err("Can't open input file for reading: "..tostring(err));
		return;
	end
	
	local outfile, err = io.open(outfile_fn..".uglified", "wb+");
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

	
	while base_char + #keywords <= 255 and code:find("["..string.char(base_char).."-"..string.char(base_char+#keywords-1).."]") do
		base_char = base_char + 1;
	end
	if base_char + #keywords > 255 then
		-- Sorry, can't uglify this file :(
		-- We /could/ use a multi-byte marker, but that would complicate
		-- things and lower the compression ratio (there are quite a few 
		-- 2-letter keywords)
		outfile:write(code);
		outfile:close();
		os.rename(outfile_fn..".uglified", outfile_fn);
		return;
	end

	local keyword_map_to_char = {}
	for i, keyword in ipairs(keywords) do
		keyword_map_to_char[keyword] = string.char(base_char + i);
	end

	-- Write loadstring and open string
	local maxequals = 0;
	data:gsub("(=+)", function (equals_string) maxequals = math.max(maxequals, #equals_string); end);
	
	-- Go lexer!
	llex.init(code, "@"..infile_fn);
	llex.llex()
	local seminfo = llex.seminfo;
	
	if opts.uglify_level == "full" and base_char+#keywords < 255 then
		-- Find longest TK_NAME and TK_STRING tokens
		local scores = {};
		for k,v in ipairs(llex.tok) do
			if v == "TK_NAME" or v == "TK_STRING" then
				local key = string.format("%q,%q", v, seminfo[k]);
				if not scores[key] then
					scores[key] = { type = v, value = seminfo[k], count = 0 };
					scores[#scores+1] = scores[key];
				end
				scores[key].count = scores[key].count + 1;
			end
		end
		for i=1,#scores do
			local v = scores[i];
			v.score = (v.count)*(#v.value-1)- #string.format("%q", v.value) - 1;
		end
		table.sort(scores, function (a, b) return a.score > b.score; end);
		local free_space = 255-(base_char+#keywords);
		for i=free_space+1,#scores do
			scores[i] = nil; -- Drop any over the limit
		end
	
		local base_keywords_len = #keywords;
		for k,v in ipairs(scores) do
			if v.score > 0 then
				table.insert(keywords, v.value);
				keyword_map_to_char[v.value] = string.char(base_char+base_keywords_len+k);
			end
		end
	end
	
	outfile:write("local base_char,keywords=", tostring(base_char), ",{");
	for _, keyword in ipairs(keywords) do
		outfile:write(string.format("%q", keyword), ',');
	end
	outfile:write[[}; function prettify(code) return code:gsub("["..string.char(base_char).."-"..string.char(base_char+#keywords).."]", 
	function (c) return keywords[c:byte()-base_char]; end) end ]]
	
	outfile:write [[return assert(loadstring(prettify]]
	outfile:write("[", string.rep("=", maxequals+1), "[");
	
	-- Write code, substituting tokens as we go
	for k,v in ipairs(llex.tok) do
		if v == "TK_KEYWORD" or v == "TK_NAME" or v == "TK_STRING" then
			local keyword_char = keyword_map_to_char[seminfo[k]];
			if keyword_char then
				outfile:write(keyword_char);
			else -- Those who think Lua shouldn't have 'continue, fix this please :)
				outfile:write(seminfo[k]);
			end
		else
			outfile:write(seminfo[k]);
		end
	end

	-- Close string/functions	
	outfile:write("]", string.rep("=", maxequals+1), "]");
	outfile:write(", '@", outfile_fn,"'))()");
	outfile:close();
	os.rename(outfile_fn..".uglified", outfile_fn);
end

if opts.uglify then
	print_info("Uglifying "..out_fn.."...");
	uglify_file(out_fn, out_fn);
	print_info("OK!");
end
