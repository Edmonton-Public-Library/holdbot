####################################################
# Makefile for project holdbot 
# Created: Wed Jun 10 11:00:07 MDT 2015
#
#<one line to give the program's name and a brief idea of what it does.>
#    Copyright (C) 2015  Andrew Nisbet
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
# MA 02110-1301, USA.
#
# Written by Andrew Nisbet at Edmonton Public Library
# Rev: 
#      0.0 - Dev. 
####################################################
# Change comment below for appropriate server.
PRODUCTION_SERVER=edpl.sirsidynix.net
TEST_SERVER=edpl-t.library.ualberta.ca
USER=sirsi
REMOTE=~/Unicorn/Bincustom/
LOCAL=~/projects/holdbot/
APP=holdbot.pl
ARGS=-x
.PHONY: put test production
put: test
	scp ${LOCAL}${APP} ${USER}@${TEST_SERVER}:${REMOTE}
	scp ${LOCAL}${APP} ${USER}@${PRODUCTION_SERVER}:${REMOTE}
test:
	perl -c ${APP}
production: test
	scp ${LOCAL}${APP} ${USER}@${PRODUCTION_SERVER}:${REMOTE}

