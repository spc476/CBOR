package = "org.conman.cbor"
version = "1.3.5-1"

source =
{
  url = "git+https://github.com/spc476/CBOR.git",
  tag = version:match "[^-]+"
}

description =
{
  homepage   = "http://github.com/spc476/CBOR.git",
  maintainer = "Sean Conner <sean@conman.org>",
  license    = "LGPL3+",
  summary    = "The most comprehensive CBOR module in the Lua universe.",
  detailed   = [[
	A complete implementation of CBOR (Concise Binary Object
	Representation) with all the currently defined bells and whistles,
	including string, array and map references (if so desired).  A
	simpler, small implementation of CBOR is also provided for less
	intensive or simpler uses.
	]]
}

dependencies =
{
  "lua  >= 5.1, <= 5.4",
  "lpeg ~= 1.0",
}

build =
{
  platforms =
  {
    linux   = { build_variables = { CC = "gcc -std=c99" } },
    solaris = { build_varaibles = { CC = "c99"          } },    
    windows =
    {
      type    = "builtin",
      modules = 
      {
        ['org.conman.cbor_c'] = 
        {
          sources = { 'cbor_c.c', 'dnf.c' },
          defines = { 'VERSION="' .. source.tag .. '"' },
        },

        ['org.conman.cbor']     = 'cbor.lua',
        ['org.conman.cbor_s']   = 'cbor_s.lua',
        ['org.conman.cbormisc'] = 'cbormisc.lua',
      }
    }
  },
  
  type = "make",
  build_variables =
  {
    CC      = "$(CC)",
    CFLAGS  = "$(CFLAGS) -DNDEBUG -I$(LUA_INCDIR)",
    LDFLAGS = "$(LIBFLAG)",
    LUA     = "$(LUA)",
  },
  
  install_variables =
  {
    LIBDIR = "$(LIBDIR)",
    LUADIR = "$(LUADIR)",
    LUA    = "$(LUA)",
  }
}
