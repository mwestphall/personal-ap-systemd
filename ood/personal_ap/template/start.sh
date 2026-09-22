#!/bin/bash
#
# start.sh - Start a personal HTCondor Access Point (AP) from an existing,
# already-configured condor dir, and run it in the foreground (intended
# for running the AP as a Slurm job). See install.sh, ap.sub, resume-ap.sub.

set -euo pipefail

usage() {
    cat <<EOF
Usage: $(basename "${BASH_SOURCE[0]}") --condor-dir <path>

Start a personal HTCondor Access Point (AP) from an existing,
already-configured condor dir (see install.sh), and run it in the
foreground.

Options:
  --condor-dir <path>   The AP's condor install dir.
  --help                Print this help message and exit.
EOF
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

if [ ! -d "$CONDOR_DIR" ]; then
    echo "error: condor dir not found at $CONDOR_DIR" >&2
    exit 1
fi

echo "==> Starting AP from $CONDOR_DIR"

echo "==> Updating shell environment with AP install"
# shellcheck disable=SC1091
. "$CONDOR_DIR/condor.sh"

# --- Run the AP (e.g. as a Slurm job) ----------------------------------
# Pin NETWORK_HOSTNAME in the shared config, removing any previous pin
# first so a resumed AP doesn't copy the old instance's hostname.
rm -f "$CONDOR_DIR/local/config.d/13-ap-hostname.conf"
AP_FULL_HOSTNAME="$(condor_config_val FULL_HOSTNAME)"
echo "==> Pinning hostname to $AP_FULL_HOSTNAME via NETWORK_HOSTNAME"
echo "NETWORK_HOSTNAME = $AP_FULL_HOSTNAME" > "$CONDOR_DIR/local/config.d/13-ap-hostname.conf"

echo "==> Starting HTCondor AP"
"$CONDOR_DIR/sbin/condor_master" -f &
MASTER_PID=$!

# --- Enable IDToken Authentication --------------------------------------
# Wait up to 10 seconds for the AP to provision its pool password.
POOL_FILE="$CONDOR_DIR/local/passwords.d/POOL"
WAITED=0
while [ ! -f "$POOL_FILE" ] && [ "$WAITED" -lt 10 ]; do
    sleep 1
    WAITED=$((WAITED + 1))
done

# Issue a sample IDToken with schedd READ/WRITE authorization into the
# AP's tokens.d directory.
echo "==> Generating IDToken for schedd access"
TOKEN_NAME="testing"
IDENTITY="$(whoami)@$(condor_config_val UID_DOMAIN)"
condor_token_create -identity "$IDENTITY" -authz READ -authz WRITE -token "$TOKEN_NAME"
echo "    Generated sample IDToken for $IDENTITY at $CONDOR_DIR/local/tokens.d/$TOKEN_NAME"

echo "==> To interact with this AP from the login node, source the condor env file at $CONDOR_DIR/condor.sh:"
echo "    '. $CONDOR_DIR/condor.sh'"

wait "$MASTER_PID"
