Interactive Shell for NaviServer
=========================
Release 0.1a
-----------

    h11728213@s.wu.ac.at
    neumann@wu-wien.ac.at

This is a NaviServer module that implements an interactive shell for NaviServer. The websocket module (https://bitbucket.org/naviserver/websocket) is required for using this module. The implementation is based on miniterm, which provided by Gustaf Neumann.

The interactive shell consists of these features:

* Web-based interactive shell
* Supports TCL, NX (http://next-scripting.org/), and Naviserver (https://wiki.tcl-lang.org/page/NaviServer) commands
* Command completion and syntax highlighting
* Supports snapshot (provided by Gustaf Neumann)
* Supports multi-users

***

Configuration:
--------------

In order to configure an interactive shell module, add the following lines to the config file of NaviServer.

    ns_section "ns/server/${server}/module/websocket/shell" {
        ns_param    urls                /shell
        ns_param    kernel_heartbeat    3
        ns_param    kernel_timeout      10
    }

The configuration consists of these parameters:

* urls: url of shell's application
* shell_heartbeat: kernel heartbeat interval (in seconds)
* shell_timeout: kernel timeout interval (in seconds)

Installation:
-------------

Copy all tcl/adp files to "/tcl/websocket" folder

Usage:
------

Go to shell's url ("/shell" by default).

Authors:
--------

    Santiphap Watcharasukchit h11728213@s.wu.ac.at
    Gustaf Neumann neumann@wu-wien.ac.at