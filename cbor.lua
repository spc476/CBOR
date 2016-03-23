local dump = require "org.conman.table".dump

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
-- Desc:	Encode and decodes CBOR data.
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
--			*** extended types
--			* false		false value	(Lua false)
--			* true		true value	(Lua true)
--			* null		NULL value	(Lua nil)
--			* undefined	undefined value	(Lua nil)
--			* half		half precicion   IEEE 754 float
--			* single	single precision IEEE 754 float
--			* double	double precision IEEE 754 float
--			* __break	SEE NOTES
--			*** tagged types
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
--			* _uuid		UUID value (BIN)
--			* _magic_cbor	itself (no data, used to self-describe CBOR data)
--			* _shareable	sharable resource (ARRAY or MAP)
--			* _sharedref	reference (UINT)
--			*** Lua CBOR library types
--			* __error	error parsing (TEXT)
--		data (any) decoded CBOR data
--		pos (integer) position parsing stopped
--
-- NOTES:	The __break type is used to indicate the end of an indefinite
--		array or map.
--
-- ********************************************************************

local _VERSION = _VERSION
local assert   = assert
local error    = error
local pcall    = pcall
local type     = type
local pairs    = pairs
local load     = load

local math     = require "math"
local string   = require "string"
local table    = require "table"
local debug    = require "debug"
local lpeg     = require "lpeg"
local cbor5    = require "cbor5"

if _VERSION == "Lua 5.1" then
  function math.type(n)
    if n == math.huge or n == -math.huge then
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

-- ***********************************************************************

local function throw(pos,...)
  error({ pos = pos , msg = string.format(...)},2)
end

-- ***********************************************************************
-- Usage:	bool = cbor.isnumber(type)
-- Desc:	returns true of the given CBOR type is a number
-- Input:	type (enum/cbor) CBOR type
-- Return:	bool (boolean) true if number, false otherwise
-- ***********************************************************************

function isnumber(type)
  return type == 'UINT'
      or type == 'NINT'
      or type == 'half'
      or type == 'single'
      or type == 'double'
end

-- ***********************************************************************
-- Usage:	bool = cbor.isinteger(type)
-- Desc:	returns true if the given CBOR type is an integer
-- Input:	type (enum/cbor) CBOR type
-- Return:	bool (boolean) true if number, false othersise
-- ***********************************************************************

function isinteger(type)
  return type == 'UINT'
      or type == 'NINT'
end

-- ***********************************************************************
-- Usage:	bool = cbor.isfloat(type)
-- Desc:	returns true if the given CBOR type is a float
-- Input:	type (enum/cbor) CBOR type
-- Return:	bool (boolean) true if number, false otherwise
-- ***********************************************************************

function isfloat(type)
  return type == 'half'
      or type == 'single'
      or type == 'double'
end  

-- ***********************************************************************

