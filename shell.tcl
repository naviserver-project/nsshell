#
# shell.tcl 
#
#
# Gustaf Neumann, April 2015
#
package require nsf
package require Thread

#
# Get configured urls
#
set urls [ns_config ns/server/[ns_info server]/module/websocket/shell urls]

if {$urls eq ""} {
    ns_log notice "websocket: no shell configured"
    return
}

#
# Register websocket shell under every configured url
#
foreach url $urls {
    ns_log notice "websocket: shell available under $url"
    ns_register_adp  GET $url [file dirname [info script]]/shell.adp
    # For ns_conn
    # ns_register_tcl  GET $url/conn [file dirname [info script]]/shell-conn.tcl
    ns_register_proc GET $url/connect ::ws::shell::connect
}

namespace eval ws::shell {
    #
    # The proc "connect" is called, whenever a new websocket is
    # established.  The terminal name is taken form the url to allow
    # multiple independent terminal on different urls.
    #
    nsf::proc connect {} {
        set term [ns_conn url]
	    set channel [ws::handshake -callback [list ws::shell::handle_input -ip [ns_conn peeraddr] -term $term]]
	ws::subscribe $channel $term
    }

    #
    # Whenever we receive a message from the terminal, evaluate it by
    # the shell::handler and send back the result to the terminal
    # via a json command. Notice that this makes both the frontend and
    # backend highly programmable which makes the protocol between the
    # webclient and protocol extensible.
    #
    # In this work-in-progress version the terminal object "myterm"
    # hardcoded and should be replaced such that multiple instances of
    # the terminal can be used on one page.
    #
    nsf::proc handle_input {{-ip ""} {-term "terminal"} channel msg} {
        ns_log notice "handle_input: msg <$msg>"
        if {[catch {set cmdList [json_to_tcl $msg]} errorMsg]} {
            ns_log error "json_to_tcl returned $errorMsg"
        }
        lappend cmdList $channel
        ns_log notice "received <$msg> -> $cmdList"
        if {[lindex $cmdList 0] in [::ws::shell::handler cget -supported]} {
            set info [::ws::shell::handler {*}$cmdList]
            ns_log notice "handler returned <$info>"
            set result [string map [list ' \\'] [dict get $info result]]
            switch [dict get $info status] {
                ok              {set reply "myterm.echo('\[\[;#FFFFFF;\]$result\]');"}
                error           {set reply "myterm.error('$result');"}     
                # ok but noreply 
                noreply         {set reply ""}
                # autocomplete
                autocomplete    {set reply "update_autocomplete('$result');"}          
            }
        } else {
            ns_log warning "command <$msg> not handled"
            set reply "myterm.error('unhandled request from client');"
        }
        set r [ws::send $channel [::ws::build_msg $reply]]
        ns_log notice "[list ws::send $channel $reply] returned $r"
        #::ws::multicast $term [::ws::build_msg [::ws::build_msg $reply]]
    }

    #
    # ::ws::shell::json_to_tcl
    #
    # Helper function to convert a json object (as produced by the
    # JSON.stringify() function) to a Tcl list. This handles just
    # escaped backslashes and double quotes.
    
    nsf::proc json_to_tcl {msg} {
        if {![regexp {^\[.*\]$} $msg]} {
            error "invalid message <$msg>"
        }
        set result ""
        set escaped 0
        set state listStart
        foreach char [split $msg ""] {
            #ns_log notice "state $state char $char escaped $escaped"
            switch $state {
                listStart {
                    if {$char ne "\["} {error "unexpected character $char, expected \["}
                    set state wordStart
                }
                wordStart {
                    if {$char eq "\""} {
                        set state doubleQuotedWord
                        set escaped 0
                        set word ""
                    } else {
                        error "expect only doublequoted words"
                    }
                }
                doubleQuotedWord {
                    if {$char eq "\""} {
                        if {$escaped == 0} {
                            lappend result $word
                            set state wordEnd
                        } else {
                            append word $char
                            set escaped 0
                        }
                    } elseif {$char eq "\\"} {
                        if {$escaped == 0} {
                            set escaped 1
                        } else {
                            append word $char
                            set escaped 0
                        }
                    } else {
                        append word $char
                    }
                }
                wordEnd {
                    if {$char eq ","} {
                        set state wordStart
                    } elseif {$char eq "\]"} {
                        set state end
                    } else {
                        error "unexpected character '$char' in state $state"
                    }
                }
                end {
                }
            }
        }
        return $result
    }


    
    #
    # Generic THREAD class, somewhat simplified version of xotcl-core,
    # ported to NX
    #
    nx::Class create THREAD {
        :property cmd:required
        :property recreate:boolean
        :property tid

        :method init {} {
            if {![ns_ictl epoch]} {
                # We are during initialization.
                set :initCmd {
                    package req nx
                }
            }
            append :initCmd {
                ns_thread name SELF
                ::nsf::exithandler set {
                    ns_log notice "[self] exits"
                }
            }
            regsub -all SELF ${:initCmd} [self] :initCmd
            append :initCmd \n\
                [list set ::currentThread [self]] \n\
                ${:cmd}
            set :mutex [thread::mutex create]
            ns_log notice "mutex ${:mutex} created"
            next
        }
        #
        # :public method getInitcmd {} {
        #     return ${:initCmd}
        # }
        # :object method recreate {obj args} {
        #     #
        #     # this method catches recreation of THREADs in worker threads 
        #     # it reinitializes the thread according to the new definition.
        #     #
        #     ns_log notice "recreating [self] $obj, tid [$obj exists tid]"
        #     if {![string match "::*" $obj]} { set obj ::$obj }
        #     $obj configure -recreate true
        #     next
        #     $obj configure -cmd [lindex $args 0]
        #     if {[nsv_exists [self] $obj]} {
        #         set tid [nsv_get [self] $obj]
        #         ::thread::send $tid [$obj getInitcmd]
        #         $obj configure -tid $tid
        #         my log "+++ content of thread $obj ($tid) redefined"
        #     }
        # }

        :public method do {cmd} {
            #ns_log notice "THREAD [self] received <$cmd>"
            if {![nsv_exists [current class] [self]]} {
                #
                # lazy creation of a new slave thread
                #
                thread::mutex lock ${:mutex}
                if {![nsv_exists [current class] [self]]} {
                    set :tid [::thread::create]
                }
                nsv_set [current class] [self] ${:tid}

                set initcmd ${:initCmd}
                ::thread::send ${:tid} $initcmd
                set :tid [nsv_get [current class] [self]]
                thread::mutex unlock ${:mutex}
            } else {
                #
                # slave thread is already up and running
                #
                set :tid [nsv_get [current class] [self]]
            }
            ns_log notice "calling [current class] (${:tid}, [pid]) $cmd"
            thread::send ${:tid} $cmd
        }
    }


