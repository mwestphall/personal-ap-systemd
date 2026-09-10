#!/bin/bash
# Read the AP's Machine and Name attributes from its schedd address file,
# write ANNEX_PILOT_COLLECTOR and ANNEX_PILOT_SCHEDD_NAME into a standalone
# config file to track that host's AP collector and schedd name, and SIGHUP
# condor_master (our great-grandparent process) to pick up the change.
#
# ANNEX_PILOT_SCHEDD_NAME needs refreshing too, not just ANNEX_PILOT_COLLECTOR:
# STARTD_DIRECT_ATTACH_SCHEDD_NAME/_POOL together make the STARTD's direct-attach
# do a collector query for Name == ANNEX_PILOT_SCHEDD_NAME (see
# ResMgr::directAttachToSchedd() and Daemon::getDaemonInfo() - specifying a pool
# forces a collector query by name, bypassing any local address file entirely).
# That value is otherwise a static string baked in once by annex-setup.sh at
# `htcondor annex create` time, so it goes stale as soon as the AP's schedd
# starts advertising a different Name (e.g. after resuming on a new Slurm
# node), and the STARTD's query stops matching anything.
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
