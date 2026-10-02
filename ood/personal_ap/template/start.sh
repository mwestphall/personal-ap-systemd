#!/bin/bash
#
# start.sh - Start a personal HTCondor Access Point (AP) from an existing,
# already-configured condor dir, and run it in the foreground (intended
# for running the AP as a Slurm job). See install.sh, ap.sub.

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

# --- Prepare the default annex ------------------------------------------
# Build the EP tarball for ep/annex-ep.sub at a well-known path (reachable
# via ~/.cache/current-ap), authenticating to the AP with the IDToken above.
# Failures here are logged but non-fatal: the AP keeps running regardless.
ANNEX_NAME="default-annex"
ANNEX_TARBALL="$CONDOR_DIR/annex-$ANNEX_NAME.tar"

export _condor_SEC_CLIENT_AUTHENTICATION_METHODS=IDTOKENS

# ASSUMPTION: an annex "exists in the schedd" if `htcondor annex status`
# reports it (vs. "Found no ... annexes named"). Adjust here if the
# htcondor CLI's behavior differs.
annex_exists_in_schedd() {
    local out
    out="$(htcondor annex status "$ANNEX_NAME" 2>&1)" || return 1
    [[ "$out" != *"Found no"* ]]
}

prepare_annex() {
    echo "==> Waiting for the schedd to accept queries"
    local tries=0
    until condor_q >/dev/null 2>&1; do
        tries=$((tries + 1))
        if [ "$tries" -ge 30 ]; then
            echo "    schedd not reachable after 30s"
            return 1
        fi
        sleep 1
    done

    local verb
    if annex_exists_in_schedd; then
        if [ -s "$ANNEX_TARBALL" ]; then
            echo "==> Annex '$ANNEX_NAME' already exists with tarball at $ANNEX_TARBALL; nothing to do"
            return 0
        fi
        verb=add
    else
        verb=create
    fi

    echo "==> Running 'htcondor annex $verb $ANNEX_NAME'"
    # The CLI writes annex-<name>.tar into its working directory.
    (cd "$CONDOR_DIR" && htcondor annex "$verb" --idle-time 3600 "$ANNEX_NAME") || return 1

    if [ ! -s "$ANNEX_TARBALL" ]; then
        echo "    expected tarball $ANNEX_TARBALL was not produced"
        return 1
    fi
    echo "==> Annex tarball at $ANNEX_TARBALL"
}

if ! prepare_annex; then
    echo "WARNING: could not prepare annex '$ANNEX_NAME'; the AP is still running"
fi

echo "==> To interact with this AP from the login node, source the condor env file at $CONDOR_DIR/condor.sh:"
echo "    '. $CONDOR_DIR/condor.sh'"

wait "$MASTER_PID"
