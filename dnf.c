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

#include <stddef.h>
#include <stdint.h>
#include <errno.h>
#include <assert.h>

#include "dnf.h"

typedef union
{
  float    f;
  uint32_t i;
} float__u;

typedef union
{
  double   d;
  uint64_t i; 
} double__u;

/**************************************************************************/

static void dnfi_normalize(dnf__s *const pv)
{
  assert(pv != NULL);
  
  for (
        size_t i = 0 ; 
        (i < 64) && ((pv->frac & 0x8000000000000000uLL) == 0uLL) ; 
        i++
      )  
  {
    pv->frac *= 2;
    pv->exp--;
  }
}

/**************************************************************************/

int dnf_fromhalf(dnf__s *const pv,const unsigned short int h)
{
  assert(pv != NULL);
  
  pv->inf  = false;
  pv->nan  = false;
  pv->sign =  h >> 15;
  pv->exp  = (h >> 10) & 0x1F;
  pv->frac = (unsigned long long)(h & 0x3FFu) << 53;
  
  if (pv->exp == 0x1F)
  {
    pv->inf = pv->frac == 0;
    pv->nan = !pv->inf;
    pv->exp = 0;
  }
  else if (pv->exp == 0)
  {
    if (pv->frac != 0uLL)
    {
      pv->exp = -14;
      dnfi_normalize(pv);
    }
  }
  else
  {
    pv->exp   = pv->exp - 15;
    pv->frac |= 0x8000000000000000uLL;
  }
  return 0;
}

/**************************************************************************/

int dnf_fromsingle(dnf__s *const pv,const float f)
{
  float__u x = { .f = f };
  
  assert(pv != NULL);
  
  pv->inf  = false;
  pv->nan  = false;
  pv->sign =  x.i >> 31;
  pv->exp  = (x.i >> 23) & 0xFFuL;
  pv->frac = (unsigned long long)(x.i & 0x007FFFFFuL) << 41;
  
  if (pv->exp == 0xFF)
  {
    pv->inf = pv->frac == 0;
    pv->nan = !pv->inf;
    pv->exp = 0;
  }
  else if (pv->exp == 0)
  {
    if (pv->frac != 0uLL)
    {
      pv->exp = - 126;
      dnfi_normalize(pv);
    }
  }
  else
  {
    pv->exp   = pv->exp - 127;
    pv->frac |= 0x8000000000000000uLL;
  }
  
  return 0;
}

/**************************************************************************/

int dnf_fromdouble(dnf__s *const pv,const double d)
{
  double__u x = { .d = d };
  
  assert(pv != NULL);
  
  pv->inf  = false;
  pv->nan  = false;
  pv->sign =  x.i >> 63;
  pv->exp  = (x.i >> 52) & 0x7FFuLL;
  pv->frac = (unsigned long long)(x.i & 0x000FFFFFFFFFFFFFuLL) << 11;
  
  if (pv->exp == 0x7FFuLL)
  {
    pv->inf = pv->frac == 0;
    pv->nan = !pv->inf;
    pv->exp = 0;
  }
  else if (pv->exp == 0)
  {
    if (pv->frac != 0uLL)
    {
      pv->exp = -1022;
      dnfi_normalize(pv);
    }
  }
  else
  {
    pv->exp   = pv->exp - 1023;
    pv->frac |= 0x8000000000000000uLL;
  }
  
  return 0;
}

/**************************************************************************/

int dnf_tohalf(unsigned short int *const ph,const dnf__s v)
{
  assert(ph != NULL);
  
  if (v.inf)
  {
    assert(v.frac == 0uLL);
    assert(v.exp  == 0);
    assert(!v.nan);
    
    *ph = v.sign ? 0xFC00 : 0x7C00;
    return 0;
  }
  
  if (v.nan)
  {
    assert(v.exp == 0);
    assert(!v.inf);
    
    if ((v.frac & 0x003FFFFFFFFFFFFFuLL) != 0uLL)
      return ERANGE;
    
    *ph  = v.sign ? 0xFC00 : 0x7C00;
    *ph |= (unsigned short)((v.frac >> 52) & 0x03FFuLL);
    return 0;
  }
  
  if ((v.exp < -14) || (v.exp > 15))
    return ERANGE;
  if ((v.frac & 0x003FFFFFFFFFFFFFuLL) != 0uLL)
    return ERANGE;
  
  if ((v.exp == -14) && (v.frac < 0x8000000000000000uLL))
    *ph = (unsigned short)((v.frac >> 52) & 0x03FFuLL);
  else
  {
    if ((v.exp == 0) && (v.frac == 0))
      *ph = 0;
    else
    {
      *ph  = (unsigned short)((v.exp + 15) & 0x1F) << 10;
      *ph |= (unsigned short)(v.frac >> 53) & 0x03FFuLL;
    }
  }
  
  *ph |= v.sign ? 0x8000 : 0x0000;
  return 0;
}

