<!DOCTYPE html>
<%
  # Get hostname without protocol (i.e. "localhost")
  set host [lindex [split [ns_conn location] "/"] 2]
  set host [ns_set iget [ns_conn headers] host]
  set wsConfigPath "ns/server/[ns_info server]/module/websocket/shell"
  set shConfigPath "ns/server/[ns_info server]/module/nsshell"

  # Get WebSocket Protocol (i.e. "ws")
  set proto [ns_set iget [ns_conn headers] x-forwarded-proto [ns_conn protocol]]
  set wsProtocol [expr {$proto eq "http" ? "ws" : "wss"}]

  # Get Shell URL from module (i.e. "nsshell")
  set shellURL [ns_config $wsConfigPath urls]
  set heartBeat [ns_config $shConfigPath kernel_heartbeat 4]

  # Generate Base URL (i.e. "localhost/shell")
  set baseURL [string trimright $host/$shellURL]

  # Generate WebSocket URL (i.e. ws://localhost/shell/connect)
  set wsUri $wsProtocol://$baseURL/connect

  # Generate kernelId
  # Combine uuid with connection id and encrypt with sha-1
  set kernelID [ns_sha1 "[ns_uuid] [ns_conn id]"]

  # Remember ns_conn settings from the start of this shell
  # in a nsv variable for this kernel.
  foreach subcommand {
      acceptedcompression auth authpassword authuser
      contentfile contentlength contentsentlength driver files flags form
      headers host id isconnected location method outputheaders peeraddr
      peerport pool port protocol query partialtimes request server sock
      start timeout url urlc urlv version zipaccepted
  } {
       nsv_set shell_conn $kernelID,$subcommand [ns_conn $subcommand]
  }

  #
  # Check, if we are connected via the WebSocket interface or via XHR
  #
  if {${shellURL} ne "" && [string match ${shellURL}* [ns_conn url]]} {
    ns_log notice "nsshell uses WebSocket interface"

    #
    # Flag WebSocket usage by setting xhrURL empty.
    #
    set xhrURL ""

    # If kernelID is specified on URL, change kernelID to the one
    # specified in the URL
    if {"kernel" in [ns_conn urlv]} {
      set kernelID [string trim [lindex [ns_conn urlv] end]]
      # KernelID cannot empty
      if {$kernelID eq ""} {
        ns_returnredirect $shellURL
      }
     } else {
      # If kernel is not specified on URL, redirect with the generated kernelId
      ns_returnredirect $shellURL/kernel/$kernelID
     }

  } else {
    ns_log notice "nsshell uses XHR interface"

    #
    # Flag XHR usage by setting wsUri empty.
    #
    set wsUri ""
    set xhrURL [ns_conn url]

    # If kernel is specified on URL, change kernelId to the URL one
    set query_kernelID [ns_queryget kernelID ""]
    if {$query_kernelID eq ""} {
      ns_returnredirect "[ns_conn url]?kernelID=$kernelID"
    } else {
      set kernelID $query_kernelID
    }
  }
  set jqt 2.6.3  ;# previous release
  set jqt 2.7.0  ;# completions broken (autocompletion works now via completion Promise)
  set jqt 2.28.1 ;# completions broken, OK
  set jqt 2.29.1 ;# completions broken, OK
  set jqt 2.29.2 ;# DUPL (duplicated prompt, change between 2.29.1 and 2.29.2)
  set jqt 2.29.3 ;# DUPL
  set jqt 2.29.4 ;# DUPL
  set jqt 2.30.2 ;# DUPL

  set jqt 2.6.3

 %>
<html>

<head>
  <title>NaviServer shell</title>
  <meta http-equiv="Content-Type" content="text/html;charset=utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <link href="https://cdnjs.cloudflare.com/ajax/libs/bootstrap/5.3.3/css/bootstrap.min.css" crossorigin="anonymous" rel="stylesheet">
  <link href="https://cdnjs.cloudflare.com/ajax/libs/jquery.terminal/<%=$jqt%>/css/jquery.terminal.min.css"
  rel="stylesheet"/>
  <script src="https://cdnjs.cloudflare.com/ajax/libs/jquery/3.7.1/jquery.min.js"></script>
  <script src="https://cdnjs.cloudflare.com/ajax/libs/popper.js/2.11.8/umd/popper.min.js" crossorigin="anonymous"></script>
  <script src="https://cdnjs.cloudflare.com/ajax/libs/bootstrap/5.3.3/js/bootstrap.min.js" crossorigin="anonymous"></script>
  <script src="https://cdnjs.cloudflare.com/ajax/libs/jquery.terminal/<%=$jqt%>/js/jquery.terminal.min.js"></script>

  <!-- PRISMJS syntax highlighter -->
  <link href="https://cdnjs.cloudflare.com/ajax/libs/prism/1.29.0/themes/prism-tomorrow.min.css" rel="stylesheet" />
  <script src="https://cdnjs.cloudflare.com/ajax/libs/prism/1.29.0/prism.min.js"></script>
  <script src="https://cdnjs.cloudflare.com/ajax/libs/prism/1.29.0/components/prism-tcl.min.js"></script>
  <script src="https://unpkg.com/jquery.terminal@<%=$jqt%>/js/prism.js"></script>
  <!-- <script src="https://unpkg.com/jquery.terminal@<%=$jqt%>/js/unix_formatting.js"></script> -->

  <style>
    #nsshell-autocomplete {
      list-style: none;
      margin: 0;
      padding: 0;
      float: left;
      position: absolute;
      top: 14px;
      left: 0;
      color: #888888;
      cursor: grabbing;
    }
    #nsshell-autocomplete a:hover {
      background-color:#cccccc;
    }
    .cmd, .terminal {
       cursor: default;
    }
  </style>
</head>

<%
  set script ""
  foreach lib {shared private} {
    set fn [ns_library $lib nsshell]/nsshell.js
    if {[file readable $fn]} {
      set F [open $fn]; set script [read $F]; close $F
    }
  }
  set script
  %>

<body role="document" class="bg-black h-100 w-100">

  <div id="nsshell" class="w-100 h-100"></div>
  <script language="javascript" type="text/javascript">
    var wsUri     = '<%= $wsUri %>'       ; // WebSocket URL
    var kernelID  = '<%= $kernelID %>'    ; // Kernel Id
    <%= $script %>

    nsshell.heartBeat = parseFloat('<%= $heartBeat %>') * 1000;
    if (wsUri == '') {
        nsshell.xhrURL = '<%= $xhrURL %>';
        nsshell.createXHRInterface();
    } else {
        nsshell.createWebSocketInterface();
    }

    $(document).ready(function () {
        nsshell.init()
    });
  </script>
</body>

</html>
