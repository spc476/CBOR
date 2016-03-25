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
-- ***************************************************************

lpeg       = require "lpeg"
safestring = require "org.conman.table".safestring
cbor       = require "cbor"
cbore      = require "cbore"
DISP       = false

-- ***********************************************************************

local UTF8 = (
                 lpeg.R("\7\13"," ~")
               + lpeg.R("\194\223") * lpeg.R("\128\191")
               + lpeg.R("\224\239") * lpeg.R("\128\191") * lpeg.R("\128\191")
               + lpeg.R("\240\224") * lpeg.R("\128\191") * lpeg.R("\128\191") * lpeg.R("\128\191")
	     )^0

-- ***********************************************************************

local function hextobin(s)
  local bin = ""
  for pair in s:gmatch("(%x%x)") do
    bin = bin .. string.char(tonumber(pair,16))
  end
  return bin
end

-- ***********************************************************************

function compare(a,b)
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
    return a == b
  end
end

assert(compare({a=1,b=2},{b=2,a=1}))
assert(compare({1,2,3},{1,2,3}))

-- ***********************************************************************

function roundtrip(v)
  local e = cbore.encode(v)
  local _,d,p,f = cbor.decode(e)
  return compare(v,d)
end

-- ***********************************************************************

local function test(tart,src,target,disp,bad,badrt)
  local t,val = cbor.decode(hextobin(src),1)

  if disp or DISP or bad or badrt then
    local xx = ""
    
    if bad     then xx = xx .. "D" end
    if badrt   then xx = xx .. "R" end
    if #xx > 0 then xx = "XX-" .. xx end
    
    if type(target) == 'string' then
      if UTF8:match(target) > #target then
        print(tart,target,t,val,xx)
      else
        local starget = safestring(target)
        print(tart,safestring(target),t,safestring(val),xx)
      end
    else
      print(tart,target,t,val,xx)
    end
  end
  
  assert(tart == t)
  
  if not bad then
    if type(target) == 'function' then
      assert(target(val))
    else
      if (t == 'half' or t == 'single' or t == 'double')
      and target ~= target and val ~= val then
        assert(true)
      else
        assert(compare(val,target))
      end
    end
  end 
  
  if not badrt then
    assert(roundtrip(target))
  end
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
test('half',"F90000",0.0)
test('half',"F98000",-0.0)
test('half',"F93C00",1.0)
test('half',"F93E00",1.5)
test('half',"F97BFF",65504.0) 
test('single',"fa47c35000",100000.0			, nil , true) 
test('single',"fa7f7fffff",3.4028234663852886e+38	, nil , true  , true)
test('double',"fb7e37e43c8800759c",1.0e+300		, nil , false , true)
test('half',"f90001",5.960464477539063e-8)
test('half',"f90400",0.00006103515625)
test('half',"f9c400",-4.0)
test('double',"fbc010666666666666",-4.1)
test('half',"f97c00",math.huge)
test('half',"f97e00",0/0				, nil , false , true)
test('half',"f9fc00",-math.huge)
test('single',"fa7f800000",math.huge)
test('single',"fa7fc00000",0/0				, nil , true  , true)
test('single',"faff800000",-math.huge)
test('double',"fb7ff0000000000000",math.huge)
test('double',"fb7ff8000000000000",0/0			, nil , true  , true)
test('double',"fbfff0000000000000",-math.huge)
test('false',"F4",false)
test('true',"F5",true)
test('null',"F6",nil)
test('undefined',"F7",nil)
test('simple',"F0",16)
test('simple',"f818",24)
test('simple',"F8FF",255)
test('_epoch',"c11a514b67b0",1363896240)
test('_epoch',"c1fb41d452d9ec200000",1363896240.5)
test('_tobase16',"d74401020304","\1\2\3\4") 	-- RFC wrong here
test('_cbor',"d818456449455446","dIETF")	-- should be a binary string
test('_url',"d82076687474703a2f2f7777772e6578616d706c652e636f6d",
	"http://www.example.com")
test('BIN',"40","")
test('BIN',"4401020304","\1\2\3\4")
test('TEXT',"60","")
test('TEXT',"6161","a")
test('TEXT',"6449455446","IETF")
test('TEXT',"62225c",[["\]])
test('TEXT',"62c3bc","\195\188")
test('TEXT',"63e6b0b4","\230\176\180")
test('TEXT',"64f0908591","\240\144\133\145")
test('ARRAY',"80",{})
test('ARRAY',"83010203",{1,2,3})
test('ARRAY',"8301820203820405",{ 1 , { 2 , 3 } , { 4 , 5 }})
test('ARRAY',"98190102030405060708090a0b0c0d0e0f101112131415161718181819",
	{ 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25 })
test('MAP',"A0",{})
test('MAP',"a201020304",{ [1] = 2 , [3] = 4}		, nil , false , true)
test('MAP',"a26161016162820203",{ a = 1 , b = { 2, 3 } })
test('ARRAY',"826161a161626163",{ "a" , { b = "c" }})
test('MAP',"a56161614161626142616361436164614461656145",
	{ a = 'A' , b = 'B' , c = 'C' , d = 'D' , e = 'E' })
test('BIN',"5f42010243030405ff","\1\2\3\4\5")
test('TEXT',"7f657374726561646d696e67ff","streaming")
test('ARRAY',"9fff",{})
test('ARRAY',"9f018202039f0405ffff",{ 1 , { 2 , 3 } , { 4 , 5 }})
test('ARRAY',"9f01820203820405ff",{ 1 , { 2 ,3 } , { 4 , 5 }})
test('ARRAY',"83018202039f0405ff",{ 1 , { 2 ,3 } , { 4 , 5 }})
test('ARRAY',"83019f0203ff820405",{ 1 , { 2 ,3 } , { 4 , 5 }})
test('ARRAY',"9f0102030405060708090a0b0c0d0e0f101112131415161718181819ff",
	{ 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25 })
test('MAP',"bf61610161629f0203ffff",{ a = 1 , b = { 2, 3 } })
test('ARRAY',"826161bf61626163ff",{ "a" , { b = "c" }})
test('MAP',"bf6346756ef563416d7421ff",{ Fun = true , Amt = -2 })
