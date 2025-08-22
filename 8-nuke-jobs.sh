#!/bin/bash

# This script deletes ALL jobs with the prefix "quick-job-" and their associated pods.
# This is a more aggressive cleanup script.

set -euo pipefail

PARALLELISM=50 # Increased parallelism

echo "Starting to nuke all 'quick-job-*' jobs..."

# The --ignore-not-found flag prevents errors if the job doesn't exist.
# Deleting the job will also trigger the deletion of its pods.
kubectl get jobs -o name | grep "quick-job-" | xargs -r -n 1 -P $PARALLELISM -I {} kubectl delete {} --ignore-not-found --cascade=background

echo "All 'quick-job-*' deletion commands have been sent."
