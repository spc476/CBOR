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
-- ====================================================================
--
-- Module:	cbor
--
-- Desc:	Encodes CBOR data.
--
-- Types:
--		cbor (enum)
--			*** base types
--			* UINT		unsigned integer (Lua number)
--			* NINT		negative integer (Lua number)
--			* BIN		binary string	(Lua string)
--			* TEXT		UTF-8 string	(Lua string)
--			* ARRAY		value is item count (Lua number)
--			* MAP		value is item count (Lua number)
--			*** simple types
--			* simple	SEE NOTES       (Lua number)
--			* false		false value	(Lua false)
--			* true		true value	(Lua true)
--			* null		NULL value	(Lua nil)
--			* undefined	undefined value	(Lua nil)
--			* half		half precicion   IEEE 754 float
--			* single	single precision IEEE 754 float
--			* double	double precision IEEE 754 float
--			* __break	SEE NOTES
--			*** tagged types
--			* tag-*		unsupported tag type (Lua number)
--			* _datetime	datetime (TEXT)
--			* _epoch	see cbor.isnumber()
--			* _pbignum	positive bignum (BIN)
--			* _nbignum	negative bignum (BIN)
--			* _decimalfraction ARRAY(integer exp, integer mantissa)
--			* _bigfloat	ARRAY(float exp,integer mantissa)
--			* _tobase64url	should be base64url encoded (BIN)
--			* _tobase64	should be base64 encoded (BIN)
--			* _tobase16	should be base16 encoded (BIN)
--			* _cbor		CBOR encoded data (BIN)
--			* _url		URL (TEXT)
--			* _base64url	base64url encoded data (TEXT)
--			* _base64	base64 encoded data (TEXT)
--			* _regex	regex (TEXT)
--			* _mime		MIME encoded messsage (TEXT)
--			* _magic_cbor	itself (no data, used to self-describe CBOR data)
--			** more tagged types, extensions
--			* _nthstring	shared string (not supported)
--			* _perlobj	Perl serialized object (not supported)
--			* _serialobj	Generic serialized object (not supported)
--			* _shareable	sharable resource (ARRAY or MAP)
--			* _sharedref	reference (UINT)
--			* _rational	Rational number (not supported)
--			* _uuid		UUID value (BIN)
--			* _langstring	Language-tagged string (not supported)
--			* _id		Identifier (not supported)
--			* _stringref	string reference (not supported)
--			* _bmime	Binary MIME message (not supported)
--			* _decimalfractionexp (not supported)
--			* _bigfloatexp	(not supported)
--			* _indirection	Indirection (not supported)
--			*** Lua CBOR library types
--			* __error	error parsing (TEXT)
--		data (any) decoded CBOR data
--		pos (integer) position parsing stopped
--
-- NOTES:	The simple type is returned for non-defined simple types.
--		
--		The __break type is used to indicate the end of an
--		indefinite array or map.
--
-- ********************************************************************

local math  = require "math"
local lpeg  = require "lpeg"
local cbor5 = require "cbor5"

local _VERSION     = _VERSION
local assert       = assert
local error        = error
local getmetatable = getmetatable
local setmetatable = setmetatable
local pairs        = pairs
local ipairs       = ipairs
local type         = type

if _VERSION == "Lua 5.1" then
  function math.type(n)
    if n ~= n then
      return 'float'
    elseif n == math.huge or n == -math.huge then
      return 'float'
    elseif math.floor(n) == n then
      return 'integer'
    else
      return 'float'
    end
  end
  
  module "cbore"
else
  _ENV = {}
end

-- ***********************************************************************

local UTF8 = (
                 lpeg.R("\7\13"," ~")
               + lpeg.R("\194\223") * lpeg.R("\128\191")
               + lpeg.R("\224\239") * lpeg.R("\128\191") * lpeg.R("\128\191")
               + lpeg.R("\240\224") * lpeg.R("\128\191") * lpeg.R("\128\191") * lpeg.R("\128\191")
	     )^0

-- ***********************************************************************

function UINT(n)
  return cbor5.encode(0x00,n)
end

-- ***********************************************************************

function NINT(n)
  return cbor5.encode(0x20,-1 - n)
end

-- ***********************************************************************

