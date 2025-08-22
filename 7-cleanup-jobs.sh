#!/bin/bash

# This script deletes 5000 jobs listed in the jobs_to_delete.txt file
# and their associated pods, simulating the cleanup process of the
# Kubernetes garbage collector.

set -euo pipefail

PARALLELISM=20
JOBS_FILE="/home/dabossch/git/SystemPoolFail/jobs_to_delete.txt"

if [ ! -f "$JOBS_FILE" ]; then
    echo "Error: $JOBS_FILE not found."
    exit 1
fi

echo "Starting to delete jobs listed in $JOBS_FILE..."

delete_job() {
  local JOB_NAME=$1
  echo "Deleting job $JOB_NAME"
  # The --ignore-not-found flag prevents errors if the job doesn't exist.
  # Deleting the job will also trigger the deletion of its pods.
  kubectl delete "$JOB_NAME" --ignore-not-found --cascade=background >/dev/null
}
;
export -f delete_job
export KUBECONFIG

# Use xargs to run job deletion in parallel
cat "$JOBS_FILE" | xargs -n 1 -P $PARALLELISM -I {} bash -c 'delete_job {}'

wait

echo "Finished deleting jobs listed in $JOBS_FILE."
