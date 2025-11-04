#!/bin/bash

# Akash Provider Bid Watchdog v0.9
# Scans for MsgCreateBid activity. Restarts provider pod if last bid is too old.

set -euo pipefail

# ── Config ─────────────────────────────────────────────────────
LIMIT=100
MAX_SKIP=3000
SKIP=0
MAX_MINUTES=(60*2)  # 🔁 Threshold for bid age before pod restart

CONFIG_PATH="$HOME/akash-provider-paladin/provider.yaml"
WALLET_ADDRESS=$(yq -r '.from' "$CONFIG_PATH")

if [[ -z "$WALLET_ADDRESS" ]] || ! [[ "$WALLET_ADDRESS" =~ ^akash ]]; then
  echo "[!] Invalid wallet address"
  exit 1
fi

NOW=$(date -u +%s)
ALL_RESULTS="[]"

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
    echo "[✓] Last MsgCreateBid at $MATCH — ${AGE_MIN} minutes ago"

    if [[ "$AGE_MIN" -gt "$MAX_MINUTES" ]]; then
      echo "[✗] Bid too old (> ${MAX_MINUTES} min) — restarting provider pod"
      kubectl delete pod akash-provider-0 -n akash-services
      exit 0
    else
      echo "[→] Bid is recent — no action needed"
      exit 0
    fi
  fi

  ALL_RESULTS=$(jq -s '.[0] + .[1]' <(echo "$ALL_RESULTS") <(echo "$CHUNK"))
  SKIP=$((SKIP + LIMIT))
done

# ── Fallback: MsgCloseBid Count ────────────────────────────────
CLOSE_COUNT=$(echo "$ALL_RESULTS" | jq '[ .[] | select(.messages[].type | test("^/akash.*MsgCloseBid$")) ] | length')

if [[ "$CLOSE_COUNT" -ge 5 ]]; then
  echo "[✗] No MsgCreateBid found, ${CLOSE_COUNT} MsgCloseBid detected — restarting provider pod"
  kubectl delete pod akash-provider-0 -n akash-services
else
  echo "[…] No MsgCreateBid detected, MsgCloseBid count (${CLOSE_COUNT}) below threshold — no action taken"
fi
