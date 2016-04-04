/***************************************************************************
*
* Copyright 2016 by Sean Conner.
*
* This library is free software; you can redistribute it and/or modify it
* under the terms of the GNU Lesser General Public License as published by
* the Free Software Foundation; either version 3 of the License, or (at your
* option) any later version.
*
* This library is distributed in the hope that it will be useful, but
* WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
* or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public
* License for more details.
*
* You should have received a copy of the GNU Lesser General Public License
* along with this library; if not, see <http://www.gnu.org/licenses/>.
*
* Comments, questions and criticisms can be sent to: sean@conman.org
*
*************************************************************************/

#include <math.h>
#include <stdint.h>
#include <stdbool.h>
#include <errno.h>
#include <assert.h>

#include <lua.h>
#include <lauxlib.h>

#include "dnf.h"

#if !defined(LUA_VERSION_NUM) || LUA_VERSION_NUM < 501
#  error You need to compile against Lua 5.1 or higher
#endif

/**************************************************************************/

typedef union
{
  uint32_t i;
  float    f;
} float__u;

typedef union
{
  uint64_t i;
  double   d;
} double__u;

typedef union
{
  uint8_t b[9];
  char    c[9];
} buffer__u;

/***************************************************************************
* Push a CBOR encoded float value onto the stack (passed in as an integer so
* we can push things like +-inf or any nubmer of NaNs).  The number of bytes
* to use is passed in (since floats are encoded in 2, 4 or 8 bytes
* respectively).
****************************************************************************/

static void cbor_cL_pushvalueN(
        lua_State              *L,
        int                     typeinfo,
        unsigned long long int  value,
        size_t                  len
)
{
  buffer__u result;
  size_t    idx = sizeof(buffer__u);
  
  assert(L != NULL);
  assert(
             ((len == 1) && ((typeinfo & 0x1F) == 24))
          || ((len == 2) && ((typeinfo & 0x1F) == 25))
          || ((len == 4) && ((typeinfo & 0x1F) == 26))
          || ((len == 8) && ((typeinfo & 0x1F) == 27))
        );
  
  for (uint8_t b = (uint8_t)value ; len > 0 ; b = (uint8_t)(value >>= 8) , len--)
    result.b[--idx] = b;
  
  result.b[--idx] = typeinfo;
  lua_pushlstring(L,&result.c[idx],sizeof(buffer__u) - idx);
}

/*************************************************************************
* Push a CBOR encoded value onto the Lua stack.  This will use the minimal
* encoding for a value.
**************************************************************************/

static void cbor_cL_pushvalue(
        lua_State              *L,
        int                     type,
        unsigned long long int  value
)
{
  assert(L             != NULL);
  assert((type & 0x1F) == 0);
  
  /*-----------------------------------------------
  ; Values below 24 are encoded in the type byte.
  ;------------------------------------------------*/
  
  if (value < 24)
  {
    char t = (char)type | (char)value;
    lua_pushlstring(L,&t,1);
  }
  
  /*----------------------------------------------------------------------
  ; larger values will take 1 additional byte (info of 24), 2 bytes (25),
  ; four bytes (26) or eight bytes (27), stored in network-byte order (MSB
  ; first).  We do this by filling in the character array backwards, filling
  ; it with the next 8 bits in network-byte-order.  When we hit a zero byte,
  ; we stop with the loop since there's no more to do.
  ;------------------------------------------------------------------------*/
  
  else
  {
    if (value < 256uLL)
      cbor_cL_pushvalueN(L,type | 24,value,1);
    else if (value < 65536uLL)
      cbor_cL_pushvalueN(L,type | 25,value,2);
    else if (value < 4294967296uLL)
      cbor_cL_pushvalueN(L,type | 26,value,4);
    else
      cbor_cL_pushvalueN(L,type | 27,value,8);
  }
}

/******************************************************************
* usage:	blob = cbor_c.encode02C(type,value)
* desc:		Encode a CBOR integer
* input:	type (integer) 0x00, 0x20, 0xC0
*		value (number) value to encode
* return:	blog (binary) CBOR encoded value
*
* note:		This is expected to be called to encode CBOR types
*		UINT (0x00), NINT (0x20) or a TAG (0xC0).
*
* note:		Throws on invalid parameters
*******************************************************************/

static int cbor_clua_encode02C(lua_State *L)
{
  assert(L != NULL);
  
#ifndef NDEBUG
  int type = luaL_checkinteger(L,1);
  assert((type == 0x00) || (type == 0x20) || (type == 0xC0));
#endif

  cbor_cL_pushvalue(L,luaL_checkinteger(L,1),luaL_checknumber(L,2));
  return 1;
}

/******************************************************************
* usage:	blob = cbor_c.encode468A(type[,value])
* desc:		Encode a CBOR integer
* input:	type (integer) 0x40, 0x60, 0x80, 0xA0
*		value (number/optional) value to encode
* return:	blob (binary) CBOR encoded value
*
* note:		This is expected to be called to encode CBOR types BIN
*		(0x40), TEXT (0x60), ARRAY (0x80) or MAP (0xA0).  The value
*		is optional, if if not present (or nil), a size of
*		indefinite (info of 31) is used.
*
* note:		Throws on invalid parameters
*******************************************************************/

static int cbor_clua_encode468A(lua_State *L)
{
  assert(L != NULL);
  
#ifndef NDEBUG
  int type = luaL_checkinteger(L,1);
  assert((type == 0x40) || (type == 0x60) || (type == 0x80) || (type ==  0xA0));
#endif

  if (lua_isnoneornil(L,2))
  {
    char t = (char)(luaL_checkinteger(L,1) | 31);
    lua_pushlstring(L,&t,1);
  }
  else
    cbor_cL_pushvalue(L,luaL_checkinteger(L,1),luaL_checknumber(L,2));
  
  return 1;
}

/******************************************************************
* usage:	blob = cbor_c.encodeE(type[,value][,value2])
* desc:		Encode a CBOR integer or float
* input:	type (integer) 0xE0
*		value (number/optional) possible integer to encode
*		value2 (number/optional) possible float to encode
* return:	blob (binary) CBOR encoded value
*
* note:		This is expected to be called to encode a CBOR simple type
*		(0xE0).  If value and value2 are nil, then the __break
*		simple type is encoded; if value is nil and value2 exists,
*		then the floating point value2 is encoded using the best
*		size fo the encoding.  If value is 25 (half), 26 (single) or
*		27 (double) then value2 is encoded.
*
* note:		Throws on invalid parameters or if float encoding will lose
*		precision.
*******************************************************************/

static int cbor_clua_encodeE(lua_State *L)
{
  unsigned short h;
  double__u      d;
  float__u       f;
  dnf__s         cv;
  int            type;
  
  type = luaL_checkinteger(L,1);
  
  assert(L != NULL);
  
  if (lua_isnoneornil(L,2))
  {
    /*--------------------------------
    ; encoding a __break value?
    ;---------------------------------*/
    
    if (lua_isnoneornil(L,3))
    {
      char t = (char)(luaL_checkinteger(L,1) | 31);
      lua_pushlstring(L,&t,1);
    }
    
    /*---------------------------------------------------------------------
    ; nope, encoding a floating point value in the smallest encoding we can
    ; muster.
    ;----------------------------------------------------------------------*/
    
    else
    {
      d.d = luaL_checknumber(L,3);
      dnf_fromdouble(&cv,d.d);
      if (dnf_tohalf(&h,cv) == 0)
        cbor_cL_pushvalueN(L,type | 25,(unsigned long long int)h,2);
      else if (dnf_tosingle(&f.f,cv) == 0)
        cbor_cL_pushvalueN(L,type | 26,(unsigned long long int)f.i,4);
      else
        cbor_cL_pushvalueN(L,type | 27,d.i,8);
    }
  }
  else
  {
    /*-------------------------------------------------------------------
    ; if we're encoding infos 25, 26 or 27, then we have a floating point
    ; number to encode, and we'll try to encode it to the specified size. 
    ; If not, boom!  If so, woot!  If it's not infos 25, 26 or 27, then
    ; proceed normally.
    ;--------------------------------------------------------------------*/
    
    unsigned long long int value = luaL_checknumber(L,2);
    if (value == 25)
    {
      d.d = luaL_checknumber(L,3);
      dnf_fromdouble(&cv,d.d);
      if (dnf_tohalf(&h,cv) != 0)
        return luaL_error(L,"cannot convert to half-precision");
      cbor_cL_pushvalueN(L,type | 25,(unsigned long long int)h,2);
    }
    else if (value == 26)
    {
      d.d = luaL_checknumber(L,3);
      dnf_fromdouble(&cv,d.d);
      if (dnf_tosingle(&f.f,cv) != 0)
        return luaL_error(L,"cannot convert to single-preccision");
      cbor_cL_pushvalueN(L,type | 26,(unsigned long long int)f.i,4);
    }
    else if (value == 27)
    {
      d.d = luaL_checknumber(L,3);
      cbor_cL_pushvalueN(L,type | 27,d.i,8);
    }
    else
      cbor_cL_pushvalue(L,luaL_checkinteger(L,1),value);
  }
  
  return 1;
}

/******************************************************************
* Usage:	blob = cbor_c.encode(type,value[,value2])
* Desc:		Encode a CBOR value
* Input:	type (integer) CBOR type
*		value (number) value to encode (see note)
*		value (number/optional) float to encode (see note)
* Return:	blob (binary) CBOR encoded value
*
* Note:		value is optional for type of 0xE0.
*		value2 is optional for type of 0xE0; otherwise it's ignored.
*******************************************************************/

static int cbor_clua_encode(lua_State *L)
{
  assert(L != NULL);
  
  switch(luaL_checkinteger(L,1))
  {
    case 0x00:
    case 0x20:
    case 0xC0: return cbor_clua_encode02C(L);
    
    case 0x40:
    case 0x60:
    case 0x80:
    case 0xA0: return cbor_clua_encode468A(L);
    
    case 0xE0: return cbor_clua_encodeE(L);
    default:   break;
  }
  
  return luaL_error(L,"invalid type %d",lua_tointeger(L,1));
}

/******************************************************************
* Usage:	ctype,info,value,pos2 = cbor_c.decode(blob,pos)
* Desc:		Decode a CBOR-encoded value
* Input:	blob (binary) binary CBOR sludge
*		pos (integer) position to start decoding from
* Return:	ctype (integer) CBOR major type
*		info (integer) sub-major type information
*		value (integer number) decoded value
*		pos2 (integer) position past decoded data
*
* Note:		Throws in invalid parameter
*******************************************************************/

static int cbor_clua_decode(lua_State *L)
{
  size_t                  packlen;
  const char             *packet = luaL_checklstring(L,1,&packlen);
  size_t                  pos    = luaL_checkinteger(L,2) - 1;
  int                     type;
  int                     info;
  unsigned long long int  value;
  size_t                  i;
  size_t                  len;

  assert(L != NULL);
    
  if (pos > packlen)
    return luaL_error(L,"no input");
  
  lua_pushinteger(L,type = packet[pos] & 0xE0);
  lua_pushinteger(L,info = packet[pos] & 0x1F);
  
  /*----------------------------------------------------------------------
  ; Info values less than 24 and 31 are inherent---the data is just there. 
  ; So we handle these directly here---the value is either the info value,
  ; or a HUGE_VAL (in the case of info=31).  Info values 24 to 27 have
  ; extention bytes (1, 2, 4 or 8).  Get the length for these and carry on.
  ;-----------------------------------------------------------------------*/
  
  if (info < 24)
  {
    lua_pushinteger(L,info);
    lua_pushinteger(L,pos + 2);
    return 4;
  }
  else if (info == 24)
    len = 1;
  else if (info == 25)
    len = 2;
  else if (info == 26)
   len = 4;
  else if (info == 27)
   len = 8;
  else if (info == 31)
  {
    lua_pushnumber(L,HUGE_VAL);
    lua_pushinteger(L,pos + 2);
    return 4;
  }
  else
    return luaL_error(L,"invalid data");
  
  /*---------------------
  ; Sanity checking
  ;--------------------*/
  
  if (pos + len + 1 > packlen)
    return luaL_error(L,"no more input");
  
  /*----------------------------------------------
  ; Read len bytes of a network-byte-order value.
  ;-----------------------------------------------*/
  
  for (value = 0 , i = 0 ; i < len ; i++)
    value = (value << 8) | (unsigned long long)((unsigned char)packet[++pos]);
  
  /*----------------------------------------------------------------------
  ; The 0xE0 type encodes actual floating point values.  If we've just read
  ; in one of these, convert to a double.
  ;-----------------------------------------------------------------------*/
  
  if ((type == 0xE0) && (len > 1))
  {
    double__u d;
    float__u  f;
    dnf__s    cv;
    
    if (len == 2)
    {
      dnf_fromhalf(&cv,value);
      dnf_todouble(&d.d,cv);
    }
    else if (len == 4)
    {
      f.i = value;
      dnf_fromsingle(&cv,f.f);
      dnf_todouble(&d.d,cv);
    }
    else if (len == 8)
      d.i = value;
    
    lua_pushnumber(L,d.d);
    lua_pushinteger(L,pos + 2);
    return 4;
  }
  
# if LUA_VERSION_NUM < 503  
    lua_pushnumber(L,value);
# else
    lua_pushinteger(L,value);
# endif
  
  lua_pushinteger(L,pos + 2);
  return 4;
}

/**************************************************************************/

static const luaL_Reg cbor_c_reg[] =
{
  { "encode"	, cbor_clua_encode	} ,
  { "decode"	, cbor_clua_decode	} ,
  { NULL	, NULL			}
};

int luaopen_org_conman_cbor_c(lua_State *L)
{
#if LUA_VERSION_NUM == 501
  luaL_register(L,"org.conman.cbor_c",cbor_c_reg);
#else
  luaL_newlib(L,cbor_c_reg);
#endif
  
  lua_pushliteral(L,VERSION);
  lua_setfield(L,-2,"_VERSION");
  
  return 1;
}

/**************************************************************************/
