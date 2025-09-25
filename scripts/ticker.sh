#!/bin/bash
#
# v 2.9.2
# Ticker is about the only thing that runs in the Paladin Pod
# Akash Provider Paladin pod exists for cluster support and redundancy
# It will choose which control plane are being by 

# Monitors provider restarts and triggers RPC rotation.
# Additionally runs stuck pod cleanup exactly on 00, 15, 30 and 45 marks
#


set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CURRENT_PALADIN_VERSION="v2.9.x"
BRANCH="stable"

# Load defaults
source "$SCRIPT_DIR/default.conf"

log_stamp() {
  echo "[$(date -u +"%Y-%m-%d %H:%M:%S")]"
}


  echo "============================"
  echo "Script cycle started at: $(date)"
  echo $CURRENT_PALADIN_VERSION 
  echo "============================"

while true; do
  echo "$(log_stamp) [log] - Checking Provider Pod restarts"
  POD="akash-provider-0"
  if kubectl -n akash-services get pod "$POD" &>/dev/null; then
    RESTARTS=$(kubectl -n akash-services get pod "$POD" -o jsonpath='{.status.containerStatuses[0].restartCount}')
    HOSTNODE=$(kubectl -n akash-services get pod akash-provider-0 -o jsonpath='{.spec.nodeName}')
    echo "$(log_stamp) [log] - Restarts: $RESTARTS"
    echo "$(log_stamp) [log] - Host:     $HOSTNODE"
  else
  echo "$(log_stamp) [log] [⚠] Pod $POD not found — skipping restart check"
  RESTARTS=0
  fi

# ── Trigger CHECK_ONLY flag at exactly 3:00 AM ──
hour=$(date +%H)
minute=$(date +%M)

#Paladin Version check
  if [[ "$minute" == "00" ]]; then


    # If no version is found in default.conf, skip comparison
    if [[ -z "${CURRENT_PALADIN_VERSION:-}" ]]; then
    echo "$(log_stamp) [log] - [skip] No version found in default.conf (expected CURRENT_PALADIN_VERSION, PALADIN_VERSION, or VERSION)"

    fi

  # ── Ensure we have a local clone of the repo ──
    REPO_DIR="/tmp/akash-provider-paladin"
    if [[ ! -d "$REPO_DIR/.git" ]]; then
      git clone --quiet https://github.com/SGC41/akash-provider-paladin.git "$REPO_DIR"
    fi

  # ── Fetch and reset to the branch from config ──
    git -C "$REPO_DIR" fetch --quiet origin "$BRANCH" --tags
    git -C "$REPO_DIR" checkout --quiet "$BRANCH"
    git -C "$REPO_DIR" reset --hard "origin/$BRANCH" --quiet

  # ── Get the latest tag reachable from that branch ──
      LATEST_VERSION=$(git -C "$REPO_DIR" describe --tags --abbrev=0 | sed 's/^v//')


    # ── Compare versions ──
    if [[ -n "$CURRENT_PALADIN_VERSION" && -n "$LATEST_VERSION" ]]; then
      if [[ "$CURRENT_PALADIN_VERSION" != "$LATEST_VERSION" ]]; then
        lower=$(printf "%s\n%s\n" "$CURRENT_PALADIN_VERSION" "$LATEST_VERSION" | sort -V | head -n1)
        if [[ "$lower" == "$CURRENT_PALADIN_VERSION" ]]; then
          echo "###########################################"
          echo "$(log_stamp) [log] - [update] A new version of paladin is available: $LATEST_VERSION (you have $CURRENT_PALADIN_VERSION)"
          echo "$(log_stamp) [log] - [update] Install with curl -fsSLo /tmp/install.sh https://raw.githubusercontent.com/SGC41/akash-provider-paladin/stable/install.sh && bash /tmp/install.sh"
          echo "###########################################"
        fi
      fi
    fi
  fi
#version check done

