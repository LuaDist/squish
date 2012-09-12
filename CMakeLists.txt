# Copyright (C) 2007-2012 LuaDist.
# Created by Peter Drahoš
# Redistribution and use of this file is allowed according to the terms of the MIT license.
# For details see the COPYRIGHT file distributed with LuaDist.
# Please note that the package source code is licensed under its own license.

project ( squish NONE )
cmake_minimum_required ( VERSION 2.8 )
include ( cmake/dist.cmake )
include ( lua )

find_package ( Lua )

# Squish itself
add_custom_target ( bootstrap ALL
	COMMAND ${LUA_EXECUTABLE} squish.lua -q --with-minify --with-uglyfy --with-compile --with-virtual-io
	COMMAND ${LUA_EXECUTABLE} squish -q gzip
	COMMAND ${LUA_EXECUTABLE} squish -q debug
	COMMAND ${LUA_EXECUTABLE} squish -q --with-minify --with-uglyfy --with-compile --with-virtual-io --with-gzip --with-debug
	WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
)

install_lua_executable ( squish ${CMAKE_CURRENT_SOURCE_DIR}/squish )
install_data ( README COPYRIGHT CHANGES )
