-- ***************************************************************
--
-- Copyright 2016 by Sean Conner.  All Rights Reserved.
-- 
-- This library is free software; you can redistribute it and/or modify it
-- under the terms of the GNU Lesser General Public License as published by
-- the Free Software Foundation; either version 3 of the License, or (at your
-- option) any later version.
-- 
-- This library is distributed in the hope that it will be useful, but
-- WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
-- or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public
-- License for more details.
-- 
-- You should have received a copy of the GNU Lesser General Public License
-- along with this library; if not, see <http://www.gnu.org/licenses/>.
--
-- Comments, questions and criticisms can be sent to: sean@conman.org
--
-- ***************************************************************

local ddt  = require "org.conman.debug"
local math = require "math"
local cbor = require "cbore"

assert(cbor.encode(false)       == '\244')
assert(cbor.encode(true)        == '\245')
assert(cbor.encode(nil)         == "\246")
assert(cbor.encode(math.huge)   == '\249\124\0')
assert(cbor.encode(.5)          == '\249\56\0')
assert(cbor.encode(6.09755516052246093750e-05) == '\250\56\127\224\0')
assert(cbor.encode(math.pi)     == '\251\64\9\33\251\84\68\45\24')

assert(cbor.encode(0)           == '\0')
assert(cbor.encode(100)         == '\24\100')
assert(cbor.encode(1000)        == '\25\03\232')
assert(cbor.encode(100000)      == '\26\0\1\134\160')
assert(cbor.encode(8589934592)  == '\27\0\0\0\2\0\0\0\0')

assert(cbor.encode(-1)          == '\32')
assert(cbor.encode(-100)        == '\56\99')
assert(cbor.encode(-1000)       == '\57\03\231')
assert(cbor.encode(-100000)     == '\58\0\1\134\159')
assert(cbor.encode(-8589934592) == '\59\0\0\0\1\255\255\255\255')

assert(cbor.encode("\0\1\2\3\4")               == '\69\0\1\2\3\4')
assert(cbor.encode("\225\254\162\225\154\177") == '\70\225\254\162\225\154\177')

assert(cbor.encode("test")                     == "dtest")
assert(cbor.encode("\225\154\162\225\154\177") == '\102\225\154\162\225\154\177')
assert(cbor.encode({false,true,0,1})           == '\132\244\245\0\1')
assert(cbor.encode({[false]=0,[true]=1,two=2}) == '\163\244\0\245\1\99two\2')