local SHAREDREFS
local TAGS =
{
  [0] = function(packet,pos)
    local type,value,pos = decode1(packet,pos)
    if type == 'TEXT' then
      return '_datetime',value,pos
    else
      throw(pos,"_datetime: wanted TEXT, got %s",type)
    end
  end,
  
  [1] = function(packet,pos)
    local type,value,pos = decode1(packet,pos)
    if isnumber(type) then
      return '_epoch',value,pos
    else
      throw(pos,"_epoch: wanted number, got %s",type)
    end
  end,
  
  [2] = function(packet,pos)
    local type,value,pos = decode1(packet,pos)
    if type == 'BIN' then
      return '_pbignum',value,pos
    else
      throw(pos,"_pbignum: wanted BIN, got %s",type)
    end
  end,
  
  [3] = function(packet,pos)
    local type,value,pos = decode1(packet,pos)
    if type == 'BIN' then
      return '_nbignum',value,pos
    else
      throw(pos,"_nbignum: wanted BIN, got %s",type)
    end
  end,
  
  [4] = function(packet,pos)
    local type,value,pos = decode1(packet,pos)
    if type ~= 'ARRAY' then throw(pos,"_decimalfraction: wanted ARRAY, got %s",type) end
    if value ~= 2 then throw(pos,"_decimalfraction: wanted ARRAY[2], got ARRAY[%s]",value) end
    result = {}
    type,result.exp,pos = decode1(packet,pos)
    if not isinteger(type) then throw(pos,"_decimalfraction: wanted integer for exp, got %s",type) end
    type,result.mantissa,pos = decode1(packet,pos)
    if not isinteger(type) then throw(pos,"_decimalfraction: wanted integer for mantissa, got %s",type) end
    return '_decimalfraction',result,pos
  end,
  
  [5] = function(packet,pos)
    local type,value,pos = decode1(packet,pos)
    if type ~= 'ARRAY' then throw(pos,"_bigfloat: wanted ARRAY, got %s",type) end
    if value ~= 2 then throw(pos,"_bigfloat: watned ARRAY[2], got ARRAY[%s]",value) end
    result = {}
    type,result.exp,pos = decode1(packet,pos)
    if not isnumber(type) then throw(pos,"_bigfloat: wanted number for exp, got %s",type) end
    type,result.mantissa,pos = decode1(packet,pos)
    if not isinteger(type) then throw(pos,"_bigfloat: wanted integer for mantissa, got %s",type) end
    return '_bigfloat',result,pos
  end,
  
  [21] = function(packet,pos)
    local type,value,pos = decode1(packet,pos)
    return '_tobase64url',value,pos
  end,
  
  [22] = function(packet,pos)
    local type,value,pos = decode1(packet,pos)
    return '_tobase64',value,pos
  end,
  
  [23] = function(packet,pos)
    local type,value,pos = decode1(packet,pos)
    return '_tobase16',value,pos
  end,
  
  [24] = function(packet,pos)
    local type,value,pos = decode1(packet,pos)
    if type == 'BIN' then
      return '_CBOR',value,pos
    else
      throw(pos,"_CBOR: wanted BIN, got %s",type)
    end
  end,
  
  [28] = function(packet,pos,value,conv)
    local type,value,pos = decode1(packet,pos,conv)
    if type == 'ARRAY' then
      local a = {}
      table.insert(SHAREDREFS,a)
      local v,pos = getarray(value,packet,pos,conv,a)
      return '_shareable',v,pos
    elseif type == 'MAP' then
      local m = {}
      table.insert(SHAREDREFS,m)
      local v,pos = getmap(value,packet,pos,conv,m)
      return '_shareable',v,pos
    else
      throw(pos,"_shareable: wanted ARRAY or MAP, got %s",type)
    end
  end,
  
  [29] = function(packet,pos)
    local type,value,pos = decode1(packet,pos,conv)
    if type == 'UINT' then
      local t = SHAREDREFS[value + 1]
      if not t then
        throw(pos,"_sharedref: unexpected reference %d",value)
      else
        return "_sharedref",t,pos
      end
    else
      throw(pos,"_sharedref: wanted UINT, got %s",type)
    end
  end,
  
  [32] = function(packet,pos)
    local type,value,pos = decode1(packet,pos)
    if type == 'TEXT' then
      return '_url',value,pos
    else
      throw(pos,"_url: wanted TEXT, got %s",type)
    end
  end,
  
  [33] = function(packet,pos)
    local type,value,pos = decode1(packet,pos)
    if type == 'TEXT' then
      return '_base64url',value,pos
    else
      throw(pos,"_base64url: wanted TEXT, got %s",type)
    end
  end,
  
  [34] = function(packet,pos)
    local type,value,pos = decode1(packet,pos)
    if type == 'TEXT' then
      return '_base64',value,pos
    else
      throw(pos,"_base64: wanted TEXT, got %s",type)
    end
  end,
  
  [35] = function(packet,pos)
    local type,value,pos = decode1(packet,pos)
    if type == 'TEXT' then
      return '_regex',value,pos
    else
      throw(pos,"_regex: wanted TEXT, got %s",type)
    end
  end,
  
  [36] = function(packet,pos)
    local type,value,pos = decode1(packet,pos)
    if type == 'TEXT' then
      return '_MIME',value,pos
    else
      throw(pos,"_MIME: wanted TEXT, got %s",type)
    end
  end,
  
  [37] = function(packet,pos)
    local type,value,pos = decode1(packet,pos)
    if type == 'BIN' then
      return '_UUID',value,pos
    else
      throw(pos,"_UUID: wanted BIN, got %s",type)
    end
  end,
  
  [55799] = function(packet,pos)
    return '_MAGIC_CBOR','CBOR',pos
  end,
}

