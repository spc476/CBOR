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

#include <stdint.h>
#include <errno.h>

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

/**************************************************************************/

static int cbor5lua_packf(lua_State *L)
{
  double__u      d;
  float__u       s;
  unsigned short h;
  dnf__s         cv;
  char           result[9];
  size_t         len;

  d.d = luaL_checknumber(L,1);  
  dnf_fromdouble(&cv,d.d);
  if (dnf_tohalf(&h,cv) == 0)
  {
    result[0] = (char)0xF9;
    result[1] = h >> 8;
    result[2] = h &  256;
    len       = 3;
  }
  else if (dnf_tosingle(&s.f,cv) == 0)
  {
    result[0] = (char)0xFA;
    result[1] = (s.i >> 24);
    result[2] = (s.i >> 16) & 255;
    result[3] = (s.i >>  8) & 255;
    result[4] = (s.i >>  0) & 255;
    len       = 5;
  }
  else
  {
    result[0] = (char)0xFB;
    result[1] = (d.i >> 56);
    result[2] = (d.i >> 48) & 255;
    result[3] = (d.i >> 40) & 255;
    result[4] = (d.i >> 32) & 255;
    result[5] = (d.i >> 24) & 255;
    result[6] = (d.i >> 16) & 255;
    result[7] = (d.i >>  8) & 255;
    result[8] = (d.i >>  0) & 255;
    len       = 9;
  }
  
  lua_pushlstring(L,result,len);
  return 1;
}

/**************************************************************************/
  
static int cbor5lua_unpackf(lua_State *L)
{
  size_t      ts;
  const char *t = luaL_checklstring(L,1,&ts);
  dnf__s      v;
  double      result;
  int         rc;
  
  if (ts == 2)
  {
    unsigned short s = (t[0] << 8) | t[1];
    dnf_fromhalf(&v,s);
  }
  else if (ts == 4)
  {
    float__u f;
    
    f.i = ((uint32_t)t[0] << 24)
        | ((uint32_t)t[1] << 16)
        | ((uint32_t)t[2] <<  8)
        | ((uint32_t)t[3] <<  0)
        ;
    dnf_fromsingle(&v,f.f);
  }
  else if (ts == 8)
  {
    double__u d;
    
    d.i = ((uint64_t)t[0] << 56)
        | ((uint64_t)t[1] << 48)
        | ((uint64_t)t[2] << 40)
        | ((uint64_t)t[3] << 32)
        | ((uint64_t)t[4] << 24)
        | ((uint64_t)t[5] << 16)
        | ((uint64_t)t[6] <<  8)
        | ((uint64_t)t[7] <<  0)
        ;
   dnf_fromdouble(&v,d.d);
  }
  else
  {
    lua_pushnil(L);
    lua_pushinteger(L,EDOM);
    return 2;
  }
  
  rc = dnf_todouble(&result,v);
  if (rc == 0)
    lua_pushnumber(L,result);
  else
    lua_pushnil(L);
  lua_pushinteger(L,rc);
  return 2;
}

/**************************************************************************/

#if LUA_VERSION_NUM < 503

static int cbor5lua_packi(lua_State *L)
{
  int        type = luaL_checkinteger(L,1);
  lua_Number n    = luaL_checknumber(L,2);
  char       result[9];
  size_t     len;
  
  if (n < 24.0)
  {
    result[0] = type | (int)n;
    len       = 1;
  }
  else if (n < 256.0)
  {
    result[0] = type | 24;
    result[1] = n;
    len       = 2;
  }
  else if (n < 65536.0)
  {
    unsigned int i = n;
    result[0] = type | 25;
    result[1] = (i >> 16);
    result[2] = (i >>  0) & 255;
    len       = 3;
  }
  else if (n < 4294967296.0)
  {
    unsigned long i = n;
    result[0] = type | 26;
    result[1] = (i >> 24);
    result[2] = (i >> 16) & 255;
    result[3] = (i >>  8) & 255;
    result[4] = (i >>  0) & 255;
    len       = 5;
  }
  else if (n < 9007199254740992.0) // 2^53---maximum integer value
  {
    unsigned long long i = n;
    result[0] = type | 27;
    result[1] = (i >> 56);
    result[2] = (i >> 48) & 255;
    result[3] = (i >> 40) & 255;
    result[4] = (i >> 32) & 255;
    result[5] = (i >> 24) & 255;
    result[6] = (i >> 16) & 255;
    result[7] = (i >>  8) & 255;
    result[8] = (i >>  0) & 255;
    len       = 9;
  }
  else
    return luaL_error(L,"Can't encode integers larger than 9007199254740992");
  
  lua_pushlstring(L,result,len);  
  return 1;
}

