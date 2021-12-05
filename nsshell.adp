<!DOCTYPE html>
<%
  # Get hostname without protocol (i.e. "localhost")
  set host [lindex [split [ns_conn location] "/"] 2]
  set wsConfigPath "ns/server/[ns_info server]/module/websocket/shell"
  set shConfigPath "ns/server/[ns_info server]/module/nsshell"

  # Get WebSocket Protocol (i.e. "ws")
  set wsProtocol [expr {[ns_conn protocol] eq "http" ? "ws" : "wss"}]

  # Get Shell URL from module (i.e. "nsshell")
  set shellURL [ns_config $wsConfigPath urls]
  set heartBeat [ns_config $shConfigPath kernel_heartbeat 4]

  # Generate Base URL (i.e. "localhost/shell")
  set baseURL [string trimright $host/$shellURL]

  # Generate WebSocket URL (i.e. ws://localhost/shell/connect)
  set wsUri $wsProtocol://$baseURL/connect

  # Generate kernelId
  # Combine uuid with connection id and encrpyt with sha-1
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

    # If kernelID is specified on URL, change kernelId to the one
    # specified in the URL
    if {"kernel" in [ns_conn urlv]} {
      set kernelID [string trim [lindex [ns_conn urlv] end]]
      # KernelID cannot empty
      if {$kernelID eq ""} {
	ns_returnredirect [ns_conn location]/$shellURL
      }
     } else {
      # If kernel isn't specified on URL, redirect with the generated kernelId
      ns_returnredirect [ns_conn location]/$shellURL/kernel/$kernelID
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
 %>
<html>

<head>
  <title>NaviServer shell</title>
  <meta http-equiv="Content-Type" content="text/html;charset=utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <link rel="stylesheet" href="https://stackpath.bootstrapcdn.com/bootstrap/4.3.1/css/bootstrap.min.css" crossorigin="anonymous">
  <link href="https://cdnjs.cloudflare.com/ajax/libs/jquery.terminal/2.6.3/css/jquery.terminal.min.css" rel="stylesheet" />
  <script src="https://code.jquery.com/jquery-3.3.1.min.js"></script>
  <script src="https://cdnjs.cloudflare.com/ajax/libs/popper.js/1.14.7/umd/popper.min.js" crossorigin="anonymous"></script>
  <script src="https://stackpath.bootstrapcdn.com/bootstrap/4.3.1/js/bootstrap.min.js" crossorigin="anonymous"></script>
  <script src="https://cdnjs.cloudflare.com/ajax/libs/jquery.terminal/2.6.3/js/jquery.terminal.min.js"></script>
  
  <!-- PRISMJS syntax highlighter -->
  <link href="https://unpkg.com/prismjs@1.23.0/themes/prism-tomorrow.css" rel="stylesheet" />
  <script src="https://unpkg.com/prismjs@1.23.0/prism.js"></script>
  <script src="https://unpkg.com/prismjs@1.23.0/components/prism-tcl.js"></script>
  <script src="https://unpkg.com/jquery.terminal@2.22.0/js/prism.js"></script>
  
  <style>
    #autocomplete {
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
    #autocomplete a:hover {
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
