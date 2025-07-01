#!/bin/bash
#
# ticker.sh v2.2.5
# Monitors provider restarts and triggers RPC rotation.
# Additionally runs stuck pod cleanup exactly on 00 and 30 minute marks.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

while true; do
  echo "============================"
  echo "Script cycle started at: $(date)"
  echo "v2.2.4"
  echo "============================"

  # ── RPC Rotation Window: At 03:00–03:04 ──
  hour=$(date +%-H)
  minute=$(date +%-M)

  if [[ "$hour" -eq 3 && "$minute" -lt 5 ]]; then
    echo "[rpc] 3:00 AM window detected — checking local RPC"
    "$SCRIPT_DIR/rpc-rotate.sh" --local && echo "RPC Rotate --local Script Ran Successfully"
  fi

  echo "Checking Provider Pod restarts"
  POD="akash-provider-0"
  RESTARTS=$(kubectl -n akash-services get pod "$POD" -o jsonpath='{.status.containerStatuses[0].restartCount}')
  echo "Restarts: $RESTARTS"

  if [[ "$RESTARTS" -ge 3 ]]; then
    echo "RPC Rotate Triggered"
    echo "[$(date -u)] run RPC rotate triggered" >> /host/tmp/rpc-rotate.do
    echo "can take up to 5 minutes"
  fi

  # ── Run stuck pod cleanup at :00 and :30 ──
  if [[ "$minute" == "00" || "$minute" == "30" ]]; then
    echo "Stuck Pod Cleanup Triggered at minute $minute"
    "$SCRIPT_DIR/clear_stuck_pods.sh"
  fi

  # ── Wait until next 5-minute boundary ──
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