-- ***********************************************************************

local EXT_TYPES = 
{
  [20] = function(packet,pos,value)
    return 'false',false,pos
  end,
  
  [21] = function(packet,pos,value)
    return 'true',true,pos
  end,
  
  [22] = function(packet,pos,value)
    return 'null',nil,pos
  end,
  
  [23] = function(packet,pos,value)
    return 'undefined',nil,pos
  end,
  
  [25] = function(packet,pos,value)
    return 'half',cbor5.unpackf(value),pos
  end,
  
  [26] = function(packet,pos,value)
    return 'single',cbor5.unpackf(value),pos
  end,
  
  [27] = function(packet,pos,value)
    return 'double',cbor5.unpackf(value),pos
  end,
  
  [31] = function(packet,pos,value)
    return '__break',false,pos
  end,
}

-- ***********************************************************************

local function bintext(packet,pos,info,value,type)
  if info < 28 then
    local value = cbor5.unpacki(value) - 1
    if pos + value > #packet then
      throw(pos,"%s: no more input (%d %d)",type,pos+value,#packet)
    end
    
    local data = packet:sub(pos,pos + value)
    return type,data,pos + value + 1
  else
    if info ~= 31 then
      throw(pos,"%s format %d not supported",type,info)
    end
    
    local acc = {}
    local t,value
    
    while true do
      t,value,pos = decode1(packet,pos)
      if t == '__break' then break end
      if t ~= type then throw(pos,"%s: expecting %s, got %s",type,type,t) end
      table.insert(acc,value)
    end
    
    return type,table.concat(acc),pos
  end
end

-- ***********************************************************************
--
-- Decodes the major eight types of CBOR encoded data.  These return the
-- base types.
--
-- ***********************************************************************

local TYPES =
{
  -- ------------------------------------------
  -- UINT	unsigned integers
  -- ------------------------------------------
  
  function(packet,pos,info,value)
    if info < 28 then
      return 'UINT',cbor5.unpacki(value),pos
    else
      throw(pos,"UINT format %d not supported",info)
    end
  end,
  
  -- ------------------------------------------
  -- NINT	negative integers
  -- ------------------------------------------
  
  function(packet,pos,info,value)
    if info < 28 then
      return 'NINT',-1 - cbor5.unpacki(value),pos
    else
      throw(pos,"NINT format %d not supported",info)
    end
  end,
  
  -- ------------------------------------------
  -- BIN	binary string
  -- ------------------------------------------
  
  function(packet,pos,info,value)
    return bintext(packet,pos,info,value,'BIN')
  end,
  
  -- ------------------------------------------
  -- TEXT	UTF-8 string
  -- ------------------------------------------
  
  function(packet,pos,info,value)
    return bintext(packet,pos,info,value,'TEXT')
  end,
  
  -- ------------------------------------------
  -- ARRAY	Array of types, value is item count
  -- ------------------------------------------
  
  function(packet,pos,info,value)
    if info < 28 then
      return 'ARRAY',cbor5.unpacki(value),pos
    elseif info == 31 then
      return 'ARRAY',math.huge,pos
    else
      throw(pos,"ARRAY format %d not supported",info)
    end
  end,
  
  -- ------------------------------------------
  -- MAP	name/value structures, value is pair count
  -- ------------------------------------------
  
  function(packet,pos,info,value)
    if info < 28 then
      return 'MAP',cbor5.unpacki(value),pos
    elseif info == 31 then
      return 'MAP',math.huge,pos
    else
      throw(pos,"MAP format %d not supported",info)
    end
  end,
  
  -- ------------------------------------------
  -- TAG	tagged data
  -- ------------------------------------------
  
  function(packet,pos,info,value,conv)
    local value = cbor5.unpacki(value)
    if TAGS[value] then
      return TAGS[value](packet,pos,value,conv)
    else
      throw(pos,"TAG type %d not supported",value)
    end
  end,
  
  -- ------------------------------------------
  -- EXT_TYPES	other (extended) values.
  -- ------------------------------------------
  
  function(packet,pos,info,value)
    if EXT_TYPES[info] then
      return EXT_TYPES[info](packet,pos,value)
    else
      throw(pos,"EXT_TYPES type %d not supported",info)
    end
  end,
}

-- ***********************************************************************
-- Usage:	cbortype,data,pos = cbor.decode1(packet[,pos])
-- Desc:	Decode a CBOR instance of data
-- Input:	packet (binary) CBOR encoded data
--		pos (integer/optional) startind position to decode
-- Return:	cbortype (enum/cbor)
--		data (any) deocded CBOR item
--		pos (integer) next byte to be parsed
--
-- Note:	This will not collect ARRAYS or MAPS.
-- ***********************************************************************

function decode1(packet,pos,conv)
  local pos = pos or 1

  local function readvalue(pos)
    local byte = packet:sub(pos):byte()
    local type = math.floor(byte / 32) + 1
    local info = byte % 32
    local value
    
    pos = pos + 1
    
    if info == 24 then
      value = packet:sub(pos,pos)
      pos = pos + 1
    elseif info == 25 then
      value = packet:sub(pos,pos+1)
      pos = pos + 2
    elseif info == 26 then
      value = packet:sub(pos,pos+3)
      pos = pos + 4
    elseif info == 27 then
      value = packet:sub(pos,pos+7)
      pos   = pos + 8
    else
      value = string.char(info)
    end
    
    if pos > #packet + 1 then
      error "bad input"
    end
    
    return type,info,value,pos
  end
  
  local okay,type,info,value,npos = pcall(readvalue,pos)
  
  if not okay then
    error { pos = pos , msg = "unexpected end of input" }
  end
  
  return TYPES[type](packet,npos,info,value,conv)
end

-- ***********************************************************************

function getarray(max,packet,pos,conv,a)
  local a = a or {}
  local ctype
  local value
  
  for i = 1 , max do
    ctype,value,pos = decode1(packet,pos,conv)
    
    if ctype == '__break' then break end
    
    if ctype == 'ARRAY' then
      value,pos = getarray(value,packet,pos,conv)
    elseif ctype == 'MAP' then
      value,pos = getmap(value,packet,pos,conv)
    end
    
    if conv[ctype] then
      value,pos = conv[ctype](value,ctype,packet,pos)
    end
    
    a[i] = value
  end
  
  return a,pos
end

-- ***********************************************************************

function getmap(max,packet,pos,conv,m)
  local m = m or {}
  local kctype,key
  local vctype,val
  
  for i = 1 , max do
    kctype,key,pos = decode1(packet,pos,conv)
    
    if kctype == '__break' then break end
    
    if kctype == 'ARRAY' then
      key,pos = getarray(key,packet,pos,conv)
    elseif kctype == 'MAP' then
      key,pos = getmap(key,packet,pos,conv)
    end
    
    if conv[kctype] then
      key,pos = conv[kctype](key,kctype,packet,pos)
    end
    
    vctype,val,pos = decode1(packet,pos,conv)
    if vctype == 'ARRAY' then
      val,pos = getarray(val,packet,pos,conv)
    elseif vctype == 'MAP' then
      val,pos = getmap(val,packet,pos,conv)
    end
    
    if conv[vctype] then
      val,pos = conv[vctype](val,vctype,packet,pos)
    end
    
    m[key] = val
  end
  
  return m,pos
end

-- ***********************************************************************
-- Usage:	cbortype,data,pos = cbor.decode1(packet[,pos,[conv]])
-- Desc:	Decode a CBOR instance of data
-- Input:	packet (binary) CBOR encoded data
--		pos (integer/optional) startind position to decode
--		conv (table/optional) converstion routines for extended
--			| or tagged data
-- Return:	cbortype (enum/cbor)
--		data (any) deocded CBOR item
--		pos (integer) next byte to be parsed
--
-- Note:	This will return a Lua table for an ARRAY or MAP.
--
-- 		The conversion table, should be constructed as:
--
--		{
--		  UINT      = function(v) return munge(v) end,
--		  _datetime = function(v) return munge(v) end,
--		  _url      = function(v) return munge(v) end
--		}
--
--		Any types not specified will return the value as-is.
--
-- ***********************************************************************
    
function decode(packet,pos,conv)
  local pos  = pos  or 1
  local conv = conv or {}
  
  local function decode_ex()
    local ctype
    local value
    
    ctype,value,pos = decode1(packet,pos,conv)
    if ctype == 'ARRAY' then
      value,pos = getarray(value,packet,pos,conv)
    elseif ctype == 'MAP' then
      value,pos = getmap(value,packet,pos,conv)
    end
    
    if conv[ctype] then
      value,pos = conv[ctype](value,ctype,packet,pos,conv)
    end
    
    return ctype,value,pos
  end
  
  SHAREDREFS = {}
  
  local okay,ctype,value,npos = pcall(decode_ex)
  
  if okay then
    return ctype,value,npos
  else
    dump("err",ctype)
    return '__error',ctype.msg,ctype.pos - 1
  end
end

-- ***********************************************************************

local UTF8 = (
                 lpeg.R("\7\13"," ~")
               + lpeg.R("\194\223") * lpeg.R("\128\191")
               + lpeg.R("\224\239") * lpeg.R("\128\191") * lpeg.R("\128\191")
               + lpeg.R("\240\224") * lpeg.R("\128\191") * lpeg.R("\128\191") * lpeg.R("\128\191")               
	     )^0

function encode(value,cache)
  if type(value) == 'nil' then
    return "\246"
  
  elseif type(value) == 'boolean' then
    if value then
      return "\245"
    else
      return "\244"
    end
  
  elseif type(value) == 'number' then
    if math.type(value) == 'integer' then
      if value >= 0 then
        return cbor5.packi(0,value)
      else
        return cbor5.packi(0x20,-1 - value)
      end
    else
      return cbor5.packf(value)
    end
  
  elseif type(value) == 'string' then
    if UTF8:match(value) > #value then
      return cbor5.packi(0x60,#value) .. value
    else
      return cbor5.packi(0x40,#value) .. value
    end
  
  elseif type(value) == 'table' then
    local count = 0
    local tres  = {}
    
    if not cache then
      cache = {}
    end
    
    table.insert(cache,value)
    cache[value] = #cache
    
    for k,v in pairs(value) do
      count = count + 1
      if type(k) == 'table' and cache[k] then
        table.insert(tres,cbor5.packi(0xC0,29))
        table.insert(tres,cbor5.packi(0,cache[k] - 1))
      else
        table.insert(tres,encode(k,cache))
      end
      if type(v) == 'table' and cache[v] then
        table.insert(tres,cbor5.packi(0xC0,29))
        table.insert(tres,cbor5.packi(0,cache[v] - 1))
      else
        table.insert(tres,encode(v,cache))
      end
    end
    
    return string.char(0xD8,0x1C) 
        .. cbor5.packi(0xA0,count) 
        .. table.concat(tres)
  end
end

-- ***********************************************************************

if _VERSION >= "Lua 5.2" then
  return _ENV
end
