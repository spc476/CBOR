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
* =======================================================================
*
* There are a lot of "magic numbers" in this file.  This is intentional.  I
* don't expect IEEE-754 formats to go away any time soon, so the numbers
* *are* defined per the spec.  I find it easier to understand, say, the 15
* in dnf_fromhalf()/dnf_tohalf() as being the maximum exponent than to have
* to parse IEEE_754_HALF_MAX_EXP or some silliness like that.  Your milage
* may vary.  You have been warned.
*
* Since the routines are all very similar, comments only appear in the first
* routine of a set (dnf_fromhalf() and dnf_tohalf()).  The magic numbers
* change, but not the algorithm itself.
*
*************************************************************************/

#include <limits.h>
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

/**************************************************************************
* Normalize a subnormal floating point number---rotate the fractional
* portion until the MSBit is set.  As this is done, the exponent is adjust
* accordingly.
***************************************************************************/

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

/**************************************************************************
* Denormalize a number to a subnormal floating point number.  We do this to
* the prescribed limit.
***************************************************************************/

static void dnfi_denormalize(dnf__s *const pv,int maxexp)
{
  while(pv->exp < maxexp)
  {
    pv->frac /= 2;
    pv->exp++;
  }
  
  assert(pv->frac != 0uLL); /* we should have at least one bit left */
}

/**************************************************************************
* Conversion FROM half/single/double
***************************************************************************/

int dnf_fromhalf(dnf__s *const pv,unsigned short int h)
{
  assert(pv != NULL);
  
  /*-------------------------------------------------------
  ; Isolate the sign bit, the exponent and the fraction.
  ;--------------------------------------------------------*/
  
  pv->sign = (h >> 15) != 0;
  pv->exp  = (h >> 10) & 0x1F;
  pv->frac = (unsigned long long)(h & 0x3FFu) << 53;
  
  /*----------------------------------------------------------------------
  ; Maximum exponent encodes +-inf and NaNs.  The only difference between
  ; the two---the fraction is 0 for +-inf, otherwise, it's a NaN.
  ;----------------------------------------------------------------------*/
  
  if (pv->exp == 0x1F)
    pv->exp = INT_MAX;
  
  /*--------------------------------------------------------------------
  ; Exponent of 0 is either +-0 (with a fractional portion of 0) or a sub-
  ; normal (a non-zero fractional portion).  If a subnormal, renornalize the
  ; number (that is, make sure the leading one bit is 1 and adjust the
  ; exponent accordingly).
  ;---------------------------------------------------------------------*/
  
  else if (pv->exp == 0)
  {
    if (pv->frac != 0uLL)
    {
      pv->exp = -14;
      dnfi_normalize(pv);
    }
  }
  
  /*---------------------------------------------------
  ; Otherwise, it's a normal floating point number.
  ;----------------------------------------------------*/
  
  else
  {
    pv->exp   = pv->exp - 15;
    pv->frac |= 0x8000000000000000uLL;
  }
  
  return 0;
}

/**************************************************************************/

