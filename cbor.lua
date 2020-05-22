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
-- Module:      cbor
--
-- Desc:        Decodes CBOR data.
--
-- Types:
--              cbor (enum)
--                      *** base types
--                      * UINT          unsigned integer (Lua number)
--                      * NINT          negative integer (Lua number)
--                      * BIN           binary string   (Lua string)
--                      * TEXT          UTF-8 string    (Lua string)
--                      * ARRAY         value is item count (Lua number)
--                      * MAP           value is item count (Lua number)
--                      *** simple types
--                      * SIMPLE        SEE NOTES       (Lua number)
--                      * false         false value     (Lua false)
--                      * true          true value      (Lua true)
--                      * null          NULL value      (Lua nil)
--                      * undefined     undefined value (Lua nil)
--                      * half          half precicion   IEEE 754 float
--                      * single        single precision IEEE 754 float
--                      * double        double precision IEEE 754 float
--                      * __break       SEE NOTES
--                      *** tagged types
--                      * TAG_*         unsupported tag type (Lua number)
--                      * _datetime     datetime (TEXT)
--                      * _epoch        see cbor.isnumber()
--                      * _pbignum      positive bignum (BIN)
--                      * _nbignum      negative bignum (BIN)
--                      * _decimalfraction ARRAY(integer exp, integer mantissa)
--                      * _bigfloat     ARRAY(float exp,integer mantissa)
--                      * _tobase64url  should be base64url encoded (BIN)
--                      * _tobase64     should be base64 encoded (BIN)
--                      * _tobase16     should be base16 encoded (BIN)
--                      * _cbor         CBOR encoded data (BIN)
--                      * _url          URL (TEXT)
--                      * _base64url    base64url encoded data (TEXT)
--                      * _base64       base64 encoded data (TEXT)
--                      * _regex        regex (TEXT)
--                      * _mime         MIME encoded messsage (TEXT)
--                      * _magic_cbor   itself (no data, used to self-describe CBOR data)
--                      ** more tagged types, extensions
--                      * _nthstring    shared string
--                      * _perlobj      Perl serialized object
--                      * _serialobj    Generic serialized object
--                      * _shareable    sharable resource (ARRAY or MAP)
--                      * _sharedref    reference (UINT)
--                      * _rational     Rational number
--                      * _uuid         UUID value (BIN)
--                      * _language     Language-tagged string
--                      * _id           Identifier
--                      * _stringref    string reference
--                      * _bmime        Binary MIME message
--                      * _decimalfractionexp like _decimalfraction, non-int exponent
--                      * _bigfloatexp  like _bigfloat, non-int exponent
--                      * _indirection  Indirection
--                      * _rains        RAINS message
--                      * _ipaddress    IP address (or MAC address)
--                      *** Lua CBOR library types
--                      * __error       error parsing (TEXT)
--              data (any) decoded CBOR data
--              pos (integer) position parsing stopped
--
-- NOTES:       The simple type is returned for non-defined simple types.
--
--              The __break type is used to indicate the end of an
--              indefinite array or map.
--
-- luacheck: globals isnumber isinteger isfloat decode encode pdecode pencode
-- luacheck: globals TYPE TAG SIMPLE _VERSION __ENCODE_MAP _ENV
-- luacheck: globals null undefined
-- luacheck: ignore 611
-- ********************************************************************

local math     = require "math"
local string   = require "string"
local table    = require "table"
local lpeg     = require "lpeg"
local cbor_c   = require "org.conman.cbor_c"

local LUA_VERSION  = _VERSION
local error        = error
local pcall        = pcall
local assert       = assert
local getmetatable = getmetatable
local setmetatable = setmetatable
local pairs        = pairs
local ipairs       = ipairs
local type         = type
local tonumber     = tonumber

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
  module "org.conman.cbor" -- luacheck: ignore
else
  _ENV = {} -- luacheck: ignore
end

_VERSION = cbor_c._VERSION

-- ***********************************************************************
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
-- usage:       len = mstrlen(ref)
-- desc:        This function returns the minimum length a string should
--              have to find its reference (see notes)
-- input:       ref (table) reference table
-- return:      len (integer) minimum string length for reference
--
-- note:        via http://cbor.schmorp.de/stringref
-- ***********************************************************************

local function mstrlen(ref)
  if #ref < 24 then
    return 3
  elseif #ref < 256 then
    return 4
  elseif #ref < 65536 then
    return 5
  elseif #ref < 4294967296 then
    return 7
  else
    return 11
  end
end

-- ***********************************************************************
-- usage:       value2,pos2,ctype2 = decbintext(packet,pos,info,value,conv,ref,ctype)
-- desc:        Decode a CBOR BIN or CBOR TEXT into a Lua string
-- input:       packet (binary) binary blob
--              pos (integer) byte position in packet
--              info (integer) CBOR info value (0..31)
--              value (integer) string length
--              conv (table) conversion routines (passed to decode())
--              ref (table) reference table
--              ctype (enum/cbor) 'BIN' or 'TEXT'
-- return:      value2 (string) string from packet
--              pos2 (integer) position past string just extracted
--              ctype2 (enum/cbor) 'BIN' or 'TEXT'
-- ***********************************************************************

