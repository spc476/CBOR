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
-- Desc:	Decodes CBOR data.
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
--			* SIMPLE	SEE NOTES       (Lua number)
--			* false		false value	(Lua false)
--			* true		true value	(Lua true)
--			* null		NULL value	(Lua nil)
--			* undefined	undefined value	(Lua nil)
--			* half		half precicion   IEEE 754 float
--			* single	single precision IEEE 754 float
--			* double	double precision IEEE 754 float
--			* __break	SEE NOTES
--			*** tagged types
--			* TAG_*		unsupported tag type (Lua number)
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

local math     = require "math"
local string   = require "string"
local table    = require "table"
local lpeg     = require "lpeg"
local cbor5    = require "cbor5"

local _LUA_VERSION = _VERSION
local error        = error
local pcall        = pcall
local assert       = assert
local getmetatable = getmetatable
local setmetatable = setmetatable
local pairs        = pairs
local ipairs       = ipairs
local type         = type

if _LUA_VERSION == "Lua 5.1" then
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
  
  module "cbor"
else
  _ENV = {}
end

_VERSION = cbor5._VERSION

-- ***********************************************************************

local UTF8 = (
                 lpeg.R("\7\13"," ~")
               + lpeg.R("\194\223") * lpeg.R("\128\191")
               + lpeg.R("\224\239") * lpeg.R("\128\191") * lpeg.R("\128\191")
               + lpeg.R("\240\224") * lpeg.R("\128\191") * lpeg.R("\128\191") * lpeg.R("\128\191")
	     )^0

-- ***********************************************************************

local function throw(pos,...)
  error( { pos = pos , msg = string.format(...) } , 2)
end

-- ***********************************************************************
-- Usage:       bool = cbor.isnumber(ctype)
-- Desc:        returns true of the given CBOR type is a number
-- Input:       type (enum/cbor) CBOR type
-- Return:      bool (boolean) true if number, false otherwise
-- ***********************************************************************

function isnumber(ctype)
  return ctype == 'UINT'
      or ctype == 'NINT'
      or ctype == 'half'
      or ctype == 'single'
      or ctype == 'double'
end

-- ***********************************************************************
-- Usage:       bool = cbor.isinteger(ctype)   
-- Desc:        returns true if the given CBOR type is an integer
-- Input:       ctype (enum/cbor) CBOR type
-- Return:      bool (boolean) true if number, false othersise
-- ***********************************************************************

function isinteger(ctype)
  return ctype == 'UINT'
      or ctype == 'NINT'
end

-- ***********************************************************************
-- Usage:       bool = cbor.isfloat(ctype)
-- Desc:        returns true if the given CBOR type is a float
-- Input:       ctype (enum/cbor) CBOR type
-- Return:      bool (boolean) true if number, false otherwise
-- ***********************************************************************

function isfloat(ctype)
  return ctype == 'half'
      or ctype == 'single'
      or ctype == 'double'
end  

-- ***********************************************************************
-- usage:	ctype2,value2,pos2 = bintext(packet,pos,info,value,conv,ref,ctype)
-- desc:	Decode a CBOR BIN or CBOR TEXT into a Lua string
-- input:	packet (binary) binary blob
--		pos (integer) byte position in packet
--		info (integer) CBOR info value (0..31)
--		value (integer) string length
--		conv (table) conversion routines (passed to decode())
--		ref (table) reference table
--		ctype (enum/cbor) 'BIN' or 'TEXT'
-- return:	ctype2 (enum/cbor) 'BIN' or 'TEXT'
--		value2 (string) string from packet
--		pos2 (integer) position past string just extracted
-- ***********************************************************************

local function bintext(packet,pos,info,value,conv,ref,ctype)
  if info < 31 then
    local data = packet:sub(pos,pos + value - 1)
    return ctype,data,pos + value
  else
    local acc = {}
    local t,nvalue
    
    while true do
      t,nvalue,pos = decode(packet,pos,conv,ref)
      if t == '__break' then
        break;
      end
      if t ~= ctype then
        throw(pos,"%s: expecting %s, got %s",ctype,ctype,t)
      end
      table.insert(acc,nvalue)
    end
    
    return ctype,table.concat(acc),pos
  end
