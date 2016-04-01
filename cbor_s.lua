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
-- luacheck: globals _ENV _VERSION decode encode
-- ***************************************************************

local math  = require "math"
local table = require "table"
local lpeg  = require "lpeg"
local cbor5 = require "cbor5"

local LUA_VERSION = _VERSION
local getmetatable = getmetatable
local setmetatable = setmetatable
local ipairs       = ipairs
local pairs        = pairs
local type         = type

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
  module "cbor_s"
else
  _ENV = {}
end

_VERSION = cbor5._VERSION

-- ***************************************************************

local UTF8 = (
                 lpeg.R("\7\13"," ~")
               + lpeg.R("\194\223") * lpeg.R("\128\191")
               + lpeg.R("\224\239") * lpeg.R("\128\191") * lpeg.R("\128\191")
               + lpeg.R("\240\244") * lpeg.R("\128\191") * lpeg.R("\128\191") * lpeg.R("\128\191")
	     )^0

-- ***************************************************************

local function bintext(packet,pos,info,value,ctype)
  if info == 31 then
    local res = ""
    while true do
      local nvalue,npos,ctype = decode(packet,pos)
      if ctype == '__break' then 
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

local SIMPLE = setmetatable(
  {
    [20] = function(pos)       return false,pos,'false'     end,
    [21] = function(pos)       return true ,pos,'true'      end,
    [22] = function(pos)       return nil  ,pos,'null'      end,
    [23] = function(pos)       return nil  ,pos,'undefined' end,
    [25] = function(pos,value) return value,pos,'half'      end,
    [26] = function(pos,value) return value,pos,'single'    end,
    [27] = function(pos,value) return value,pos,'double'    end,
    [31] = function(pos)       return false,pos,'__break'   end,
  },
  {
    __index = function()
      return function(value,pos) return value,pos end
    end
  }
)

-- ***************************************************************

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

function decode(packet,pos,conv)
  pos = pos or 1
  local ctype,info,value,npos = cbor5.decode(packet,pos)
  return TYPE[ctype](packet,npos,info,value,conv)
end

-- ***************************************************************

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
        return cbor5.encode(0x20,-1 - value)
      else
        return cbor5.encode(0x00,value)
      end
    else
      return cbor5.encode(0xE0,nil,value)
    end
  end,
  
  ['string'] = function(value)
    if UTF8:match(value) > #value then
      return cbor5.encode(0x60,#value) .. value
    else
      return cbor5.encode(0x40,#value) .. value
    end
  end,
  
  ['table'] = function(value)
    local mt = getmetatable(value)
    if mt and mt.__tocbor then
      return mt.__tocbor(value)
    else
      if #value > 0 then
        local res = cbor5.encode(0x80,#value)
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
        return cbor5.encode(0xA0,cnt) .. res
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

function encode(value,tag)
  if tag then
    return cbor5.encode(0xC0,tag) .. ENCODE_MAP[type(value)](value)
  else
    return ENCODE_MAP[type(value)](value)
  end
end

-- ***************************************************************

if LUA_VERSION >= "Lua 5.2" then
  return _ENV
end
