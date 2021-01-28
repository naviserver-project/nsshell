Interactive Shell for NaviServer
================================
Release 0.2b
------------

    สันติภาพ วัชระสุขจิตร (Santiphap Watcharasukchit)
    neumann@wu-wien.ac.at

This is a NaviServer module that implements an interactive shell for
NaviServer. The shell can be used via XMLHttpRequests (XHR) or via
the WebSocket interface, which requires that the websocket module
(https://bitbucket.org/naviserver/websocket) is installed.

The interactive shell supports the following features:

* Web-based interactive shell
* Command completion
* Syntax highlighting
* Support for Tcl, NX, XOTcl (http://next-scripting.org/),
  and NaviServer (https://wiki.tcl-lang.org/page/NaviServer) commands
* Support for snapshots of content of current interpreter (provided by Gustaf Neumann)
* Support for multi-users
* Support for "proc" and "nsf::proc"
* Support for multiline commands


Current shortcomings:

* limited connection-relevant information available
* Tcl complete command determination is just a heuristic
* probably a good idea to factor out "kernel handling"
* use more consistent naming based on nsshell
* no security management

***

Configuration:
--------------

In general, the nsshell module can interface via XHR or via WebSocket
interface with the server.

In order to configure an interactive shell module for XHR mode, add
the following lines to the config file of NaviServer (assuming the
variable $server is properly set to the server to be configured.

    #
    # nsshell configuration (per-server module)
    #
    ns_section "ns/server/${server}/modules" {
        ns_param    nsshell   tcl
    }

    ns_section "ns/server/${server}/module/nsshell" {
        ns_param    url                 /nsshell
        ns_param    kernel_heartbeat    5
        ns_param    kernel_timeout      10
	}

The first block makes sure that the Tcl module "nsshell"
is loaded. The second block defines the following parameters:

* url: url of shell's application
* shell_heartbeat: kernel heartbeat interval (in seconds)
* shell_timeout: kernel timeout interval (in seconds)

In order to configure nsshell via the WebSocket interface,
make sure that the websocket module is loaded and configure then
the URLs, under which nsshell should be available.

    #
    # nsshell configuration (per-server module)
    #
    ns_section "ns/server/${server}/modules" {
        ns_param    websocket tcl
    }

    ns_section "ns/server/${server}/module/websocket/shell" {
        ns_param    urls                /websocket/nsshell
    }



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

Copyright:
----------

    This Source Code Form is subject to the terms of the Mozilla Public
    License, v. 2.0. If a copy of the MPL was not distributed with this
    file, You can obtain one at https://mozilla.org/MPL/2.0/.