    #
    # Class Handler
    #
    # Generic superclass for terminal command handlers. The property
    # "supported" tells the terminal interface, what commands will be
    # handled at the backend of the websocket to provide some
    # protection.
    #
    nx::Class create Handler {
        :property supported:1..n
    }
    
    #
    # Class CurrentThreadHandler
    #
    # The CurrentThreadHandler evals the sent command in the current
    # connection thread. This is e.g. useful for debugging
    # OpenACS. Note that after every command in a connection thread,
    # global variables are deleted. So the behavior is different from
    # a normal Tcl shell.
    #
    nx::Class create CurrentThreadHandler -superclass Handler {
        
        :property {supported:1..n {eval autocomplete}}
        

        :method init {} {
            nsv_array set shell_kernels {}
            nsv_array set shell_conn {}
        }

        :public method eval {arg kernel channel} {

            # Update lastest kernel used
            nsv_set shell_kernels $kernel [list $channel [ns_time]]
            nsv_set shell_conn $kernel,channel $channel

            # Copy object variables from thread into this method
            ns_log notice "[current class] copy variables from thread"
            set reserveName {tcl_version tcl_interactive auto_path errorCode errorInfo auto_index env tcl_pkgPath tcl_patchLevel tcl_platform tcl_library}
            set vars [lindex [threadHandler eval "info vars" $kernel $channel] 3]
            foreach var $vars {
                if {[lsearch ${reserveName} $var] == -1} { 
                    if {[lindex [threadHandler eval "array exists $var" $kernel $channel] 3]} {
                        set cmd "array set $var {[lindex [threadHandler eval "array get $var" $kernel $channel] 3]}"
                        namespace eval $kernel $cmd
                    } else {
                        namespace eval $kernel set $var [lindex [threadHandler eval "set $var" $kernel $channel] 3]
                    }
                }
            }

            # Original
            #if {[catch {
            #    return [list status ok result [namespace eval :: $arg]]
            #} errorMsg]} {
            #    return [list status error result $errorMsg]
            #}

            # Add ns_conn proc to namespace
            namespace eval $kernel {
                proc ns_conn {args} {
                    set kernel [lindex [split [namespace current] ::] 6]
                    if {[nsv_exists shell_conn "$kernel,$args"]} {
                        return [nsv_get shell_conn "$kernel,$args"]
                    } else {
                        return -code error "bad option \"$args\": must be acceptedcompression, auth, authpassword, authuser, contentfile, contentlength, contentsentlength, driver, files, flags, form, headers, host, id, isconnected, location, method, outputheaders, peeraddr, peerport, pool, port, protocol, query, partialtimes, request, server, sock, start, timeout, url, urlc, urlv, version, or zipaccepted"
                    }
                }
            }
            
            # Change "puts ..." to "set {} ..." to make it echo value
            if {[string first puts $arg ] == 0} {
                set arg [string replace $arg 0 3 "set ${kernel}_output"]
            }

            # Execute command in ws::shell::$kernel
            ns_log notice "ws::shell::$kernel evals <$arg>"
            if {[catch {set result [namespace eval $kernel $arg]} errorMsg]} {
                return [list status error result $errorMsg]
            } else {
                # Copy variables back to thread
                ns_log notice "[current class] copy variables back to thread"
                foreach var [namespace eval $kernel info vars] {
                    if {[lsearch ${reserveName} $var] == -1 && $var ne "${kernel}_output"} {
                        if {[namespace eval $kernel array exists $var]} {
                            threadHandler eval "array set $var {[namespace eval $kernel array get $var]}" $kernel $channel
                            namespace eval $kernel array unset $var
                        } else {
                            threadHandler eval "set $var [namespace eval $kernel set {} $var]" $kernel $channel
                            namespace eval $kernel unset $var
                        }
                    } elseif {$var eq "${kernel}_output"} {
                        # Unset temp output
                        namespace eval $kernel unset $var
                    }
                }
                return [list status ok result $result]
            }
        }

        :public method autocomplete {arg kernel channel} {
            ns_log notice "[current class] autocomplete command: $arg"
            set result ""
            # General command autocomplete
            if { [llength [split $arg " "]] eq 1} {
                # Get matched commands list
                set commands [lindex [:eval "info commands $arg*" $kernel $channel] 3]
                # Get matched class list, since some might not appear on info commands 
                set classes [lindex [:eval "nx::Class info instances $arg*" $kernel $channel] 3]
                # Get matched object list, since some might not appear on info commands 
                set objects [lindex [:eval "nx::Object info instances $arg*" $kernel $channel] 3]
                # Sort & unique
                set result [lsort -unique [concat $commands $classes $objects]]
            }
            # Variable autocomplete
            if { [string match "$*" [lindex [split $arg " "] end]] } {
                # Get var prefix without $
                set var_prefix [string range [lindex [split $arg " "] end] 1 end]
                # Eval command and set result
                set result [lindex [:eval "info vars $var_prefix*" $kernel $channel] 3]
            }
            return [list status autocomplete result $result]
        }
    }
    CurrentThreadHandler create handler

