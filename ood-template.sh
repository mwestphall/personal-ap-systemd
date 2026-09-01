#!/bin/bash
#
# ood-template.sh - Copy an HTCondor annex tarball to a Slurm login host and
# create an OpenOnDemand Job Composer template for launching it, following
# the "Submit your Annex via OpenOnDemand" steps in README.md.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANNEX_SUBMIT_TEMPLATE="$REPO_DIR/annex_submit.sh"

TEMPLATE_DIR_DEFAULT="~/ondemand/templates"

usage() {
    cat <<EOF
Usage: $(basename "${BASH_SOURCE[0]}") --host <user@slurm-login-host> --tarball <path> --queue <name> [OPTIONS]

Copy an HTCondor annex tarball (from 'htcondor annex create') to a Slurm
login host, and create an OpenOnDemand Job Composer template that launches
it via annex_submit.sh.

Required arguments:
  --host <user@slurm-login-host>   SSH destination for the Slurm login host.
  --tarball <path>                 Path to the local annex tarball produced
                                    by 'htcondor annex create'.
  --queue <name>                   Slurm partition/queue to submit the annex
                                    job to.

Optional arguments:
  --mem <size>            Memory to request for the annex job (default: 4G).
  --cpus <n>              CPUs to request for the annex job (default: 2).
  --name <name>           Name of the OOD template to create (default:
                          derived from the tarball filename). Converted to
                          snake_case, e.g. "OOD Template Name" becomes
                          "ood_template_name".
  --template-dir <path>   Directory on the login host in which to create
                          the template (default: ${TEMPLATE_DIR_DEFAULT}).
  --help                  Print this help message and exit.
EOF
}

# Convert a string to snake_case, e.g. "OOD Template Name" -> "ood_template_name"
to_snake_case() {
    printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/_/g; s/^_+//; s/_+$//'
}

HOST=""
TARBALL=""
QUEUE=""
MEM="4G"
CPUS="2"
TEMPLATE_NAME=""
TEMPLATE_DIR_ARG="$TEMPLATE_DIR_DEFAULT"

while [ $# -gt 0 ]; do
    case "$1" in
        --help)
            usage
            exit 0
            ;;
        --host)
            [ $# -ge 2 ] || { echo "error: --host requires an argument" >&2; exit 1; }
            HOST="$2"
            shift 2
            ;;
        --tarball)
            [ $# -ge 2 ] || { echo "error: --tarball requires an argument" >&2; exit 1; }
            TARBALL="$2"
            shift 2
            ;;
        --queue)
            [ $# -ge 2 ] || { echo "error: --queue requires an argument" >&2; exit 1; }
            QUEUE="$2"
            shift 2
            ;;
        --mem)
            [ $# -ge 2 ] || { echo "error: --mem requires an argument" >&2; exit 1; }
            MEM="$2"
            shift 2
            ;;
        --cpus)
            [ $# -ge 2 ] || { echo "error: --cpus requires an argument" >&2; exit 1; }
            CPUS="$2"
            shift 2
            ;;
        --name)
            [ $# -ge 2 ] || { echo "error: --name requires an argument" >&2; exit 1; }
            TEMPLATE_NAME="$2"
            shift 2
            ;;
        --template-dir)
            [ $# -ge 2 ] || { echo "error: --template-dir requires an argument" >&2; exit 1; }
            TEMPLATE_DIR_ARG="$2"
            shift 2
            ;;
        *)
            echo "error: unknown argument: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

if [ -z "$HOST" ] || [ -z "$TARBALL" ] || [ -z "$QUEUE" ]; then
    echo "error: --host, --tarball, and --queue are required" >&2
    usage >&2
    exit 1
fi

if [ ! -f "$TARBALL" ]; then
    echo "error: tarball not found at $TARBALL" >&2
    exit 1
fi

TARBALL_BASENAME="$(basename "$TARBALL")"

if [ -z "$TEMPLATE_NAME" ]; then
    # Derive a template name from a tarball like "annex-test-annex.tar" -> "test-annex"
    TEMPLATE_NAME="${TARBALL_BASENAME%.tar}"
    TEMPLATE_NAME="${TEMPLATE_NAME#annex-}"
fi
TEMPLATE_NAME="$(to_snake_case "$TEMPLATE_NAME")"

# Templates are created relative to the login host's home directory unless an
# absolute --template-dir path is given.
if [[ "$TEMPLATE_DIR_ARG" == /* ]]; then
    TEMPLATE_BASE_DIR="$TEMPLATE_DIR_ARG"
    REMOTE_PREFIX=""
else
    TEMPLATE_BASE_DIR="${TEMPLATE_DIR_ARG#\~/}"
    REMOTE_PREFIX="~/"
fi

WORKDIR="$(mktemp -d)"

# Open a single multiplexed SSH connection in the background and reuse it for
# every subsequent ssh/scp call below, so the user only authenticates once.
CONTROL_PATH="$WORKDIR/ssh-control"
SSH_OPTS=(-o "ControlMaster=auto" -o "ControlPath=$CONTROL_PATH" -o "ControlPersist=5m")

cleanup() {
    ssh "${SSH_OPTS[@]}" -O exit "$HOST" >/dev/null 2>&1 || true
    rm -rf "$WORKDIR"
}
trap cleanup EXIT

echo "==> Opening SSH connection to $HOST"
ssh "${SSH_OPTS[@]}" -fN "$HOST"

# --- Copy the created tarball to your HPC login node ------------------------
echo "==> Copying $TARBALL_BASENAME to $HOST:~/"
scp "${SSH_OPTS[@]}" "$TARBALL" "$HOST:~/"

# --- Update main_job.sh in the template to the contents of annex_submit.sh --
# Substitute the given queue/memory/cpu/tarball parameters into annex_submit.sh
echo "==> Generating annex submit script for template '$TEMPLATE_NAME'"
MAIN_JOB="$WORKDIR/main_job.sh"
sed \
    -e "s|^#SBATCH --job-name=.*|#SBATCH --job-name=${TEMPLATE_NAME}|" \
    -e "s|^#SBATCH --partition=.*|#SBATCH --partition=${QUEUE}|" \
    -e "s|^#SBATCH --cpus-per-task=.*|#SBATCH --cpus-per-task=${CPUS}|" \
    -e "s|^#SBATCH --mem=.*|#SBATCH --mem=${MEM}|" \
    -e "s|^SOURCE=.*|SOURCE=\"\$HOME/${TARBALL_BASENAME}\"|" \
    "$ANNEX_SUBMIT_TEMPLATE" > "$MAIN_JOB"

# --- Log onto your HPC cluster's OpenOnDemand instance -----------------------
# SSH into the Slurm login host to create a New Template directory for the
# Job Composer app.
TEMPLATE_DIR="${TEMPLATE_BASE_DIR}/${TEMPLATE_NAME}"
echo "==> Creating OOD template directory ${REMOTE_PREFIX}${TEMPLATE_DIR} on $HOST"
ssh "${SSH_OPTS[@]}" "$HOST" "mkdir -p ${REMOTE_PREFIX}${TEMPLATE_DIR}"

# --- Create a New Template in the Job Composer -------------------------------
FORM_YML="$WORKDIR/form.yml"
cat > "$FORM_YML" <<EOF
---
name: ${TEMPLATE_NAME}
form:
  - queue
attributes:
  queue:
    value: ${QUEUE}
script:
  batch_connect:
    template: basic
EOF

echo "==> Copying template files to $HOST:${REMOTE_PREFIX}${TEMPLATE_DIR}/"
scp "${SSH_OPTS[@]}" "$MAIN_JOB" "$HOST:${REMOTE_PREFIX}${TEMPLATE_DIR}/main_job.sh"
scp "${SSH_OPTS[@]}" "$FORM_YML" "$HOST:${REMOTE_PREFIX}${TEMPLATE_DIR}/form.yml"

echo "==> Template complete"
echo "    Template '${TEMPLATE_NAME}' installed at ${REMOTE_PREFIX}${TEMPLATE_DIR} on ${HOST}."
echo "    Log into OpenOnDemand's Job Composer and select this template to submit your annex job."
