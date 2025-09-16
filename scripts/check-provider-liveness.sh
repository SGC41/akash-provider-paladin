#!/usr/bin/env bash

echo "Provider pod liveness check"

# Run the command and capture all output (stdout + stderr)
output=$(kubectl -n akash-services exec -ti akash-provider-0 -- bash -x /scripts/liveness_checks.sh 2>&1)

# Check if the output contains the success message
if echo "$output" | grep -q "All checks passed"; then
    echo "All checks passed"
else
    echo "$output"
fi

