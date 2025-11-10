#!/bin/bash

# Akash Provider Bid Watchdog v1.1.0
# Scans for MsgCreateBid activity. Restarts provider pod if last bid is too old.

set -uo pipefail

# ── Config ─────────────────────────────────────────────────────
LIMIT=100
MAX_SKIP=3000
SKIP=0
MAX_MINUTES=(60*1)  # 🔁 Threshold for bid age before pod restart
PROVIDER_POD_AGE_SECOND_RESTART_TRIGGER=(80*60)
CONFIG_PATH="$HOME/akash-provider-paladin/provider.yaml"
WALLET_ADDRESS=$(yq -r '.from' "$CONFIG_PATH")

# Load Custom Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/default.conf"


log_stamp() {
  echo "[$(date -u +"%Y-%m-%d %H:%M:%S")]"
}

if [[ -z "$WALLET_ADDRESS" ]] || ! [[ "$WALLET_ADDRESS" =~ ^akash ]]; then
  echo "$(log_stamp) [Warn] Invalid wallet address"
  exit 1
fi

NOW=$(date -u +%s)
ALL_RESULTS="[]"

PROVIDER_POD_CREATION_TIME=$(kubectl -n akash-services get pod akash-provider-0 \
    -o jsonpath='{.metadata.creationTimestamp}')

# Requires GNU date
PROVIDER_POD_AGE_SECONDS=$(( $(date +%s) - $(date -d "$PROVIDER_POD_CREATION_TIME" +%s) ))

# Provider age check - so that the script won't bounce the provider pod all the time.
echo "$(log_stamp) [Info] Provider Pod age : '$PROVIDER_POD_AGE_SECONDS' seconds - Minimum age for provider bounce '$PROVIDER_POD_AGE_SECOND_RESTART_TRIGGER'"
if [[ "$PROVIDER_POD_AGE_SECONDS" -le "$PROVIDER_POD_AGE_SECOND_RESTART_TRIGGER" ]]; then
echo "$(log_stamp) [Info] Provider Pod has recently been re/started, Check Provider Bid script run not required skipping."
exit 0
fi

# ── Scan Loop ──────────────────────────────────────────────────
while [[ "$SKIP" -lt "$MAX_SKIP" ]]; do
  API="https://console-api.akash.network/v1/addresses/${WALLET_ADDRESS}/transactions/${SKIP}/${LIMIT}"
  RESPONSE=$(curl -s "$API" -H 'accept: application/json')
  CHUNK=$(echo "$RESPONSE" | jq '.results // []')

  MATCH=$(echo "$CHUNK" | jq -r '
    .[] | select(.messages[].type | test("^/akash.*MsgCreateBid$")) | .datetime' | head -n 1)

  if [[ -n "$MATCH" ]]; then
    MATCH_TS=$(date -u -d "$MATCH" +%s)
    AGE_MIN=$(( (NOW - MATCH_TS) / 60 ))
    echo "$(log_stamp) [Info] [✓] Last MsgCreateBid at $MATCH — ${AGE_MIN} minutes ago"

    if [[ "$AGE_MIN" -gt "$MAX_MINUTES" ]]; then
      echo "$(log_stamp) [Warn] [✗] Bid too old (> ${MAX_MINUTES} min) — restarting provider pod"
      kubectl delete pod akash-provider-0 -n akash-services
      exit 0
    else
      echo "$(log_stamp) [Info] [→] Bid is recent — no action needed"
      exit 0
    fi
  fi

  ALL_RESULTS=$(jq -s '.[0] + .[1]' <(echo "$ALL_RESULTS") <(echo "$CHUNK"))
  SKIP=$((SKIP + LIMIT))
done

# ── Fallback: MsgCloseBid Count ────────────────────────────────
CLOSE_COUNT=$(echo "$ALL_RESULTS" | jq '[ .[] | select(.messages[].type | test("^/akash.*MsgCloseBid$")) ] | length')

if [[ "$CLOSE_COUNT" -ge 5 ]]; then
  echo "$(log_stamp) [Warn] [✗] No MsgCreateBid found, ${CLOSE_COUNT} MsgCloseBid detected — restarting provider pod"
  kubectl delete pod akash-provider-0 -n akash-services
else
  echo "$(log_stamp) [Info] […] No MsgCreateBid detected, MsgCloseBid count (${CLOSE_COUNT}) below threshold — no action taken"
fi
