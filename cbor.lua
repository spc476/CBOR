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
--			* tag_*		unsupported tag type (Lua number)
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
local cbor5    = require "cbor5"

local _LUA_VERSION = _VERSION
local error        = error
local pcall        = pcall

if _LUA_VERSION == "Lua 5.1" then
  module "cbor"
else
  _ENV = {}
end

_VERSION = cbor5._VERSION

-- ***********************************************************************

local function throw(pos,...)
  error( { pos = pos , msg = string.format(...) } , 2)
end

-- ***********************************************************************
-- Usage:       bool = cbor.isnumber(type)
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
-- Usage:       bool = cbor.isinteger(type)   
-- Desc:        returns true if the given CBOR type is an integer
-- Input:       type (enum/cbor) CBOR type
-- Return:      bool (boolean) true if number, false othersise
-- ***********************************************************************

function isinteger(type)
  return type == 'UINT'
      or type == 'NINT'
end

-- ***********************************************************************
-- Usage:       bool = cbor.isfloat(type)
-- Desc:        returns true if the given CBOR type is a float
-- Input:       type (enum/cbor) CBOR type
-- Return:      bool (boolean) true if number, false otherwise
-- ***********************************************************************

function isfloat(type)
  return type == 'half'
      or type == 'single'
      or type == 'double'
end  

-- ***********************************************************************

local function bintext(packet,pos,info,value,ctype)
  if info < 31 then
    local data = packet:sub(pos,pos + value - 1)
    return ctype,data,pos + value
  else
    local acc = {}
    local t,nvalue
    
    while true do
      t,nvalue,pos = decode(packet,pos)
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

TYPES =
{
  [0x00] = function(_,pos,_,value)
    return 'UINT',value,pos
  end,
  
  [0x20] = function(_,pos,_,value)
    return 'NINT',-1 - value,pos
  end,
  
  [0x40] = function(packet,pos,info,value)
    return bintext(packet,pos,info,value,'BIN')
  end,
  
  [0x60] = function(packet,pos,info,value)
    return bintext(packet,pos,info,value,'TEXT')
  end,
  
  [0x80] = function(packet,pos,_,value)
    local acc = {}
    
    for i = 1 , value do
      local ctype,avalue,npos = decode(packet,pos)
      if ctype == '__break' then return 'ARRAY',acc,npos end
      acc[i] = avalue
      pos    = npos
    end
    return 'ARRAY',acc,pos
  end,
  
  [0xA0] = function(packet,pos,_,value)
    local acc = {}
    for _ = 1 , value do
      local nctype,nvalue,npos = decode(packet,pos)
      if nctype == '__break' then return 'MAP',acc,npos end
      local _,vvalue,npos = decode(packet,npos)
      acc[nvalue] = vvalue
      pos         = npos
    end
    return 'MAP',acc,pos
  end,
  
  [0xC0] = function(packet,pos,_,value)
    if TAG[value] then
      return TAG[value](packet,pos)
    else
      local _,newvalue,npos = decode(packet,pos)
      return string.format("tag_%d",value),newvalue,npos
    end
  end,
  
  [0xE0] = function(_,pos,info,value)
    if SIMPLE[info] then
      return SIMPLE[info](pos,value)
    else
      return 'simple',value,pos
    end
  end,
}

-- ***********************************************************************

TAG =
{
  [0] = function(packet,pos)
    local ctype,value,npos = decode(packet,pos)
    if type == 'TEXT' then
      return '_datetime',value,npos
    else
      throw(pos,"_datetime: wanted TEXT, got %s",ctype)
    end
  end,
  
  [1] = function(packet,pos)
    local ctype,value,npos = decode(packet,pos)
    if isnumber(ctype) then
      return '_epoch',value,npos
    else
      throw(pos,"_epoch: wanted number, got %s",ctype)
    end
  end,
  
  [2] = function(packet,pos)
    local ctype,value,npos = decode(packet,pos)
    if ctype == 'BIN' then
      return '_pbignum',value,npos
    else
      throw(pos,"_pbignum: wanted BIN, got %s",ctype)
    end
  end,
  
  [3] = function(packet,pos)
    local ctype,value,npos = decode(packet,pos)
    if ctype == 'BIN' then
      return '_nbignum',value,npos
    else
      throw(pos,"_nbignum: wanted BIN, got %s",ctype)
    end
  end,
  
  [4] = function(packet,pos)
    local ctype,value,npos = decode(packet,pos)
    if ctype ~= 'ARRAY' then throw(pos,"_decimalfraction: wanted ARRAY, got %s",ctype) end
    if value ~= 2 then throw(pos,"_decimalfraction: wanted ARRAY[2], got ARRAY[%s]",value) end
    local result = {}
    ctype,result.exp,npos = decode(packet,npos)
    if not isinteger(ctype) then throw(pos,"_decimalfraction: wanted integer for exp, got %s",ctype) end
    ctype,result.mantissa,npos = decode(packet,npos)
    if not isinteger(ctype) then throw(pos,"_decimalfraction: wanted integer for mantissa, got %s",ctype) end
    return '_decimalfraction',result,npos
  end,
  
  [5] = function(packet,pos)
    local ctype,value,npos = decode(packet,pos)
    if ctype ~= 'ARRAY' then throw(pos,"_bigfloat: wanted ARRAY, got %s",ctype) end
    if value ~= 2 then throw(pos,"_bigfloat: watned ARRAY[2], got ARRAY[%s]",value) end
    local result = {}
    ctype,result.exp,npos = decode(packet,pos)
    if not isnumber(ctype) then throw(pos,"_bigfloat: wanted number for exp, got %s",ctype) end
    ctype,result.mantissa,npos = decode(packet,pos)
    if not isinteger(ctype) then throw(pos,"_bigfloat: wanted integer for mantissa, got %s",ctype) end
    return '_bigfloat',result,npos
  end,
  
  [21] = function(packet,pos)
    local _,value,npos = decode(packet,pos)
    return '_tobase64url',value,npos
  end,
  
  [22] = function(packet,pos)
    local _,value,npos = decode(packet,pos)
    return '_tobase64',value,npos
  end,
  
  [23] = function(packet,pos)
    local _,value,npos = decode(packet,pos)
    return '_tobase16',value,npos
  end,
  
  [24] = function(packet,pos)
    local ctype,value,npos = decode(packet,pos)
    if ctype == 'BIN' then
      return '_cbor',value,npos
    else
      throw(pos,"_cbor: wanted BIN, got %s",ctype)
    end
  end,
  
  [32] = function(packet,pos)
    local ctype,value,npos = decode(packet,pos)
    if ctype == 'TEXT' then
      return '_url',value,npos
    else
      throw(pos,"_url: wanted TEXT, got %s",ctype)
    end
  end,
  
  [33] = function(packet,pos)
    local ctype,value,npos = decode(packet,pos)
    if ctype == 'TEXT' then
      return '_base64url',value,npos
    else
      throw(pos,"_base64url: wanted TEXT, got %s",ctype)
    end
  end,
  
  [34] = function(packet,pos)
    local ctype,value,npos = decode(packet,pos)
    if ctype == 'TEXT' then
      return '_base64',value,npos
    else
      throw(pos,"_base64: wanted TEXT, got %s",ctype)
    end
  end,
  
  [35] = function(packet,pos)
    local ctype,value,npos = decode(packet,pos)
    if ctype == 'TEXT' then
      return '_regex',value,npos
    else
      throw(pos,"_regex: wanted TEXT, got %s",ctype)
    end
  end,
  
  [36] = function(packet,pos)
    local ctype,value,npos = decode(packet,pos)
    if ctype == 'TEXT' then
      return '_mime',value,npos
    else
      throw(pos,"_mime: wanted TEXT, got %s",ctype)
    end
  end,
  
  [55799] = function(_,pos)
    return '_magic_cbor','_magic_cbor',pos
  end,
  
  -- ----------------------------------------------------------
  -- Following defined by IANA  
  -- http://www.iana.org/assignments/cbor-tags/cbor-tags.xhtml
  -- ----------------------------------------------------------
  
  [25] = function(_,pos)
    return '_nthstring',nil,pos
  end,
  
  [26] = function(_,pos)
    return '_perlobj',nil,pos
  end,
  
  [27] = function(_,pos)
    return '_serialobj',nil,pos
  end,
  
  [28] = function(_,pos)
    return '_shareable',nil,pos
  end,
  
  [29] = function(_,pos)
    return '_sharedref',nil,pos
  end,
  
  [30] = function(_,pos)
    return '_rational',nil,pos
  end,
  
  [37] = function(packet,pos)  
    local ctype,value,npos = decode1(packet,pos)
    if ctype == 'BIN' then
      return '_uuid',value,npos
    else
      throw(pos,"_uuid: wanted BIN, got %s",ctype)
    end 
  end,
  
  [38] = function(_,pos)
    return '_langstring',nil,pos
  end,
  
  [39] = function(_,pos)
    return '_id',nil,pos
  end,
  
  [256] = function(_,pos)
    return '_stringref',nil,pos
  end,
  
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
  
  [21] = function(pos)
    return 'true',true,pos
  end,
  
  [22] = function(pos)
    return 'null',nil,pos
  end,
  
  [23] = function(pos)
    return 'undefined',nil,pos
  end,
  
  [25] = function(pos,value)
    return 'half',value,pos
  end,
  
  [26] = function(pos,value)
    return 'single',value,pos
  end,
  
  [27] = function(pos,value)
    return 'double',value,pos
  end,
  
  [31] = function(pos)
    return '__break',math.huge,pos
  end,
}

-- ***********************************************************************

local function decode1(packet,pos)
  local ctype,info,value,npos = cbor5.decode(packet,pos)
  return TYPES[ctype](packet,npos,info,value)
end

function decode(packet,pos)
  local okay,ctype,value,npos = pcall(decode1,packet,pos or 1)
  
  if okay then
    return ctype,value,npos
  else
    return '__error',ctype,pos
  end
end

-- ***********************************************************************

if _LUA_VERSION >= "Lua 5.2" then
  return _ENV
end
