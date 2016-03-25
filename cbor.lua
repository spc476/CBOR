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

local _LUA_VERSION = _VERSION
local error    = error
local pcall    = pcall

local string   = require "string"
local table    = require "table"
local cbor5    = require "cbor5"

if _LUA_VERSION == "Lua 5.1" then
  module "cbor"
else
  _ENV = {}
end

_VERSION = cbor5._VERSION

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

TAG =
{
  -- -------------------------------
  -- Following defined in RFC-7049
  -- -------------------------------

  [0] = function(packet,pos)
    local type,value,pos = decode1(packet,pos)
    if type == 'TEXT' then
      return '_datetime',value,pos
    else
      throw(pos,"_datetime: wanted TEXT, got %s",type)
    end
  end,
  
  -- --------------------------------------------
  
  [1] = function(packet,pos)
    local type,value,pos = decode1(packet,pos)
    if isnumber(type) then
      return '_epoch',value,pos
    else
      throw(pos,"_epoch: wanted number, got %s",type)
    end
  end,
  
  -- --------------------------------------------
  
  [2] = function(packet,pos)
    local type,value,pos = decode1(packet,pos)
    if type == 'BIN' then
      return '_pbignum',value,pos
    else
      throw(pos,"_pbignum: wanted BIN, got %s",type)
    end
  end,
  
  -- --------------------------------------------
  
  [3] = function(packet,pos)
    local type,value,pos = decode1(packet,pos)
    if type == 'BIN' then
      return '_nbignum',value,pos
    else
      throw(pos,"_nbignum: wanted BIN, got %s",type)
    end
  end,
  
  -- --------------------------------------------
  
  [4] = function(packet,pos)
    local type,value,pos = decode1(packet,pos)
    if type ~= 'ARRAY' then throw(pos,"_decimalfraction: wanted ARRAY, got %s",type) end
    if value ~= 2 then throw(pos,"_decimalfraction: wanted ARRAY[2], got ARRAY[%s]",value) end
    local result = {}
    type,result.exp,pos = decode1(packet,pos)
    if not isinteger(type) then throw(pos,"_decimalfraction: wanted integer for exp, got %s",type) end
    type,result.mantissa,pos = decode1(packet,pos)
    if not isinteger(type) then throw(pos,"_decimalfraction: wanted integer for mantissa, got %s",type) end
    return '_decimalfraction',result,pos
  end,
  
  -- --------------------------------------------
  
  [5] = function(packet,pos)
    local type,value,pos = decode1(packet,pos)
    if type ~= 'ARRAY' then throw(pos,"_bigfloat: wanted ARRAY, got %s",type) end
    if value ~= 2 then throw(pos,"_bigfloat: watned ARRAY[2], got ARRAY[%s]",value) end
    local result = {}
    type,result.exp,pos = decode1(packet,pos)
    if not isnumber(type) then throw(pos,"_bigfloat: wanted number for exp, got %s",type) end
    type,result.mantissa,pos = decode1(packet,pos)
    if not isinteger(type) then throw(pos,"_bigfloat: wanted integer for mantissa, got %s",type) end
    return '_bigfloat',result,pos
  end,
  
  -- --------------------------------------------
  
  [21] = function(packet,pos)
    local _,value,pos = decode1(packet,pos)
    return '_tobase64url',value,pos
  end,
  
  -- --------------------------------------------
  
  [22] = function(packet,pos)
    local _,value,pos = decode1(packet,pos)
    return '_tobase64',value,pos
  end,
  
  -- --------------------------------------------
  
  [23] = function(packet,pos)
    local _,value,pos = decode1(packet,pos)
    return '_tobase16',value,pos
  end,
  
  -- --------------------------------------------
  
  [24] = function(packet,pos)
    local type,value,pos = decode1(packet,pos)
    if type == 'BIN' then
      return '_cbor',value,pos
    else
      throw(pos,"_cbor: wanted BIN, got %s",type)
    end
  end,
  
  -- --------------------------------------------
  
  [32] = function(packet,pos)
    local type,value,pos = decode1(packet,pos)
    if type == 'TEXT' then
      return '_url',value,pos
    else
      throw(pos,"_url: wanted TEXT, got %s",type)
    end
  end,
  
  -- --------------------------------------------
  
  [33] = function(packet,pos)
    local type,value,pos = decode1(packet,pos)
    if type == 'TEXT' then
      return '_base64url',value,pos
    else
      throw(pos,"_base64url: wanted TEXT, got %s",type)
    end
  end,
  
  -- --------------------------------------------
  
  [34] = function(packet,pos)
    local type,value,pos = decode1(packet,pos)
    if type == 'TEXT' then
      return '_base64',value,pos
    else
      throw(pos,"_base64: wanted TEXT, got %s",type)
    end
  end,
  
  -- --------------------------------------------
  
  [35] = function(packet,pos)
    local type,value,pos = decode1(packet,pos)
    if type == 'TEXT' then
      return '_regex',value,pos
    else
      throw(pos,"_regex: wanted TEXT, got %s",type)
    end
  end,
  
  -- --------------------------------------------
  
  [36] = function(packet,pos)
    local type,value,pos = decode1(packet,pos)
    if type == 'TEXT' then
      return '_mime',value,pos
    else
      throw(pos,"_mime: wanted TEXT, got %s",type)
    end
  end,
  
  -- --------------------------------------------
  
  [55799] = function(_,pos)
    return '_magic_cbor','cbor',pos
  end,
  
  -- ----------------------------------------------------------
  -- Following defined by IANA
  -- http://www.iana.org/assignments/cbor-tags/cbor-tags.xhtml
  -- ----------------------------------------------------------
  
  [25] = function(_,pos)
    return '_nthstring',nil,pos
  end,
  
  -- --------------------------------------------
  
  [26] = function(_,pos)
    return '_perlobj',nil,pos
  end,
  
  -- --------------------------------------------
  
  [27] = function(_,pos)
    return '_serialobj',nil,pos
  end,
  
  -- --------------------------------------------
  
  [28] = function(packet,pos,_,conv)
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
  
  -- --------------------------------------------
  
  [29] = function(packet,pos,conv)
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
  
  -- --------------------------------------------
  
  [30] = function(_,pos)
    return '_rational',nil,pos
  end,
  
  -- --------------------------------------------
  
  [37] = function(packet,pos)
    local type,value,pos = decode1(packet,pos)
    if type == 'BIN' then
      return '_uuid',value,pos
    else
      throw(pos,"_uuid: wanted BIN, got %s",type)
    end
  end,
  
  -- --------------------------------------------
  
  [38] = function(_,pos)
    return '_langstring',nil,pos
  end,
  
  -- --------------------------------------------
  
  [39] = function(_,pos)
    return '_id',nil,pos
  end,
  
  -- --------------------------------------------
  
  [256] = function(_,pos)
    return '_stringref',nil,pos
  end,
  
  -- --------------------------------------------
  
  [257] = function(_,pos)
    return '_bmime',nil,pos
  end,
  
  -- --------------------------------------------
  
  [264] = function(_,pos)
    return '_decimalfractionexp',nil,pos
  end,
  
  -- --------------------------------------------
  
  [265] = function(_,pos)
    return '_bigfloatexp',nil,pos
  end,
  
  -- --------------------------------------------
  
  [22098] = function(_,pos)
    return '_indirection',nil,pos
  end,
}

