#!/bin/bash
#
# check-port.sh - Make sure port 9618 is available to this node's AP and, if
# it is not, requeue this Slurm job onto a different node. Only one AP (from
# any user) can listen on 9618 per node, and the firewall rules out other
# ports. See notes.md's "Port Collisions".
#
# Exits 0 if the port is available, 75 once the job has been requeued (the
# caller should stop), or 1 on error (e.g. not running under Slurm, or out of
# retries).

set -uo pipefail

PORT=9618
MAX_REQUEUES="${AP_MAX_REQUEUES:-5}"
EX_REQUEUED=75

usage() {
    cat <<EOF2
Usage: $(basename "${BASH_SOURCE[0]}") [--started-by <master pid>]

Without arguments, check that nothing is listening on port ${PORT} on this
node, and requeue this Slurm job onto a different node if something is.

Options:
  --started-by <pid>   Instead, verify that the AP just started by the
                       condor_master with this pid bound port ${PORT}. If
                       another process holds it, kill that condor_master and
                       requeue. Use this after starting the AP to catch APs
                       that raced for the port.
  --help               Print this help message and exit.

Environment:
  AP_MAX_REQUEUES      Give up after this many requeues (default: 5).
EOF2
}

# Print the listeners on the port, one per line.
listeners() {
    ss -H -ltnp "sport = :$PORT" 2>/dev/null
}

# Requeue this job with this node excluded, then exit.
requeue_elsewhere() {
    echo "==> $1"
    if [ -z "${SLURM_JOB_ID:-}" ]; then
        echo "error: not running under Slurm; cannot requeue" >&2
        exit 1
    fi

    local restarts="${SLURM_RESTART_COUNT:-0}"
    if [ "$restarts" -ge "$MAX_REQUEUES" ]; then
        echo "error: already requeued $restarts times; giving up" >&2
        exit 1
    fi

    local node="${SLURMD_NODENAME:-$(hostname -s)}"
    local excluded
    excluded="$(scontrol show job "$SLURM_JOB_ID" -o | sed -n 's/.*ExcNodeList=\([^ ]*\).*/\1/p')"
    [ "$excluded" = "(null)" ] && excluded=""
    excluded="${excluded:+$excluded,}$node"

    # Slurm signals this job once it is requeued; keep going until we have
    # excluded this node and released the job.
    trap '' TERM HUP

    echo "==> Requeuing job $SLURM_JOB_ID, excluding node(s) $excluded"
    # Hold the job while editing it: ExcNodeList can only be changed while pending.
    if ! scontrol requeuehold "$SLURM_JOB_ID"; then
        echo "error: scontrol requeuehold failed (is requeue enabled?)" >&2
        exit 1
    fi
    if ! scontrol update JobId="$SLURM_JOB_ID" ExcNodeList="$excluded"; then
        echo "WARNING: could not exclude $excluded; the job may land here again" >&2
    fi
    scontrol release "$SLURM_JOB_ID"
    exit "$EX_REQUEUED"
}

MASTER_PID=""

while [ $# -gt 0 ]; do
    case "$1" in
        --help)
            usage
            exit 0
            ;;
        --started-by)
            if [ $# -lt 2 ]; then
                echo "error: --started-by requires a pid argument" >&2
                usage >&2
                exit 1
            fi
            MASTER_PID="$2"
            shift 2
            ;;
        *)
            echo "error: unknown argument: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

if ! command -v ss >/dev/null 2>&1; then
    echo "WARNING: ss not found; cannot check port $PORT"
    exit 0
fi

if [ -z "$MASTER_PID" ]; then
    if [ -n "$(listeners)" ]; then
        requeue_elsewhere "Port $PORT is already in use on $(hostname -s)"
    fi
    echo "==> Port $PORT is free on $(hostname -s)"
    exit 0
fi

# Wait for the AP's shared port daemon (a child of its condor_master) to
# listen on the port.
FOREIGN=0
for _ in $(seq 1 15); do
    OUT="$(listeners)"
    if [ -n "$OUT" ]; then
        for pid in $(echo "$OUT" | grep -o 'pid=[0-9]*' | cut -d= -f2); do
            if [ "$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')" = "$MASTER_PID" ]; then
                echo "==> AP is listening on port $PORT"
                exit 0
            fi
        done
        FOREIGN=1
    fi
    sleep 1
done

if [ "$FOREIGN" -eq 1 ]; then
    kill "$MASTER_PID" 2>/dev/null
    requeue_elsewhere "Port $PORT is held by another process, not this AP"
fi
echo "WARNING: could not confirm that the AP is listening on port $PORT"
exit 0
