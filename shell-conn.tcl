set args [ns_queryget args ""]

if {$args ne ""} {
    if {[catch {set result [ns_conn $args]} errorMsg]} {
        ns_return 200 text/html $errorMsg
    } else { 
        ns_return 200 text/html $result
    }
}