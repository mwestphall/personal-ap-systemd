#!/bin/bash
# STARTD_CRON job: read the AP's Machine/Name from its schedd address file,
# refresh ANNEX_PILOT_COLLECTOR/ANNEX_PILOT_SCHEDD_NAME, and SIGHUP
# condor_master (our great-grandparent process) to reconfig. See notes.md's
# "AP Address Polling".
ADDR_FILE="$1"
MACHINE="$(grep -m1 '^Machine' "$ADDR_FILE" | sed -E 's/^Machine[[:space:]]*=[[:space:]]*"([^"]*)".*/\1/')"
if [ -z "$MACHINE" ]; then
    echo "ERROR: Could not find a Machine attribute in $ADDR_FILE" >&2
    exit 1
fi

NAME="$(grep -m1 '^Name' "$ADDR_FILE" | sed -E 's/^Name[[:space:]]*=[[:space:]]*"([^"]*)".*/\1/')"
if [ -z "$NAME" ]; then
    echo "ERROR: Could not find a Name attribute in $ADDR_FILE" >&2
    exit 1
fi

CONFIG_DIR="$(condor_config_val LOCAL_CONFIG_DIR)"
if ! printf 'ANNEX_PILOT_COLLECTOR = %s:9618?sock=ap_collector\nANNEX_PILOT_SCHEDD_NAME = %s\n' "$MACHINE" "$NAME" > "${CONFIG_DIR}/21-annex-pilot-updates"; then
    echo "ERROR: Failed to write ${CONFIG_DIR}/21-annex-pilot-updates" >&2
    exit 1
fi

pid=$$
master_pid=""
for _ in $(seq 1 10); do
    pid="$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')"
    [ -z "$pid" ] && break
    if ps -o comm= -p "$pid" 2>/dev/null | grep -q '^condor_master$'; then
        master_pid="$pid"
        break
    fi
done

if [ -z "$master_pid" ]; then
    echo "ERROR: Could not find condor_master in the process ancestry" >&2
    exit 1
fi

if ! kill -HUP "$master_pid"; then
    echo "ERROR: Failed to send SIGHUP to condor_master (pid $master_pid)" >&2
    exit 1
fi
