#
# Initialize the nsshell Tcl module and register the URL if specified.
#

set url [ns_config ns/server/[ns_info server]/module/nsshell url ""]
if {$url ne ""} {
    ns_register_adp GET $url [ns_library shared nsshell]/nsshell.adp
    ns_log notice "nsshell: XHR shell registered under url $url"

    ns_register_proc -noinherit POST $url {
	#ns_log notice "nsshell POST [ns_conn content]"
	set reply [::nsshell::handle_input {} [ns_conn content]]
	#ns_log notice "nsshell POST: <[ns_conn content]>\n-> $reply"
	ns_return 200 "application/json; charset=utf-8" $reply
    }
}


#
# Get configured WebSocket urls
#
set webSocketURLs [ns_config ns/server/[ns_info server]/module/websocket/shell urls]

if {$webSocketURLs eq ""} {
    ns_log notice "WebSocket: no nsshell configured ([info script])"
} else {

    #
    # Register WebSocket shell under every configured url
    #
    foreach url $webSocketURLs {
        ns_log notice "WebSocket: nsshell available under $url"
        ns_register_adp -noinherit GET $url [ns_library shared nsshell]/nsshell.adp
        # Santiphap: For using shell with specific kernelId
        ns_register_adp GET $url/kernel/ [ns_library shared nsshell]/nsshell.adp
        ns_register_proc -noinherit GET $url/connect ::nsshell::connect
    }
}