end

-- ***********************************************************************
--
--                             CBOR base TYPES
--
-- Both encoding and decoding functions for CBOR base types are here.
--
-- Usage:	blob = cbor.TYPE['name'](n)
-- Desc:	Encode a CBOR base type
-- Input:	n (integer string table) Lua type (see notes)
-- Return:	blob (binary) CBOR encoded value
--
-- Note:	UINT and NINT take an integer.
--
--		BIN and TEXT take a string.  TEXT will check to see if
--		the text is well formed UTF8 and throw an error if the
--		text is not valid UTF8.
--
--		ARRAY and MAP take a table of an appropriate type. No
--		checking is done of the passed in table, so a table
--		of just name/value pairs passed in to ARRAY will return
--		an empty CBOR encoded array.
--
--		TAG and SIMPLE encoding are handled elsewhere.
--
-- Usage:	ctype,value2,pos2 = cbor.TYPE[n](packet,pos,info,value,conv,ref)
-- Desc:	Decode a CBOR base type
-- Input:	packet (binary) binary blob of CBOR data
--		pos (integer) byte offset in packet to start parsing from
--		info (integer) CBOR info (0 .. 31)
--		value (integer) CBOR decoded value
--		conv (table) conversion table (passed to decode())
--		ref (table) used to generate references (TAG types only)
-- Return:	ctype (enum/cbor) CBOR deocded type
--		value2 (any) decoded CBOR value
--		pos2 (integer) byte offset just past parsed data
--
-- Note:	tag_* is returned for any non-supported TAG types.  The
--		actual format is 'tag_' <integer value>---for example,
--		'tag_1234567890'.  Supported TAG types will return the
--		appropriate type name.
--
--		simple is returned for any non-supported SIMPLE types. 
--		Supported simple types will return the appropriate type
--		name.
--
-- ***********************************************************************

