#!/bin/bash
#
# update-view.sh - Periodically write the file that view.html.erb reads
# (ood-view.json) into a running AP's condor dir, until killed. Intended to
# be run in the background alongside start.sh.

set -uo pipefail

INTERVAL=15

usage() {
    cat <<EOF2
Usage: $(basename "${BASH_SOURCE[0]}") --condor-dir <path>

Every ${INTERVAL}s, write <path>/ood-view.json with the number of EPs
currently attached to the AP, the AP's running/held/idle/completed job counts, and
the time of the update.

Options:
  --condor-dir <path>   The AP's condor install dir.
  --help                Print this help message and exit.
EOF2
}

CONDOR_DIR=""

while [ $# -gt 0 ]; do
    case "$1" in
        --help)
            usage
            exit 0
            ;;
        --condor-dir)
            if [ $# -lt 2 ]; then
                echo "error: --condor-dir requires a path argument" >&2
                usage >&2
                exit 1
            fi
            CONDOR_DIR="$2"
            shift 2
            ;;
        *)
            echo "error: unknown argument: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

if [ -z "$CONDOR_DIR" ]; then
    echo "error: --condor-dir is required" >&2
    usage >&2
    exit 1
fi

VIEW_FILE="$CONDOR_DIR/ood-view.json"

# shellcheck disable=SC1091
. "$CONDOR_DIR/condor.sh"
export _condor_SEC_CLIENT_AUTHENTICATION_METHODS=IDTOKENS

while sleep "$INTERVAL"; do
    # Count distinct startd names (<slot>@<EP name>).
    if ! EPS="$($CONDOR_DIR/bin/condor_status -pool localhost:9618?sock=ap_collector -startd -af Name 2>/dev/null)"; then
        continue
    fi
    NUM_EPS="$(printf '%s\n' "$EPS" | sed '/^$/d' | sort -u | wc -l)"

    # Count the AP's jobs by JobStatus: 1 = idle, 2 = running, 5 = held.
    if ! JOBS="$(condor_q -af JobStatus 2>/dev/null)"; then
        continue
    fi
    IDLE="$(printf '%s\n' "$JOBS" | grep -c '^1$')"
    RUNNING="$(printf '%s\n' "$JOBS" | grep -c '^2$')"
    HELD="$(printf '%s\n' "$JOBS" | grep -c '^5$')"

    # Completed jobs have left the queue; count them from the history (4 = completed).
    if ! HISTORY="$(condor_history -af JobStatus 2>/dev/null)"; then
        continue
    fi
    COMPLETED="$(printf '%s\n' "$HISTORY" | grep -c '^4$')"

    printf '{"num_eps": %s, "running": %s, "held": %s, "idle": %s, "completed": %s, "updated": "%s"}\n' \
        "$NUM_EPS" "$RUNNING" "$HELD" "$IDLE" "$COMPLETED" "$(date '+%F %T')" > "$VIEW_FILE.tmp" \
        && mv "$VIEW_FILE.tmp" "$VIEW_FILE"
done