function BIN(b)
  if not b then
    return "\95"
  else
    return cbor5.encode(0x40,#b) .. b
  end
end

-- ***********************************************************************

function TEXT(s)
  if not s then
    return "\127"
  else
    assert(UTF8:match(s) > #s)
    return cbor5.encode(0x60,#s) .. s
  end
end

-- ***********************************************************************

function ARRAY(array)
  if not array then
    return "\159"
  elseif type(array) == 'number' then
    return cbor5.encode(0x80,array)
  end
  
  local res = cbor5.encode(0x80,#array)
  for _,item in ipairs(array) do
    res = res .. encode(item)
  end
  return res
end

-- ***********************************************************************

function MAP(map)
  if not map then
    return "\191"
  elseif type(map) == 'number' then
    return cbor5.encode(0xA0,map)
  end
  
  local res = ""
  local cnt = 0
  for key,value in pairs(map) do
    res = res .. encode(key)
    res = res .. encode(value)
    cnt = cnt + 1
  end
  return cbor5.encode(0xA0,cnt) .. res
end

-- ***********************************************************************

TAG = setmetatable(
  {
    _datetime = function(value)
      return cbor5.encode(0xC0,0) .. TEXT(value)
    end,
    
    _epoch = function(value)
      assert(type(value) == 'number',"_epoch exepcts a number")
      return cbor5.encode(0xC0,1) .. encode(value)
    end,
    
    _pbignum = function(value)
      return cbor5.encode(0xC0,2) .. BIN(value)
    end,
    
    _nbignum = function(value)
      return cbor5.encode(0xC0,3) .. BIN(value)
    end,
    
    _decimalfraction = function(value)
      assert(type(value)    == 'table', "_decimalfractoin expects an array")
      assert(#value         == 2,       "_decimalfraction expects a two item array")
      assert(type(value[1]) == 'number',"_decimalfraction expects number as first element")
      assert(type(value[2]) == 'number',"_decimalfraction expects number as second element")
      
      return cbor5.encode(0xC0,4) .. ARRAY(value)
    end,
    
    _bigfloat = function(value)
      assert(type(value)         == 'table',  "_bigfloat expects an array")
      assert(#value              == 2,        "_bigfloat expects a two item array")
      assert(type(value[1])      == 'number', "_bigfloat expects a number as first element")
      assert(math.type(value[2]) == 'integer',"_bigfloat expecta an integer as second element")
      
      return cbor5.encode(0xC0,5) .. ARRAY(value)
    end,
    
    _tobase64url = function(value)
      return cbor5.encode(0xC0,21) .. encode(value)
    end,
    
    _tobase64 = function(value)
      return cbor5.encode(0xC0,22) .. encode(value)
    end,
    
    _tobase16 = function(value)
      return cbor5.encode(0xC0,23) .. encode(value)
    end,
    
    _cbor = function(value)
      return cbor5.encode(0xC0,24) .. BIN(value)
    end,
    
    _url = function(value)
      return cbor5.encode(0xC0,32) .. TEXT(value)
    end,
    
    _base64url = function(value)
      return cbor5.encode(0xC0,33) .. TEXT(value)
    end,
    
    _base64 = function(value)
      return cbor5.encode(0xC0,34) .. TEXT(value)
    end,
    
    _regex = function(value)
      return cbor5.encode(0xC0,35) .. TEXT(value)
    end,
    
    _mime = function(value)
      return cbor5.encode(0xC0,36) .. TEXT(value)
    end,

    _magic_cbor = function()
      return cbor5.encode(0xC0,55799)
    end,

    -- ------------------------------------------------------
    -- Extensions
    -- ------------------------------------------------------
    
    _nthstring = function()
      -- 25
    end,
    
    _perlobj = function()
      -- 26
    end,
    
    _serialobj = function()
      -- 27
    end,
    
    _shareable = function()
      -- 28,
    end,
    
    _shared = function()
      -- 29,
    end,
    
    _rational = function()
      -- 30
    end,
    
    _uuid = function(value) -- extension
      return cbor5.encode(0xC0,37) .. BIN(value)
    end,
    
    _langstring = function()
      -- 38
    end,
    
    _id = function()
      -- 39
    end,
    
    _stringref = function()
      -- 256
    end,
    
    _bmime = function()
      -- 257
    end,
    
    _decimalfractionexp = function()
      -- 264
    end,
    
    _bigfloatexp = function()
      -- 265
    end,
    
    _indirection = function()
      -- 22098
    end,
  },
  {
    __index = function(_,key)
      if type(key) ~= 'number' then
        return nil
      end
      
      return function(value)
        return cbor5.encode(0xC0,key) .. encode(value)
      end
    end
  }
)

-- ***********************************************************************

SIMPLE =
{
  ['false'] = function()
    return "\244"
  end,
  
  ['true'] = function()
    return "\245"
  end,
  
  null = function()
    return "\246"
  end,
  
  undefined = function()
    return "\247"
  end,
  
  half = function(h)
    return cbor5.encode(0xE0,25,h)
  end,
  
  single = function(s)
    return cbor5.encode(0xE0,26,s)
  end,
  
  double = function(d)
    return cbor5.encode(0xE0,27,d)
  end,
  
  __break = function()
    return "\255"
  end,
}

-- ***********************************************************************

local function generic(v)
  local mt = getmetatable(v)
  if not mt then
    if type(v) == 'table' then
      if #v > 0 then
        return ARRAY(v)
      else
        return MAP(v)
      end
    else
      error(string.format("Cannot encode %s",type(v)))
    end
  end
  
  if mt.__tocbor then
    return mt.__tocbor(v)
  
  elseif mt.__len then
    return ARRAY(v)
    
  elseif _VERSION >= "Lua 5.2" and mt.__ipairs then
    return ARRAY(v)
  
  elseif _VERSION >= "Lua 5.3" and mt.__pairs then
    return MAP(v)
  
  else
    error(string.format("Cannot encode %s",type(v)))
  end
end

-- ***********************************************************************

__ENCODE_MAP =
{
  ['nil'] = SIMPLE.null,
  
  ['boolean'] = function(b)
    if b then
      return SIMPLE['true']()
    else
      return SIMPLE['false']()
    end
  end,
  
  ['number'] = function(value)
    if math.type(value) == 'integer' then
      if value < 0 then
        return NINT(value)
      else
        return UINT(value)
      end
    else
      return cbor5.encode(0xE0,nil,value)
    end
  end,
  
  ['string'] = function(value)
    if UTF8:match(value) > #value then
      return TEXT(value)
    else
      return BIN(value)
    end
  end,
  
  ['table']    = generic,
  ['function'] = generic,
  ['userdata'] = generic,
  ['thread']   = generic,
}

-- ***********************************************************************

function encode(value)
  return __ENCODE_MAP[type(value)](value)
end

-- ***********************************************************************

if _VERSION > "Lua 5.1" then
  return _ENV
end
