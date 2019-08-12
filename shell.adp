<!DOCTYPE html>
<%
   # Get hostname without protocol (i.e. "localhost")
   set host [lindex [split [ns_conn location] "/"] 2]
   # Get WebSocket Protocol (i.e. "ws")
   set wsProtocol [expr {[ns_conn protocol] eq "http" ? "ws" : "wss"}]
   # Get Shell url from module (i.e. "shell")
   set shellUrl [string map {"/" ""} [ns_config ns/server/[ns_info server]/module/websocket/shell urls]]

   # Generate Base url (i.e. "localhost/shell")
   set baseUrl [string trimright $host/$shellUrl]
   # Generate WebSocket url (i.e. ws://localhost/shell/connect)
   set wsUri $wsProtocol://$baseUrl/connect

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

   # If kernel is specified on url, change kernelId to the url one 
   if {[lindex [split [string map [list /$shellUrl ""] [ns_conn url]] /] 1] eq "kernel"} {
    set kernelID [string trim [string map [list /$shellUrl/kernel ""] [ns_conn url]] "/"]
    # KernelID cannot empty
    if {[string trim $kernelID] eq ""} {
      ns_returnredirect [ns_conn location]/$shellUrl
    }
   } else {
    # If kernel isn't specified on url, redirect with the generated kernelId
    ns_returnredirect [ns_conn location]/$shellUrl/kernel/$kernelID 
   }
 %>
<html>

<head>
  <title>NaviServer shell</title>
  <meta http-equiv="Content-Type" content="text/html;charset=utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <link rel="stylesheet" href="https://stackpath.bootstrapcdn.com/bootstrap/4.3.1/css/bootstrap.min.css"
    crossorigin="anonymous">
  <link href="https://cdnjs.cloudflare.com/ajax/libs/jquery.terminal/2.6.3/css/jquery.terminal.min.css"
    rel="stylesheet" />
  <link href="https://unpkg.com/prismjs@1.16.0/themes/prism-tomorrow.css" rel="stylesheet" />
  <script src="https://code.jquery.com/jquery-3.3.1.min.js"></script>
  <script src="https://cdnjs.cloudflare.com/ajax/libs/popper.js/1.14.7/umd/popper.min.js" crossorigin="anonymous">
  </script>
  <script src="https://stackpath.bootstrapcdn.com/bootstrap/4.3.1/js/bootstrap.min.js" crossorigin="anonymous"></script>
  <script src="https://cdnjs.cloudflare.com/ajax/libs/jquery.terminal/2.6.3/js/jquery.terminal.min.js"></script>
  <script src="https://unpkg.com/prismjs@1.16.0/prism.js"></script>
  <script src="https://unpkg.com/prismjs@1.16.0/components/prism-tcl.js"></script>
  <script src="https://unpkg.com/jquery.terminal@2.6.3/js/prism.js"></script>
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
    var wsUri     = '<%= $wsUri %>'       ; // WebSocket Url
    var kernelID  = '<%= $kernelID %>'    ; // Kernel Id
    var heartBeat = parseFloat('<%= [ns_config ns/server/[ns_info server]/module/websocket/shell kernel_heartbeat 3] %>') * 1000 ;
    <%= $script %>
  </script>
</body>

</html>