-- ***********************************************************************

SIMPLE = 
{
  [20] = function(pos)
    return 'false',false,pos
  end,
  
  -- --------------------------------------------
  
  [21] = function(pos)
    return 'true',true,pos
  end,
  
  -- --------------------------------------------
  
  [22] = function(pos)
    return 'null',nil,pos
  end,
  
  -- --------------------------------------------
  
  [23] = function(pos)
    return 'undefined',nil,pos
  end,
  
  -- --------------------------------------------
  
  [25] = function(pos,value)
    return 'half',value,pos
  end,
  
  -- --------------------------------------------
  
  [26] = function(pos,value)
    return 'single',value,pos
  end,
  
  -- --------------------------------------------
  
  [27] = function(pos,value)
    return 'double',value,pos
  end,
  
  -- --------------------------------------------
  
  [31] = function(pos)
    return '__break',false,pos
  end,
}

-- ***********************************************************************

local function bintext(packet,pos,info,value,type)
  if info < 31 then
    local data = packet:sub(pos,pos + value - 1)
    return type,data,pos + value
  else
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

TYPES =
{
  -- ------------------------------------------
  -- UINT	unsigned integers
  -- ------------------------------------------
  
  [0x00] = function(_,pos,_,value)
    return 'UINT',value,pos
  end,
  
  -- ------------------------------------------
  -- NINT	negative integers
  -- ------------------------------------------
  
  [0x20] = function(_,pos,_,value)
    return 'NINT',-1 - value,pos
  end,
  
  -- ------------------------------------------
  -- BIN	binary string
  -- ------------------------------------------
  
  [0x40] = function(packet,pos,info,value)
    return bintext(packet,pos,info,value,'BIN')
  end,
  
  -- ------------------------------------------
  -- TEXT	UTF-8 string
  -- ------------------------------------------
  
  [0x60] = function(packet,pos,info,value)
    return bintext(packet,pos,info,value,'TEXT')
  end,
  
  -- ------------------------------------------
  -- ARRAY	Array of types, value is item count
  -- ------------------------------------------
  
  [0x80] = function(_,pos,_,value)
    return 'ARRAY',value,pos
  end,
  
  -- ------------------------------------------
  -- MAP	name/value structures, value is pair count
  -- ------------------------------------------
  
  [0xA0] = function(_,pos,_,value)
    return 'MAP',value,pos
  end,
  
  -- ------------------------------------------
  -- TAG	tagged data
  -- ------------------------------------------
  
  [0xC0] = function(packet,pos,_,value,conv)
    if TAG[value] then
      return TAG[value](packet,pos,value,conv)
    else
      local _,tvalue,npos = decode(packet,pos)
      return string.format("tag-%d",value),tvalue,npos
    end
  end,
  
  -- ------------------------------------------
  -- SIMPLE	other (extended) values.
  -- ------------------------------------------
  
  [0xE0] = function(_,pos,info,value)
    if SIMPLE[info] then
      return SIMPLE[info](pos,value)
    else
      return 'simple',value,pos
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
  local okay,type,info,value,npos = pcall(cbor5.decode,packet,pos)
  
  if not okay then
    error { pos = pos , msg = type }
  end
  
  return TYPES[type](packet,npos,info,value,conv)
end

-- ***********************************************************************

function getarray(max,packet,pos,conv,a)
  a = a or {}
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
  m = m or {}
  local kctype,key
  local vctype,val
  
  for i = 1 , max do -- luacheck: ignore
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

if _LUA_VERSION >= "Lua 5.2" then
  return _ENV
end
