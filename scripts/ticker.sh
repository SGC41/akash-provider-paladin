#!/bin/bash
#
# Ticker is about the only thing that runs in the Paladin Pod
# Akash Provider Paladin pod exists for cluster support and redundancy
# It will choose which control plane are being by 

# Monitors provider restarts and triggers RPC rotation.
# Additionally runs stuck pod cleanup exactly on 00 and 30 minute marks.
# now 00, 20 and 40
# 


set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CURRENT_PALADIN_VERSION="v2.6.3"

# Load defaults
#source "etc/scripts/default.conf"

while true; do
  echo "============================"
  echo "Script cycle started at: $(date)"
  echo $CURRENT_PALADIN_VERSION 
  echo "============================"


  echo "Checking Provider Pod restarts"
  POD="akash-provider-0"
  if kubectl -n akash-services get pod "$POD" &>/dev/null; then
    RESTARTS=$(kubectl -n akash-services get pod "$POD" -o jsonpath='{.status.containerStatuses[0].restartCount}')
    echo "Restarts: $RESTARTS"
  else
  echo "[⚠] Pod $POD not found — skipping restart check"
  RESTARTS=0
  fi

# ── Trigger CHECK_ONLY flag at exactly 3:00 AM ──
hour=$(date +%H)
minute=$(date +%M)

#  if [[ "$hour" == "03" && "$minute" == "00" ]]; then
  if [[ "$minute" == "00" || "$minute" == "20" || "$minute" == "40" ]]; then
    echo "[log] [event] 3 AM local time check-daily.sh for control plane activated"
     echo "check-daily=true" >> /host/tmp/control-plane.do
     echo "rpc-rorate=true ; --check" >> /host/tmp/control-plane.do
  fi


  if [[ "$RESTARTS" -ge 3 ]]; then
    echo "RPC Rotate Triggered sent"
     echo "rpc-rotate=true" >> /host/tmp/control-plane.do
    echo "can take up to a few minutes"
  fi

  # ── Run stuck pod cleanup at ── changed to 20min
  if [[ "$minute" == "00" || "$minute" == "20" || "$minute" == "40" ]]; then
    echo "Stuck Pod Cleanup Triggered at minute $minute"
    "$SCRIPT_DIR/clear_stuck_pods.sh"

    echo "check-unpaid-leases=true ; --execute" >> /host/tmp/control-plane.do && \
    echo "check for unpaid leases request sent to control-plane"

    echo "akash-console-prov-on-check=true" >> /host/tmp/control-plane.do && \
    echo "Akash Console Online check request sent to control-plane"
    #"$SCRIPT_DIR/akash-console-online-check.sh"


  fi

  # ── Wait until next 5-minute boundary ──
  # added Akash Console Uptime check
  now=$(date +%s)
  next_min=$(( ( (minute / 5 + 1) * 5 ) % 60 ))
  if [[ "$next_min" -eq 0 ]]; then
    target=$(date -d "$(date +%Y-%m-%d) $(date +%H):00:00 next hour" +%s)
  else
    target=$(date -d "$(date +%Y-%m-%d\ %H):$next_min:00" +%s)
  fi

  waitTime=$(( target - now ))
  echo "Sleeping for $waitTime seconds until next run at $(date -d @$target)"
  sleep "$waitTime"
done
