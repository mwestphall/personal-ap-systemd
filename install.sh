#!/bin/bash
#
# install.sh - Install a personal HTCondor Access Point (AP) and run it in
# the foreground as a Slurm job. See ap.sub.
#
# This script performs the "Personal AP Install" steps described in
# README.md. It is expected to be run from within a clone of the
# personal-ap-systemd repository.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

BASE_DIR_DEFAULT="/scratch/$USER"

usage() {
    cat <<EOF
Usage: $(basename "${BASH_SOURCE[0]}") [OPTIONS] <tarball-path>

Install a personal HTCondor Access Point (AP) from the HTCondor tarball
at <tarball-path>, and run it in the foreground (intended for running
the AP as a Slurm job; see ap.sub).

Options:
  --base-dir <path>    Base directory for the AP install, on storage
                       shared with wherever condor tools will be run
                       from (default: ${BASE_DIR_DEFAULT}).
  --help               Print this help message and exit.
EOF
}

BASE_DIR="$BASE_DIR_DEFAULT"
TARBALL_PATH=""

while [ $# -gt 0 ]; do
    case "$1" in
        --help)
            usage
            exit 0
            ;;
        --base-dir)
            if [ $# -lt 2 ]; then
                echo "error: --base-dir requires a path argument" >&2
                usage >&2
                exit 1
            fi
            BASE_DIR="$2"
            shift 2
            ;;
        *)
            TARBALL_PATH="$1"
            shift
            ;;
    esac
done

if [ -z "$TARBALL_PATH" ]; then
    echo "error: a tarball path is required" >&2
    usage >&2
    exit 1
fi

if [ ! -f "$TARBALL_PATH" ]; then
    echo "error: tarball not found at $TARBALL_PATH" >&2
    exit 1
fi

echo "==> Using base directory $BASE_DIR"
mkdir -p "$BASE_DIR"

# Use a randomly-suffixed install directory.
SUFFIX="$RANDOM$RANDOM"
CONDOR_DIR="$BASE_DIR/condor-$SUFFIX"

# --- Install HTCondor --------------------------------------------------
# Unpack the tarball and configure it as a single-user AP.
echo "==> Unpacking HTCondor to $CONDOR_DIR"
mkdir -p "$CONDOR_DIR"
tar -xf "$TARBALL_PATH" -C "$CONDOR_DIR" --strip-components=1

echo "==> Configuring HTCondor as a single-user AP"
(cd "$CONDOR_DIR" && bin/make-ap-from-tarball)

echo "==> Updating shell environment with AP install"
# shellcheck disable=SC1091
. "$CONDOR_DIR/condor.sh"

# --- Configure HTCondor for Annex Mode --------------------------------------
# Enable the optional Annex feature.
echo "==> Installing Annex configuration"
cp "$REPO_DIR/11-ap-annex.conf" "$CONDOR_DIR/local/config.d/"

# --- Run the AP (e.g. as a Slurm job) ----------------------------------
# Pin this node's hostname via NETWORK_HOSTNAME in the shared config.
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
