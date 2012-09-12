
OPTIONS=-q --with-minify --with-uglify --with-compile --with-virtual-io

squish: squish.lua squishy
	./squish.lua $(OPTIONS) # Bootstrap squish
	chmod +x squish
	./squish -q gzip # Minify gunzip code
	./squish -q debug # Minify debug code
	./squish $(OPTIONS) --with-gzip --with-debug # Build squish with minified gzip/debug
	
install: squish
	install squish /usr/local/bin/squish

clean:
	rm squish squish.debug gunzip.lua
