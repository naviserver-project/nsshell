var nsshell = {
    kernelName: "user-" + kernelID.substring(0, 5).toLowerCase(), // Username based on KernelId
    websocket: 0,           // WebSocket object
    xhrURL: '',             // URL for XHR interface
    myterm: null,           // Shell object
    autocomplete_options: null, // Current autocomplete options
    complete_command: 0,    // For checking whether command is complete; currently in complete_command();
    wrapper: null,          // Wrapper part of the terminal, used for showing autocomplete options
    keywords: [],           // Command keywords
    tclKeywords: Prism.languages.tcl.keyword, // Tcl keywords

    // Function: init()
    // Description: initialize when document ready
    init: function() {
        this.initializeTerminal();      // Initialize terminal
        this.initializeCommunication(); // Initialize communication interface
    },

    // Initialize terminal
    initializeTerminal: function() {
        // Initialize terminal div
        jQuery(function ($, undefined) {
            // Handle when command sent
            $('#nsshell').terminal(function (command, term) {
                // Update terminal object
                nsshell.myterm = term;
                // Get kernel ID
                var kernel = kernelID;
                if (kernel === undefined) {
                    kernel = '';
                }
                // Send command to the server
                command = command.trimLeft();
                if (command !== '') {
                    nsshell.doSend(JSON.stringify(['eval', command, kernel]));
                }
            }, {
                // Greeting message
                greetings: function () {
                    this.echo('[[;white;]######################################]');
                    this.echo('[[;white;]#  Welcome to the NaviServer Shell.  #]');
                    this.echo('[[;white;]######################################]');
                    nsshell.myterm = this;
                    //nsshell.myterm.echo('GREETING DONE');
                    //console.info(nsshell.myterm) ;
                },
                onInit: function (term) {
                    // Get wrapper from terminal
                    var wrapper = term.cmd().find('.cursor').wrap('<span/>').parent().addClass('cmd-wrapper');
                    // Add autocomplete span to wrapper
                    $("<span id='nsshell-autocomplete'></span>").appendTo(wrapper);
                    //console.log("terminal onInit DONE") ;
                    //nsshell.myterm.echo('terminal onInit');
                },
                //name: this.kernelName,
                prompt: "[[;yellow;]" + nsshell.kernelName + "]" + "$ ",
                keydown: function (e) {
                    // If Tab, autocomplete
                    if (e.key == "Tab") {
                        // Check if all options are start with :: or not
                        var autocompletion_colon =
                            nsshell.autocomplete_options != null
                            && nsshell.autocomplete_options.length > 0;
                        for (var i = 0 ; i < nsshell.autocomplete_options.length ; i++){
                            if (!nsshell.autocomplete_options[i].startsWith("::")
                                && !nsshell.autocomplete_options[i].startsWith("[::")
                               ) {
                                autocompletion_colon = false;
                                break;
                            }
                        }
                        // Add :: to current command if necessary
                        if(autocompletion_colon){
                            // Get last commands
                            var commands = nsshell.myterm.get_command().split(" ");
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
                            nsshell.myterm.set_command(commands.join(" "));
                        }
                        // Auto complete
                        nsshell.myterm.complete(nsshell.autocomplete_options);
                        return false;
                    }
                },
                onCommandChange: function (command, term) {
                    var lines = command.split(/\r?\n/);
                    var lastLine = lines[lines.length -1];
                    //
                    // Show autocomplete options when command changes.  If
                    // command is empty, not run autocomplete and hide
                    // autocomplete options.
                    //
                    if (lastLine != "") {
                        //console.log("TRIMMED <" + lastLine  +"> " + JSON.stringify(['autocomplete', lastLine, kernelID]));
                        // Get autocomplete options from backend.
                        // See also: function updateAutocomplete(),
                        nsshell.doSend(JSON.stringify(['autocomplete', lastLine, kernelID]));

                        //nsshell.websocket.addEventListener("open", (ev) => {
                        //    nsshell.doSend(JSON.stringify(['autocomplete', lastLine, kernelID]))
                        //});
                    } else {
                        nsshell.updateAutocomplete("");
                    }
                },
                keymap: {
                    ENTER: function(e, original) {
                        if (nsshell.command_complete(this.get_command())) {
                            original();
                            //console.log("CALL ORIGINAL DONE");
                        } else {
                            this.insert('\n');
                        }
                    }
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
    },

    //
    // These regular expressions are not fine-tuned for Tcl, but they seem to work quite well.
    //

    pre_parse_re: /("(?:\\[\S\s]|[^"])*"|\/(?! )[^\/\\]*(?:\\[\S\s][^\/\\]*)*\/[gimy]*(?=\s|\(|\)|$)|;.*)/g,
    tokens_re: /("(?:\\[\S\s]|[^"])*"|\/(?! )[^\/\\]*(?:\\[\S\s][^\/\\]*)*\/[gimy]*(?=\s|\(|\)|$)|\(|\)|'|"(?:\\[\S\s]|[^"])+|(?:\\[\S\s]|[^"])*"|;.*|(?:[-+]?(?:(?:\.[0-9]+|[0-9]+\.[0-9]+)(?:[eE][-+]?[0-9]+)?)|[0-9]+\.)[0-9]|\.|,@|,|`|[^(\s)]+)/gim,

    tokenize: function(str) {
        var count = 0;
        var offset = 0;
        var tokens = [];
        str.split(this.pre_parse_re).filter(Boolean).forEach(function(string) {
            if (string.match(nsshell.pre_parse_re)) {
                if (!string.match(/^;/)) {
                    var col = (string.split(/\n/), [""]).pop().length;
                    tokens.push({
                        token: string,
                        col,
                        offset: count + offset,
                        line: offset
                    });
                    count += string.length;
                }
                offset += (string.match("\n") || []).length;
                return;
            }
            string.split('\n').filter(Boolean).forEach(function(line, i) {
                var col = 0;
                line.split(nsshell.tokens_re).filter(Boolean).forEach(function(token) {
                    var line = i + offset;
                    var result = {
                        col,
                        line,
                        token,
                        offset: count + line
                    };
                    col += token.length;
                    count += token.length;
                    tokens.push(result);
                });
            });
        });
        return tokens;
    },

    command_complete: function(code) {
        var tokens = this.tokenize(code);
        var count = 0;
        var token;
        var i = tokens.length;
        if (i > 0) {
            while ((token = tokens[--i])) {
                if (token.token === '{') {
                    count++
                } else if (token.token == '}') {
                    count--;
                }
            }
            var hasContinuation = (tokens[tokens.length -1].token === "\\");
            //
            // save "complete_command" in a global variable to avoid
            // potentially other commands in "incomplete" state.
            //
            this.complete_command = (count == 0) && ! hasContinuation;

            //console.log('complete_command => ' + this.complete_command);
        } else {
            this.complete_command = 1; // allow empty command to be sent
        }
        return this.complete_command;
    },

    // Eval received message and scroll to bottom
    onMessage: function(evt) {
        if (evt.data == "") return;
        //console.log("message: evt.data " + evt.data);
        var result = window.eval(evt.data.split("\n").join("\\n"));
        $('html, body').scrollTop($(document).height());
    },

    // Unused
    onError: function(evt) {},

    // Unused
    checkSubmit: function(e) {
        if (e && e.keyCode == 13) {
            doSend($('#msg').val());
        }
    },

    // Unused
    clearOutput: function() {
        this.myterm.clear();
    },

    // Update autocomplete options
    updateAutocomplete: function(text) {
        if (this.myterm == null) return;
        // Update options array
        this.autocomplete_options = text.split(" ");
        // First element is type of options. So, extract it
        var type = this.autocomplete_options.shift();
        // Add commands to keywords for syntax highlighting
        if (type == "commands") {
            this.keywords = this.keywords.concat(this.autocomplete_options).filter(this.unique);
            this.updateKeywords();
        }
        // Add '[' if necessary, for autocomplete
        if (this.myterm.get_command().trim().split(" ").pop().charAt(0) == '[') {
            for (let i = 0; i < this.autocomplete_options.length; i++)
                this.autocomplete_options[i] = "[" + this.autocomplete_options[i];
        }
        let element = document.getElementById("nsshell-autocomplete");

        //console.log('X updateAutocomplete options length ' + this.autocomplete_options.length + ' el ' + element);
        if (!!element) {
            // If there is any option, show options
            if (this.autocomplete_options.length > 0 &&
                this.myterm.get_command().trim().split(" ").pop() != this.autocomplete_options.join(" ") &&
                this.myterm.get_command().trim() != "") {
                element.innerHTML = "<a ondblclick='nsshell.selectCommand(this)'>" +
                    this.autocomplete_options.join("</a> <a onclick='nsshell.selectCommand(this)'>") +
                    "</a>";
            } else {
                element.innerHTML = "";
            }
        } else {
            console.log("Autocompletion element is not found");
        }
    },

    // Update command when user select command by double click
    selectCommand: function(cmd) {
        var commands = this.myterm.get_command().split(" ");
        commands[commands.length - 1] = cmd.innerHTML;
        this.myterm.set_command(commands.join(" "));
    },

    // Update keywords, for syntax highlighting
    updateKeywords: function() {
        // Get source from original Tcl keywords
        var new_source = this.tclKeywords.pattern.source;

        // GN: Append new keywords. tcl_keywords.pattern.source is a regular
        // expression, where the last term is inside the string. We do
        // here some surgery depending on the assumption, that "vwaid"
        // stays the last command.
        var index = new_source.indexOf("vwait");
        new_source = new_source.substring(0, index)
            + this.keywords.join("|")
            + "|"
            + new_source.substring(index);
        // Extend PrismJS for syntax highlighting
        Prism.languages.tcl = Prism.languages.extend('tcl', {
            'keyword': {
                lookbehind: true,
                pattern: new RegExp(new_source, "m")
            }
        });
    },

    // For making keywords array becomes unique
    unique: function(value, index, self) {
        return self.indexOf(value) === index;
    },

    // Sending heartbeat every heartBeat seconds to server
    heartbeat: function() {
        this.doSend(JSON.stringify(['heartbeat', kernelID]));
        setTimeout(function () { nsshell.heartbeat(); }, this.heartBeat);
    },

    //
    // WebSocket specific commands
    //
    createWebSocketInterface: function () {
        console.log("createWebSocketInterface");
        this.initializeCommunication = function() {
            if ("WebSocket" in window) {
                this.websocket = new WebSocket(wsUri);
            } else {
                this.websocket = new MozWebSocket(wsUri);
            }
            this.websocket.onopen = function (evt) {
                nsshell.onOpen(evt)
            };
            this.websocket.onclose = function (evt) {
                nsshell.onClose(evt)
            };
            this.websocket.onmessage = function (evt) {
                nsshell.onMessage(evt)
            };
            this.websocket.onerror = function (evt) {
                nsshell.onError(evt)
            };
        };
        this.messageQueue = [];
        // Show message when websocket is connected and also start sending heartbeat
        this.onOpen = function(evt) {
            console.log("WebSocket opened.");
            while (this.messageQueue.length > 0) {
                const msg = this.messageQueue.shift();
                this.websocket.send(msg);
            }
            this.myterm.echo('[[;lightgreen;]Kernel "' + this.kernelName + '" is connected.]');
            this.heartbeat();
        };


        // Show message when websocket is disconnected and also restart websocket again
        this.onClose = function(evt) {
            this.myterm.echo('[[;red;]Kernel "' + this.kernelName + '" is disconnected.]');
            //this.startWebSocket();
        };

        this.doSend = function(message) {
            console.log("doSend readystate " + this.websocket.readyState);
            //this.websocket.send(message);
            if (this.websocket.readyState === 1) {
               this.websocket.send(message);
            } else {
               // Queue the message to be sent when the socket is open
               this.messageQueue.push(message);
               console.log("doSend queued");
             }
        };
    },

    //
    // XHR specific commands
    //
    createXHRInterface: function () {
        console.log("createXHRInterface");

        this.initializeCommunication = function() {
            nsshell.heartbeat();
        };

        // Not needed for XHR interface
        //this.onOpen = function(evt) {};
        //this.onClose = function(evt) {} ;

        this.doSend = function(message) {
            console.log("doSend " + message);
            var xhttp = new XMLHttpRequest();
            xhttp.open("POST", this.xhrURL, true);
            xhttp.setRequestHeader("Content-type", "application/json; charset=utf-8");
            xhttp.onreadystatechange = function() {
                //console.log("doSend readyState " + this.readyState  + " status " + this.status);
                if (this.readyState == 4 && this.status == 200) {
                    var data = xhttp.responseText;
                    if (data == "") return;
                    console.log("XHR message: data " + data);
                    var result = window.eval(data.split("\n").join("\\n"));
                    //nsshell.myterm.echo('XXXXX');
                    //console.log(nsshell.myterm);
                    $('html, body').scrollTop($(document).height());
                }
            };
            xhttp.send(message);
        };
    }



}

//
// Local variables:
//   mode: JavaScript
//   indent-tabs-mode: nil
// End:
