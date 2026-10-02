#!/bin/bash
#
# release-requeued-job.sh - Helper Slurm job submitted by check-port.sh. Waits
# for a job that was requeued held to become pending, excludes the given nodes
# from it, and releases it. See notes.md's "Port Collisions".
#
# Usage: sbatch [OPTIONS] release-requeued-job.sh <job id> <excluded nodes>
#
# ExcNodeList can only be edited while a job is pending, which doesn't happen
# until the job's previous run has been torn down, so the job can't do this
# itself.

set -uo pipefail

JOB_ID="${1:?Usage: release-requeued-job.sh <job id> <excluded nodes>}"
EXCLUDED="${2:?Usage: release-requeued-job.sh <job id> <excluded nodes>}"

for _ in $(seq 1 60); do
    STATE="$(scontrol show job "$JOB_ID" -o | sed -n 's/.*JobState=\([A-Z_]*\).*/\1/p')"
    if [ "$STATE" = "PENDING" ]; then
        if ! scontrol update JobId="$JOB_ID" ExcNodeList="$EXCLUDED"; then
            echo "WARNING: could not exclude $EXCLUDED; job $JOB_ID may land there again"
        fi
        scontrol release "$JOB_ID" && exit 0
    fi
    sleep 5
done

echo "error: job $JOB_ID did not become pending; releasing it anyway"
scontrol release "$JOB_ID"
exit 1