#  if [[ "$minute" == "00" || "$minute" == "20" || "$minute" == "40" ]]; then
# debug replacement line above
  if [[ "$hour" == "03" && "$minute" == "00" ]]; then
    echo "$(log_stamp) [log] - [event] 3 AM local time check-daily.sh for control plane activated"
     echo "check-daily=true" >> /host/tmp/control-plane.do
     grep -q '^rpc-rotate=true' /host/tmp/control-plane.do || echo "rpc-rotate=true ; --check" >> /host/tmp/control-plane.do
  fi


  if [[ "$RESTARTS" -ge 3 ]]; then
    echo "$(log_stamp) [log] [event] - RPC Rotate Triggered sent"
    grep -q '^rpc-rotate=true' /host/tmp/control-plane.do || echo "rpc-rotate=true" >> /host/tmp/control-plane.do
    echo "$(log_stamp) [log] - should trigger within a  minutes on the host control-plane."
  fi

  # ── Run stuck pod cleanup at ── 
  if [[ "$minute" == "00" || "$minute" == "15" || "$minute" == "30" || "$minute" == "45" ]]; then
    echo "$(log_stamp) [log] - Stuck Pod Cleanup Triggered at minute $minute"
#    "$SCRIPT_DIR/clear_stuck_pods.sh"
    echo "clear-stuck-pods=true" >> /host/tmp/control-plane.do && \

    echo "check-unpaid-leases=true ; --execute" >> /host/tmp/control-plane.do && \
    echo "$(log_stamp) [log] - check for unpaid leases request sent to control-plane"

    echo "akash-console-prov-on-check=true" >> /host/tmp/control-plane.do && \
    echo "$(log_stamp) [log] - Akash Console Online check request sent to control-plane"

    echo "check-provider-liveness=true" >> /host/tmp/control-plane.do && \
    echo "$(log_stamp) [log] - Provider pod liveness check request sent to control-plane"

  fi

# ── Wait until next 5 minute boundary, but watch for restarts ──
POD="akash-provider-0"
NS="akash-services"

# Calculate seconds until next 5 minute mark
now=$(date +%s)
minute=$(date +%M)
next_min=$(( ( (minute / 5 + 1) * 5 ) % 60 ))
if [[ "$next_min" -eq 0 ]]; then
  target=$(date -d "$(date +%Y-%m-%d) $(date +%H):00:00 next hour" +%s)
else
  target=$(date -d "$(date +%Y-%m-%d\ %H):$next_min:00" +%s)
fi
waitTime=$(( target - now ))

if kubectl -n "$NS" get pod "$POD" &>/dev/null; then

  # Get the current restart count
  current_restarts=$(kubectl -n "$NS" get pod "$POD" \
    -o jsonpath='{.status.containerStatuses[0].restartCount}')

  echo "$(log_stamp) [log] - Watching $POD for up to $waitTime seconds (current restarts: $current_restarts)..."

  while read -r new_restarts; do
      if [[ "$new_restarts" != "$current_restarts" ]]; then
          echo "$(log_stamp) [log] - [watch] Restart detected at $(date) — breaking early"
          pkill -P $$ kubectl  # kill the kubectl watch process
          echo "$(log_stamp) [log] - [watch] Recent Kubernetes events for $POD:"
          # Get the last 2–3 events for this pod
          kubectl -n "$NS" get events \
            --field-selector involvedObject.name="$POD" \
            --sort-by=.lastTimestamp | tail -n 10 | grep -v '^[[:space:]]*$'
          echo "$(log_stamp) [log] - Sending check-current-rpc trigger to Control Plane, due to Provider Pod Restart"
          grep -q '^check-current-rpc=true' /host/tmp/control-plane.do || echo "check-current-rpc=true" >> /host/tmp/control-plane.do

          break
      fi
  done < <(
      timeout "$waitTime" kubectl get pod "$POD" -n "$NS" \
        -o jsonpath='{.status.containerStatuses[0].restartCount}{"\n"}' -w
  )




else
  echo "$(log_stamp) [log] - [⚠] Pod $POD not found — sleeping $waitTime seconds"
  sleep "$waitTime"
  echo ""

fi
# end of  5 min block
echo "" #5 min segments seperator for log readability.
done
