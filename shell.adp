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
  <link href="https://cdnjs.cloudflare.com/ajax/libs/jquery.terminal/2.4.1/css/jquery.terminal.min.css"
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
      color: #555555;
    }
  </style>
</head>

<body role="document" class="bg-black h-100 w-100">

  <div id="ns_term" class="w-100 h-100"></div>
  <script language="javascript" type="text/javascript">
    var wsUri = '<%= $wsUri %>'; // Websocket Url
    var kernelID = '<%= $kernelID %>'; // Kernel Id
    var kernelName = "user-" + kernelID.substring(0, 5).toLowerCase(); // Username based on KernelId
    var websocket = 0; // Websocket object
    var myterm = null; // Shell object
    var autocomplete_options = null; // Current autocomplete options
    var wrapper = null; // Wrapper part of the terminal, used for showing autocomplete options
    var keywords = []; // Command keywords
    var original_keywords = Prism.languages.tcl.keyword; // TCL keywords

    // Function: init()
    // Description: initialize when document ready
    function init() {
      initializeTerminal(); // Initialize terminal
      startWebSocket(); // Initialize Websocket
    }

    // Initialize terminal
    function initializeTerminal() {
      // Initialize terminal div
      jQuery(function ($, undefined) {
        // Handle when command sent
        $('#ns_term').terminal(function (command, term) {
          // Update terminal object
          myterm = term;
          // Get kernel ID
          var kernel = kernelID;
          if (kernel === undefined) {
            kernel = '';
          }
          // Set command via websocket
          command = command.trimLeft();
          if (command !== '') {
            websocket.send(JSON.stringify(['eval', command, kernel]));
          }
        }, {
          // Greeting message
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
            // If Tab, autocomplete
            if (e.key == "Tab") {
              // Check if all options are start with :: or not
              var is_all_semicolon = autocomplete_options != null & autocomplete_options.length > 0;
              for(var i = 0 ; i < autocomplete_options.length ; i++){
                if(!autocomplete_options[i].startsWith("::") && !autocomplete_options[i].startsWith("[::")){
                  is_all_semicolon = false;
                  break;
                }
              }
              // Add :: to current command if necessary
              if(is_all_semicolon){
                // Get last commands
                var commands = myterm.get_command().split(" ");
                var last_command = commands[commands.length - 1];
                // Add :: if necessary
                if(!last_command.startsWith("::")){
                  if(last_command.startsWith("["))
                    last_command = "[::" + last_command.slice(1);
                  else
                    last_command = "::" + last_command;
                }
                // Update commands
                commands[commands.length - 1] = last_command;
                myterm.set_command(commands.join(" "));
              }
              // Auto complete
              myterm.complete(autocomplete_options);
              return false;
            }
          },
          onCommandChange: function (command, term) {
            // Show autocomplete options when command change
            // Trim whitespace
            command = command.trimLeft();
            // If command is blank, not run autocomplete & hide current option
            if (command.trim() != "")
              // Get autocomplete options via websocket, look at function update_autocomplete()
              websocket.send(JSON.stringify(['autocomplete', command, kernelID]));
            else
              update_autocomplete("");
          }
        });
        // Syntax Highlight
        $.terminal.defaults.formatters.push(function (string) {
          // After execute, command will start with "$ "
          // Therefore, extract the prefix
          var prefix = "";
          if (string.split(" ")[0] == "$") {
            prefix = "$ ";
            var s = string.split(" ");
            s.shift();
            string = s.join(" ");
          }
          // Highlight command
          return prefix + $.terminal.prism("tcl", $.terminal.escape_brackets(string));
        });
      });
    }

    function startWebSocket() {
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

    // Show message when websocket is connected and also start sending heartbeat
    function onOpen(evt) {
      myterm.echo('[[;lightgreen;]Kernel "' + kernelName + '" is connected.]');
      heartbeat();
    }

    // Show message when websocket is disconnected and also restart websocket again
    function onClose(evt) {
      myterm.echo('[[;red;]Kernel "' + kernelName + '" is disconnected.]');
      startWebSocket();
    }

    // Eval received message and scroll to bottom
    function onMessage(evt) {
      if (evt.data == "") return;
      var result = window.eval(evt.data.split("\n").join("\\n"));
      $('html, body').scrollTop($(document).height());
    }

    // Unused
    function onError(evt) {}

    // Unused
    function doSend(message) {
      websocket.send(message);
    }

    // Unused
    function checkSubmit(e) {
      if (e && e.keyCode == 13) {
        doSend($('#msg').val());
      }
    }

    // Unused
    function clearOutput() {
      myterm.clear();
    }

    // Update autocomplete options
    function update_autocomplete(text) {
      if (myterm == null) return;
      // Update options array
      autocomplete_options = text.split(" ");
      // First element is type of options. So, extract it
      var type = autocomplete_options.shift();
      // Add commands to keywords for syntax highlighting
      if (type == "commands") {
        keywords = keywords.concat(autocomplete_options).filter(unique);
        updateKeywords();
      }
      // Add '[' if necessary, for autocomplete
      if (myterm.get_command().trim().split(" ").pop().charAt(0) == '[') {
        for (var i = 0; i < autocomplete_options.length; i++)
          autocomplete_options[i] = "[" + autocomplete_options[i];
      }
      // If there is any option, show options
      if (autocomplete_options.length > 0 &&
        myterm.get_command().trim().split(" ").pop() != autocomplete_options.join(" ") &&
        myterm.get_command().trim() != "") {
        $("#autocomplete").html(autocomplete_options.join(" "));
      } else {
        $("#autocomplete").html("");
      }
    }

    // Update keywords, for syntax highlighting
    function updateKeywords() {
      // Get source from origin Tcl keywords
      var new_source = original_keywords.pattern.source;
      // Append new keywords
      var index = new_source.indexOf("vwait");
      new_source = new_source.substring(0, index) + keywords.join("|") + "|" + new_source.substring(index);
      // Extend PrismJS for syntax highlighting
      Prism.languages.tcl = Prism.languages.extend('tcl', {
        'keyword': {
          lookbehind: true,
          pattern: new RegExp(new_source, "m")
        }
      });
    }

    // For making keywords array becomes unique
    function unique(value, index, self) {
      return self.indexOf(value) === index;
    }

    // Sending heartbeat to server
    function heartbeat() {
      websocket.send(JSON.stringify(['heartbeat', kernelID]));
      // Send heartbeat every 3s
      setTimeout(function () {
        heartbeat();
      }, parseFloat("<%= [ns_config ns/server/[ns_info server]/module/websocket/shell kernel_heartbeat 3] %>")*1000);
    }

    $(document).ready(function () {
      init()
    });
  </script>
</body>

</html>
