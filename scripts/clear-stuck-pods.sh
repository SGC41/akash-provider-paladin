#!/bin/bash
#
# clear_stuck_pods.sh v2.7.0
# ---------------------------------------
# Scans all namespaces for pods stuck in
# Terminating, Error, or Unknown states.
# Tries graceful deletion first, then
# force-deletes if needed. Supports
# namespace and pod-level exclusions.
# ---------------------------------------

set -euo pipefail

# ==== CONFIGURATION ===========================================================
# Namespaces to exclude entirely (space-separated)
EXCLUDED_NAMESPACES=(
#  "akash-services"
#  "namespace-example"
#  "these-will-be-excluded-from-clearing"
)

# Pods to exclude (use namespace/podname format)
EXCLUDED_PODS=(
  "akash-services/operator-inventory-hardware-discovery-*"
#  "add-custom-pods-here"
)

# Graceful deletion settings
GRACE_PERIOD_SECONDS=30            # how long to ask Kubernetes to terminate cleanly
GRACE_WAIT_TIMEOUT_SECONDS=45      # how long this script waits for graceful delete

# Force deletion follow-up wait (optional but helpful for logging)
FORCE_WAIT_TIMEOUT_SECONDS=20
# ============================================================================


# ---- Helpers: Exclusion checks ----------------------------------------------
is_namespace_excluded() {
  local ns="$1"
  for excluded in "${EXCLUDED_NAMESPACES[@]}"; do
    [[ "$ns" == "$excluded" ]] && return 0
  done
  return 1
}

# Check if a pod (namespace/pod) is in the exclusion list
is_pod_excluded() {
  local ns="$1"
  local pod="$2"
  local full="${ns}/${pod}"
  for excluded in "${EXCLUDED_PODS[@]}"; do
    # If excluded contains a wildcard, let Bash match it
    if [[ "$full" == $excluded ]]; then
      return 0
    fi
  done
  return 1
}
# -----------------------------------------------------------------------------

echo "========== Stuck Pod Cleanup =========="
echo "Started at: $(date)"
echo "Excluding namespaces: ${EXCLUDED_NAMESPACES[*]:-<none>}"
echo "Excluding pods: ${EXCLUDED_PODS[*]:-<none>}"

# ── Identify stuck pods globally (kept from original) ──
STUCK_PODS=$(
  kubectl get pods --all-namespaces |
  grep -E 'Terminating|Error|Terminated|ContainerStatusUnknown|Unknown|NodeAffinity|Completed' |
  awk '{print $1 " " $2}'
)

if [[ -z "${STUCK_PODS}" ]]; then
  echo "No stuck pods detected."
  echo "Completed at: $(date)"
  echo "========================================"
  exit 0
fi

# ── Attempt deletion per pod ──
while read -r NAMESPACE POD; do
  [[ -z "$NAMESPACE" || -z "$POD" ]] && continue  # skip empty lines

  # Skip if excluded
  if is_namespace_excluded "$NAMESPACE"; then
    echo "⏩ Skipping $POD (namespace $NAMESPACE is excluded)"
    continue
  fi
  if is_pod_excluded "$NAMESPACE" "$POD"; then
    echo "⏩ Skipping $POD in namespace $NAMESPACE (pod is excluded)"
    continue
  fi

  # Proceed only if the pod still exists
  if ! kubectl get pod "$POD" -n "$NAMESPACE" &>/dev/null; then
    continue
  fi

  # 1) Try graceful deletion first
  echo "Attempting graceful delete of $POD in namespace $NAMESPACE (grace=${GRACE_PERIOD_SECONDS}s)"
  kubectl delete pod "$POD" -n "$NAMESPACE" \
    --grace-period="$GRACE_PERIOD_SECONDS" --wait=false >/dev/null 2>&1 || true

  if kubectl wait pod "$POD" -n "$NAMESPACE" --for=delete --timeout="${GRACE_WAIT_TIMEOUT_SECONDS}s" >/dev/null 2>&1; then
    echo "✅ Gracefully deleted pod $POD in namespace $NAMESPACE"
    continue
  fi

  # 2) Fall back to force deletion
  echo "❌ Graceful delete timed out; forcing deletion of $POD in namespace $NAMESPACE"
  if kubectl delete pod "$POD" -n "$NAMESPACE" --grace-period=0 --force --wait=false; then
    # Optional: wait briefly to confirm removal for clearer logs
    if kubectl wait pod "$POD" -n "$NAMESPACE" --for=delete --timeout="${FORCE_WAIT_TIMEOUT_SECONDS}s" >/dev/null 2>&1; then
      echo "✅ Force-deleted pod $POD in namespace $NAMESPACE"
    else
      # Double-check: sometimes it's already gone even if wait timed out
      if ! kubectl get pod "$POD" -n "$NAMESPACE" &>/dev/null; then
        echo "✅ Force-deleted pod $POD in namespace $NAMESPACE"
      else
        echo "❌ Still present after force delete: $POD in namespace $NAMESPACE"
      fi
    fi
  else
    echo "❌ Failed to force-delete pod $POD in namespace $NAMESPACE"
  fi

done <<< "$STUCK_PODS"

echo "Completed at: $(date)"
echo "========================================"
