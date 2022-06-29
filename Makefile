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

UNAME   := $(shell uname)
VERSION := $(shell git describe --tag)

ifeq ($(VERSION),)
  VERSION=1.3.5
endif

# ===================================================

CC      = gcc -std=c99 -Wall -Wextra -pedantic
CFLAGS  = -g -fPIC

ifeq ($(UNAME),Linux)
  LDFLAGS = -g -shared
endif

ifeq ($(UNAME),Darwin)
  LDFLAGS = -g -bundle -undefined dynamic_lookup -all_load
endif

INSTALL         = /usr/bin/install
INSTALL_PROGRAM = $(INSTALL)
INSTALL_DATA    = $(INSTALL) -m 644

prefix      ?= /usr/local
libdir      ?= $(prefix)/lib
datarootdir ?= $(prefix)/share
dataroot    ?= $(datarootdir)

override CFLAGS += -DVERSION='"$(VERSION)"'

# ===================================================

LUA         ?= lua
LUA_VERSION := $(shell $(LUA) -e "io.stdout:write(_VERSION:match '^Lua (.*)','\n')")
LIBDIR      ?= $(libdir)/lua/$(LUA_VERSION)
LUADIR      ?= $(dataroot)/lua/$(LUA_VERSION)

ifneq ($(LUA_INCDIR),)
  override CFLAGS += -I$(LUA_INCDIR)
endif

# ===================================================

%.so :
	$(CC) $(LDFLAGS) -o $@ $^ $(LDLIBS)

.PHONY:	install uninstall clean check

cbor_c.so : cbor_c.o dnf.o
cbor_c.o  : dnf.h
dnf.o     : dnf.h

# ===================================================

install: cbor_c.so
	$(INSTALL) -d $(DESTDIR)$(LIBDIR)/org/conman
	$(INSTALL) -d $(DESTDIR)$(LUADIR)/org/conman
	$(INSTALL_PROGRAM) cbor_c.so    $(DESTDIR)$(LIBDIR)/org/conman/cbor_c.so
	$(INSTALL_DATA)    cbor.lua     $(DESTDIR)$(LUADIR)/org/conman/cbor.lua
	$(INSTALL_DATA)    cbor_s.lua   $(DESTDIR)$(LUADIR)/org/conman/cbor_s.lua
	$(INSTALL_DATA)    cbormisc.lua $(DESTDIR)$(LUADIR)/org/conman/cbormisc.lua

uninstall:
	$(RM) $(DESTDIR)$(LIBDIR)/org/conman/cbor_c.so
	$(RM) $(DESTDIR)$(LUADIR)/org/conman/cbor.lua
	$(RM) $(DESTDIR)$(LUADIR)/org/conman/cbor_s.lua
	$(RM) $(DESTDIR)$(LUADIR)/org/conman/cbormisc.lua

check:
	luacheck cbor.lua test.lua cbor_s.lua test_s.lua cbormisc.lua

clean:
	$(RM) *~ *.so *.o
