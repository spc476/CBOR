package = "org.conman.cbor"
version = "0.9.0-1"

source =
{
  url = "git://github.com/spc476/CBOR.git",
  tag = "0.9.0"
}

description =
{
  homepage = "http://github.com/spc476/CBOR.git",
  maintainer = "Sean Conner <sean@conman.org>",
  license    = "LGPL-3",
  summary    = "A Lua implementatino of the CBOR spec (RFC-7049)",
  detailed   = [[ ]]
}

dependencies =
{
  "lua  >= 5.1, < 5.4",
  "lpeg ~= 1.0",
}

build =
{
  type           = "make",
  install_target = "install"
}
