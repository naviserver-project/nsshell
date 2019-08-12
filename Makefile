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
# List of components to be installed as the the Tcl module section
#
TCL =	shell.adp \
	shell.tcl \
	snapshot.tcl \
	nsshell.js \
	README.md

#
# Get the common Makefile rules
#
include  $(NAVISERVER)/include/Makefile.module

