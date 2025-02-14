#!/bin/bash
# This script solves the issue with pods getting stuck on down nodes.
# Which can lead to provider downtime, persistent storage crashes and many other issues.
# List all terminating and error state pods across all namespaces
# Log location: /var/log/clear-stuck-pods.log
# clear_stuck_pods v1.01

STUCK_PODS=$(kubectl get pods --all-namespaces | grep -E 'Terminating|Error|ContainerStatusUnknown' | awk '{print $1 " " $2}')

LOGFILE="/var/log/clear-stuck-pods.log"

# Ensure log directory exists
mkdir -p /var/log

echo "Running at $(date)" >> $LOGFILE
echo "Force deleting the following pods stuck in a terminating or error state:" >> $LOGFILE

while read -r NAMESPACE POD; do
  # Check if the pod still exists before attempting to delete
  if kubectl get pod $POD -n $NAMESPACE > /dev/null 2>&1; then
    echo "$(date) - $NAMESPACE/$POD" >> $LOGFILE
    kubectl delete pod $POD -n $NAMESPACE --grace-period=0 --force --wait=false >> $LOGFILE 2>&1
  else
    echo "$(date) - Pod $POD in namespace $NAMESPACE not found, skipping." >> $LOGFILE
  fi
done <<< "$STUCK_PODS"

echo "-----------------------------------------------" >> $LOGFILE
