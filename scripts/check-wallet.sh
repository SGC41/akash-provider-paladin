#!/usr/bin/env bash

# check_wallet.sh v1.32
# ------------------------------------------
# Checks AKT and USDC balances in a given wallet using the akash CLI.
# If balance exceeds (minimum + delta) for a token, moves the excess
# to a secondary wallet. Defaults to dry-run unless --execute is used.

# Provider.yaml entries for ease of customization.
# paladin_provider_wallet_max_allowed_akt: 20                                           ## Defaults to 20 AKT
# paladin_provider_wallet_max_allowed_akt_delta: 50                                     ## Defaults to 50 AKT

# paladin_provider_wallet_max_allowed_usdc: 20                                          ## Defaults to 20 AKT
# paladin_provider_wallet_max_allowed_usdc_delta: 50                                    ## Defaults to 50 AKT

# paladin_cold_wallet: <your cold akash wallet, should beging with akash....>           ## disabling script while not set in paladin provider.yaml

# Note: will only work when local rpc node is online, but it only runs daily and else just doesn't run... so more or less a useless feature.

# ===== CONFIGURATION =====

# Wallet addresses

set -euo pipefail

CONFIG="$HOME/akash-provider-paladin/provider.yaml"
PROVIDER_WALLET=$(yq -r '.from' "$CONFIG")
COLD_WALLET=$(yq -r '.paladin_cold_wallet' "$CONFIG")


# Minimum and delta AKT grabbed from provider.yaml
MIN_AKT=$(yq -r '.paladin_provider_wallet_max_allowed_akt // 20' "$CONFIG")
DELTA_AKT=$(yq -r '.paladin_provider_wallet_max_allowed_akt_delta // 50' "$CONFIG")

# Minimum and delta AKT grabbed from provider.yaml
MIN_USDC=$(yq -r '.paladin_provider_wallet_max_allowed_usdc // 20' "$CONFIG")
DELTA_USDC=$(yq -r '.paladin_provider_wallet_max_allowed_usdc_delta // 50' "$CONFIG")

# Denomination symbols (as used in Akash CLI)
DENOM_AKT="uakt"        # micro-AKT
DENOM_USDC="ibc/170C677610AC31DF0904FFE09CD3B5C657492170E7E52372E48756B71E56F2F1"      # micro-USDC

# Akash CLI binary path
AKASH_BIN="provider-services"

#Export RPC
export AKASH_NODE="http://$(kubectl -n akash-services get ep akash-node-1 -o jsonpath='{.subsets[0].addresses[0].ip}'):26657"

# ===== END CONFIGURATION =====


if [[ -z "$PROVIDER_WALLET" ]] || ! [[ "$PROVIDER_WALLET" =~ ^akash ]]; then
  echo "[!] Invalid provider wallet address"
  exit 1
fi


if [[ -z "$COLD_WALLET" ]] || ! [[ "$COLD_WALLET" =~ ^akash ]]; then
  echo "[!] No  wallet address found, please add it to your provider.yaml example.  paladin_cold_wallet: <should beging with akash....>"
  exit 1
fi

if ! provider-services keys parse "$COLD_WALLET" > /dev/null 2>&1; then
    echo "Invalid Akash wallet address for your cold wallet script seeing: $COLD_WALLET"
    echo "Please input a correct Akash wallet address for you cold wallet" 
    exit 1
fi

if [[ "$PROVIDER_WALLET" == "$COLD_WALLET" ]]; then
  echo "[!] Your cold wallet can't be the same as your provider wallet"
  echo "Please input a correct Akash wallet address for you cold wallet, in your provider.yaml"
  exit 1
fi

provider-services keys parse "$COLD_WALLET"

EXECUTE=false

# Parse flags
for arg in "$@"; do
  case $arg in
    --execute)
      EXECUTE=true
      shift
      ;;
  esac
done

[ "$EXECUTE" = false ] && echo "RUNNING IN DEBUG MODE!!! No actions will be taken, use --execute flag to allow suggested commands to run"

# Helper: Convert whole units to micro-units (Akash uses micro denominations)
to_micro() {
  # $1 = amount, $2 = factor (1 AKT = 1_000_000 uakt)
  awk -v amt="$1" -v factor="$2" 'BEGIN { printf "%.0f", amt * factor }'
}

# Helper: Convert micro-units to whole units for display
from_micro() {
  awk -v amt="$1" -v factor="$2" 'BEGIN { printf "%.6f", amt / factor }'
}

# Get balance in micro-units
get_balance() {
  local wallet=$1
  local denom=$2
  $AKASH_BIN query bank balances "$wallet" --denom "$denom" --output json 2>/dev/null \
    | jq -r '.amount // "0"'
}

# Check one currency
check_and_transfer() {
  local label=$1
  local denom=$2
  local min=$3
  local delta=$4
  local factor=1000000  # micro-units factor

  local balance_micro
  balance_micro=$(get_balance "$PROVIDER_WALLET" "$denom")
  local balance
  balance=$(from_micro "$balance_micro" "$factor")

  echo "[$label] Current balance: $balance"

  local min_plus_delta
  min_plus_delta=$(echo "$min + $delta" | bc)

  # Check if we have excess over min+delta
  comp=$(echo "$balance >= $min_plus_delta" | bc)
  if [[ "$comp" -eq 1 ]]; then
    local amount_to_send
    amount_to_send=$(echo "$balance - $min" | bc)  # Send excess over min

    local amount_micro
    amount_micro=$(to_micro "$amount_to_send" "$factor")

    local cmd="kubectl -n akash-services exec -i akash-provider-0 -- bash -c \
               '$AKASH_BIN tx bank send $PROVIDER_WALLET $COLD_WALLET ${amount_micro}${denom} --yes'"

    if $EXECUTE; then
      echo "Exceeds threshold: sending $amount_to_send $label to $COLD_WALLET"
      eval "$cmd"
    else
      echo "[DRY-RUN] Would run: $cmd"
      echo "Reason: $label balance above minimum + delta by $(echo "$balance - $min" | bc) $label"
    fi
  else
    echo "$label balance within thresholds; no transfer."
  fi
}

# ===== Main =====

check_and_transfer "AKT" "$DENOM_AKT" "$MIN_AKT" "$DELTA_AKT"
check_and_transfer "USDC" "$DENOM_USDC" "$MIN_USDC" "$DELTA_USDC"
