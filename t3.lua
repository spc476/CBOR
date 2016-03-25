dump  = require "org.conman.table".dump
cbor5 = require "cbor5"
DISP  = true

TYPES =
{
  UINT     = 0x00,
  NINT     = 0x20,
  BIN      = 0x40,
  TEXT     = 0x60,
  ARRAY    = 0x80,
  MAP      = 0xA0,
  TAG      = 0xC0,
  EXTENDED = 0xE0
}

local function hextobin(s)
  local bin = ""
  for pair in s:gmatch("(%x%x)") do
    bin = bin .. string.char(tonumber(pair,16))
  end
  return bin
end

local function test(tart,src,target,disp)
  local t,info,val,pos = cbor5.decode(hextobin(src),1)

  if t == 0x20 then val = -1 - val end
  
  if disp or DISP then
    print(tart,target,t,val,pos)
  end
  
  assert(TYPES[tart] == t)
  
  if type(target) == 'function' then
    assert(target(val))
  else
    assert(val == target)
  end
end

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
--test('TEXT',"6161","a")
--test('TEXT',"6449455446","IETF")
