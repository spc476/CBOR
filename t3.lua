dump       = require "org.conman.table".dump
safestring = require "org.conman.table".safestring
cbor       = require "cbor"
cbore      = require "cbore"
DISP       = true

-- ***********************************************************************

local function hextobin(s)
  local bin = ""
  for pair in s:gmatch("(%x%x)") do
    bin = bin .. string.char(tonumber(pair,16))
  end
  return bin
end

-- ***********************************************************************

local function test(tart,src,target,disp)
  local t,val = cbor.decode(hextobin(src),1)

  if disp or DISP then
    if tart == 'TEXT' or tart == 'BIN' then
      local starget = safestring(target)
      print(tart,safestring(target),t,safestring(val))
    else
      print(tart,target,t,val)
    end
  end
  
  assert(tart == t)
  
  if type(target) == 'function' then
    assert(target(val))
  else
    if (t == 'half' or t == 'single' or t == 'double')
    and target ~= target and val ~= val then
      assert(true)
    else
      assert(val == target)
    end
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
--test('single',"fa47c35000",100000.0)
--test('single',"fa7f7fffff",3.4028234663852886e+38)
test('double',"fb7e37e43c8800759c",1.0e+300)
--test('single',"f90001",5.960464477539063e-8)
--test('single',"f90400",0.00006103515625)
--test('single',"f9c400",-4.0)
test('double',"fbc010666666666666",-4.1)
test('half',"f97c00",math.huge)
test('half',"f97e00",0/0)
test('half',"f9fc00",-math.huge)
test('single',"fa7f800000",math.huge)
--test('single',"fa7fc00000",0/0)
test('single',"faff800000",-math.huge)
test('double',"fb7ff0000000000000",math.huge)
test('double',"fb7ff8000000000000",0/0)
test('double',"fbfff0000000000000",-math.huge)
test('false',"F4",false)
test('true',"F5",true)
test('null',"F6",nil)
test('undefined',"F7",nil)




test('NINT',"21",-2)
test('TEXT',"6161","a")
test('TEXT',"6449455446","IETF")
test('BIN',"450001020304","\0\1\2\3\4")

