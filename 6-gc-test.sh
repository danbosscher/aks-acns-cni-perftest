#!/bin/bash

# This script creates 10,000 short-lived jobs in Kubernetes to test
# the garbage collector for completed pods.

# It includes a sleep command to avoid overloading the K8s API server.
# Jobs are configured to not retry on failure to ensure exactly 10,000 are created.
# It also includes a retry mechanism to handle API server timeouts.
# This version creates jobs in parallel to speed up the process.

set -euo pipefail

JOB_COUNT=10000
PARALLELISM=20 # Number of parallel job creation processes
RETRY_DELAY=5 # Delay in seconds before retrying a failed job creation

echo "Starting to create $JOB_COUNT jobs with PARALLELISM=${PARALLELISM}..."

create_job() {
  local i=$1
  local JOB_NAME="quick-job-$i"
  echo "Creating job $JOB_NAME ($i/$JOB_COUNT)"

  local JOB_MANIFEST
  JOB_MANIFEST=$(cat <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: ${JOB_NAME}
spec:
  template:
    spec:
      containers:
      - name: busybox
        image: busybox:1.28
        command: ["/bin/sh",  "-c", "echo 'Job ${JOB_NAME} completed'; sleep 0"]
      restartPolicy: Never
      tolerations:
      - key: "CriticalAddonsOnly"
        operator: "Exists"
        effect: "NoSchedule"
  backoffLimit: 0
EOF
)

  # Retry loop to ensure the job is created
  while ! echo "${JOB_MANIFEST}" | kubectl apply -f - >/dev/null; do
    echo "Failed to create job ${JOB_NAME}. Retrying in $RETRY_DELAY seconds..."
    sleep $RETRY_DELAY
  done
}

export -f create_job
export KUBECONFIG

# Use xargs to run job creation in parallel
seq 1 $JOB_COUNT | xargs -n 1 -P $PARALLELISM -I {} bash -c 'create_job {}'

wait

echo "Finished creating $JOB_COUNT jobs."
