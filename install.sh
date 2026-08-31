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

usage() {
    cat <<EOF
Usage: $(basename "${BASH_SOURCE[0]}") [OPTIONS]

Install a personal HTCondor Access Point (AP), configure it to run
persistently via unprivileged SystemD, and enable lingering so it
survives logout.

Options:
  --download        Download the HTCondor release tarball from
                     get.htcondor.org (default).
  --tarball <path>   Install HTCondor from an existing tarball on disk
                     at <path>, instead of downloading one.
  --help             Print this help message and exit.
EOF
}

SOURCE_MODE="download"
TARBALL_PATH=""

while [ $# -gt 0 ]; do
    case "$1" in
        --help)
            usage
            exit 0
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

# --- Download Prerequisites -------------------------------------------------
# Fetch the HTCondor release tarball (personal-ap-systemd itself is assumed to
# already be cloned, since this script lives inside it), or use one supplied
# on-disk via --tarball.
if [ -d "$HOME/condor" ]; then
    echo "==> $HOME/condor already exists, skipping download/install"
else
    if [ "$SOURCE_MODE" = "tarball" ]; then
        echo "==> Using HTCondor tarball at $TARBALL_PATH"
        CONDOR_TARBALL="$TARBALL_PATH"
    else
        echo "==> Downloading HTCondor"
        if [ ! -f "$HOME/condor.tar.gz" ]; then
            curl -fsSL https://get.htcondor.org | /bin/bash -s -- -download
        else
            echo "    $HOME/condor.tar.gz already downloaded"
        fi
        CONDOR_TARBALL="$HOME/condor.tar.gz"
    fi

    # --- Install HTCondor ---------------------------------------------------
    # Unpack the tarball and configure it as a single-user AP.
    echo "==> Unpacking HTCondor"
    tar -xf "$CONDOR_TARBALL" -C "$HOME"
    mv "$HOME"/condor-*stripped/ "$HOME/condor/"

    echo "==> Configuring HTCondor as a single-user AP"
    (cd "$HOME/condor" && bin/make-ap-from-tarball)
fi

echo "==> Updating shell environment with AP install"
# shellcheck disable=SC1091
. "$HOME/condor/condor.sh"

if ! grep -qF '. ~/condor/condor.sh' "$HOME/.bashrc" 2>/dev/null; then
    echo "==> Adding condor.sh sourcing to .bashrc"
    echo '. ~/condor/condor.sh' >> "$HOME/.bashrc"
else
    echo "==> .bashrc already sources condor.sh"
fi

# --- Configure HTCondor for Annex Mode --------------------------------------
# Enable the optional Annex feature so EPs can be launched via Slurm jobs.
echo "==> Installing Annex configuration"
cp "$REPO_DIR/11-ap-annex.conf" "$HOME/condor/local/config.d/"

# --- Personal AP SystemD Configuration --------------------------------------
# Install and enable an unprivileged SystemD user service for HTCondor so it
# starts automatically on login.
echo "==> Configuring HTCondor SystemD user service"
mkdir -p "$HOME/.config/systemd/user"
cp "$REPO_DIR/htcondor.service" "$HOME/.config/systemd/user/"

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
echo "    Run '. ~/condor/condor.sh' in your current shell, or start a new shell,"
echo "    to pick up your HTCondor environment."