/**************************************************************************/

int dnf_tosingle(float *const pf,const dnf__s v)
{
  float__u f;
  
  assert(pf != NULL);
  
  if (v.inf)
  {
    assert(v.frac == 0uLL);
    assert(v.exp  == 0);
    assert(!v.nan);
    
    f.i = v.sign ? 0xFF800000uL : 0x7F800000uL;
    *pf = f.f;
    return 0;
  }
  
  if (v.nan)
  {
    assert(v.exp == 0);
    assert(!v.inf);
    
    if ((v.frac & 0x000003FFFFFFFFFFuLL) != 0uLL)
      return ERANGE;
    
    f.i  = v.sign ? 0xFF800000uL : 0x7F800000uL;
    f.i |= (uint32_t)((v.frac >> 40) & 0x007FFFFFuL);
    *pf = f.f;
    return 0;
  }
  
  if ((v.exp < -126) || (v.exp > 127))
    return ERANGE;
  if ((v.frac & 0x000001FFFFFFFFFFuLL) != 0uLL)
    return ERANGE;
  
  if ((v.exp == -126) && (v.frac < 0x8000000000000000uLL))
    f.i = (uint32_t)(v.frac >> 42) &  0x007FFFFFuL;
  else
  {
    if ((v.exp == 0) && (v.frac == 0))
      f.i = 0;
    else
    {
      f.i  = (uint32_t)((v.exp + 127) & 0xFFuL) << 23;
      f.i |= (uint32_t)(v.frac >> 41) & 0x007FFFFFuL;
    }
  }
  
  f.i |= v.sign ? 0x80000000uL : 0x00000000uL;
  *pf  = f.f;
  return 0;
}

/**************************************************************************/

int dnf_todouble(double *const pd,const dnf__s v)
{
  double__u d;
  
  assert(pd != NULL);
  
  if (v.inf)
  {
    assert(v.frac == 0uLL);
    assert(v.exp  == 0);
    assert(!v.nan);
    
    d.i = v.sign ? 0xFFF0000000000000uLL : 0x7FF0000000000000uLL;
    *pd = d.d;
    return 0;
  }
  
  if (v.nan)
  {
    assert(v.exp == 0);
    assert(!v.inf);
    
    if ((v.frac & 0x0000000000000FFFuLL) != 0uLL)
      return ERANGE;
    
    d.i  = v.sign ? 0xFFF0000000000000uLL : 0x7FF0000000000000uLL;
    d.i |= (uint64_t)((v.frac >> 12) & 0x000FFFFFFFFFFFFFuLL);
    *pd  = d.d;
    return 0;
  }
    
  if ((v.exp < -1022) || (v.exp > 1023))
    return ERANGE;
  if ((v.frac & 0x00000000000007FFuLL) != 0uLL)
    return ERANGE;
  
  if ((v.exp == -1022) && (v.frac < 0x8000000000000000uLL))
    d.i = (uint64_t)(v.frac >> 12) & 0x000FFFFFFFFFFFFFuLL;
  else
  {
    if ((v.exp == 0) && (v.frac == 0))
      d.i = 0;
    else
    {
      d.i  = (uint64_t)((v.exp + 1023) & 0x7FFuLL) << 52;
      d.i |= (uint64_t)(v.frac >> 11) & 0x000FFFFFFFFFFFFFuLL;
    }
  }
  
  d.i |= v.sign ? 0x8000000000000000uLL : 0x0000000000000000uLL;
  *pd  = d.d;
  return 0;
}

/**************************************************************************/
