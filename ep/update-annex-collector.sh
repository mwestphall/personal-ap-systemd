#!/bin/bash
# Read the AP's Machine attribute from its schedd address file, write
# ANNEX_PILOT_COLLECTOR into a standalone config file pointing at that
# host's AP collector, and SIGHUP condor_master (our great-grandparent
# process) to pick up the change.
ADDR_FILE="$1"
MACHINE="$(grep -m1 '^Machine' "$ADDR_FILE" | sed -E 's/^Machine[[:space:]]*=[[:space:]]*"([^"]*)".*/\1/')"
if [ -n "$MACHINE" ]; then
    CONFIG_DIR="$(condor_config_val LOCAL_CONFIG_DIR)"
    echo "ANNEX_PILOT_COLLECTOR = ${MACHINE}:9618?sock=ap_collector" > "${CONFIG_DIR}/21-annex-pilot-updates"

    pid=$$
    for _ in $(seq 1 10); do
        pid="$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')"
        [ -z "$pid" ] && break
        if ps -o comm= -p "$pid" 2>/dev/null | grep -q '^condor_master$'; then
            kill -HUP "$pid"
            break
        fi
    done
fi
