Require: websocket

Installation:
1. Copy to tcl/websocket
2. Add module to nsd_config.tcl file

# Santiphap: Shell module
#   urls - url of shell
#   shell_heartbeat - interval how client sending heartbeat (in seconds)
#   shell_timeout - interval how server deleting unused kernel (in seconds)
ns_section "ns/server/default/module/websocket/shell" {
    ns_param    urls            /shell
    ns_param    shell_heartbeat 3
    ns_param    shell_timeout   10
}