local function decbintext(packet,pos,info,value,conv,ref,ctype)

  -- ----------------------------------------------------------------------
  -- Support for _stringref and _nthstring tags [1].  Strings shorter than
  -- the reference mark will NOT be encoded, so these strings will not have
  -- a reference upon decoding.
  --
  -- [1] http://cbor.schmorp.de/stringref
  -- ----------------------------------------------------------------------
  
  if info < 31 then
    local data = packet:sub(pos,pos + value - 1)
    
    -- --------------------------------------------------
    -- make sure the string is long enough to reference
    -- --------------------------------------------------
    
    if not ref._stringref[data] then
      if #data >= mstrlen(ref._stringref) then
        table.insert(ref._stringref,{ ctype = ctype , value = data })
        ref._stringref[data] = true
      end
    end
    return data,pos + value,ctype
    
  else
    local acc = {}
    local t,nvalue
    
    while true do
      nvalue,pos,t = decode(packet,pos,conv,ref)
      if t == '__break' then
        break;
      end
      if t ~= ctype then
        throw(pos,"%s: expecting %s, got %s",ctype,ctype,t)
      end
      table.insert(acc,nvalue)
    end
    
    return table.concat(acc),pos,ctype
  end
end


-- ***********************************************************************
-- usage:       blob = encbintext(value,sref,stref,ctype)
-- desc:        Encode a string into a CBOR BIN or TYPE
-- input:       value (string) Lua string to encode
--              sref (table) shared references
--              stref (table) string references
--              ctype (integer) either 0x40 (BIN) or 0x60 (TEXT)
-- return:      blob (binary) encoded string
-- ***********************************************************************

local function encbintext(value,sref,stref,ctype)
  if stref then
    if not stref[value] then
      if #value >= mstrlen(stref) then
        table.insert(stref,value)
        stref[value] = #stref - 1
      end
    else
      return TAG._nthstring(stref[value],sref,stref)
    end
  end
  
  return cbor_c.encode(ctype,#value) .. value
end

-- ***********************************************************************
--
--                             CBOR base TYPES
--
-- Both encoding and decoding functions for CBOR base types are here.
--
-- Usage:       blob = cbor.TYPE['name'](n,sref,stref)
-- Desc:        Encode a CBOR base type
-- Input:       n (integer string table) Lua type (see notes)
--              sref (table/optional) shared reference table
--              stref (table/optional) shared string reference table
-- Return:      blob (binary) CBOR encoded value
--
-- Note:        UINT and NINT take an integer.
--
--              BIN and TEXT take a string.  TEXT will check to see if
--              the text is well formed UTF8 and throw an error if the
--              text is not valid UTF8.
--
--              ARRAY and MAP take a table of an appropriate type. No
--              checking is done of the passed in table, so a table
--              of just name/value pairs passed in to ARRAY will return
--              an empty CBOR encoded array.
--
--              TAG and SIMPLE encoding are handled elsewhere.
--
-- Usage:       value2,pos2,ctype = cbor.TYPE[n](packet,pos,info,value,conv,ref)
-- Desc:        Decode a CBOR base type
-- Input:       packet (binary) binary blob of CBOR data
--              pos (integer) byte offset in packet to start parsing from
--              info (integer) CBOR info (0 .. 31)
--              value (integer) CBOR decoded value
--              conv (table) conversion table (passed to decode())
--              ref (table) used to generate references (TAG types only)
-- Return:      value2 (any) decoded CBOR value
--              pos2 (integer) byte offset just past parsed data
--              ctype (enum/cbor) CBOR deocded type
--
-- Note:        tag_* is returned for any non-supported TAG types.  The
--              actual format is 'tag_' <integer value>---for example,
--              'tag_1234567890'.  Supported TAG types will return the
--              appropriate type name.
--
--              simple is returned for any non-supported SIMPLE types.
--              Supported simple types will return the appropriate type
--              name.
--
-- ***********************************************************************

TYPE =
{
  UINT = function(n)
    return cbor_c.encode(0x00,n)
  end,
  
  [0x00] = function(_,pos,info,value)
    if info == 31 then throw(pos,"invalid data") end
    return value,pos,'UINT'
  end,
  
  -- =====================================================================
  
  NINT = function(n)
    return cbor_c.encode(0x20,-1 - n)
  end,
  
  [0x20] = function(_,pos,info,value)
    if info == 31 then throw(pos,"invalid data") end
    return -1 - value,pos,'NINT'
  end,
  
  -- =====================================================================
  
  BIN = function(b,sref,stref)
    if not b then
      return "\95"
    else
      return encbintext(b,sref,stref,0x40)
    end
  end,
  
  [0x40] = function(packet,pos,info,value,conv,ref)
    return decbintext(packet,pos,info,value,conv,ref,'BIN')
  end,
  
  -- =====================================================================
  
  TEXT = function(s,sref,stref)
    if not s then
      return "\127"
    else
      assert(UTF8:match(s) > #s,"TEXT: not UTF-8 text")
      return encbintext(s,sref,stref,0x60)
    end
  end,
  
  [0x60] = function(packet,pos,info,value,conv,ref)
    return decbintext(packet,pos,info,value,conv,ref,'TEXT')
  end,
  
  -- =====================================================================
  
  ARRAY = function(array,sref,stref)
    if not array then
      return "\159"
    elseif type(array) == 'number' then
      return cbor_c.encode(0x80,array)
    end
    
    local res = ""
    
    if sref then
      if sref[array] then
        return TAG._sharedref(sref[array],sref,stref)
      end
      
      res = TAG._shareable(array)
      table.insert(sref,array)
      sref[array] = #sref - 1
    end
    
    res = res .. cbor_c.encode(0x80,#array)
    for _,item in ipairs(array) do
      res = res .. encode(item,sref,stref)
    end
    return res
  end,
  
  [0x80] = function(packet,pos,_,value,conv,ref)
  
    -- ---------------------------------------------------------------------
    -- Per [1], shared references need to exist before the decoding process.
    -- ref._sharedref.REF will be such a reference.  If it doesn't exist,
    -- then just create a table.
    --
    -- [1] http://cbor.schmorp.de/value-sharing
    -- ---------------------------------------------------------------------
    
    local acc = ref._sharedref.REF or {}
    
    for i = 1 , value do
      local avalue,npos,ctype = decode(packet,pos,conv,ref)
      if ctype == '__break' then return acc,npos,'ARRAY' end
      acc[i] = avalue
      pos    = npos
    end
    return acc,pos,'ARRAY'
  end,
  
  -- =====================================================================
  
  MAP = function(map,sref,stref)
    if not map then
      return "\191"
    elseif type(map) == 'number' then
      return cbor_c.encode(0xA0,map)
    end
    
    local ref = ""
    
    if sref then
      if sref[map] then
        return TAG._sharedref(sref[map],sref,stref)
      end
      
      ref = TAG._shareable(map)
      table.insert(sref,map)
      sref[map] = #sref - 1
    end
    
    local res = ""
    local cnt = 0
    
    for key,value in pairs(map) do
      res = res .. encode(key,sref,stref)
      res = res .. encode(value,sref,stref)
      cnt = cnt + 1
    end
    
    return ref .. cbor_c.encode(0xA0,cnt) .. res
  end,
  
  [0xA0] = function(packet,pos,_,value,conv,ref)
    local acc = ref._sharedref.REF or {} -- see comment above
    for _ = 1 , value do
      local nvalue,npos,nctype = decode(packet,pos,conv,ref,true)
      if nctype == '__break' then return acc,npos,'MAP' end
      local vvalue,npos2 = decode(packet,npos,conv,ref)
      acc[nvalue] = vvalue
      pos         = npos2
    end
    return acc,pos,'MAP'
  end,
  
  -- =====================================================================
  
  [0xC0] = function(packet,pos,info,value,conv,ref)
    if info == 31 then throw(pos,"invalid data") end
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
-- Usage:       blob = cbor.TAG['name'](value,sref,stref)
-- Desc:        Encode a CBOR tagged value
-- Input:       value (any) any Lua type
--              sref (table/optional) shared reference table
--              stref (table/optional) shared string reference table
-- Return:      blob (binary) CBOR encoded tagged value
--
-- Note:        Some tags only support a subset of Lua types.
--
-- Usage:       value,pos2,ctype = cbor.TAG[n](packet,pos,conv,ref)
-- Desc:        Decode a CBOR tagged value
-- Input:       packet (binary) binary blob of CBOR tagged data
--              pos (integer) byte offset into packet
--              conv (table) conversion routines (passed to decode())
--              ref (table) reference table
-- Return:      value (any) decoded CBOR tagged value
--              pos2 (integer) byte offset just past parsed data
--              ctype (enum/cbor) CBOR type of value
--
-- ***********************************************************************

TAG = setmetatable(
  {
    _datetime = function(value)
      return cbor_c.encode(0xC0,0) .. TYPE.TEXT(value)
    end,
    
    [0] = function(packet,pos,conv,ref)
      local value,npos,ctype = decode(packet,pos,conv,ref)
      if ctype == 'TEXT' then
        return value,npos,'_datetime'
      else
        throw(pos,"_datetime: wanted TEXT, got %s",ctype)
      end
    end,
    
    -- =====================================================================
    
    _epoch = function(value,sref,stref)
      assert(type(value) == 'number',"_epoch expects a number")
      return cbor_c.encode(0xC0,1) .. encode(value,sref,stref)
    end,
    
    [1] = function(packet,pos,conv,ref)
      local value,npos,ctype = decode(packet,pos,conv,ref)
      if isnumber(ctype) then
        return value,npos,'_epoch'
      else
        throw(pos,"_epoch: wanted number, got %s",ctype)
      end
    end,
    
    -- =====================================================================
    
    _pbignum = function(value,sref,stref)
      return cbor_c.encode(0xC0,2) .. TYPE.BIN(value,sref,stref)
    end,
    
    [2] = function(packet,pos,conv,ref)
      local value,npos,ctype = decode(packet,pos,conv,ref)
      if ctype == 'BIN' then
        return value,npos,'_pbignum'
      else
        throw(pos,"_pbignum: wanted BIN, got %s",ctype)
      end
    end,
    
    -- =====================================================================
    
    _nbignum = function(value,sref,stref)
      return cbor_c.encode(0xC0,3) .. TYPE.BIN(value,sref,stref)
    end,
    
    [3] = function(packet,pos,conv,ref)
      local value,npos,ctype = decode(packet,pos,conv,ref)
      if ctype == 'BIN' then
        return value,npos,'_nbignum'
      else
        throw(pos,"_nbignum: wanted BIN, got %s",ctype)
      end
    end,
    
    -- =====================================================================
    
    _decimalfraction = function(value,sref,stref)
      assert(type(value)    == 'table', "_decimalfractoin expects an array")
      assert(#value         == 2,       "_decimalfraction expects a two item array")
      assert(math.type(value[1]) == 'integer',"_decimalfraction expects integer as first element")
      assert(math.type(value[2]) == 'integer',"_decimalfraction expects integer as second element")
      return cbor_c.encode(0xC0,4) .. TYPE.ARRAY(value,sref,stref)
    end,
    
    [4] = function(packet,pos,conv,ref)
      local value,npos,ctype = decode(packet,pos,conv,ref)
      
      if ctype ~= 'ARRAY' then
        throw(pos,"_decimalfraction: wanted ARRAY, got %s",ctype)
      end
      
      if #value ~= 2 then
        throw(pos,"_decimalfraction: wanted ARRAY[2], got ARRAY[%d]",#value)
      end
      
      if math.type(value[1]) ~= 'integer' then
        throw(pos,"_decimalfraction: wanted integer for exp, got %s",type(value[1]))
      end
      
      if math.type(value[2]) ~= 'integer' then
        throw(pos,"_decimalfraction: wanted integer for mantissa, got %s",type(value[2]))
      end
      
      return value,npos,'_decimalfraction'
    end,
    
    -- =====================================================================
    
    _bigfloat = function(value,sref,stref)
      assert(type(value)         == 'table',  "_bigfloat expects an array")
      assert(#value              == 2,        "_bigfloat expects a two item array")
      assert(math.type(value[1]) == 'integer',"_bigfloat expects an integer as first element")
      assert(math.type(value[2]) == 'integer',"_bigfloat expects an integer as second element")
      return cbor_c.encode(0xC0,5) .. TYPE.ARRAY(value,sref,stref)
    end,
    
    [5] = function(packet,pos,conv,ref)
      local value,npos,ctype = decode(packet,pos,conv,ref)
      
      if ctype ~= 'ARRAY' then
        throw(pos,"_bigfloat: wanted ARRAY, got %s",ctype)
      end
      
      if #value ~= 2 then
        throw(pos,"_bigfloat: wanted ARRAY[2], got ARRAY[%s]",value)
      end
      
      if type(value[1]) ~= 'number' then
        throw(pos,"_bigfloat: wanted number for exp, got %s",ctype)
      end
      
      if math.type(value[2]) ~= 'integer' then
        throw(pos,"_bigfloat: wanted integer for mantissa, got %s",ctype)
      end
      
      return value,npos,'_bigfloat'
    end,
    
    -- =====================================================================
    
    _tobase64url = function(value,sref,stref)
      return cbor_c.encode(0xC0,21) .. encode(value,sref,stref)
    end,
    
    [21] = function(packet,pos,conv,ref)
      local value,npos = decode(packet,pos,conv,ref)
      return value,npos,'_tobase64url'
    end,
    
    -- =====================================================================
    
    _tobase64 = function(value,sref,stref)
      return cbor_c.encode(0xC0,22) .. encode(value,sref,stref)
    end,
    
    [22] = function(packet,pos,conv,ref)
      local value,npos = decode(packet,pos,conv,ref)
      return value,npos,'_tobase64'
    end,
    
    -- =====================================================================
    
    _tobase16 = function(value,sref,stref)
      return cbor_c.encode(0xC0,23) .. encode(value,sref,stref)
    end,
    
    [23] = function(packet,pos,conv,ref)
      local value,npos = decode(packet,pos,conv,ref)
      return value,npos,'_tobase16'
    end,
    
    -- =====================================================================
    
    _cbor = function(value,sref,stref)
      return cbor_c.encode(0xC0,24) .. TYPE.BIN(value,sref,stref)
    end,
    
    [24] = function(packet,pos,conv,ref)
      local value,npos,ctype = decode(packet,pos,conv,ref)
      if ctype == 'BIN' then
        return value,npos,'_cbor'
      else
        throw(pos,"_cbor: wanted BIN, got %s",ctype)
      end
    end,
    
    -- =====================================================================
    
    _url = function(value,sref,stref)
      return cbor_c.encode(0xC0,32) .. TYPE.TEXT(value,sref,stref)
    end,
    
    [32] = function(packet,pos,conv,ref)
      local value,npos,ctype = decode(packet,pos,conv,ref)
      if ctype == 'TEXT' then
        return value,npos,'_url'
      else
        throw(pos,"_url: wanted TEXT, got %s",ctype)
      end
    end,
    
    -- =====================================================================
    
    _base64url = function(value,sref,stref)
      return cbor_c.encode(0xC0,33) .. TYPE.TEXT(value,sref,stref)
    end,
    
    [33] = function(packet,pos,conv,ref)
      local value,npos,ctype = decode(packet,pos,conv,ref)
      if ctype == 'TEXT' then
        return value,npos,'_base64url'
      else
        throw(pos,"_base64url: wanted TEXT, got %s",ctype)
      end
    end,
    
    -- =====================================================================
    
    _base64 = function(value,sref,stref)
      return cbor_c.encode(0xC0,34) .. TYPE.TEXT(value,sref,stref)
    end,
    
    [34] = function(packet,pos,conv,ref)
      local value,npos,ctype = decode(packet,pos,conv,ref)
      if ctype == 'TEXT' then
        return value,npos,'_base64'
      else
        throw(pos,"_base64: wanted TEXT, got %s",ctype)
      end
    end,
    
    -- =====================================================================
    
    _regex = function(value,sref,stref)
      return cbor_c.encode(0xC0,35) .. TYPE.TEXT(value,sref,stref)
    end,
    
    [35] = function(packet,pos,conv,ref)
      local value,npos,ctype = decode(packet,pos,conv,ref)
      if ctype == 'TEXT' then
        return value,npos,'_regex'
      else
        throw(pos,"_regex: wanted TEXT, got %s",ctype)
      end
    end,
    
    -- =====================================================================
    
    _mime = function(value,sref,stref)
      return cbor_c.encode(0xC0,36) .. TYPE.TEXT(value,sref,stref)
    end,
    
    [36] = function(packet,pos,conv,ref)
      local value,npos,ctype = decode(packet,pos,conv,ref)
      if ctype == 'TEXT' then
        return value,npos,'_mime'
      else
        throw(pos,"_mime: wanted TEXT, got %s",ctype)
      end
    end,
    
    -- =====================================================================
    
    _magic_cbor = function()
      return cbor_c.encode(0xC0,55799)
    end,
    
    [55799] = function(_,pos)
      return '_magic_cbor',pos,'_magic_cbor'
    end,
    
    -- **********************************************************
    -- Following defined by IANA
    -- http://www.iana.org/assignments/cbor-tags/cbor-tags.xhtml
    -- **********************************************************
    
    _nthstring = function(value,sref,stref)
      return cbor_c.encode(0xC0,25) .. encode(value,sref,stref)
    end,
    
    [25] = function(packet,pos,conv,ref)
      local value,npos,ctype = decode(packet,pos,conv,ref)
      if ctype == 'UINT' then
        value = value + 1
        if not ref._stringref[value] then
          throw(pos,"_nthstring: invalid index %d",value - 1)
        end
        return ref._stringref[value].value,npos,ref._stringref[value].ctype
      else
        throw(pos,"_nthstring: wanted UINT, got %s",ctype)
      end
    end,
    
    -- =====================================================================
    
    _perlobj = function(value,sref,stref)
      return cbor_c.encode(0xC0,26) .. TYPE.ARRAY(value,sref,stref)
    end,
    
    [26] = function(packet,pos,conv,ref)
      local value,npos,ctype = decode(packet,pos,conv,ref)
      if ctype == 'ARRAY' then
        return value,npos,'_perlobj'
      else
        throw(pos,"_perlobj: wanted ARRAY, got %s",ctype)
      end
    end,
    
    -- =====================================================================
    
    _serialobj = function(value,sref,stref)
      return cbor_c.encode(0xC0,27) .. TYPE.ARRAY(value,sref,stref)
    end,
    
    [27] = function(packet,pos,conv,ref)
      local value,npos,ctype = decode(packet,pos,conv,ref)
      if ctype == 'ARRAY' then
        return value,npos,'_serialobj'
      else
        throw(pos,"_serialobj: wanted ARRAY, got %s",ctype)
      end
    end,
    
    -- =====================================================================
    -- To cut down on the silliness, not all types are shareable, only
    -- ARRAYs and MAPs will be supported.  TEXT and BIN have their own
    -- reference system; sharing UINT, NINT or SIMPLE just doesn't make
    -- sense, and TAGs aren't shareable either.  So ARRAY and MAP it is!
    -- =====================================================================
    
    _shareable = function(value)
      assert(type(value) == 'table',"_shareable: expects a table")
      return cbor_c.encode(0xC0,28)
    end,
    
    [28] = function(packet,pos,conv,ref)
      ref._sharedref.REF = {}
      table.insert(ref._sharedref,{ value = ref._sharedref.REF })
      local value,npos,ctype = decode(packet,pos,conv,ref)
      if ctype == 'ARRAY' or ctype == 'MAP' then
        ref._sharedref[#ref._sharedref].ctype = ctype
        return value,npos,ctype
      else
        throw(pos,"_shareable: wanted ARRAY or MAP, got %s",ctype)
      end
    end,
    
    -- =====================================================================
    
    _sharedref = function(value,sref,stref)
      return cbor_c.encode(0xC0,29) .. encode(value,sref,stref)
    end,
    
    [29] = function(packet,pos,conv,ref)
      local value,npos,ctype = decode(packet,pos,conv,ref)
      if ctype == 'UINT' then
        value = value + 1
        if not ref._sharedref[value] then
          throw(pos,"_sharedref: invalid index %d",value - 1)
        end
        return ref._sharedref[value].value,npos,ref._sharedref[value].ctype
      else
        throw(pos,"_sharedref: wanted ARRAY or MAP, got %s",ctype)
      end
    end,
    
    -- =====================================================================
    
    _rational = function(value,sref,stref)
      -- -----------------------------------------------------------------
      -- Per spec [1], the first value must be an integer (positive or
      -- negative) and the second value must be a positive integer greater
      -- than 0.  Since I'm don't know the format for bignums, there's
      -- little error checking if those are in use.  That's the way things
      -- go.
      --
      -- The encoding phase is done by hand for this.  Here we go ...
      -- -----------------------------------------------------------------
      
      assert(type(value) == 'table',"_rational: expecting a table")
      assert(#value == 2,"_rational: expecting a table of two values")
      assert(math.type(value[1]) == 'integer' or type(value[1] == 'string'),"_rational: bad numerator")
      assert(
              math.type(value[2]) == 'integer' and value[2] > 0
              or type(value[2]) == 'string',
              "_rational: bad denominator"
            )
            
      local res = cbor_c.encode(0xC0,30) .. cbor_c.encode(0x80,2)
      
      if math.type(value[1]) == 'integer' then
        res = res .. __ENCODE_MAP.number(value[1],sref,stref)
      else
        res = res .. TYPE.BIN(value[1],sref,stref)
      end
      
      if math.type(value[2]) == 'integer' then
        res = res .. TYPE.UINT(value[2],sref,stref)
      else
        res = res .. TYPE.BIN(value[2],sref,stref)
      end
      
      return res
    end,
    
    [30] = function(packet,pos,conv,ref)
      local value,npos,ctype = decode(packet,pos,conv,ref)
      
      if ctype ~= 'ARRAY' then
        throw(pos,"_rational wanted ARRAY, got %s",ctype)
      end
      
      if #value ~= 2 then
        throw(pos,"_rational: wanted ARRAY[2], got ARRAY[%d]",#value)
      end
      
      if math.type(value[1]) ~= 'integer' and type(value[1]) ~= 'string' then
        throw(pos,"_rationa;: wanted integer or bignum for numerator, got %s",type(value[1]))
      end
      
      if math.type(value[2]) ~= 'integer' and type(value[2]) ~= 'string' then
        throw(pos,"_rational: wanted integer or bignum for demoninator, got %s",type(value[2]))
      end
      
      if math.type(value[2]) == 'integer' and value[2] < 1 then
        throw(pos,"_rational: wanted >1 for demoninator")
      end
      
      return value,npos,'_rational'
    end,
    
    -- =====================================================================
    
    _uuid = function(value,sref,stref)
      assert(type(value) == 'string',"_uuid: expecting a string")
      assert(#value == 16,"_uuid: expecting a binary string of 16 bytes")
      return cbor_c.encode(0xC0,37) .. TYPE.BIN(value,sref,stref)
    end,
    
    [37] = function(packet,pos,conv,ref)
      local value,npos,ctype = decode(packet,pos,conv,ref)
      if ctype == 'BIN' then
        if #value ~= 16 then
          throw(pos,"_uuid: invalid data for UUID")
        end
        return value,npos,'_uuid'
      else
        throw(pos,"_uuid: wanted BIN, got %s",ctype)
      end
    end,
    
    -- =====================================================================
    
    _language = function(value,sref,stref)
      assert(type(value) == 'table',"_language: expecting a table")
      assert(#value == 2,"_language: expecting a table of two values")
      assert(type(value[1]) == 'string',"_language: expeting a string")
      assert(type(value[2]) == 'string',"_language: expeting a string")
      
      return cbor_c.encode(0xC0,38) .. TYPE.ARRAY(value,sref,stref)
    end,
    
    [38] = function(packet,pos,conv,ref)
      local value,npos,ctype = decode(packet,pos,conv,ref)
      if ctype ~= 'ARRAY' then
        throw(pos,"_language: wanted ARRAY, got %s",ctype)
      end
      
      if #value ~= 2 then
        throw(pos,"_language: wanted ARRAY(2), got ARRAY(%d)",#value)
      end
      
      if type(value[1]) ~= 'string' then
        throw(pos,"_langauge: wanted TEXT for language specifier")
      end
      
      if type(value[2]) ~= 'string' then
        throw(pos,"_language: wanted TEXT for text");
      end
      
      return value,npos,'_language'
    end,
    
    -- =====================================================================
    
    _id = function(value,sref,stref)
      return cbor_c.encode(0xC0,39) .. encode(value,sref,stref)
    end,
    
    [39] = function(packet,pos,conv,ref)
      local value,npos = decode(packet,pos,conv,ref)
      return value,npos,'_id'
    end,
    
    -- =====================================================================
    -- _stringref is like _magic_cbor, it stands for itself and just
    -- indicates that we're using string references for the next object.
    -- I'm doing this because this also have to interact with _sharedref.
    -- =====================================================================
    
    _stringref = function(_,_,stref)
      stref.SEEN = true
      return cbor_c.encode(0xC0,256)
    end,
    
    [256] = function(packet,pos,conv,ref)
      local prev = ref._stringref
      ref._stringref = {}
      local value,npos,ctype = decode(packet,pos,conv,ref)
      ref._stringref = prev
      return value,npos,ctype
    end,
    
    -- =====================================================================
    
    _bmime = function(value,sref,stref)
      return cbor_c.encode(0xC0,257) .. TYPE.BIN(value,sref,stref)
    end,
    
    [257] = function(packet,pos,conv,ref)
      local value,npos = decode(packet,pos,conv,ref)
      return value,npos,'_bmime'
    end,
    
    -- =====================================================================
    
    _ipaddress = function(value,sref,stref)
      assert(type(value) == 'string',"_ipaddress expects a string")
      assert(#value == 4 or #value == 16 or #value == 6,"_ipaddress wrong length")
      return cbor_c.encode(0xC0,260) .. TYPE.BIN(value,sref,stref)
    end,
    
    [260] = function(packet,pos,conv,ref)
      local value,npos,ctype = decode(packet,pos,conv,ref)
      
      if ctype ~= 'BIN' then
        throw(pos,"_ipaddress: wanted BIN, got %s",ctype)
      end
      
      if #value ~= 4 and #value ~= 16 and #value ~= 6 then
        throw(pos,"_ipaddress: wrong size address: %d",#value)
      end
      
      return value,npos,'_ipaddress'
    end,
    
    -- =====================================================================
    
    _decimalfractionexp = function(value,sref,stref)
      assert(type(value) == 'table',"__decimalfractionexp expects an array")
      assert(#value == 2,"_decimalfractionexp expects a two item array")
      assert(type(value[1]) == 'string' or math.type(value[1]) == 'integer')
      assert(math.type(value[2]) == 'integer')
      return cbor_c.encode(0xC0,264) .. TYPE.ARRAY(value,sref,stref)
    end,
    
    [264] = function(packet,pos,conv,ref)
      local value,npos,ctype = decode(packet,pos,conv,ref)
      
      if ctype ~= 'ARRAY' then
        throw(pos,"_decimalfractionexp: wanted ARRAY, got %s",ctype)
      end
      
      if #value ~= 2 then
        throw(pos,"_decimalfractionexp: wanted ARRAY(2), got ARRAY(%d)",#value)
      end
      
      if type(value[1]) ~= 'string' and math.type(value[1]) ~= 'integer' then
        throw(pos,"_decimalfractionexp: wanted integer or bignum for exp, got %s",type(value))
      end
      
      if math.type(value[2]) ~= 'integer' then
        throw(pos,"_decimalfractionexp: wanted integer or mantissa, got %s",type(value))
      end
      
      return value,npos,'_decimalfractionexp'
    end,
    
    -- =====================================================================
    
    _bigfloatexp = function(value,sref,stref)
      assert(type(value) == 'table',"__bigfloatexp expects an array")
      assert(#value == 2,"_bigfloatexp expects a two item array")
      assert(type(value[1]) == 'string' or math.type(value[1]) == 'integer')
      assert(math.type(value[2]) == 'integer')
      return cbor_c.encode(0xC0,265) .. TYPE.ARRAY(value,sref,stref)
      
    end,
    
    [265] = function(packet,pos,conv,ref)
      local value,npos,ctype = decode(packet,pos,conv,ref)
      
      if ctype ~= 'ARRAY' then
        throw(pos,"_bigfloatexp: wanted ARRAY, got %s",ctype)
      end
      
      if #value ~= 2 then
        throw(pos,"_bigfloatexp: wanted ARRAY(2), got ARRAY(%d)",#value)
      end
      
      if type(value[1]) ~= 'string' and math.type(value[1]) ~= 'integer' then
        throw(pos,"_bigfloatexp: wanted integer or bignum for exp, got %s",type(value))
      end
      
      if math.type(value[2]) ~= 'integer' then
        throw(pos,"_bigfloatexp: wanted integer or mantissa, got %s",type(value))
      end
      
      return value,npos,'_bigfloatexp'
    end,
    
    -- =====================================================================
    
    _indirection = function(value,sref,stref)
      return cbor_c.encode(0xC0,22098) .. encode(value,sref,stref)
    end,
    
    [22098] = function(packet,pos,conv,ref)
      local value,npos = decode(packet,pos,conv,ref)
      return value,npos,'_indirection'
    end,
    
    -- =====================================================================
    
    _rains = function(value,sref,stref)
      return cbor_c.encode(0xC0,15309736) .. TYPE.MAP(value,sref,stref)
    end,
    
    [15309736] = function(packet,pos,conv,ref)
      local value,npos = decode(packet,pos,conv,ref)
      return value,npos,'_rains'
    end,
  },
  {
    __index = function(_,key)
      if type(key) == 'number' then
        return function(packet,pos,conv,ref)
          local value,npos = decode(packet,pos,conv,ref)
          return value,npos,string.format('TAG_%d',key)
        end
        
      elseif type(key) == 'string' then
        return function(value)
          return cbor_c.encode(0xC0,tonumber(key)) .. encode(value)
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
-- Usage:       blob = cbor.SIMPLE['name'](n)
-- Desc:        Encode a CBOR simple type
-- Input:       n (number/optional) floating point number to encode (see notes)
-- Return:      blob (binary) CBOR encoded simple type
--
-- Note:        Some functions ignore the passed in parameter.
--
--              WARNING! The functions that do not ignore the parameter may
--              throw an error if floating point precision will be lost
--              during the encoding.  Please be aware of what you are doing
--              when calling SIMPLE.half(), SIMPLE.float() or
--              SIMPLE.double().
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

SIMPLE = setmetatable(
  {
    [20] = function(pos)       return false    ,pos,'false'     end,
    [21] = function(pos)       return true     ,pos,'true'      end,
    [22] = function(pos)       return null     ,pos,'null'      end,
    [23] = function(pos)       return undefined,pos,'undefined' end,
    [25] = function(pos,value) return value    ,pos,'half'      end,
    [26] = function(pos,value) return value    ,pos,'single'    end,
    [27] = function(pos,value) return value    ,pos,'double'    end,
    [31] = function(pos)       return false    ,pos,'__break'   end,
    
    ['false'] = function()  return "\244" end,
    ['true']  = function()  return "\245" end,
    null      = function()  return "\246" end,
    undefined = function()  return "\247" end,
    half      = function(h) return cbor_c.encode(0xE0,25,h) end,
    single    = function(s) return cbor_c.encode(0xE0,26,s) end,
    double    = function(d) return cbor_c.encode(0xE0,27,d) end,
    __break   = function()  return "\255" end,
  },
  {
    __index = function(_,key)
      if type(key) == 'number' then
        return function(pos,value)
          return value,pos,'SIMPLE'
        end
        
      elseif type(key) == 'string' then
        return function()
          return cbor_c.encode(0xE0,tonumber(key))
        end
      end
    end
  }
)

-- ***********************************************************************
-- Usage:       value,pos2,ctype = cbor.decode(packet[,pos][,conv][,ref][,iskey])
-- Desc:        Decode CBOR encoded data
-- Input:       packet (binary) CBOR binary blob
--              pos (integer/optional) starting point for decoding
--              conv (table/optional) table of conversion routines
--              ref (table/optional) reference table (see notes)
--              iskey (boolean/optional) is a key in a MAP (see notes)
-- Return:      value (any) the decoded CBOR data
--              pos2 (integer) offset past decoded data
--              ctype (enum/cbor) CBOR type of value
--
-- Note:        The conversion table should be constructed as:
--
--              {
--                UINT      = function(v) return munge(v) end,
--                _datetime = function(v) return munge(v) end,
--                _url      = function(v) return munge(v) end,,
--              }
--
--              The keys are CBOR types (listed above).  These functions are
--              expected to convert the decoded CBOR type into a more
--              appropriate type for your code.  For instance, an _epoch can
--              be converted into a table.
--
--              Users of this function *should not* pass a reference table
--              into this routine---this is used internally to handle
--              references.  You need to know what you are doing to use this
--              parameter.  You have been warned.
--
--              The iskey is true if the value is being used as a key in a
--              map, and is passed to the conversion routine; this too,
--              is an internal use only variable and you need to know what
--              you are doing to use this.  You have been warned.
--
--              This function can throw an error.  The returned error object
--              MAY BE a table, in which case it has the format:
--
--              {
--                msg = "Error text",
--                pos = 13 -- position in binary object of error
--              }
--
-- ***********************************************************************

function decode(packet,pos,conv,ref,iskey)
  pos  = pos  or 1
  conv = conv or {}
  ref  = ref  or { _stringref = {} , _sharedref = {} }
  
  local ctype,info,value,npos = cbor_c.decode(packet,pos)
  local value2,npos2,ctype2 = TYPE[ctype](packet,npos,info,value,conv,ref)
  
  if conv[ctype2] then
    value2 = conv[ctype2](value2,iskey)
  end
  
  return value2,npos2,ctype2
end

-- ***********************************************************************
-- Usage:       value,pos2,ctype[,err] = cbor.pdecode(packet[,pos][,conv][,ref])
-- Desc:        Protected call to cbor.decode(), which will return an error
-- Input:       packet (binary) CBOR binary blob
--              pos (integer/optional) starting point for decoding
--              conv (table/optional) table of conversion routines (see cbor.decode())
--              ref (table/optional) reference table (see cbor.decode())
-- Return:      value (any) the decoded CBOR data, nil on error
--              pos2 (integer) offset past decoded data; if error, position of error
--              ctype (enum/cbor) CBOR type
--              err (string/optional) error message (if any)
-- ***********************************************************************

function pdecode(packet,pos,conv,ref)
  local okay,value,npos,ctype = pcall(decode,packet,pos,conv,ref)
  if okay then
    return value,npos,ctype
  else
    return nil,value.pos,'__error',value.msg
  end
end

-- ***********************************************************************

local function generic(value,sref,stref)
  local mt = getmetatable(value)
  if not mt then
    if type(value) == 'table' then
      if #value > 0 then
        return TYPE.ARRAY(value,sref,stref)
      else
        return TYPE.MAP(value,sref,stref)
      end
    else
      error(string.format("Cannot encode %s",type(value)))
    end
  end
  
  if mt.__tocbor then
    return mt.__tocbor(value,sref,stref)
    
  elseif mt.__len then
    return TYPE.ARRAY(value,sref,stref)
    
  elseif LUA_VERSION == "Lua 5.2" and mt.__ipairs then
    return TYPE.ARRAY(value,sref,stref)
    
  elseif LUA_VERSION >= "Lua 5.2" and mt.__pairs then
    return TYPE.MAP(value,sref,stref)
    
  else
    error(string.format("Cannot encode %s",type(value)))
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
-- Usage:       blob = cbor.__ENCODE_MAP[luatype](value,sref,stref)
-- Desc:        Encode a Lua type into a CBOR type
-- Input:       value (any) a Lua value who's type matches luatype.
--              sref (table/optional) shared reference table
--              stref (table/optional) shared string reference table
-- Return:      blob (binary) CBOR encoded data
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
      return cbor_c.encode(0xE0,nil,value)
    end
  end,
  
  ['string'] = function(value,sref,stref)
    if UTF8:match(value) > #value then
      return TYPE.TEXT(value,sref,stref)
    else
      return TYPE.BIN(value,sref,stref)
    end
  end,
  
  ['table']    = generic,
  ['function'] = generic,
  ['userdata'] = generic,
  ['thread']   = generic,
}

-- ***********************************************************************
-- Usage:       blob = cbor.encode(value[,sref][,stref])
-- Desc:        Encode a Lua type into a CBOR type
-- Input:       value (any)
--              sref (table/optional) shared reference table
--              stref (table/optional) shared string reference table
-- Return:      blob (binary) CBOR encoded value
-- ***********************************************************************

function encode(value,sref,stref)
  if value == null then
    return SIMPLE.null()
  elseif value == undefined then
    return SIMPLE.undefined()
  end
  
  local res = ""
  
  if stref and not stref.SEEN then
    res = TAG._stringref(nil,nil,stref)
  end
  
  return res .. __ENCODE_MAP[type(value)](value,sref,stref)
end

-- ***********************************************************************
-- Usage:       blob[,err] = cbor.pencode(value[,sref][,stref])
-- Desc:        Protected call to encode a CBOR type
-- Input:       value (any)
--              sref (table/optional) shared reference table
--              stref (table/optional) shared string reference table
-- Return:      blob (binary) CBOR encoded value, nil on error
--              err (string/optional) error message
-- ***********************************************************************

function pencode(value,sref,stref)
  local okay,value2 = pcall(encode,value,sref,stref)
  if okay then
    return value2
  else
    return nil,value2
  end
end

-- ***********************************************************************

if LUA_VERSION >= "Lua 5.2" then
  return _ENV
end
