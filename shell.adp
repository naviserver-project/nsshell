<!DOCTYPE html>
<%
   set host [ns_info hostname]
   set host localhost   
   #set host "192.168.0.131"   
   set wsProtocol [expr {[ns_conn protocol] eq "http" ? "ws" : "wss"}]
   set port [ns_config [ns_driversection] port [ns_conn port]]
   set baseUrl [string trimright $host:$port/[ns_conn url]]
   set wsUri $wsProtocol://$baseUrl/connect
   set kernelID [ns_sha1 naviserver_shell_[ns_conn id]]

   # Set ns_conn global variable for this kernel
   set conn_commands [list acceptedcompression auth authpassword authuser contentfile contentlength contentsentlength driver files flags form headers host id isconnected location method outputheaders peeraddr peerport pool port protocol query partialtimes request server sock start timeout url urlc urlv version zipaccepted]
   foreach command $conn_commands {
      nsv_set shell_conn $kernelID,$command [ns_conn $command]
   }
 %>
<html>

<head>
  <title>mini term</title>
  <meta http-equiv="Content-Type" content="text/html;charset=utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <link rel="stylesheet" href="https://stackpath.bootstrapcdn.com/bootstrap/4.3.1/css/bootstrap.min.css"
    crossorigin="anonymous">
  <link href="https://cdnjs.cloudflare.com/ajax/libs/jquery.terminal/2.4.1/css/jquery.terminal.min.css"
    rel="stylesheet" />
  <script src="https://code.jquery.com/jquery-3.3.1.min.js"></script>
  <script src="https://cdnjs.cloudflare.com/ajax/libs/popper.js/1.14.7/umd/popper.min.js" crossorigin="anonymous">
  </script>
  <script src="https://stackpath.bootstrapcdn.com/bootstrap/4.3.1/js/bootstrap.min.js" crossorigin="anonymous"></script>
  <script src="https://cdnjs.cloudflare.com/ajax/libs/jquery.terminal/2.4.1/js/jquery.terminal.min.js"></script>
  <style>
    #autocomplete {
      list-style: none;
      margin: 0;
      padding: 0;
      float: left;
      position: absolute;
      top: 14px;
      left: 0;
    }
  </style>
</head>

<body role="document" class="bg-black h-100 w-100">

  <div id="term_demo" class="w-100 h-100"></div>
  <script language="javascript" type="text/javascript">
    var wsUri = '<%= $wsUri %>';
    var kernelID = '<%= $kernelID %>';
    var kernelName = "user-" + kernelID.substring(0, 5).toLowerCase();
    var output;
    var state;
    var websocket = 0;
    var myterm = $('#term_demo');
    var autocomplete_options = null;
    var wrapper = null;

    function init() {
      initializeTerminal();
      testWebSocket();
    }

    function initializeTerminal() {
      jQuery(function ($, undefined) {
        $('#term_demo').terminal(function (command, term) {
          myterm = term;
          var kernel = kernelID;
          if (kernel === undefined) {
            kernel = '';
          }
          if (command !== '') {
            websocket.send(JSON.stringify(['eval', command, kernel]));
          } else {
            term.echo('');
          }
        }, {
          greetings: function () {
            this.echo('[[;white;]##################################]');
            this.echo('[[;white;]#  Welcome to naviserver shell.  #]');
            this.echo('[[;white;]##################################]');
            myterm = this;
          },
          onInit: function (term) {
            // Get wrapper from terminal
            wrapper = term.cmd().find('.cursor').wrap('<span/>').parent().addClass('cmd-wrapper');
            // Add autocomplete span to wrapper
            $("<span id='autocomplete'></span>").appendTo(wrapper);
          },
          name: kernelName,
          prompt: "[[;yellow;]" + kernelName + "]" + "$ ",
          keydown: function (e) {
            // Get current command
            var command = myterm.get_command();
            // If Tab, autocomplete
            if (e.key == "Tab") {
              myterm.complete(autocomplete_options);
              command = myterm.get_command();
            }
            // Delete last char if key is backspace
            if (e.key == "Backspace") command = command.substring(0, command.length - 1);
            // Add lastest char in command
            if (e.key.length == 1) command += e.key;
            // Get autocomplete options via websocket, look at function update_autocomplete()
            websocket.send(JSON.stringify(['autocomplete', command, kernelID]));
            // Ignore Tab key
            if (e.key == "Tab") {
              return false;
            }
          }
        });
      });
    }

    function testWebSocket() {
      if ("WebSocket" in window) {
        websocket = new WebSocket(wsUri);
      } else {
        websocket = new MozWebSocket(wsUri);
      }
      websocket.onopen = function (evt) {
        onOpen(evt)
      };
      websocket.onclose = function (evt) {
        onClose(evt)
      };
      websocket.onmessage = function (evt) {
        onMessage(evt)
      };
      websocket.onerror = function (evt) {
        onError(evt)
      };
    }

    function onOpen(evt) {
      myterm.echo('[[;lightgreen;]Kernel "' + kernelName + '" is connected.]');
    }

    function onClose(evt) {
      myterm.echo('[[;red;]Kernel "' + kernelName + '" is disconnected.]');
      testWebSocket();
    }

    function onMessage(evt) {
      if (evt.data == "") return;
      var result = window.eval(evt.data);
      $('html, body').scrollTop($(document).height());
    }

    function onError(evt) {}

    function doSend(message) {
      websocket.send(message);
    }

    function checkSubmit(e) {
      if (e && e.keyCode == 13) {
        doSend($('#msg').val());
      }
    }

    function clearOutput() {
      myterm.clear();
    }

    function update_autocomplete(text) {
      // Update options array
      autocomplete_options = text.split(" ");
      // If there is any option and the only option is not same as current command, show options
      if (autocomplete_options.length > 0 && myterm.get_command() != text) {
        $("#autocomplete").html(text);
      } else {
        $("#autocomplete").html("");
      }
    }

    $(document).ready(function () {
      init()
    });
  </script>
</body>

</html>