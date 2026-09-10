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

# Pin TRUST_DOMAIN, ANNEX_TOKEN_DOMAIN, and SCHEDD_NAME to this install's
# own name rather than letting them default to hostname-derived values
# (TRUST_DOMAIN defaults to FULL_HOSTNAME; ANNEX_TOKEN_DOMAIN defaults to
# $(UID_DOMAIN) = $(FULL_HOSTNAME); SCHEDD_NAME defaults to FULL_HOSTNAME
# too), so IDTokens, annex job/EP identity matching, and the EP's
# STARTD_DIRECT_ATTACH_SCHEDD_NAME lookup (a collector query by Name, which
# a hostname-derived SCHEDD_NAME would silently stop matching every time
# the AP resumes on a different Slurm node) all stay valid across resumes.
cat > "$CONDOR_DIR/local/config.d/12-ap-trust-domain.conf" <<EOF
TRUST_DOMAIN = condor-$SUFFIX
ANNEX_TOKEN_DOMAIN = condor-$SUFFIX
SCHEDD_NAME = condor-$SUFFIX@condor-$SUFFIX
EOF

# --- Configure HTCondor for Annex Mode --------------------------------------
# Enable the optional Annex feature.
echo "==> Installing Annex configuration"
cp "$REPO_DIR/11-ap-annex.conf" "$CONDOR_DIR/local/config.d/"

# FS auth can succeed for EP connections since every Slurm node shares a
# filesystem, which lets the EP authenticate as its own local
# user@hostname instead of via the IDToken we issue it. Restricting only
# the specific levels an EP needs (e.g. SEC_DAEMON_AUTHENTICATION_METHODS)
# isn't enough: SECMAN caches and reuses a negotiated session across
# multiple commands, so if some other, unrestricted level (e.g. READ)
# happens to establish the session first via FS, that FS-derived identity
# gets reused for later commands on the same session regardless of their
# own level's method restriction. Forcing IDTOKENS at
# SEC_DEFAULT_AUTHENTICATION_METHODS scope instead means no session to
# these daemons can be established via FS in the first place, no matter
# which command starts it.
#
# The resulting identity then also needs an explicit ALLOW_DAEMON entry,
# since the default (condor@*, condor@password) doesn't match our own
# user@domain tokens.
cat > "$CONDOR_DIR/local/config.d/14-ap-force-idtoken.conf" <<EOF
AP_COLLECTOR.SEC_DEFAULT_AUTHENTICATION_METHODS = IDTOKENS
SCHEDD.SEC_DEFAULT_AUTHENTICATION_METHODS = IDTOKENS

AP_COLLECTOR.ALLOW_DAEMON = \$(ALLOW_DAEMON), $(whoami)@condor-$SUFFIX
SCHEDD.ALLOW_DAEMON = \$(ALLOW_DAEMON), $(whoami)@condor-$SUFFIX
EOF

echo "==> Install complete"
echo "CONDOR_DIR=$CONDOR_DIR"
