#!/bin/bash
#
# install.sh - Install a personal HTCondor Access Point (AP), configure it to run
# persistently via unprivileged SystemD, and enable lingering so it survives logout.
#
# This script performs the "Personal AP Install" and "Personal AP SystemD Configuration"
# steps described in README.md. It is expected to be run from within a clone of the
# personal-ap-systemd repository.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

BASE_DIR_DEFAULT="/scratch/$USER"

usage() {
    cat <<EOF
Usage: $(basename "${BASH_SOURCE[0]}") [OPTIONS]

Install a personal HTCondor Access Point (AP), configure it to run
persistently via unprivileged SystemD, and enable lingering so it
survives logout.

Options:
  --base-dir <path>    Base directory for the AP install, on storage
                       shared with wherever condor tools will be run
                       from (default: ${BASE_DIR_DEFAULT}).
  --download          Download the HTCondor release tarball from
                       get.htcondor.org (default).
  --tarball <path>     Install HTCondor from an existing tarball on disk
                       at <path>, instead of downloading one.
  --foreground         After installing, run the AP in the foreground
                       (condor_master -f) instead of installing it as a
                       SystemD user service. Intended for running the AP
                       as a Slurm job; see ap.sub.
  --enable-idtoken-auth
                       Generate a sample IDToken with schedd READ/WRITE
                       authorization, placed in the AP's shared tokens.d
                       directory. IDTOKENS is already an accepted
                       authentication method, so no config changes are
                       needed - this just issues a credential. Assumes a
                       filesystem shared with the client host (e.g. a
                       Slurm login node), which will pick up the token
                       automatically from that same path. Testing only.
  --help               Print this help message and exit.
EOF
}

SOURCE_MODE="download"
TARBALL_PATH=""
FOREGROUND="false"
IDTOKEN_AUTH="false"
BASE_DIR="$BASE_DIR_DEFAULT"

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
        --download)
            SOURCE_MODE="download"
            shift
            ;;
        --tarball)
            if [ $# -lt 2 ]; then
                echo "error: --tarball requires a path argument" >&2
                usage >&2
                exit 1
            fi
            SOURCE_MODE="tarball"
            TARBALL_PATH="$2"
            shift 2
            ;;
        --foreground)
            FOREGROUND="true"
            shift
            ;;
        --enable-idtoken-auth)
            IDTOKEN_AUTH="true"
            shift
            ;;
        *)
            echo "error: unknown argument: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

if [ "$SOURCE_MODE" = "tarball" ] && [ ! -f "$TARBALL_PATH" ]; then
    echo "error: tarball not found at $TARBALL_PATH" >&2
    exit 1
fi

echo "==> Using base directory $BASE_DIR"
mkdir -p "$BASE_DIR"

# Each install gets its own randomly-suffixed directory, so repeated or
# concurrent job submissions sharing $BASE_DIR don't collide.
SUFFIX="$RANDOM$RANDOM"
CONDOR_DIR="$BASE_DIR/condor-$SUFFIX"

# --- Download Prerequisites -------------------------------------------------
# Fetch the HTCondor release tarball (personal-ap-systemd itself is assumed to
# already be cloned, since this script lives inside it), or use one supplied
# on-disk via --tarball.
if [ "$SOURCE_MODE" = "tarball" ]; then
    echo "==> Using HTCondor tarball at $TARBALL_PATH"
    CONDOR_TARBALL="$TARBALL_PATH"
