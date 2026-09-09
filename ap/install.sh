#!/bin/bash
#
# install.sh - Install a personal HTCondor Access Point (AP) from an
# HTCondor tarball. See start.sh to run the installed AP, and ap.sub.
#
# This script performs the "Personal AP Install" steps described in
# README.md. It is expected to be run from within a clone of the
# personal-ap-systemd repository.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

BASE_DIR_DEFAULT="/scratch/$USER"

usage() {
    cat <<EOF
Usage: $(basename "${BASH_SOURCE[0]}") [OPTIONS] --tarball-path <path>

Install a personal HTCondor Access Point (AP) from the HTCondor tarball
at <path>. Prints the resulting install directory as
"CONDOR_DIR=<path>" as its last line of output; see start.sh to
actually run the installed AP.

Options:
  --base-dir <path>       Base directory for the AP install, on storage
                          shared with wherever condor tools will be run
                          from (default: ${BASE_DIR_DEFAULT}).
  --tarball-path <path>   Install HTCondor from the tarball at <path>.
  --help                  Print this help message and exit.
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
        --tarball-path)
            if [ $# -lt 2 ]; then
                echo "error: --tarball-path requires a path argument" >&2
                usage >&2
                exit 1
            fi
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

if [ -z "$TARBALL_PATH" ]; then
    echo "error: --tarball-path is required" >&2
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

# Pin TRUST_DOMAIN to this install's own name rather than letting it
# default to a hostname-derived value, so IDTokens stay valid when the
# AP moves to a different Slurm node on resume.
echo "TRUST_DOMAIN = condor-$SUFFIX" > "$CONDOR_DIR/local/config.d/12-ap-trust-domain.conf"

# --- Configure HTCondor for Annex Mode --------------------------------------
# Enable the optional Annex feature.
echo "==> Installing Annex configuration"
cp "$REPO_DIR/11-ap-annex.conf" "$CONDOR_DIR/local/config.d/"

echo "==> Install complete"
echo "CONDOR_DIR=$CONDOR_DIR"
