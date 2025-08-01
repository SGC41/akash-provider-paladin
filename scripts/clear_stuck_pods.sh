#!/bin/bash
#
# clear_stuck_pods.sh v2.2.4
# ---------------------------------------
# Scans all namespaces for pods stuck in
# Terminating, Error, or Unknown states.
# Deletes them forcefully without delay.
# ---------------------------------------

set -euo pipefail

echo "========== Stuck Pod Cleanup =========="
echo "Started at: $(date)"

# ── Identify stuck pods globally ──
STUCK_PODS=$(
  kubectl get pods --all-namespaces |
  grep -E 'Terminating|Error|Terminated|ContainerStatusUnknown|Unknown' |
  awk '{print $1 " " $2}'
)

# ── Attempt deletion per pod ──
while read -r NAMESPACE POD; do
  if kubectl get pod "$POD" -n "$NAMESPACE" &>/dev/null; then
    echo "Deleting pod $POD in namespace $NAMESPACE"
    if kubectl delete pod "$POD" -n "$NAMESPACE" --grace-period=0 --force --wait=false; then
      echo "✅ Successfully deleted pod $POD in namespace $NAMESPACE"
    else
      echo "❌ Failed to delete pod $POD in namespace $NAMESPACE"
    fi
  fi
done <<< "$STUCK_PODS"

echo "Completed at: $(date)"
echo "========================================"