else
    echo "==> Downloading HTCondor"
    if [ ! -f "$BASE_DIR/condor.tar.gz" ]; then
        (cd "$BASE_DIR" && curl -fsSL https://get.htcondor.org | /bin/bash -s -- -download)
    else
        echo "    $BASE_DIR/condor.tar.gz already downloaded"
    fi
    CONDOR_TARBALL="$BASE_DIR/condor.tar.gz"
fi

# --- Install HTCondor ---------------------------------------------------
# Unpack the tarball and configure it as a single-user AP.
echo "==> Unpacking HTCondor to $CONDOR_DIR"
mkdir -p "$CONDOR_DIR"
tar -xf "$CONDOR_TARBALL" -C "$CONDOR_DIR" --strip-components=1

echo "==> Configuring HTCondor as a single-user AP"
(cd "$CONDOR_DIR" && bin/make-ap-from-tarball)

echo "==> Updating shell environment with AP install"
# shellcheck disable=SC1091
. "$CONDOR_DIR/condor.sh"

if [ "$FOREGROUND" != "true" ]; then
    # Each install lives in its own randomly-suffixed directory, so this is
    # skipped for ephemeral --foreground (Slurm job) installs - there's no
    # stable path to point an interactive shell at, and this would otherwise
    # accumulate a new stale line on every job submission.
    if ! grep -qF ". $CONDOR_DIR/condor.sh" "$HOME/.bashrc" 2>/dev/null; then
        echo "==> Adding condor.sh sourcing to .bashrc"
        echo ". $CONDOR_DIR/condor.sh" >> "$HOME/.bashrc"
    else
        echo "==> .bashrc already sources condor.sh"
    fi
fi

# --- Configure HTCondor for Annex Mode --------------------------------------
# Enable the optional Annex feature so EPs can be launched via Slurm jobs.
echo "==> Installing Annex configuration"
cp "$REPO_DIR/11-ap-annex.conf" "$CONDOR_DIR/local/config.d/"

# --- Enable IDToken Authentication (testing only) ----------------------------
# IDTOKENS is already an accepted authentication method via
# security:recommended, so no config changes are needed here - just issue a
# sample token with schedd READ/WRITE authorization into the AP's shared
# tokens.d directory ($(SEC_TOKEN_DIRECTORY), which make-ap-from-tarball
# points at $(SEC_TOKEN_SYSTEM_DIRECTORY), i.e. condor/local/tokens.d).
if [ "$IDTOKEN_AUTH" = "true" ]; then
    echo "==> Enabling IDToken authentication"

    POOL_KEY_FILE="$CONDOR_DIR/local/passwords.d/POOL"
    if [ -f "$POOL_KEY_FILE" ]; then
        echo "    $POOL_KEY_FILE already exists, leaving it in place"
    else
        if ! command -v openssl >/dev/null 2>&1; then
            echo "error: openssl is required to generate a pool signing key" >&2
            exit 1
        fi
        condor_store_cred add -c -f "$POOL_KEY_FILE" -p "$(openssl rand -base64 32)"
        echo "    Generated pool signing key at $POOL_KEY_FILE"
    fi

    TOKEN_NAME="testing"
    TOKEN_FILE="$CONDOR_DIR/local/tokens.d/$TOKEN_NAME"
    if [ -f "$TOKEN_FILE" ]; then
        echo "    $TOKEN_FILE already exists, leaving it in place"
    else
        IDENTITY="$(whoami)@$(condor_config_val UID_DOMAIN)"
        condor_token_create -identity "$IDENTITY" -authz READ -authz WRITE -token "$TOKEN_NAME"
        echo "    Generated sample IDToken for $IDENTITY at $TOKEN_FILE"
        echo "    On a host sharing this filesystem (e.g. the login node), condor"
        echo "    tools will pick this token up automatically from that same path."
    fi
fi

# --- Run the AP in the foreground (e.g. as a Slurm job) ----------------------
# Skip SystemD/loginctl entirely and run condor_master directly, blocking for
# as long as the AP should stay up (e.g. the lifetime of a Slurm allocation).
if [ "$FOREGROUND" = "true" ]; then
    # Pin FULL_HOSTNAME to this node's value in the shared config. Without
    # this, condor tools run from another host sharing $BASE_DIR (e.g. the
    # Slurm login node) would each auto-detect their own local hostname
    # instead of the AP's, causing a mismatch.
    AP_FULL_HOSTNAME="$(condor_config_val FULL_HOSTNAME)"
    echo "==> Pinning FULL_HOSTNAME to $AP_FULL_HOSTNAME"
    echo "FULL_HOSTNAME = $AP_FULL_HOSTNAME" > "$CONDOR_DIR/local/config.d/13-ap-hostname.conf"

    echo "==> Running HTCondor AP in the foreground"
    exec "$CONDOR_DIR/sbin/condor_master" -f
fi

# --- Personal AP SystemD Configuration --------------------------------------
# Install and enable an unprivileged SystemD user service for HTCondor so it
# starts automatically on login. htcondor.service refers to ~/condor as a
# stand-in for the install location; substitute in the actual base directory.
echo "==> Configuring HTCondor SystemD user service"
mkdir -p "$HOME/.config/systemd/user"
sed "s|~/condor|${CONDOR_DIR}|g" "$REPO_DIR/htcondor.service" > "$HOME/.config/systemd/user/htcondor.service"

systemctl --user daemon-reload
systemctl --user enable htcondor.service

# --- Confirm that your AP starts via Systemctl ------------------------------
echo "==> Starting HTCondor service"
systemctl --user start htcondor.service
systemctl --user status --no-pager htcondor.service

# --- Persist the HTCondor service through logouts via loginctl -------------
# By default user SystemD services exit on logout; enabling linger keeps the
# AP running while no session is connected. This may require admin rights.
echo "==> Enabling lingering so the AP persists through logout"
if command -v loginctl >/dev/null 2>&1; then
    if ! loginctl enable-linger "$USER" 2>/tmp/loginctl_err; then
        echo "    Could not enable linger for $USER (may require admin privileges):"
        cat /tmp/loginctl_err
        echo "    Ask a system administrator to run: loginctl enable-linger $USER"
    fi
    rm -f /tmp/loginctl_err
    loginctl show-user "$USER" | grep Linger || true
else
    echo "    loginctl not found; ask a system administrator to enable lingering for $USER"
fi

echo "==> Install complete"
echo "    Run '. $CONDOR_DIR/condor.sh' in your current shell, or start a new shell,"
echo "    to pick up your HTCondor environment."