int dnf_fromsingle(dnf__s *const pv,float f)
{
  float__u x = { .f = f };
  
  assert(pv != NULL);
  
  pv->sign = (x.i >> 31) != 0;
  pv->exp  = (int)((x.i >> 23) & 0xFFuL);
  pv->frac = (unsigned long long)(x.i & 0x007FFFFFuL) << 40;
  
  if (pv->exp == 0xFF)
    pv->exp = INT_MAX;
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

int dnf_fromdouble(dnf__s *const pv,double d)
{
  double__u x = { .d = d };
  
  assert(pv != NULL);
  
  pv->sign = (x.i >> 63) != 0;
  pv->exp  = (int)((x.i >> 52) & 0x7FFuLL);
  pv->frac = (unsigned long long)(x.i & 0x000FFFFFFFFFFFFFuLL) << 11;
  
  if (pv->exp == 0x7FF)
    pv->exp = INT_MAX;
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

/**************************************************************************
* Conversion TO half/single/double
***************************************************************************/

int dnf_tohalf(unsigned short int *const ph,dnf__s v)
{
  unsigned short h;
  
  assert(ph != NULL);
  
  /*-------------------------------------------------------
  ; Maximum exponent designates either +-inf or a NaN.  
  ;--------------------------------------------------------*/
  
  if (v.exp == INT_MAX)
    h = 0x7C00;
  
  /*-----------------------------------------------------------------------
  ; Normally a half-precision float can only handle exponents down to -14,
  ; but with subnormals, we can go as low as -24.  We check the extreme low
  ; end with the normal high end.  If we exceed either of those, we signal
  ; an error.
  ;------------------------------------------------------------------------*/
  
  else if ((v.exp < -24) || (v.exp > 15))
    return ERANGE;
    
  /*----------------------------------------
  ; Check for 0---this is a special case.
  ;-----------------------------------------*/
  
  else if ((v.exp == 0) && (v.frac == 0))
    h = 0;
  
  /*------------------------------------------------------------------------
  ; We have a subnormal.  Adjust the fraction; the exponent is then set to 0
  ; to indicate a subnormal.
  ;-------------------------------------------------------------------------*/
  
  else if (v.exp < -14)
  {
    dnfi_denormalize(&v,-14);
    h = 0;
  }
  
  /*-----------------------------------
  ; It's a normal exponent.  
  ;------------------------------------*/
  
  else
    h = (unsigned short)((unsigned)((v.exp + 15) & 0x1F) << 10);
  
  /*--------------------------------------------------------------------
  ; Check the precision and indicate an error if we exceed the number of
  ; bits we have for the fractional portion.
  ;---------------------------------------------------------------------*/
  
  if ((v.frac & 0x001FFFFFFFFFFFFFuLL) != 0uLL)
    return EDOM;
  
  h   |= (unsigned short)(v.frac >> 53) & 0x03FFuLL;
  h   |= v.sign ? 0x8000 : 0x0000;
  *ph  = h;
  return 0;  
}

/**************************************************************************/

int dnf_tosingle(float *const pf,dnf__s v)
{
  float__u f;
  
  assert(pf != NULL);
  
  if (v.exp == INT_MAX)
    f.i = (uint32_t)0x7F800000uL;
  else if ((v.exp < -149) || (v.exp > 127))
    return ERANGE;
  else if ((v.exp == 0) && (v.frac == 0))
    f.i = 0;
  else if (v.exp < -126)
  {
    dnfi_denormalize(&v,-126);
    f.i = 0;
  }
  else
    f.i = (uint32_t)((v.exp + 127) & 0xFFuL) << 23;
  
  if ((v.frac & 0x000000FFFFFFFFFFuLL) != 0uLL)
    return EDOM;
  
  f.i |= (uint32_t)(v.frac >> 40) & 0x007FFFFFuL;
  f.i |= v.sign ? 0x80000000uL : 0x00000000uL;
  *pf  = f.f;
  return 0;
}

/**************************************************************************/

int dnf_todouble(double *const pd,dnf__s v)
{
  double__u d;
  
  assert(pd != NULL);
  
  if (v.exp == INT_MAX)
    d.i = 0x7FF0000000000000uLL;
  else if ((v.exp < -1074) || (v.exp > 1023))
    return ERANGE;
  else if ((v.exp == 0) && (v.frac == 0))
    d.i = 0;
  else if (v.exp < -1022)
  {
    dnfi_denormalize(&v,-1022);
    d.i = 0;
  }
  else
    d.i = (uint64_t)((v.exp + 1023) & 0x7FFuLL) << 52;
  
  if ((v.frac & 0x0000000000000FFFuLL) != 0uLL)
    return EDOM;
  
  d.i |= (uint64_t)((v.frac >> 11) & 0x000FFFFFFFFFFFFFuLL);
  d.i |= v.sign ? 0x8000000000000000uLL : 0x0000000000000000uLL;
  *pd  = d.d;
  return 0;
}

/**************************************************************************/