    #
    # Class KernelThreadHandler
    #
    # The KernelThreadHandler somewhat mimics Jupyter/ipython notebook
    # "kernels". We create a separate thread that will contain the
    # actual state from all commands of a session. The commands maybe
    # either be executed in
    #
    #  a) the main interpreter of the thread (which contains all the
    #     currently defined infrastructure of the blueprint), or
    #  b) in a named child interpreter (named by the property "kernel").
    #     A named kernels is activated via the method "useKernel"
    #
    nx::Class create KernelThreadHandler -superclass Handler {
        
        :property {supported:1..n {eval dropKernel}}
        
        :property {kernel ""}
        :variable kernels ""

        :method init {} {
            #
            # Create a thread named "kernels" for handling the cmds
            #
            THREAD create kernels -cmd [subst {
                ns_log notice "Kernel thread [self] is running"
            }]
        }

        :public method useKernel {name} {
            if {$name ni ${:kernels} && $name ne ""} {
                ns_log notice "Kernel thread creates kernel (= interp) '$name'"
                kernels do [list interp create $name]
                # autoload nx, should be generalized
                kernels do [list interp eval $name package require nx]
                lappend :kernels $name
            }
        }

        :public method dropKernel {name} {
            if {$name in ${:kernels} && $name ne ""} {
                ns_log notice "dropKernel: drop kernel '$name'"
                #
                # Delete interpreter
                #
                kernels do [list interp delete $name]
                #
                # Remove name from the kernels list
                #
                set posn [lsearch -exact ${:kernels} $name]
                set list [lreplace ${:kernels} $posn $posn]
            } else {
                ns_log notice "dropKernel: No kernel named '$name' defined."
            }
        }
        
        :public method eval {arg kernel channel} {
            ns_log notice "[current class] eval <$arg> <$kernel>"
            :useKernel $kernel
            if {$kernel ne ""} {
                set cmd [list interp eval $kernel $arg]
            } else {
                set cmd $arg
            }
            ns_log notice "[current class] executes <kernels do $cmd>"
            if {[catch {
                set info [list status ok result [kernels do $cmd]]
            } errorMsg]} {
                ns_log notice "we got an error <$errorMsg> $::errorInfo"
                set info [list status error result $errorMsg]
            }
            return $info

        }
    }
    KernelThreadHandler create threadHandler

    # Clear dead kernels every 10 second
    ns_schedule_proc 10 {
        array set kernels [nsv_array get shell_kernels]
        foreach name [array names kernels] {
            set is_alive 0
            foreach conn [ns_connchan list] {
                if { [lindex $conn 0] eq [lindex $kernels($name) 0] } {
                    set is_alive 1
                    break
                }
            }
            if {$is_alive eq 0} {
                ::ws::shell::kernels do [list interp delete $name]
                nsv_unset shell_kernels $name
                foreach key [nsv_array names shell_conn] {
                    if {$name eq [lindex [split $key ,] 0]} {
                        nsv_unset shell_conn $key
                    }
                }
            }
        }
    }
}

#
# Local variables:
#    mode: tcl
#    tcl-indent-level: 4
#    indent-tabs-mode: nil
# End:

