#!/bin/bash
#
# install.sh - Install a personal HTCondor Access Point (AP) from an
# HTCondor tarball (downloaded automatically if not already present). See
# start.sh to run the installed AP, and ap.sub.
#
# This script performs the "Personal AP Install" steps described in
# README.md. It is expected to be run from within a clone of the
# personal-ap-systemd repository.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

BASE_DIR_DEFAULT="/scratch/$USER"

usage() {
    cat <<EOF
Usage: $(basename "${BASH_SOURCE[0]}") [OPTIONS]

Install a personal HTCondor Access Point (AP) from the HTCondor tarball
at <base-dir>/condor.tar.gz, first downloading the tarball matching this
host's EL version (8, 9, or 10) if it does not exist. Leaves a symlink
to the install at ~/.cache/current-ap and prints the resulting install
directory as "CONDOR_DIR=<path>" as its last line of output; see
start.sh to actually run the installed AP.

Options:
  --base-dir <path>       Base directory for the AP install, on storage
                          shared with wherever condor tools will be run
                          from (default: ${BASE_DIR_DEFAULT}).
  --help                  Print this help message and exit.
EOF
}

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
        *)
            echo "error: unknown argument: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

echo "==> Using base directory $BASE_DIR"
mkdir -p "$BASE_DIR"

# --- Fetch the HTCondor tarball ------------------------------------------
TARBALL_PATH="$BASE_DIR/condor.tar.gz"
CONDOR_VERSION="25.15.15"
if [ ! -f "$TARBALL_PATH" ]; then
    # Detect this host's EL major version.
    if [ ! -r /etc/os-release ]; then
        echo "error: /etc/os-release not found; cannot detect EL version" >&2
        exit 1
    fi
    OS_INFO="$(. /etc/os-release && echo " $ID $ID_LIKE |${VERSION_ID%%.*}")"
    EL_VERSION="${OS_INFO##*|}"
    case "$OS_INFO" in
        *" rhel "*|*" rhel|"*|*" centos "*|*" rocky "*|*" almalinux "*) ;;
        *)
            echo "error: this host is not an EL (RHEL-compatible) host" >&2
            exit 1
            ;;
    esac
    case "$EL_VERSION" in
        8|9|10) ;;
        *)
            echo "error: unsupported EL version '$EL_VERSION' (supported: 8, 9, 10)" >&2
            exit 1
            ;;
    esac
    TARBALL_URL="https://htcss-downloads.chtc.wisc.edu/tarball/25.x/$CONDOR_VERSION/snapshot/condor-$CONDOR_VERSION-x86_64_AlmaLinux$EL_VERSION-stripped.tar.gz"
    echo "==> Downloading $TARBALL_URL to $TARBALL_PATH"
    if ! curl -fsSL -o "$TARBALL_PATH.part" "$TARBALL_URL"; then
        rm -f "$TARBALL_PATH.part"
        echo "error: failed to download $TARBALL_URL" >&2
        exit 1
    fi
    mv "$TARBALL_PATH.part" "$TARBALL_PATH"
fi

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

# Pin daemon names, which otherwise default to this node's FULL_HOSTNAME,
# so they stay consistent across resumes on a different Slurm node. See
# notes.md's "Daemon Name Pinning".
cat > "$CONDOR_DIR/local/config.d/12-ap-trust-domain.conf" <<EOF
TRUST_DOMAIN = condor-$SUFFIX
ANNEX_TOKEN_DOMAIN = condor-$SUFFIX
SCHEDD_NAME = condor-$SUFFIX@condor-$SUFFIX
EOF

# Alias `condor_status` to run against the AP's annex collector
cat >> "$CONDOR_DIR/condor.sh" << EOF
alias condor_status="condor_status -pool \$(condor_config_val NETWORK_HOSTNAME):9618?sock=ap_collector"
EOF

# --- Configure HTCondor for Annex Mode --------------------------------------
# Enable the optional Annex feature.
echo "==> Installing Annex configuration"
cp "$REPO_DIR/11-ap-annex.conf" "$CONDOR_DIR/local/config.d/"

# Force IDToken auth for the EP-facing daemons (an EP scheduled onto the
# AP's own node could otherwise authenticate via FS with the wrong
# identity), and grant its custom subject DAEMON access for schedd direct
# connect and CCB registration. See notes.md's "Force IDToken Auth".
cat > "$CONDOR_DIR/local/config.d/14-ap-force-idtoken.conf" <<EOF
AP_COLLECTOR.SEC_DEFAULT_AUTHENTICATION_METHODS = IDTOKENS
SCHEDD.SEC_DEFAULT_AUTHENTICATION_METHODS = IDTOKENS

AP_COLLECTOR.ALLOW_DAEMON = \$(ALLOW_DAEMON), $(whoami)@condor-$SUFFIX
SCHEDD.ALLOW_DAEMON = \$(ALLOW_DAEMON), $(whoami)@condor-$SUFFIX
EOF

# Leave a well-known symlink so later jobs can find and resume this AP.
mkdir -p "$HOME/.cache"
ln -sfn "$CONDOR_DIR" "$HOME/.cache/current-ap"

echo "==> Install complete"
echo "CONDOR_DIR=$CONDOR_DIR"
