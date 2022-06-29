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
-- Output in the CBOR dianostic format
--
-- luacheck: globals _ENV TYPE TAG SIMPLE diagnostic pdiagnostic
-- luacheck: ignore 611
-- ***************************************************************

local string = require "string"
local math   = require "math"
local cbor_c = require "org.conman.cbor_c"

local _VERSION     = _VERSION
local setmetatable = setmetatable
local tostring     = tostring
local pcall        = pcall
local type         = type

if _VERSION == "Lua 5.1" then
  module "org.conman.cbormisc" -- luacheck: ignore
else
  _ENV = {} -- luacheck: ignore
end

-- ***************************************************************

local char_trans =
{
  ['\a'] = '\\a',
  ['\b'] = '\\b',
  ['\t'] = '\\t',
  ['\n'] = '\\n',
  ['\v'] = '\\v',
  ['\f'] = '\\f',
  ['\r'] = '\\r',
  ['"']  = '\\"',
  ['\\'] = '\\\\',
}

local function safestring(v)
  if type(v) == 'string' then
    return '"' .. v:gsub(".",function(c)
      if char_trans[c] then
        return char_trans[c]
      end
      
      local b = c:byte()
      
      if b < 32 or b > 126 then
        return string.format("\\%03d",b)
      else
        return c
      end
    end) .. '"'
  else
    return tostring(v)
  end
end

-- *************************************************************

local function bintext(packet,pos,info,value,ctype,f)
  if info == 31 then
    local res   = "(_ "
    local comma = ""
    
    while true do
      local ltype,nvalue,npos = diagnostic(packet,pos)
      if ltype == '__break' then
        return ctype,res .. ")",npos
      end
      res = res .. comma .. nvalue
      comma = ", "
      pos   = npos
    end
  end
  
  local bt = packet:sub(pos,pos + value - 1)
  return ctype,f(bt),pos + value
end

-- ***************************************************************

TYPE =
{
  [0x00] = function(_,pos,_,value)
    return 'UINT',tostring(value),pos
  end,
  
  [0x20] = function(_,pos,_,value)
    return 'NINT',tostring(-1 - value),pos
  end,
  
  [0x40] = function(packet,pos,info,value)
    return bintext(packet,pos,info,value,'BIN',function(c)
      c = c:gsub(".",function(ch)
        return string.format("%02X",ch:byte())
      end)
      return string.format("h'%s'",c)
    end)
  end,
  
  [0x60] = function(packet,pos,info,value)
    return bintext(packet,pos,info,value,'TEXT',safestring)
  end,
  
  [0x80] = function(packet,pos,info,value)
    local res = "["
    if info == 31 then
      res = res .. "_ "
    end
    
    for i = 1 , value do
      local ctype,s,npos = diagnostic(packet,pos)
      if ctype == '__break' then break end
      res = res .. s
      if i < value then res = res .. ", " end
      pos = npos
    end
    return 'ARRAY',res .. "]",pos
  end,
  
  [0xA0] = function(packet,pos,info,value)
    local res = "{"
    if info == 31 then
      res = res .. "_ "
    end
    
    for i = 1 , value do
      local ctypen,name,npos = diagnostic(packet,pos)
      if ctypen == '__break' then break end
      local _,val,npos2 = diagnostic(packet,npos)
      res = res .. string.format("%s: %s",name,val)
      if i < value then res = res .. ", " end
      pos = npos2
    end
    return 'MAP',res .. "}",pos
  end,
  
  [0xC0] = function(packet,pos,_,value)
    local _,s,npos = diagnostic(packet,pos)
    local ctype    = TAG[value]
    return ctype,string.format("%s(%s)",ctype,s),npos
  end,
  
  [0xE0] = function(_,pos,info,value)
    if info >= 25 and info <= 27 then
      return '__float',SIMPLE[info](value),pos
    elseif info == 31 then
      return '__break',math.huge,pos
    else
      return SIMPLE[value],SIMPLE[value],pos
    end
  end,
}

-- ***************************************************************

TAG = setmetatable(
  {
    [    0] = "_datetime",
    [    1] = "_epoch",
    [    2] = "_pbignum",
    [    3] = "_nbignum",
    [    4] = "_decimalfraction",
    [    5] = "_bigfloat",
    [   21] = "_tobase64url",
    [   22] = "_tobase64",
    [   23] = "_tobase16",
    [   24] = "_cbor",
    [   32] = "_url",
    [   33] = "_base64url",
    [   34] = "_base64",
    [   35] = "_regex",
    [   36] = "_mime",
    [55799] = "_magic_cbor",
    
    [   25] = "_nthstring",
    [   26] = "_perlobj",
    [   27] = "_serialobj",
    [   28] = "_shareable",
    [   29] = "_sharedref",
    [   30] = "_rational",
    [   37] = "_uuid",
    [   38] = "_language",
    [   39] = "_id",
    [  256] = "_stringref",
    [  257] = "_bmime",
    [  264] = "_decimalfractionexp",
    [  265] = "_bigfloatexp",
    [22098] = "_indirection",
  },
  {
    __index = function(_,key)
      return tostring(key)
    end
  }
)

-- ***************************************************************

local function simple(value)
  if value ~= value then
    return 'NaN'
  elseif value == math.huge then
    return 'Infinity'
  elseif value == -math.huge then
    return '-Infinity'
  else
    return string.format('%f',value)
  end
end

-- ***************************************************************

SIMPLE = setmetatable(
  {
    [20] = 'false',
    [21] = 'true',
    [22] = 'null',
    [23] = 'undefined',
    [25] = simple,
    [26] = simple,
    [27] = simple,
    [31] = '__break',
  },
  {
    __index = function(_,key)
      return string.format("simple(%d)",key)
    end
  }
)

-- ***************************************************************

function diagnostic(packet,pos)
  pos = pos or 1
  
  local ctype,info,value,npos = cbor_c.decode(packet,pos)
  return TYPE[ctype](packet,npos,info,value)
end

-- ***************************************************************

function pdiagnostic(packet,pos)
  local okay,result = pcall(diagnostic,packet,pos)
  if okay then
    return result
  else
    return nil,result
  end
end

-- ***************************************************************

if _VERSION > "Lua 5.1" then
  return _ENV
end
