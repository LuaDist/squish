
# Squish - One language to write them all, one squisher to squish them

Squish is a simple script to build a single file out of multiple scripts, modules, and other files.

For example if you have a script called A, and it requires modules X, Y and Z, all of them could be squished 
into a single file, B.

When run, Squish reads a file called 'squishy' in the current (or specified) directory, which contains 
instructions on how to squish a project.

For an example you can see Squish's own squishy file, included in this package. For reference, see below.

## Building and installing

Squish uses itself to squish itself and its components into a single 'squish' utility that can be run anywhere.
To build squish, just run "make" - there are no dependencies other than Lua.

You can run "make install" to copy squish to /usr/local/bin/ if you have permission.

## Squishing

Running squish will search for a 'squishy' file in the current directory. Alternatively you can pass to squish 
a directory to look in.

Command-line options vary depending on what features squish has been built with. Below are the standard ones.

### Minify
'Minification' is the act of condensing source code by stripping out spaces, line breaks, comments and anything 
that isn't required to be there. Although the source code is re-organised and changed, the program is still the 
same and runs without any changes.

#### --no-minify
Disable minification of the output file after squishing. Default is to minify.

#### --minify-level=level
The level may be one of: none, basic, default, full

They vary in effectiveness, and the time taken to process large files. Experiment!

### Uglify
'Uglification' is the name Squish gives to a certain basic form of compression. With large files it can reduce the 
size by some kilobytes, even after full minification. It works by replacing Lua keywords with a single byte and 
inserting some short code at the start of the script to expand the keywords when it is run.

#### --uglify
Enable the uglification filter. Default is to not uglify.

#### --uglify-level=LEVEL
If the level specified is "full" then Squish will extend its replacement to identifiers and string literals, as
well as Lua keywords. It first assigns each identifier and string a score based on its length and how many times
it appears in the file. The top scorers are assigned single-byte identifiers and replaced the same as the keywords.

### Gzip
Gzip, or rather the DEFLATE algorithm, is extremely good at compressing text-based data, including scripts. Using
this extension compresses the squished code, and adds some runtime decompression code. This decompression code adds
a little bit of time to the loading of the script, and adds 4K to the size of the generated code, but the overall
savings are usually well worth it.

#### --gzip
Compress the generated code with gzip. Requires the gzip command-line utility (for compression only).

### Compile
Squish can compile the resulting file to Lua bytecode. This is experimental at this stage (you may get better results 
with luac right now), however it's a work in progress. Compiling to bytecode can actually increase the size of 
minified output, but it can speed up loading (not that you would notice it anyway, since the Lua compiler is so fast).

#### --compile
Enables compilation of the output file.

### Debug
Due to the way Squish combines multiple scripts into one, sometimes when a squished script raises an error the traceback 
will be fairly unhelpful, and point to a line in the unreadable squished script. This is where the debug extension comes in!

#### --debug
This option includes some code into the squished file which will restore the filenames and line numbers in error messages and 
tracebacks. This option will increase the size of the output by no more than about 6KB, so may be very much worth it when 
squishing large tricky-to-debug applications and libraries.

**Note:** Minification may interfere with the line number calculation, use --minify-level=debug to enable all features of minify 
that don't change line numbers, and everything will be fine.

### Virtual IO
Squish allows you to pack resources (any file) into the squished output. Sometimes it would be convenient to access these through 
the standard Lua io interface. Well now you can! :)

#### --virtual-io
Inserts code into the squished output which replaces io.open, io.lines, dofile and loadfile. The new functions will first check 
whether the specified filename matches a packed resource's name. If it does then it will operate on that resource instead of an 
actual file. If the filename does _not_ match a resource then the function passes on to the real Lua functions.

## Squishy reference

A squishy file is actually a Lua script which calls some Squish functions. These functions are listed here.

### Module "name" "path"
Adds the specified module to the list of those to be squished into the output file. The optional path specifies 
where to find the file (relative to the squishy file), otherwise Squish will attempt to find the module itself.

### Main "script.lua"
Adds a script into the squished output. Scripts are executed in the order specified in the squishy file, but only 
after all modules have been loaded.

### Output "filename.lua"
Names the output file. If none is specified, the default is 'squished.out.lua'.

### Option "name" "value"
Sets the specified option, to 'true', or to the optional given value. This allows a squishy file to set default 
command-line options.

### GetOption "name"
Returns the current value of the given option.

### Resource "name" "path"
Adds a 'resource' to the squished file. A resource may be any file, text, binary, large or small. Scripts can 
retrieve the resource at runtime by calling require_resource("name"). If no path is given then the name is used 
as the path.

### AutoFetchURL "url"
**Experimental** feature which is subject to change. When specified, all the following Module statements will be 
fetched via HTTP if not found on the filesystem. A ? (question mark) in the URL is replaced by the relative path 
of the module file that was given in the Module statement.

## make_squishy

Squish includes a small utility which aims to help with converting a project to use Squish. Pass it a list of files 
and it will scan those files looking for calls to require(). It will then attempt to resolve the module names to 
files relative to the directory of the first filename passed to make_squishy.

It generates a 'squishy.new' file in the current directory. Modify accordingly and rename to just 'squishy'.
