var kernelName = "user-" + kernelID.substring(0, 5).toLowerCase(); // Username based on KernelId
var websocket = 0;        // Websocket object
var myterm = null;        // Shell object
var autocomplete_options = null; // Current autocomplete options
//var can_send = 0;         // Status for cond_send
//var cond_send = '';       // Delayed request, depending on can_send
var complete_command = 0; // For checking whether command is complete; currently in complete_command();
var wrapper = null;       // Wrapper part of the terminal, used for showing autocomplete options
var keywords = [];        // Command keywords
var tcl_keywords = Prism.languages.tcl.keyword; // TCL keywords

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
            // Send command via WebSocket
            command = command.trimLeft();
            if (command !== '') {
                //console.log("TRIMMED <" + command +"> " + JSON.stringify(['eval', command, kernelID]));
                websocket.send(JSON.stringify(['eval', command, kernel]));
                //websocket.send(JSON.stringify(['info_complete', command, kernelID]));
                //cond_send = JSON.stringify(['eval', command, kernel]);
            }
        }, {
            // Greeting message
            greetings: function () {
                this.echo('[[;white;]######################################]');
                this.echo('[[;white;]#  Welcome to the NaviServer shell.  #]');
                this.echo('[[;white;]######################################]');
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
                    var autocompletion_colon = autocomplete_options != null & autocomplete_options.length > 0;
                    for (var i = 0 ; i < autocomplete_options.length ; i++){
                        if (!autocomplete_options[i].startsWith("::")
                            && !autocomplete_options[i].startsWith("[::")
                           ) {
                            autocompletion_colon = false;
                            break;
                        }
                    }
                    // Add :: to current command if necessary
                    if(autocompletion_colon){
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
                var lines = command.trim().split(/\r?\n/);
                var lastLine = lines[lines.length -1];
                //
                // Show autocomplete options when command change.  If
                // command is empty, not run autocomplete & hide
                // autocomplete options.
                //
                if (lastLine != "") {
                    //console.log("TRIMMED <" + lastLine  +"> " + JSON.stringify(['autocomplete', lastLine, kernelID]));
                    // Get autocomplete options via websocket, look at function update_autocomplete()
                    websocket.send(JSON.stringify(['autocomplete', lastLine, kernelID]));
                } else {
                    update_autocomplete("");
                }
            },
            keymap: {
                ENTER: function(e, original) {
                    if (command_complete(this.get_command())) {
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
}

//
// These regular expressions are not fine-tuned for Tcl, but they seem to work quite well.
//

var pre_parse_re = /("(?:\\[\S\s]|[^"])*"|\/(?! )[^\/\\]*(?:\\[\S\s][^\/\\]*)*\/[gimy]*(?=\s|\(|\)|$)|;.*)/g;
var tokens_re = /("(?:\\[\S\s]|[^"])*"|\/(?! )[^\/\\]*(?:\\[\S\s][^\/\\]*)*\/[gimy]*(?=\s|\(|\)|$)|\(|\)|'|"(?:\\[\S\s]|[^"])+|(?:\\[\S\s]|[^"])*"|;.*|(?:[-+]?(?:(?:\.[0-9]+|[0-9]+\.[0-9]+)(?:[eE][-+]?[0-9]+)?)|[0-9]+\.)[0-9]|\.|,@|,|`|[^(\s)]+)/gim;

function tokenize(str) {
    var count = 0;
    var offset = 0;
    var tokens = [];
    str.split(pre_parse_re).filter(Boolean).forEach(function(string) {
        if (string.match(pre_parse_re)) {
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
            line.split(tokens_re).filter(Boolean).forEach(function(token) {
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
}

function command_complete(code) {
    var tokens = tokenize(code);
    var count = 0;
    var token;
    var i = tokens.length;
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
    complete_command = (count == 0) && ! hasContinuation;

    //console.log('complete_command => ' + complete_command);
    return complete_command;
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
    //console.log("message: evt.data " + evt.data);
    var result = window.eval(evt.data.split("\n").join("\\n"));
    //if (cond_send != "") {
    //    console.log("cond_send: " + cond_send + " can_send: " + can_send);
    //    if (can_send) {
    //        websocket.send(cond_send);
    //        console.log("==> message sent");
    //   }
    //    cond_send = '';
    //    can_send = 0;
    // }
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
        $("#autocomplete").html("<a ondblclick='selectCommand(this)'>" +
                                autocomplete_options.join("</a> <a ondblclick='selectCommand(this)'>") +
                                "</a>");
    } else {
        $("#autocomplete").html("");
    }
}

// Update command when user select command by double click
function selectCommand(cmd) {
    var commands = myterm.get_command().split(" ");
    commands[commands.length - 1] = cmd.innerHTML;
    myterm.set_command(commands.join(" "));
}

// Update keywords, for syntax highlighting
function updateKeywords() {
    // Get source from origin Tcl keywords
    var new_source = tcl_keywords.pattern.source;

    // GN: Append new keywords. tcl_keywords.pattern.source is a regular
    // expression, where the last term is inside the string. We do
    // here some surgery depending on the assumption, that "vwaid"
    // stays the last command.
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

// Sending heartbeat every heartBeat seconds to server
function heartbeat() {
    websocket.send(JSON.stringify(['heartbeat', kernelID]));
    setTimeout(function () { heartbeat(); }, heartBeat);
}

$(document).ready(function () {
    init()
});

//
// Local variables:
//   mode: JavaScript
//   indent-tabs-mode: nil
// End:
