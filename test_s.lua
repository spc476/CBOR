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
-- luacheck: globals cbor
-- ***************************************************************

local cbor  = require "org.conman.cbor_s"

-- ***********************************************************************

local function assertf(cond,...)
  local msg = string.format(...)
  assert(cond,msg)
end

-- ***********************************************************************

local function hextobin(hbin)
  local bin = ""
  for pair in hbin:gmatch "(%x%x)" do
    bin = bin .. string.char(tonumber(pair,16))
  end
  return bin
end

-- ***********************************************************************

local function bintohex(bin)
  local hbin = ""
  for c in bin:gmatch(".") do
    hbin = hbin .. string.format("%02X ",string.byte(c))
  end
  return hbin
end

-- ***********************************************************************

local function compare(a,b)
  if type(a) ~= type(b) then
    return false
  end
  
  if type(a) == 'table' then
    for name,value in pairs(a) do
      if not compare(value,b[name]) then
        return false
      end
    end
    for name,value in pairs(b) do
      if not compare(value,a[name]) then
        return false
      end
    end
    return true
  else
    if a ~= a and b ~= b then -- handle NaNs
      return true
    else
      return a == b
    end
  end
end

assert(compare({a=1,b=2},{b=2,a=1}))
assert(compare({1,2,3},{1,2,3}))

-- ***********************************************************************

local function test(ctype,hbinary,src,srcf,destf)
  local bin = hextobin(hbinary)
  local encoded
  
  io.stdout:write("\tTesting ",ctype," ...") io.stdout:flush()
  
  if srcf ~= 'SKIP' then
    if srcf then
      encoded = srcf()
    else
      encoded = cbor.encode(src)
    end
    
    assertf(encoded == bin,"encoding for %s failed:\n%s\n%s",ctype,bintohex(bin),bintohex(encoded))
  else
    print("SKIPPED encoding",ctype)
    encoded = bin
  end
  
  local decoded,_,rctype = cbor.decode(encoded)
  
  assertf(rctype == ctype,"decoding type failed: wanted %s got %s",ctype,rctype)
  
  if type(destf) == 'function' then
    assertf(destf(src,decoded),"decoding for %s is different",ctype)
  else
    assertf(compare(src,decoded),"xdecoding for %s is different",ctype)
  end
  
  io.stdout:write("GO\n")
  return true
end

-- ***********************************************************************

local function rtst(ctype,src,f)
  local encode
  
  io.stdout:write("\tTesting ",ctype," ...") io.stdout:flush()
  if f then
    encode = f(src)
  else
    encode = cbor.encode(src)
  end
  
  local decode,_,rctype = cbor.decode(encode)
  assertf(rctype == ctype,"decoding type failed: wanted %s got %s",ctype,rctype)
  assertf(compare(src,decode),"decoding for %s is different",ctype)
  io.stdout:write("GO!\n")
end

-- ***********************************************************************
-- values from RFC-7049
-- ***********************************************************************

test('UINT',"00",0)
test('UINT',"01",1)
test('UINT',"0A",10)
test('UINT',"17",23)
test('UINT',"1818",24)
test('UINT',"1819",25)
test('UINT',"1864",100)
test('UINT',"1903e8",1000)
test('UINT',"1a000f4240",1000000)
test('UINT',"1b000000e8d4a51000",1000000000000)
test('NINT',"20",-1)
test('NINT',"29",-10)
test('NINT',"3863",-100)
test('NINT',"3903E7",-1000)
test('half',"F93E00",1.5)
test('single',"fa7f7fffff",3.4028234663852886e+38,
	function()
	  return cbor.encode(3.40282346638528859811704183484516925440e+38)
	end)
test('double',"fb7e37e43c8800759c",1.0e+300,
	function()
	  return cbor.encode(1.0e+300)
	end)
test('half',"f90001",5.960464477539063e-8)
test('half',"f90400",0.00006103515625)
test('double',"fbc010666666666666",-4.1)
test('half',"f97c00",math.huge)
test('half',"f9fe00",0/0) -- can't code a positive NaN here 
test('half',"f9fc00",-math.huge)
test('false',"F4",false)
test('true',"F5",true)
test('null',"F6",nil)

test('UINT',"c11a514b67b0",1363896240,
	function() return cbor.encode(1363896240,1) end)
test('double',"c1fb41d452d9ec200000",1363896240.5,
	function() return cbor.encode(1363896240.5,1) end)
test('BIN',"d74401020304","\1\2\3\4", 	-- RFC wrong here
	function() return cbor.encode("\1\2\3\4",23) end)
test('TEXT',"d818656449455446","dIETF", -- modified slightly from RFC
	function() return cbor.encode(cbor.encode("IETF"),24) end)
test('TEXT',"d82076687474703a2f2f7777772e6578616d706c652e636f6d",
	"http://www.example.com",
	function() return cbor.encode("http://www.example.com",32) end)
test('BIN',"4401020304","\1\2\3\4")
test('TEXT',"60","")
test('TEXT',"6161","a")
test('TEXT',"6449455446","IETF")
test('TEXT',"62225c",[["\]])
test('TEXT',"62c3bc","\195\188")
test('TEXT',"63e6b0b4","\230\176\180")
test('TEXT',"64f0908591","\240\144\133\145")
test('ARRAY',"83010203",{1,2,3})
test('ARRAY',"8301820203820405",{ 1 , { 2 , 3 } , { 4 , 5 }})
test('ARRAY',"98190102030405060708090a0b0c0d0e0f101112131415161718181819",
	{ 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25 })
rtst('MAP',{ a = 1 , b = { 2 , 3 }} )
test('ARRAY',"826161a161626163",{ "a" , { b = "c" }})
rtst('MAP',{ a = "A" , b = 'B' , c = 'C' , d = "D" , e = [[E]] })
