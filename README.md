Interactive Shell for NaviServer
=========================
Release 0.1a
------------

    h11728213@s.wu.ac.at
    neumann@wu-wien.ac.at

This is a NaviServer module that implements an interactive shell for
NaviServer. The websocket module
(https://bitbucket.org/naviserver/websocket) is required for using
this module. The implementation is based on miniterm developed by Gustaf Neumann.

The interactive shell supports the following features:

* Web-based interactive shell
* Supports Tcl, NX (http://next-scripting.org/),
  and NaviServer (https://wiki.tcl-lang.org/page/NaviServer) commands
* Command completion
* Syntax highlighting
* Supports snapshot (provided by Gustaf Neumann)
* Supports multi-users

Current shortcomings:

* no procs can be defined (required in snapshots)
* limited connection relevant information
* single line commands (no handling of multi-line commands, unbalanced
  braces, etc.)


***

Configuration:
--------------

In order to configure an interactive shell module, add the following
lines to the config file of NaviServer (assuming the variable $server
is properly set to the server to be configured.

    #
    # nsshell configuration (per-server module)
    #
    ns_section "ns/server/${server}/modules" {
        ns_param    websocket tcl
        ns_param    nsshell   tcl
    }
    
    ns_section "ns/server/${server}/module/websocket/shell" {
        ns_param    urls                /nsshell
        ns_param    kernel_heartbeat    3
        ns_param    kernel_timeout      10
    }

The first block makes sure that the modules "websocket" and "nsshell"
are loaded. The second block defines the following parameters:

* urls: url of shell's application
* shell_heartbeat: kernel heartbeat interval (in seconds)
* shell_timeout: kernel timeout interval (in seconds)



Installation:
-------------

    cd SOMEPATH/nsshell
    sudo make install

Usage:
------

Navigate to the configured browser URL ("/nsshell" by default).

Authors:
--------

    Santiphap Watcharasukchit h11728213@s.wu.ac.at
    Gustaf Neumann neumann@wu-wien.ac.at
