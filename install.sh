cat << 'EOF' > /usr/local/bin/clear_stuck_pods.sh
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
EOF

chmod +x /usr/local/bin/clear_stuck_pods.sh

(crontab -l 2>>/dev/null; echo "# clear_stuck_pods v1.0
# This cron job runs every 30 minutes and executes the clear_stuck_pods script to remove pods stuck in a terminating or error state.
# Log location: /var/log/clear-stuck-pods.log
# 30 minutes was choose to avoid hitting normally terminating pods and so that a node can return before a pod will be bounced.
# lower might be good for the pods, but then increases the odds of hitting normally operating pods as termining state can take a few minutes in some cases.
# also pod jumping around, if you wanted to reboot a GPU node, might not be what you want.... thus 30minutes...
# most likely fine to put it to 5 minutes tho
*/30 * * * * /usr/local/bin/clear_stuck_pods.sh") | crontab -
