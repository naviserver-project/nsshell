#
# shell.tcl
#
# Santiphap Watcharasukchit, June 2019
# Gustaf Neumann, April 2015 - August 2019
#
package require nsf
package require Thread

namespace eval ::nsshell {

    nsf::proc debug {msg} {
        #ns_log notice "nxshell: $msg"
    }

    #
    # The proc "connect" is called, whenever a new websocket is
    # established.  The terminal name is taken form the URL to allow
    # multiple independent terminal on different urls.
    #
    nsf::proc connect {} {
        set term [ns_conn url]
        set channel [ws::handshake -callback [list ::nsshell::handle_input -ip [ns_conn peeraddr] -term $term]]
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
        debug "handle_input: msg <$msg>"
        if {[catch {set cmdList [json_to_tcl $msg]} errorMsg]} {
            ns_log error "json_to_tcl returned $errorMsg"
            return
        }
        lappend cmdList $channel
        debug "handle_input received <$msg> -> $cmdList"
        set cmd [lindex $cmdList 0]
        if {$cmd in [::nsshell::handler cget -supported]} {
            try {
                ::nsshell::handler {*}$cmdList
            } on error {errorMsg} {
                ns_log warning "handle_input $cmdList returned: $errorMsg"
                dict set info status error
                dict set info result $errorMsg\n$::errorInfo
            } on ok {result} {
                set info $result
            }
            debug "handler returned <$info>"
            set result [string map [list ' \\' \r \\r] [dict get $info result]]
            switch [dict get $info status] {
                ok              {
                    if {$cmd eq "info_complete"} {
                        ns_log notice "RESULT FROM info_complete $info // result $result"
                        set reply "can_send = $result;"
                    } else {
                        set reply "nsshell.myterm.echo('\[\[;#FFFFFF;\][ns_quotehtml $result]\]');"
                    }
                }
                error           {set reply "nsshell.myterm.error('$result');"}
                noreply         {set reply ""}
                autocomplete    {set reply "nsshell.updateAutocomplete('$result');"}
            }
        } else {
            ns_log warning "command <$msg> not handled"
            set reply "nsshell.myterm.error('unhandled request from client');"
        }
        if {$channel ne ""} {
            set r [ws::send $channel [ns_connchan wsencode -opcode text $reply]]
            #set r [ws::send $channel [::ws::build_msg $reply]]
            debug "[list ws::send $channel $reply] returned $r"
        } else {
            return $reply
        }
    }

    #
    # ::nsshell::json_to_tcl
    #
    # Helper function to convert a json object (as produced by the
    # JSON.stringify() function) to a Tcl list. This handles just
    # escaped backslashes and double quotes.

