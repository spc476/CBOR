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
-- A simpler CBOR encoding/decoding module
--
-- luacheck: globals _ENV _VERSION decode encode pdecode pencode
-- luacheck: ignore 611
-- ***************************************************************

local math   = require "math"
local table  = require "table"
local lpeg   = require "lpeg"
local cbor_c = require "org.conman.cbor_c"

local LUA_VERSION  = _VERSION
local getmetatable = getmetatable
local setmetatable = setmetatable
local ipairs       = ipairs
local pairs        = pairs
local type         = type
local pcall        = pcall

if LUA_VERSION < "Lua 5.3" then
  function math.type(n)
    return n >= -9007199254740992
       and n <=  9007199254740992
       and n % 1 == 0
       and 'integer'
       or  'float'
  end
end

if LUA_VERSION == "Lua 5.1" then
  module "org.conman.cbor_s" -- luacheck: ignore
else
  _ENV = {} -- luacheck: ignore
end

_VERSION = cbor_c._VERSION

-- ***************************************************************
-- UTF-8 defintion from RFC-3629.  There's a deviation from the RFC
-- specification in that I only allow certain codes from the US-ASCII C0
-- range (control codes) that are in common use.
-- ***********************************************************************

local UTF8 = (
                 lpeg.R("\7\13"," ~")
               + lpeg.R("\194\223") * lpeg.R("\128\191")
               + lpeg.P("\224")     * lpeg.R("\160\191") * lpeg.R("\128\191")
               + lpeg.R("\225\236") * lpeg.R("\128\191") * lpeg.R("\128\191")
               + lpeg.P("\237")     * lpeg.R("\128\159") * lpeg.R("\128\191")
               + lpeg.R("\238\239") * lpeg.R("\128\191") * lpeg.R("\128\191")
               + lpeg.P("\240")     * lpeg.R("\144\191") * lpeg.R("\128\191") * lpeg.R("\128\191")
               + lpeg.R("\241\243") * lpeg.R("\128\191") * lpeg.R("\128\191") * lpeg.R("\128\191")
               + lpeg.P("\224")     * lpeg.R("\128\142") * lpeg.R("\128\191") * lpeg.R("\128\191")
             )^0
             
-- ***********************************************************************
-- usage:       value2,pos2,ctype2 = bintext(packet,pos,info,value,ctype)
-- desc:        Decode a CBOR BIN or CBOR TEXT into a Lua string
-- input:       packet (binary) binary blob
--              pos (integer) byte position in packet
--              info (integer) CBOR info value (0..31)
--              value (integer) string length
--              ctype (enum/cbor) 'BIN' or 'TEXT'
-- return:      value2 (string) string from packet
--              pos2 (integer) position past string just extracted
--              ctype2 (enum/cbor) 'BIN' or 'TEXT'
-- ***********************************************************************

local function bintext(packet,pos,info,value,ctype)
  if info == 31 then
    local res = ""
    while true do
      local nvalue,npos,ntype = decode(packet,pos)
      if ntype == '__break' then
        return res,npos,ctype
      end
      res = res .. nvalue
      pos = npos
    end
  end
  
  local bt = packet:sub(pos,pos + value - 1)
  return bt,pos + value,ctype
end

-- ***************************************************************
--
--                         CBOR SIMPLE data types
--
-- Dencoding of CBOR simple types are here.
--
-- Usage:       value2,pos,ctype = cbor.SIMPLE[n](pos,value)
-- Desc:        Decode a CBOR simple type
-- Input:       pos (integer) byte offset in packet
--              value (number/optional) floating point number
-- Return:      value2 (any) decoded value as Lua value
--              pos (integer) original pos passed in (see notes)
--              ctype (enum/cbor) CBOR type of value
--
-- Note:        The pos parameter is passed in to avoid special cases in
--              the code and to conform to all other decoding routines.
--
-- ***********************************************************************

local SIMPLE = setmetatable(
  {
    [20] = function(pos)       return false    ,pos,'false'     end,
    [21] = function(pos)       return true     ,pos,'true'      end,
    [22] = function(pos)       return null     ,pos,'null'      end,
    [23] = function(pos)       return undefined,pos,'undefined' end,
    [25] = function(pos,value) return value    ,pos,'half'      end,
    [26] = function(pos,value) return value    ,pos,'single'    end,
    [27] = function(pos,value) return value    ,pos,'double'    end,
    [31] = function(pos)       return false    ,pos,'__break'   end,
  },
  {
    __index = function()
      return function(pos,value) return value,pos,'SIMPLE' end
    end
  }
)

-- ***************************************************************
--
--                             CBOR base TYPES
--
-- Dencoding functions for CBOR base types are here.
--
-- Usage:       value2,pos2,ctype = cbor.TYPE[n](packet,pos,info,value,conv)
-- Desc:        Decode a CBOR base type
-- Input:       packet (binary) binary blob of CBOR data
--              pos (integer) byte offset in packet to start parsing from
--              info (integer) CBOR info (0 .. 31)
--              value (integer) CBOR decoded value
--              conv (table) conversion table (passed to decode())
-- Return:      value2 (any) decoded CBOR value
--              pos2 (integer) byte offset just past parsed data
--              ctype (enum/cbor) CBOR deocded type
--
-- Note:        simple is returned for any non-supported SIMPLE types.
--              Supported simple types will return the appropriate type
--              name.
--
-- ***********************************************************************

local TYPE =
{
  [0x00] = function(_,pos,_,value)
    return value,pos,'UINT'
  end,
  
  [0x20] = function(_,pos,_,value)
    return -1 - value,pos,'NINT'
  end,
  
  [0x40] = function(packet,pos,info,value)
    return bintext(packet,pos,info,value,'BIN')
  end,
  
  [0x60] = function(packet,pos,info,value)
    return bintext(packet,pos,info,value,'TEXT')
  end,
  
  [0x80] = function(packet,pos,_,value,conv)
    local array = {}
    for _ = 1 , value do
      local val,npos,ctype = decode(packet,pos,conv)
      if ctype == '__break' then break end
      table.insert(array,val)
      pos = npos
    end
    return array,pos,'ARRAY'
  end,
  
  [0xA0] = function(packet,pos,_,value,conv)
    local map = {}
    for _ = 1 , value do
      local name,npos,ctype = decode(packet,pos,conv)
      if ctype == '__break' then break end
      local val,npos2 = decode(packet,npos,conv)
      map[name] = val;
      pos = npos2
    end
    return map,pos,'MAP'
  end,
  
  [0xC0] = function(packet,pos,_,value,conv)
    local val,npos,ctype = decode(packet,pos,conv)
    if conv and conv[value] then
      val = conv[value](val)
    end
    return val,npos,ctype
  end,
  
  [0xE0] = function(_,pos,info,value)
    return SIMPLE[info](pos,value)
  end,
}

-- ***************************************************************
-- Usage:       value,pos2,ctype = cbor.decode(packet[,pos][,conv])
-- Desc:        Decode CBOR encoded data
-- Input:       packet (binary) CBOR binary blob
--              pos (integer/optional) starting point for decoding
--              conv (table/optional) table of tagged conversion routines
-- Return:      value (any) the decoded CBOR data
--              pos2 (integer) offset past decoded data
--              ctype (enum/cbor) CBOR type of value
--
-- Note:        The conversion table should be constructed as:
--
--              {
--                [ 0] = function(v) return munge(v) end,
--                [32] = function(v) return munge(v) end,,
--              }
--
--              The keys are CBOR types (as integers).  These functions are
--              expected to convert the decoded CBOR type into a more
--              appropriate type for your code.  For instance, [1] (epoch)
--              can be converted into a table.
--
-- ***********************************************************************

function decode(packet,pos,conv)
  pos = pos or 1
  local ctype,info,value,npos = cbor_c.decode(packet,pos)
  return TYPE[ctype](packet,npos,info,value,conv)
end

-- ***************************************************************
-- Usage:       value,pos2,ctype[,err] = cbor.pdecode(packet[,pos][,conv])
-- Desc:        Protected call to decode CBOR data
-- Input:       packet (binary) CBOR binary blob
--              pos (integer/optional) starting point for decoding
--              conv (table/optional) table of tagged conversion routines
-- Return:      value (any) the decoded CBOR data, nil on error
--              pos2 (integer) offset past decoded data, 0 on error
--              ctype (enum/cbor) CBOR type of value
--              err (string/optional) error message, if any
-- ***********************************************************************

function pdecode(packet,pos,conv)
  local okay,value,npos,ctype = pcall(decode,packet,pos,conv)
  if okay then
    return value,npos,ctype
  else
    return nil,0,'__error',value
  end
end

-- ***************************************************************
--
--                              __ENCODE_MAP
--
-- A table of functions to map Lua values to CBOR encoded values.  nil,
-- boolean, number, string and tables are handled directly (if a Lua string
-- is valid UTF8, then it's encoded as a CBOR TEXT.
--
-- For tables, if the __tocbor method exists, it will be called; otherwise,
-- if the table has a length greater than 0, it's encoded as an ARRAY;
-- otherwise it's encoded as a MAP (so empty tables will end up as a MAP by
-- default).
--
-- Other Lua types are not supported.
--
-- Usage:       blob = cbor.__ENCODE_MAP[luatype](value[,tag])
-- Desc:        Encode a Lua type into a CBOR type
-- Input:       value (any) a Lua value who's type matches luatype.
--              tag (number/optional) CBOR tag type
-- Return:      blob (binary) CBOR encoded data
--
-- ***********************************************************************

local ENCODE_MAP =
{

  ['nil'] = function()
    return "\246"
  end,
  
  ['boolean'] = function(b)
    if b then
      return "\245"
    else
      return "\244"
    end
  end,
  
  ['number'] = function(value)
    if math.type(value) == 'integer' then
      if value < 0 then
        return cbor_c.encode(0x20,-1 - value)
      else
        return cbor_c.encode(0x00,value)
      end
    else
      return cbor_c.encode(0xE0,nil,value)
    end
  end,
  
  ['string'] = function(value)
    if UTF8:match(value) > #value then
      return cbor_c.encode(0x60,#value) .. value
    else
      return cbor_c.encode(0x40,#value) .. value
    end
  end,
  
  ['table'] = function(value)
    local mt = getmetatable(value)
    if mt and mt.__tocbor then
      return mt.__tocbor(value)
    else
      if #value > 0 then
        local res = cbor_c.encode(0x80,#value)
        for _,item in ipairs(value) do
          res = res .. encode(item)
        end
        return res
      else
        local res = ""
        local cnt = 0
        
        for key,item in pairs(value) do
          res = res .. encode(key)
          res = res .. encode(item)
          cnt = cnt + 1
        end
        return cbor_c.encode(0xA0,cnt) .. res
      end
    end
  end,
  
  ['function'] = function()
    error("function not supported")
  end,
  
  ['userdata'] = function()
    error("userdata not supported")
  end,
  
  ['thread'] = function()
    error("thread not supported")
  end,
}

-- ***************************************************************
-- Usage:       blob = cbor.encode(value[,tag])
-- Desc:        Encode a Lua type into a CBOR type
-- Input:       value (any)
--              tag (number/optional) CBOR tag value
-- Return:      blob (binary) CBOR encoded value
-- ***********************************************************************

function encode(value,tag)
  local blob do
    if value == null then
      blob = "\246"
    elseif value == undefined then
      blob = "\247"
    else
      blob = ENCODE_MAP[type(value)](value)
    end
  end
  
  if tag then
    return cbor_c.encode(0xC0,tag) .. blob
  else
    return blob
  end
end

-- ***************************************************************
-- Usage:       blob[,err] = cbor_s.pencode(value[,tag])
-- Desc:        Protected call to encode into CBOR
-- Input:       value (any)
--              tag (number/optional) CBOR tag value
-- Return:      blob (binary) CBOR encoded value
--              err (string/optional) error message
-- ***************************************************************

function pencode(value,tag)
  local okay,value2 = pcall(encode,value,tag)
  if okay then
    return value2
  else
    return nil,value2
  end
end

-- ***************************************************************

if LUA_VERSION >= "Lua 5.2" then
  return _ENV
end
