#!/usr/bin/env bash
# v2.8.11

# Namespace and pod name
NS="akash-services"
POD="akash-provider-0"


echo "Provider pod liveness check"


# Check if pod is in Running state
if ! kubectl -n "$NS" get pod "$POD" 2>/dev/null | grep -q "Running"; then
    echo "Provider pod is not ready yet. Skipping liveness check."
    exit 0
fi

# Run the liveness check and capture output
output=$(kubectl -n "$NS" exec "$POD" -- bash /scripts/liveness_checks.sh 2>&1)

# Check for success
if echo "$output" | grep -q "All checks passed"; then
    echo "All checks passed"
else
    echo "Liveness check failed:"
    echo "$output"
fi



## Run the command and capture all output (stdout + stderr)
#output=$(kubectl -n akash-services exec -ti akash-provider-0 -- bash -x /scripts/liveness_checks.sh 2>&1)

# Check if the output contains the success message
# if echo "$output" | grep -q "All checks passed"; then
#    echo "All checks passed"
# else
#    echo "$output"
# fi

