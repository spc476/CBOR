#########################################################################
#
# Copyright 2016 by Sean Conner.  All Rights Reserved.
#
# This library is free software; you can redistribute it and/or modify it
# under the terms of the GNU Lesser General Public License as published by
# the Free Software Foundation; either version 3 of the License, or (at your
# option) any later version.
#
# This library is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
# or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public
# License for more details.
#
# You should have received a copy of the GNU Lesser General Public License
# along with this library; if not, see <http://www.gnu.org/licenses/>.
#
# Comments, questions and criticisms can be sent to: sean@conman.org
#
########################################################################

.PHONY:	clean check

VERSION = $(shell git describe --tag)

CC      = gcc -std=c99 -Wall -Wextra -pedantic
CFLAGS  = -g
LDFLAGS = -shared -fPIC
LDLIBS  =

override CFLAGS += -shared -fPIC -DVERSION='"$(VERSION)"'

%.so :
	$(CC) $(LDFLAGS) -o $@ $^ $(LDLIBS)

cbor5.so : cbor5.o dnf.o

check:
	luacheck cbor.lua test.lua cbor_s.lua test_s.lua cbormisc.lua

clean:
	$(RM) *~ *.so *.o

cbor5.o : dnf.h
dnf.o   : dnf.h