    nsf::proc json_to_tcl {msg} {
        #ns_log notice [list json_to_tcl $msg]
        if {![regexp {^\[.*\]$} $msg]} {
            error "invalid message <$msg>"
        }
        #set msg [string map {"\\\\" "\\"} $msg]

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
                            lappend result [subst -novariables -nocommands $word]
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
                        if {$escaped == 1} {
                            append word "\\"
                        }
                        append word $char
                        set escaped 0
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
        #ns_log notice [list json_to_tcl => $result]

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
            #
            # Execute the provided cmd in the slave thread. If the
            # thread does not exist, create it.
            #

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

        :property {supported:1..n {eval autocomplete heartbeat}}

        :method init {} {
            nsv_array set shell_kernels {}
            nsv_array set shell_conn {}
        }

        :public method "context require" {kernel channel} {
            # Update kernel timestamp as well as latest channel
            nsv_set shell_kernels $kernel [ns_time]
            nsv_set shell_conn $kernel,channel $channel
            if {![nsv_exists shell_conn $kernel,snapshot]} {
                nsv_set -default shell_conn $kernel,snapshot ""
            }
            #ns_log notice "====  REQUIRE nsv_set -default shell_conn $kernel exists?[namespace exists $kernel]"

            if {![namespace exists $kernel]} {
                #
                # Create temporary namespace named "$kernel" for executing
                # command in current thread.
                #
                namespace eval $kernel {
                    # Santiphap: Create substitute "ns_conn", since original "ns_conn" in kernel will return "no connection"
                    proc ns_conn {args} {
                        set kernel [lindex [split [namespace current] ::] end]
                        if {[nsv_exists shell_conn "$kernel,$args"]} {
                            return [nsv_get shell_conn "$kernel,$args"]
                        } else {
                            return -code error "bad option \"$args\": must be acceptedcompression, auth, authpassword, authuser, contentfile, contentlength, contentsentlength, driver, files, flags, form, headers, host, id, isconnected, location, method, outputheaders, peeraddr, peerport, pool, port, protocol, query, partialtimes, request, server, sock, start, timeout, url, urlc, urlv, version, or zipaccepted"
                        }
                    }
                    # Santiphap: Create snapshot object, see shell.tcl
                    ::ws::snapshot::Snapshot create snapshot -namespace [namespace current]
                }
                # Restore snapshot
                #ns_log notice "SNAPSHOT $kernel restore <[nsv_get shell_conn $kernel,snapshot]>"
                namespace eval $kernel [nsv_get shell_conn $kernel,snapshot]
            }
        }

        :public method _eval {arg kernel channel} {
            #
            # Light weight "eval" method for querying the current
            # content of the workspace/snapshot.  This method does
            # NOT update the snapshot, but is intended for
            # e.g. autocompletion and the like.
            #
            :context require $kernel $channel
            #
            # Qualify cmd and reject certain commands (should be
            # configurable).
            #
            set cmd ""
            regexp {^\s*(\S+)\s?} $arg - cmd
            set cmd [namespace which $cmd]

            if {$cmd in {::return ::exit}} {
                set status error
                set result "command rejected: '$arg'"
            } else {
                try {
                    #
                    # Execute command in temporary unique namespace
                    # based on kernelId (nsshell::kernelId)
                    #
                    namespace eval $kernel $arg
                } on ok {result} {
                    set status ok
                } on error {result} {
                    set status error
                }
            }
            return [list status $status result $result]
        }

        :public method eval {arg kernel channel} {
            #
            # Full featured "eval" method that updates the associated
            # snapshot after the command after success.
            #
            ns_log notice "CurrentThreadHandler.eval called with <$arg> [namespace exists $kernel]"
            set result [:_eval $arg $kernel $channel]

            if {[dict get $result status] eq "ok"} {
                nsv_set shell_conn $kernel,snapshot [namespace eval $kernel {snapshot get_delta}]
                #ns_log notice "SNAPSHOT $kernel saved, is now: <[ns_get shell_conn $kernel,snapshot]>"
            }
            #
            # Delete context (temporary namespace) and return result
            #
            namespace delete $kernel
            ns_log notice "CurrentThreadHandler.eval <$arg> returns $result"
            return $result
        }

        :public method info_complete {arg kernel channel} {
            #
            # Check, whether the passed in command in "$arg" is a
            # complete Tcl command.
            #
            ns_log notice "=====info_complete===== arg <$arg>"
            return [list status ok result [info complete $arg]]
        }

        :method completion_elements {arg kernel channel} {
            #
            # completion_elements: call ":eval" and return elements if
            # command was successful
            #
            set result [:_eval $arg $kernel $channel]
            if {[dict get $result status] eq "ok"} {
                return [dict get $result result]
            }
            return ""
        }

        :public method autocomplete {arg kernel channel} {
            #
            # Try to autocomplete the value provided in "$arg".  This
            # method returns a dict with the "status" and a "result"
            # consisting of potential completions.
            #
            ns_log notice "===== Autocomplete ===== arg <$arg>"
            set result {}
            set type ""
            set words [split $arg " "]
            set lastWord [lindex $words end]
            # Santiphap: Variable autocomplete if last word start with $
            if { [string match {$*} $lastWord] } {
                ns_log notice "Autocomplete variable: $arg"
                set type variables
                # Santiphap: Get var prefix without $
                set var_prefix [string range $lastWord 1 end]
                # Santiphap: Get matched variable
                set var_result [:completion_elements "info vars $var_prefix*" $kernel $channel]
                # Santiphap: Get matched namespace
                set namespace_parent [join [lreplace [split $var_prefix :] end-1 end] ::]
                set namespace_pattern [lindex [split $var_prefix :] end]
                set namespace_result [:completion_elements \
                                          "namespace children ${namespace_parent}:: $namespace_pattern*" \
                                          $kernel $channel]
                #
                # Prepend dollar "$" to variable names for the result
                #
                set var_result       [lmap v $var_result {set _ "\$$v"}]
                set namespace_result [lmap v $namespace_result {set _ "\$${v}::"}]
                set result [join [lsort -unique [concat $var_result $namespace_result]]]
            } else {
                # Santiphap: Get last word of the last command
                set sub_arg [string trimleft [lindex [split $arg "\["] end]]
                #ns_log notice "===== arg <$arg> sub_arg <$sub_arg>"
                # Santiphap: Command autocomplete
                set words [split $sub_arg " "]
                if { [llength $words] == 1} {
                    #
                    # A single word was provided, try to autocomplete
                    # it as a command.
                    #
                    set type commands
                    ns_log notice "===== Autocomplete single word command: <$sub_arg>"

                    set providedNs [namespace qualifiers $sub_arg]
                    set checkNs [expr {$providedNs eq "" ? "::" : $providedNs}]

                    lappend cmds \
                        {*}[:completion_elements [list info commands $sub_arg*] $kernel $channel] \
                        {*}[:completion_elements [list namespace children $checkNs $sub_arg*] $kernel $channel]

                    set result [lsort -unique $cmds]

                } elseif { [llength $words] eq 2} {

                    #
                    # Two words
                    #
                    lassign $words main sub

                    if {$main in {set unset}} {
                        set result [:completion_elements "info vars $sub*" $kernel $channel]
                        set type variables
                        #
                        # We could add here as well namespace
                        # completion for namespaced vars.
                        #

                    } else {
                        set type subcommands
                        ns_log notice "Autocomplete subcommand: <$sub_arg>"

                        try {
                            #
                            # Get matched class/object methods. We use
                            # here the nsf primitive "lookupmethods",
                            # since this works for NX and XOTcl.
                            #
                            :completion_elements \
                                [list $main ::nsf::methods::object::info::lookupmethods $sub*] \
                                $kernel $channel
                        } on error {errorMsg} {
                            ns_log notice "lookupmethods failed: $errorMsg"
                            set methods {}
                        } on ok {result} {
                            set methods $result
                        }
                        #
                        # In case, we found no XOTcl/NX methods,
                        # check, if there are Tcl/NaviServer commands
                        # with subcommands. In order to avoid
                        # collateral damage, we do this just for
                        # asserted commands.
                        #
                        if {[llength $methods] == 0} {
                            ns_log notice "NO methods for <$sub*>"
                            if { $main in {

                                array binary chan clock encoding file info
                                namespace package string trace

                                ns_accesslog
                                ns_adp_ctl
                                ns_asynclogfile
                                ns_certctl
                                ns_chan
                                ns_cond
                                ns_conn
                                ns_connchan
                                ns_critsec
                                ns_crypto::eckey
                                ns_crypto::hmac
                                ns_crypto::md
                                ns_db
                                ns_driver
                                ns_env
                                ns_hmac
                                ns_http
                                ns_ictl
                                ns_info
                                ns_ip
                                ns_job
                                ns_logctl
                                ns_md
                                ns_mutex
                                ns_perm
                                ns_proxy
                                ns_rwlock
                                ns_sema
                                ns_server
                                ns_set
                                ns_sls
                                ns_thread
                                ns_time
                                ns_urlspace
                                ns_writer
                                nsv_array
                                nsv_dict

                            }} {
                                try {
                                    $main ""
                                } on error {errMsg} {
                                    if {[regexp {: must be (.*)$} $errMsg . subcmds]} {
                                        regsub -all ", or " $subcmds "" subcmds
                                        set methods [lmap c [split $subcmds ,] {
                                            set m [string trim $c]
                                            if {![string match $sub* $m]} continue
                                            set m
                                        }]
                                    }
                                }
                            }
                        }
                        # Sort & unique
                        #ns_log notice "RESULT for <$sub*> -> [concat $methods]"
                        set result [lsort -unique [concat $methods]]
                    }
                }
            }
            if {[namespace exists $kernel]} {
                #
                # Clean up after the _eval commands
                #
                namespace delete $kernel
            }

            # Santiphap: Return autocomplete option type and list
            return [list status autocomplete result [concat $type $result]]
        }

        # Santiphap: Receiving heartbeat from client
        :public method heartbeat {kernel channel} {
            # Santiphap: Update kernel timestamp
            debug "heartbeat: $kernel"
            nsv_set shell_kernels $kernel [ns_time]
            return [list status noreply result ""]
        }
    }
    # Santiphap: CurrentThreadHandler will be the main handler
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
            #
            # Create or use the named kernel. If the kernel does not
            # exist, create it new by creating an slave interpreter.
            #
            if {$name ni ${:kernels} && $name ne ""} {
                ns_log notice "Kernel thread creates kernel (= interp) '$name'"
                kernels do [list interp create $name]
                # autoload nx, should be generalized
                kernels do [list interp eval $name {
                    package require nx
                }]
                lappend :kernels $name
            }
        }

        :public method dropKernel {name} {
            #
            # Delete a kernel in memory. This method actually deletes
            # the interpreter used for the kernel.
            #
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
            #
            # Evaluate the command provided by "$arg" in the
            # specified kernel.
            #
            debug "[current class] eval <$arg> <$kernel>"
            :useKernel $kernel
            if {$kernel ne ""} {
                set cmd [list interp eval $kernel $arg]
            } else {
                set cmd $arg
            }
            debug "[current class] executes <kernels do $cmd>"
            try {
                set info [list status ok result [kernels do $cmd]]
            } on error {errorMsg} {
                ns_log warning "nsshell: kernel eval returned error <$errorMsg> $::errorInfo"
                set info [list status error result $errorMsg]
            }
            return $info
        }
    }
    # Santiphap: KernelThreadHandler only uses for store snapshot for each kernel
    KernelThreadHandler create threadHandler

    # Santiphap: Clear dead kernels after some timeout
    # - based param "kernel_timeout" in module
    # - default 30s

    ns_schedule_proc [ns_config ns/server/[ns_info server]/module/nsshell kernel_timeout 30] {
        array set kernels [nsv_array get shell_kernels]
        foreach name [array names kernels] {
            # Santiphap: Delete kernel if no heartbeat more than 10s
            if { [ns_time] - $kernels($name) >
                 [ns_config ns/server/[ns_info server]/module/nsshell kernel_timeout 30]
             } {
                catch {::nsshell::kernels do [list interp delete $name]}
                nsv_unset shell_kernels $name
                foreach key [nsv_array names shell_conn $name,*] {
                    nsv_unset shell_conn $key
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