#else

static int cbor5lua_packi(lua_State *L)
{
  int          type = luaL_checkinteger(L,1);
  lua_Unsigned n    = luaL_checkinteger(L,2);
  char         result[10];
  
  if (n < 24uLL)
  {
    result[0] = type | n;
    result[1] = '\0';
  }
  else if (n < 256uLL)
  {
    result[0] = type | 24;
    result[1] = n;
    result[2] = '\0';
  }
  else if (n < 65536uLL)
  {
    result[0] = type | 25;
    result[1] = (i >> 16);
    result[2] = (i >>  0) & 255;
    result[3] = '\0';
  }
  else if (n < 4294967296uLL)
  {
    result[0] = type | 26;
    result[1] = (i >> 24);
    result[2] = (i >> 16) & 255;
    result[3] = (i >>  8) & 255;
    result[4] = (i >>  0) & 255;
    result[5] = '\0';
  }
  else
  {
    result[0] = type | 27;
    result[1] = (i >> 56);
    result[2] = (i >> 48) & 255;
    result[3] = (i >> 40) & 255;
    result[4] = (i >> 32) & 255;
    result[5] = (i >> 24) & 255;
    result[6] = (i >> 16) & 255;
    result[7] = (i >>  8) & 255;
    result[8] = (i >>  0) & 255;
    result[9] = '\0';
  }
  
  lua_pushstring(L,result);
  return 1;
}

#endif

/**************************************************************************/

static int cbor5lua_unpacki(lua_State *L)
{
  size_t              ts;
  const char         *t = luaL_checklstring(L,1,&ts);
  unsigned long long  i;
  
  if (ts == 1)
    i = (unsigned long long)t[0];
  else if (ts == 2)
    i = ((unsigned long long)t[0] << 16)
      | ((unsigned long long)t[1])
      ;
  else if (ts == 4)
    i = ((unsigned long long)t[0] << 24)
      | ((unsigned long long)t[1] << 16)
      | ((unsigned long long)t[2] <<  8)
      | ((unsigned long long)t[3] <<  0)
      ;
  else
    i = ((unsigned long long)t[0] << 56)
      | ((unsigned long long)t[1] << 48)
      | ((unsigned long long)t[2] << 40)
      | ((unsigned long long)t[3] << 32)
      | ((unsigned long long)t[4] << 24)
      | ((unsigned long long)t[5] << 16)
      | ((unsigned long long)t[6] <<  8)
      | ((unsigned long long)t[7] <<  0)
      ;
  
#if LUA_VERSION_NUM == 503
  lua_pushinteger(L,i);
#else
  lua_pushnumber(L,i);
#endif
  return 1;
}

/**************************************************************************/

static luaL_Reg cbor5_reg[] =
{
  { "packf"	, cbor5lua_packf	} ,
  { "unpackf"	, cbor5lua_unpackf	} ,
  { "packi"	, cbor5lua_packi	} ,
  { "unpacki"	, cbor5lua_unpacki	} ,
  { NULL	, NULL			}
};

int luaopen_cbor5(lua_State *L)
{
#if LUA_VERSION_NUM == 501
  luaL_register(L,"cbor5",cbor5_reg);
#else
  luaL_newlib(L,cbor5_reg);
#endif

  return 1;
}

/**************************************************************************/
