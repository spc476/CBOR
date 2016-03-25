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
    assert(val == target)
  end
end

-- ***********************************************************************

test('false',"F4",false)
test('true',"F5",true)
test('null',"F6",nil)
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
test('NINT',"21",-2)
test('TEXT',"6161","a")
test('TEXT',"6449455446","IETF")
test('BIN',"450001020304","\0\1\2\3\4")

