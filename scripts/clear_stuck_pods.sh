#!/bin/bash
# This script solves the issue with pods getting stuck on down nodes.
# Which can lead to provider downtime, persistent storage crashes and many other issues.
# clear_stuck_pods.sh v2.0

while true; do
  # Calculate wait time until next half-hour boundary
  now=$(date +%s)
  currentMin=$(date +%M)
  if [ "$currentMin" -lt 30 ]; then
      target=$(date -d "$(date +%Y-%m-%d) $(date +%H):30:00" +%s)
  else
      target=$(date -d "$(date +%Y-%m-%d) $(date +%H):00:00 next hour" +%s)
  fi
  waitTime=$(( target - now ))
  echo "Sleeping for $waitTime seconds until scheduled run at $(date -d @$target)"
  sleep "$waitTime"

  echo "Executing stuck pod check at $(date)"

  # Fetch stuck pods based on their status
  STUCK_PODS=$(kubectl get pods --all-namespaces | grep -E 'Terminating|Error|Terminated|ContainerStatusUnknown' | awk '{print $1 " " $2}')

  echo "Stuck Pod Check Started at $(date)"

  # Process each stuck pod
  while read -r NAMESPACE POD; do
    if kubectl get pod "$POD" -n "$NAMESPACE" > /dev/null 2>&1; then
      echo "Deleting pod $POD in namespace $NAMESPACE"
      kubectl delete pod "$POD" -n "$NAMESPACE" --grace-period=0 --force --wait=false
      echo "Successfully deleted pod $POD in namespace $NAMESPACE"
    fi
  done <<< "$STUCK_PODS"

  echo "Stuck Pod Check Completed at $(date)"
done
