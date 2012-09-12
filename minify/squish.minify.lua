local optlex = require "optlex"
local optparser = require "optparser"
local llex = require "llex"
local lparser = require "lparser"

local minify_defaults = {
	none = {};
	debug = { "whitespace", "locals", "entropy", "comments", "numbers" };
	default = { "comments", "whitespace", "emptylines", "numbers", "locals" };
	basic = { "comments", "whitespace", "emptylines" };
	full = { "comments", "whitespace", "emptylines", "eols", "strings", "numbers", "locals", "entropy" };
	}

if opts.minify_level and not minify_defaults[opts.minify_level] then
	print_err("Unknown minify level: "..opts.minify_level);
	print_err("Available minify levels: none, basic, default, full, debug");
end
for _, opt in ipairs(minify_defaults[opts.minify_level or "default"] or {}) do
	if opts["minify_"..opt] == nil then
		opts["minify_"..opt] = true;
	end
end

local option = {
	["opt-locals"] = opts.minify_locals;
	["opt-comments"] = opts.minify_comments;
	["opt-entropy"] = opts.minify_entropy;
	["opt-whitespace"] = opts.minify_whitespace;
	["opt-emptylines"] = opts.minify_emptylines;
	["opt-eols"] = opts.minify_eols;
	["opt-strings"] = opts.minify_strings;
	["opt-numbers"] = opts.minify_numbers;
	}

local function die(msg)
  print_err("minify: "..msg); os.exit(1);
end

local function load_file(fname)
  local INF = io.open(fname, "rb")
  if not INF then die("cannot open \""..fname.."\" for reading") end
  local dat = INF:read("*a")
  if not dat then die("cannot read from \""..fname.."\"") end
  INF:close()
  return dat
end

local function save_file(fname, dat)
  local OUTF = io.open(fname, "wb")
  if not OUTF then die("cannot open \""..fname.."\" for writing") end
  local status = OUTF:write(dat)
  if not status then die("cannot write to \""..fname.."\"") end
  OUTF:close()
end


function minify_string(dat)
	llex.init(dat)
	llex.llex()
	local toklist, seminfolist, toklnlist
	= llex.tok, llex.seminfo, llex.tokln
	if option["opt-locals"] then
		optparser.print = print  -- hack
		lparser.init(toklist, seminfolist, toklnlist)
		local globalinfo, localinfo = lparser.parser()
		optparser.optimize(option, toklist, seminfolist, globalinfo, localinfo)
	end
	optlex.print = print  -- hack
	toklist, seminfolist, toklnlist
		= optlex.optimize(option, toklist, seminfolist, toklnlist)
	local dat = table.concat(seminfolist)
	-- depending on options selected, embedded EOLs in long strings and
	-- long comments may not have been translated to \n, tack a warning
	if string.find(dat, "\r\n", 1, 1) or
		string.find(dat, "\n\r", 1, 1) then
		optlex.warn.mixedeol = true
	end
	return dat;
end

function minify_file(srcfl, destfl)
	local z = load_file(srcfl);
	z = minify_string(z);
	save_file(destfl, z);
end

if opts.minify ~= false then
	print_info("Minifying "..out_fn.."...");
	minify_file(out_fn, out_fn);
	print_info("OK!");
end
