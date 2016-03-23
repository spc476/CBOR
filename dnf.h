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
* DNF---the floating point conversion routines.  These routines allow you to
* safely convert halfs (16b IEEE-754), singles (32b IEEE-754) or doubles
* (64b IEEE-764) values to halfs, singles or doubles.  This is done in two
* steps, a conversion *from* one of the formats, and a conversion *to* one
* of the formats.
*
* 	dnf_fromhalf()
*		Convert from IEEE-754 16b format to internal format used
*		for conversion.
*
*	dnf_fromsingle()
*		Convert from IEEE-754 32b format to internal format used
*		for conversion.
*
*	dnf_fromdouble()
*		Convert from IEEE-754 62b format to internal format used
*		for conversion.
*
*	dnf_tohalf()
*		Convert internal format to IEEE-754 16b format.  
*
*	dnf_tosingle()
*		Convert internal format to IEEE-754 32b format.
*
*	dnf_todouble()
*		Convert internal format to IEEE_754 64b format.
*
* All routines will return an error code:
*
*	0	conversion succeeded
*	EDOM	fraction contains too many bits to safely convert
*	ERANGE	exponent exceeds allowable range of format
*
*************************************************************************/

#ifndef I_C49BBFEF_CB06_5427_B636_83754812AC51
#define I_C49BBFEF_CB06_5427_B636_83754812AC51

#include <stdbool.h>

typedef struct
{
  bool               sign;
  int                exp;
  unsigned long long frac;
} dnf__s;

extern int dnf_fromhalf  (dnf__s *const,unsigned short int);
extern int dnf_fromsingle(dnf__s *const,float);
extern int dnf_fromdouble(dnf__s *const,double);

extern int dnf_tohalf    (unsigned short int *const,dnf__s);
extern int dnf_tosingle  (float              *const,dnf__s);
extern int dnf_todouble  (double             *const,dnf__s);

#endif
