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

#ifndef I_C49BBFEF_CB06_5427_B636_83754812AC51
#define I_C49BBFEF_CB06_5427_B636_83754812AC51

#include <stdbool.h>

typedef struct
{
  bool               inf;
  bool               nan;
  bool               sign;
  int                exp;
  unsigned long long frac;
} dnf__s;

extern int dnf_fromhalf  (dnf__s *const,const unsigned short int);
extern int dnf_fromsingle(dnf__s *const,const float);
extern int dnf_fromdouble(dnf__s *const,const double);

extern int dnf_tohalf    (unsigned short int *const,const dnf__s);
extern int dnf_tosingle  (float              *const,const dnf__s);
extern int dnf_todouble  (double             *const,const dnf__s);

#endif