TYPE =
{
  UINT = function(n)
    return cbor5.encode(0x00,n)
  end,
  
  [0x00] = function(_,pos,_,value)
    return 'UINT',value,pos
  end,
  
  -- =====================================================================
  
  NINT = function(n)
    return cbor5.encode(0x20,-1 - n)
  end,
  
  [0x20] = function(_,pos,_,value)
    return 'NINT',-1 - value,pos
  end,
  
  -- =====================================================================
  
  BIN = function(b)
    if not b then
      return "\95"
    else
      return cbor5.encode(0x40,#b) .. b
    end
  end,
  
  [0x40] = function(packet,pos,info,value,conv,ref)
    return bintext(packet,pos,info,value,conv,ref,'BIN')
  end,
  
  -- =====================================================================
  
  TEXT = function(s)
    if not s then
      return "\127"
    else
      assert(UTF8:match(s) > #s)
      return cbor5.encode(0x60,#s) .. s
    end
  end,
  
  [0x60] = function(packet,pos,info,value,conv,ref)
    return bintext(packet,pos,info,value,conv,ref,'TEXT')
  end,
  
  -- =====================================================================
  
  ARRAY = function(array)
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
  end,
  
  [0x80] = function(packet,pos,_,value,conv,ref)
    local acc = {}
    
    for i = 1 , value do
      local ctype,avalue,npos = decode(packet,pos,conv,ref)
      if ctype == '__break' then return 'ARRAY',acc,npos end
      acc[i] = avalue
      pos    = npos
    end
    return 'ARRAY',acc,pos
  end,
  
  -- =====================================================================
  
  MAP = function(map)
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
  end,
  
  [0xA0] = function(packet,pos,_,value,conv,ref)
    local acc = {}
    for _ = 1 , value do
      local nctype,nvalue,npos = decode(packet,pos,conv,ref,true)
      if nctype == '__break' then return 'MAP',acc,npos end
      local _,vvalue,npos = decode(packet,npos,conv,ref)
      acc[nvalue] = vvalue
      pos         = npos
    end
    return 'MAP',acc,pos
  end,
  
  -- =====================================================================
  
  [0xC0] = function(packet,pos,_,value,conv,ref)
    return TAG[value](packet,pos,conv,ref)
  end,

  -- =====================================================================
  
  [0xE0] = function(_,pos,info,value)
    return SIMPLE[info](pos,value)
  end,
}

-- ***********************************************************************
--
--                             CBOR TAG values
--
-- Encoding and decoding of CBOR TAG types are here.
--
-- Usage:	blob = cbor.TAG['name'](value)
-- Desc:	Encode a CBOR tagged value
-- Input:	value (any) any Lua type
-- Return:	blob (binary) CBOR encoded tagged value
--
-- Note:	Some tags only support a subset of Lua types.
--
-- Usage:	ctype,value,pos2 = cbor.TAG[n](packet,pos,conv,ref)
-- Desc:	Decode a CBOR tagged value
-- Input:	packet (binary) binary blob of CBOR tagged data
--		pos (integer) byte offset into packet
--		conv (table) conversion routines (passed to decode())
--		ref (table) reference table
-- Return:	ctype (enum/cbor) CBOR type of value
--		value (any) decoded CBOR tagged value
--		pos2 (integer) byte offset just past parsed data
--
-- ***********************************************************************

TAG = setmetatable(
  {
    _datetime = function(value)
      return cbor5.encode(0xC0,0) .. TYPE.TEXT(value)
    end,
    
    [0] = function(packet,pos,conv,ref)
      local ctype,value,npos = decode(packet,pos,conv,ref)
      if type == 'TEXT' then
        return '_datetime',value,npos
      else
        throw(pos,"_datetime: wanted TEXT, got %s",ctype)
      end
    end,
    
    -- =====================================================================
    
    _epoch = function(value)
      assert(type(value) == 'number',"_epoch expects a number")
      return cbor5.encode(0xC0,1) .. encode(value)
    end,
    
    [1] = function(packet,pos,conv,ref)
      local ctype,value,npos = decode(packet,pos,conv,ref)
      if isnumber(ctype) then
        return '_epoch',value,npos
      else
        throw(pos,"_epoch: wanted number, got %s",ctype)
      end
    end,
    
    -- =====================================================================
    
    _pbignum = function(value)
      return cbor5.encode(0xC0,2) .. TYPE.BIN(value)
    end,
    
    [2] = function(packet,pos,conv,ref)
      local ctype,value,npos = decode(packet,pos,conv,ref)
      if ctype == 'BIN' then
        return '_pbignum',value,npos
      else
        throw(pos,"_pbignum: wanted BIN, got %s",ctype)
      end
    end,
    
    -- =====================================================================
    
    _nbignum = function(value)
      return cbor5.encode(0xC0,3) .. TYPE.BIN(value)
    end,
    
    [3] = function(packet,pos,conv,ref)
      local ctype,value,npos = decode(packet,pos,conv,ref)
      if ctype == 'BIN' then
        return '_nbignum',value,npos
      else
        throw(pos,"_nbignum: wanted BIN, got %s",ctype)
      end
    end,
    
    -- =====================================================================

    _decimalfraction = function(value)
      assert(type(value)    == 'table', "_decimalfractoin expects an array")
      assert(#value         == 2,       "_decimalfraction expects a two item array")
      assert(type(value[1]) == 'number',"_decimalfraction expects number as first element")
      assert(type(value[2]) == 'number',"_decimalfraction expects number as second element")
        
      return cbor5.encode(0xC0,4) .. TYPE.ARRAY(value)
    end,
    
    [4] = function(packet,pos,conv,ref)
      local ctype,value,npos = decode(packet,pos,conv,ref)
      if ctype ~= 'ARRAY' then throw(pos,"_decimalfraction: wanted ARRAY, got %s",ctype) end
      if value ~= 2 then throw(pos,"_decimalfraction: wanted ARRAY[2], got ARRAY[%s]",value) end
      local result = {}
      ctype,result.exp,npos = decode(packet,npos,conv,ref)
      if not isinteger(ctype) then throw(pos,"_decimalfraction: wanted integer for exp, got %s",ctype) end
      ctype,result.mantissa,npos = decode(packet,npos,conv,ref)
      if not isinteger(ctype) then throw(pos,"_decimalfraction: wanted integer for mantissa, got %s",ctype) end
      return '_decimalfraction',result,npos
    end,
    
    -- =====================================================================
    
    _bigfloat = function(value)
      assert(type(value)         == 'table',  "_bigfloat expects an array")
      assert(#value              == 2,        "_bigfloat expects a two item array")
      assert(type(value[1])      == 'number', "_bigfloat expects a number as first element")
      assert(math.type(value[2]) == 'integer',"_bigfloat expecta an integer as second element")
      
      return cbor5.encode(0xC0,5) .. TYPE.ARRAY(value)
    end,
      
    [5] = function(packet,pos,conv,ref)
      local ctype,value,npos = decode(packet,pos,conv,ref)
      if ctype ~= 'ARRAY' then throw(pos,"_bigfloat: wanted ARRAY, got %s",ctype) end
      if value ~= 2 then throw(pos,"_bigfloat: watned ARRAY[2], got ARRAY[%s]",value) end
      local result = {}
      ctype,result.exp,npos = decode(packet,pos,conv,ref)
      if not isnumber(ctype) then throw(pos,"_bigfloat: wanted number for exp, got %s",ctype) end
      ctype,result.mantissa,npos = decode(packet,pos,conv,ref)
      if not isinteger(ctype) then throw(pos,"_bigfloat: wanted integer for mantissa, got %s",ctype) end
      return '_bigfloat',result,npos
    end,
    
    -- =====================================================================
    
    _tobase64url = function(value)
      return cbor5.encode(0xC0,21) .. encode(value)
    end,
    
    [21] = function(packet,pos,conv,ref)
      local _,value,npos = decode(packet,pos,conv,ref)
      return '_tobase64url',value,npos
    end,
    
    -- =====================================================================
    
    _toase64 = function(value)
      return cbor5.encode(0xC0,22) .. encode(value)
    end,
    
    [22] = function(packet,pos,conv,ref)
      local _,value,npos = decode(packet,pos,conv,ref)
      return '_tobase64',value,npos
    end,
    
    -- =====================================================================
    
    _tobase16 = function(value)
      return cbor5.encode(0xC0,23) .. ecode(value)
    end,
    
    [23] = function(packet,pos,conv,ref)
      local _,value,npos = decode(packet,pos,conv,ref)
      return '_tobase16',value,npos
    end,
    
    -- =====================================================================
    
    _cbor = function(value)
      return cbor5.encode(0xC0,24) .. TYPE.BIN(value)
    end,
    
    [24] = function(packet,pos,conv,ref)
      local ctype,value,npos = decode(packet,pos,conv,ref)
      if ctype == 'BIN' then
        return '_cbor',value,npos
      else
        throw(pos,"_cbor: wanted BIN, got %s",ctype)
      end
    end,
    
    -- =====================================================================
    
    _url = function(value)
      return cbor5.encode(0xC0,32) .. TYPE.TEXT(value)
    end,
    
    [32] = function(packet,pos,conv,ref)
      local ctype,value,npos = decode(packet,pos,conv,ref)
      if ctype == 'TEXT' then
        return '_url',value,npos
      else
        throw(pos,"_url: wanted TEXT, got %s",ctype)
      end
    end,
    
    -- =====================================================================
    
    _base64url = function(value)
      return cbor5.encode(0xC0,33) .. TYPE.TEXT(value)
    end,
    
    [33] = function(packet,pos,conv,ref)
      local ctype,value,npos = decode(packet,pos,conv,ref)
      if ctype == 'TEXT' then
        return '_base64url',value,npos
      else
        throw(pos,"_base64url: wanted TEXT, got %s",ctype)
      end
    end,
    
    -- =====================================================================
    
    _base64 = function(value)
      return cbor5.encide(0xC0,34) .. TYPE.TEXT(value)
    end,
    
    [34] = function(packet,pos,conv,ref)
      local ctype,value,npos = decode(packet,pos,conv,ref)
      if ctype == 'TEXT' then
        return '_base64',value,npos
      else
        throw(pos,"_base64: wanted TEXT, got %s",ctype)
      end
    end,
    
    -- =====================================================================
    
    _regex = function(value)
      return cbor5.encode(0xC0,35) .. TYPE.TEXT(value)
    end,
    
    [35] = function(packet,pos,conv,ref)
      local ctype,value,npos = decode(packet,pos,conv,ref)
      if ctype == 'TEXT' then
        return '_regex',value,npos
      else
        throw(pos,"_regex: wanted TEXT, got %s",ctype)
      end
    end,
    
    -- =====================================================================
    
    _mime = function(value)
      return cbor5.encode(0xC0,36) .. TYPE.TEXT(value)
    end,
    
    [36] = function(packet,pos,conv,ref)
      local ctype,value,npos = decode(packet,pos,conv,ref)
      if ctype == 'TEXT' then
        return '_mime',value,npos
      else
        throw(pos,"_mime: wanted TEXT, got %s",ctype)
      end
    end,
    
    -- =====================================================================
    
    _magic_cbor = function()
      return cbor5.encode(0xC0,55799)
    end,
    
    [55799] = function(_,pos)
      return '_magic_cbor','_magic_cbor',pos
    end,
    
    -- ----------------------------------------------------------
    -- Following defined by IANA  
    -- http://www.iana.org/assignments/cbor-tags/cbor-tags.xhtml
    -- ----------------------------------------------------------
    
    _nthstring = function()
    end,
    
    [25] = function(_,pos)
      return '_nthstring',nil,pos
    end,
    
    -- =====================================================================
    
    _perlobj = function()
    end,
    
    [26] = function(_,pos)
      return '_perlobj',nil,pos
    end,
    
    -- =====================================================================
    
    _serialobj = function()
    end,
    
    [27] = function(_,pos)
      return '_serialobj',nil,pos
    end,
    
    -- =====================================================================
    
    _shareable = function()
    end,
    
    [28] = function(_,pos)
      return '_shareable',nil,pos
    end,
    
    -- =====================================================================
    
    _sharedref = function()
    end,
    
    [29] = function(_,pos)
      return '_sharedref',nil,pos
    end,
    
    -- =====================================================================
    
    _rational = function()
    end,
    
    [30] = function(_,pos)
      return '_rational',nil,pos
    end,
    
    -- =====================================================================
    
    _uuid = function(value)
      return cbor5.encode(0xC0,37) .. TYPE.BIN(value)
    end,
    
    [37] = function(packet,pos,conv,ref)
      local ctype,value,npos = decode(packet,pos,conv,ref)
      if ctype == 'BIN' then
        return '_uuid',value,npos
      else
        throw(pos,"_uuid: wanted BIN, got %s",ctype)
      end 
    end,
    
    -- =====================================================================
    
    _langstring = function()
    end,
    
    [38] = function(_,pos)
      return '_langstring',nil,pos
    end,
    
    -- =====================================================================
    
    _id = function()
    end,
    
    [39] = function(_,pos)
      return '_id',nil,pos
    end,
    
    -- =====================================================================
    
    _stringref = function()
    end,
    
    [256] = function(_,pos)
      return '_stringref',nil,pos
    end,
    
    -- =====================================================================
    
    _bmime = function()
    end,
    
    [257] = function(_,pos)
      return '_bmime',nil,pos
    end,
    
    -- =====================================================================
    
    _decimalfractionexp = function()
    end,
    
    [264] = function(_,pos)
      return '_decimalfractionexp',nil,pos
    end,
    
    -- =====================================================================
    
    _bigfloatexp = function()
    end,
    
    [265] = function(_,pos)
      return '_bigfloatexp',nil,pos
    end,
    
    -- =====================================================================
    
    _indirection = function()
    end,
    
    [22098] = function(_,pos)
      return '_indirection',nil,pos
    end,    
  },
  {
    __index = function(_,key)
      if type(key) == 'number' then
        return function(packet,pos,conv,ref)
          local _,value,npos = decode(packet,pos,conv,ref)
          return string.format('TAG_%d',key),value,npos
        end
        
      elseif type(key) == 'string' then
        return function(value)
          return cbor5.encode(0xC0,key) .. encode(value)
        end
      end
    end
  }
)

-- ***********************************************************************
--
--                         CBOR SIMPLE data types
--
-- Encoding and decoding of CBOR simple types are here.
--
-- Usage:	blob = cbor.SIMPLE['name'](n)
-- Desc:	Encode a CBOR simple type
-- Input:	n (number/optional) floating point number to encode (see notes)
-- Return:	blob (binary) CBOR encoded simple type
--
-- Note:	Some functions ignore the passed in parameter.  
--
--		WARNING! The functions that do not ignore the parameter may
--		throw an error if floating point precision will be lost
--		during the encoding.  Please be aware of what you are doing
--		when calling SIMPLE.half(), SIMPLE.float() or
--		SIMPLE.double().
--
-- Usage:	ctype,value2,pos = cbor.SIMPLE[n](pos,value)
-- Desc:	Decode a CBOR simple type
-- Input:	pos (integer) byte offset in packet
--		value (number/optional) floating point number
-- Return:	ctype (enum/cbor) CBOR type of value
--		value2 (any) decoded value as Lua value
--		pos (integer) original pos passed in (see notes)
--
-- Note:	The pos parameter is passed in to avoid special cases in
--		the code and to conform to all other decoding routines.
--
-- ***********************************************************************

SIMPLE = setmetatable(
  {
    ['false'] = function()
      return "\244"
    end,
    
    [20] = function(pos)
      return 'false',false,pos
    end,
    
    -- =====================================================================
    
    ['true'] = function()
      return "\245"
    end,
    
    [21] = function(pos)
      return 'true',true,pos
    end,
    
    -- =====================================================================
    
    null = function()
      return "\246"
    end,
    
    [22] = function(pos)
      return 'null',nil,pos
    end,
    
    -- =====================================================================
    
    undefined = function()
      return "\247"
    end,
    
    [23] = function(pos)
      return 'undefined',nil,pos
    end,
    
    -- =====================================================================
    
    half = function(h)
      return cbor5.encode(0xE0,25,h)
    end,
    
    [25] = function(pos,value)
      return 'half',value,pos
    end,
    
    -- =====================================================================
    
    single = function(s)
      return cbor5.encode(0xE0,26,s)
    end,
    
    [26] = function(pos,value)
      return 'single',value,pos
    end,
    
    -- =====================================================================
    
    double = function(d)
      return cbor5.encode(0xE0,27,d)
    end,
    
    [27] = function(pos,value)
      return 'double',value,pos
    end,
    
    -- =====================================================================
    
    __break = function()
      return "\255"
    end,
    
    [31] = function(pos)
      return '__break',math.huge,pos
    end,
  },
  {
    __index = function(_,key)
      if type(key) == 'number' then
        return function(pos,value)
          return 'SIMPLE',value,pos
        end
        
      elseif type(key) == 'string' then
        return function()
          cbor5.encode(0xE0,key)
        end
      end
    end
  }
)

-- ***********************************************************************

local function decode1(packet,pos,conv,ref)
  local ctype,info,value,npos = cbor5.decode(packet,pos)
  return TYPE[ctype](packet,npos,info,value,conv,ref)
end

-- ***********************************************************************
-- Usage:	ctype,value,pos2 = cbor.decode(packet,pos,conv,ref,iskey)
-- Desc:	Decode CBOR encoded data
-- Input:	packet (binary) CBOR binary blob
--		pos (integer) starting point for decoding
--		conv (table/optional) table of conversion routines
--		ref (table/optional) reference table (see notes)
--		iskey (boolean/optional) is a key in a MAP (see notes)
-- Return:	ctype (enum/cbor) CBOR type of value
--		value (any) the decoded CBOR data
--		pos2 (integer) offset past decoded data
--		conv (table) conversion routines (see note)
--
-- Note:	The conversion table should be constructed as:
--
--		{
--		  UINT      = function(v) return munge(v) end,
--		  _datetime = function(v) return munge(v) end,
--		  _url      = function(v) return munge(v) end,,
--		}
--
--		The keys are CBOR types (listed above).  These functions are
--		expected to convert the decoded CBOR type into a more
--		appropriate type for your code.  For instance, an _epoch can
--		be converted into a table.
--
--		The reference table is used (with tagging) to construct
--		references (allowing string reuse, or cycles in tables).  An
--		empty table *should* be passed in and not at all stored,
--		since it will be used by the decode() function to store data
--		as it decodes references.
--
--		The iskey is true if the value is being used as a key in a
--		map, and is passed to the conversion routine.
--
-- ***********************************************************************

function decode(packet,pos,conv,ref,iskey)
  pos  = pos  or 1
  conv = conv or {}
  
  local okay,ctype,value,npos = pcall(decode1,packet,pos,conv,ref)
  
  if okay then
    if conv[ctype] then
      value = conv[ctype](value,iskey)
    end
    return ctype,value,npos
  else
    return '__error',ctype,pos
  end
end

-- ***********************************************************************

local function generic(v)
  local mt = getmetatable(v)
  if not mt then
    if type(v) == 'table' then
      if #v > 0 then
        return TYPE.ARRAY(v)
      else
        return TYPE.MAP(v)
      end
    else
      error(string.format("Cannot encode %s",type(v)))
    end
  end
  
  if mt.__tocbor then
    return mt.__tocbor(v)
  
  elseif mt.__len then
    return TYPE.ARRAY(v)
    
  elseif _LUA_VERSION >= "Lua 5.2" and mt.__ipairs then
    return TYPE.ARRAY(v)
  
  elseif _LUA_VERSION >= "Lua 5.3" and mt.__pairs then
    return TYPE.MAP(v)
  
  else
    error(string.format("Cannot encode %s",type(v)))
  end
end

-- ***********************************************************************
--
--                              __ENCODE_MAP
--
-- A table of functions to map Lua values to CBOR encoded values.  nil,
-- boolean, number and string are handled directly (if a Lua string is valid
-- UTF8, then it's encoded as a CBOR TEXT.
--
-- For the other four types, only tables are directly supported without
-- metatable support.  If a metatable does exist, if the method '__tocbor'
-- is defined, that function is called and the results returned.  If '__len'
-- is defined, then it is mapped as a CBOR ARRAY.  For Lua 5.2, if
-- '__ipairs' is defined, then it too, is mapped as a CBOR ARRAY.  If Lua
-- 5.2 or higher and '__pairs' is defined, then it's mapped as a CBOR MAP.
--
-- Otherwise, an error is thrown.
--
-- Usage:	blob = cbor.__ENCODE_MAP[luatype](value)
-- Desc:	Encode a Lua type into a CBOR type
-- Input:	value (any) a Lua value who's type matches luatype.
-- Return:	blob (binary) CBOR encoded data
--
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
        return TYPE.NINT(value)
      else
        return TYPE.UINT(value)
      end
    else
      return cbor5.encode(0xE0,nil,value)
    end
  end,
  
  ['string'] = function(value)
    if UTF8:match(value) > #value then
      return TYPE.TEXT(value)
    else
      return TYPE.BIN(value)
    end
  end,
  
  ['table']    = generic,
  ['function'] = generic,
  ['userdata'] = generic,
  ['thread']   = generic,
}

-- ***********************************************************************
-- Usage:	blob = cbor.encode(value)
-- Desc:	Encode a Lua type into a CBOR type
-- Input:	value (any) 
-- Return:	blob (binary) CBOR encoded value
-- ***********************************************************************

function encode(value)
  return __ENCODE_MAP[type(value)](value)
end

-- ***********************************************************************

if _LUA_VERSION >= "Lua 5.2" then
  return _ENV
end
