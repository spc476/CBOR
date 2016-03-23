
local ddt   = require "org.conman.debug"
local cbor  = require "cbor"
local cbore = require "cbore"

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

function roundtrip(v)
  local e = cbore.encode(v)
  local _,d = cbor.decode(e)
  return compare(v,d)
end

assert(roundtrip())
assert(roundtrip(false))
assert(roundtrip(true))
assert(roundtrip(     1))
assert(roundtrip(    -1))
assert(roundtrip(   127))
assert(roundtrip(  -127))
assert(roundtrip( 32767))
assert(roundtrip(-32767))
assert(roundtrip( 2^30))
assert(roundtrip(-2^30))
assert(roundtrip(0.25))
assert(roundtrip(math.huge))
assert(roundtrip(-math.huge))
assert(roundtrip(math.pi))
assert(roundtrip{1,2,3})
assert(roundtrip{one=1,two=2,three=3})
assert(roundtrip{[false]=true,[3]='four',five=6})
