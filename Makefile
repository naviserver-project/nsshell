#
# Support for multiple NaviServer installations on a single host
#
ifndef NAVISERVER
    NAVISERVER  = /usr/local/ns
endif

#
# Name of the modules
#
MODNAME = nsshell

#
# List of components to be installed in the Tcl module section
#
TCL =	nsshell.adp \
	shell.tcl \
	init.tcl \
	snapshot.tcl \
	nsshell.js \
	README.md

#
# Get the common Makefile rules
#
include  $(NAVISERVER)/include/Makefile.module

