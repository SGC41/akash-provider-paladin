#!/usr/bin/env bash
#
# Paladin v2.9.6
# check-unpaid-leases.sh v1.1.2
# creator SGC | DCnorse
# 2025-11-02
#
# Features
# Checks for unpaid leases, by introducing delta triggered withdrawals of all leases.
# Cleans old inactive or leases that aren't paying.
#
# Script Modes / Flags - default is not a flag:
#
#  default              The script when run will only create lists of withdrawal or delete commands, it will not run them.
#                       This allows for easy testing, and makes it fool proof, as anyone can easily check actions.
#
#
#  --execute            This  mode will end by running the withdraw-list.sh and kill-list.sh after they have been generated.
#                       Ends with the a report, like default.
#
#  --debug               Verbose, need i say more...
#
#  --withdraw             will add unique leases in the future.
#
# Operation, will pull information from provider yaml.
# such as withdrawal period, wallet, rpc nodes, if it can't find the local rpc node.
#
# also introduces new option for the Provider.yaml such as.
# this sets the delta required for the script to trigger withdrawal query / executing.
# the number is in USD.
# paladin_unpaid_withdraw_trigger: 10
#
# USD is the default used for ease of use, across almost all script outputs, when not noted with Denom.
#
# The script should be able to run without paladin, but has no automatic runtime, so one would have to use cronjob or systemd.
# if one wanted to use it without paladin.
#
# it will compare manifests against blockchain active leases, is forced to only look at akash leases, so is unable to affect any other pods.
# but it will decimate any akash deployment leases not recorded as active in the block chain, after attempting a withdrawal.
# the script tracks withdrawals of closed leases and will only allow closed leases to go onto the kill list.
# this is done to have multiple failsafes, so its impossible to have a failure state where the script will delete, something it shouldn't by mistake.
#
# Not sure if there is anything else to note... i'm sure there is...
# but it does its job when run...  ./check-unpaid-leases.sh --execute
#

set -uo pipefail
trap 'echo "[Crash] Exited at line $LINENO"' ERR
export AP_MINIMUM_GAS_PRICES="0.0025uakt"


snap list yq || sudo snap install yq
# ── Config & Globals ──────────────────────────────────────────────────────────
CONFIG="$HOME/akash-provider-paladin/provider.yaml"
AKASH_CLI="provider-services"
DEBUG=false
EXECUTE=false
MANUAL=false
BLOCK_TIME=6
BLOCKS_PER_HOUR=$((3600 / BLOCK_TIME))
BLOCKS_PER_DAY=$((86400 / BLOCK_TIME))
# use 30.436875 days per month (365.2425/12)
MONTH_DAYS=30.436875
BLOCKS_PER_MONTH=$(awk "BEGIN{printf \"%d\", $MONTH_DAYS * $BLOCKS_PER_DAY}")
#if file is older than 48 hours will rm.
file="$HOME/akash-provider-paladin/.withdrawn.tmp"
# Only delete if the file exists AND is older than 48 hours
[ -f "$file" ] && find "$file" -type f -mmin +2880 -exec rm {} \;
# Ensure it always exists afterward
touch "$file"



log_stamp() {
  echo "[$(date -u +"%Y-%m-%d %H:%M:%S")]"
}



#checking for provider.yaml, if not then download it from ETCD
[ ! -f "$CONFIG" ] && echo "provider.yaml missing downloading from ETCD" && $HOME/akash-provider-paladin/update-local-provider-yaml.sh

# read withdrawal period (e.g. "12h") and convert to blocks
WITHDRAWAL_PERIOD_RAW=$(yq -r '.withdrawalperiod // "144h"' "$CONFIG")
if [[ $WITHDRAWAL_PERIOD_RAW =~ ^([0-9]+)h$ ]]; then
  WITHDRAWAL_HOURS=${BASH_REMATCH[1]}
  echo "withdrawally value grabbed from provider.yaml $WITHDRAWAL_HOURS"
  else
  echo "$(date -u '+[%Y-%m-%d %H:%M:%S]')[Warn] Invalid withdrawally period=$WITHDRAWAL_PERIOD_RAW, defaulting to 144h" >&2
  WITHDRAWAL_HOURS=144
fi


# thresholds & files
MIN_USD_THRESHOLD=$(yq -r '.paladin_unpaid_withdraw_trigger // 10' "$CONFIG")
WITHDRAW_FILE="$HOME/akash-provider-paladin/withdraw-list.sh"
KILL_FILE="$HOME/akash-provider-paladin/kill-list.sh"

for arg in "$@"; do
  [[ $arg == "--debug"         ]] && DEBUG=true
  [[ $arg == "--execute"       ]] && EXECUTE=true
  [[ $arg == "--withdraw"       ]] && MANUAL=true
done

FALLBACK_RPC=$(yq -r '.paladin_rpc_fallback // "https://rpc-akash.ecostake.com:443"' "$CONFIG")

#on MANUAL flag withdraw all by setting trigger to 0
$MANUAL && MIN_USD_THRESHOLD=0

NODE_IP=$(kubectl -n akash-services get ep akash-node-1 -o 'jsonpath={.subsets[0].addresses[0].ip}' 2>/dev/null || echo "")
if [[ -n "$NODE_IP" ]]; then
  echo "$(log_stamp) [Info] Local RPC node found successfully"
  NODE_RPC="http://${NODE_IP}:26657"
else
  [[ -z "$FALLBACK_RPC" || "$FALLBACK_RPC" == "null" ]] && {
    echo "$(log_stamp) [Fatal] No local RPC found and no fallback RPC provided"
    exit 1
  }
  NODE_RPC="$FALLBACK_RPC"
  echo "$(log_stamp) [Warn] Using fallback RPC: $NODE_RPC"
fi


WALLET=$(yq -r '.from' "$CONFIG")
#RPC="http://<YOUR_RPC>:26657"       # ← your existing RPC logic
RPC="$NODE_RPC"

HEIGHT=0                             # placeholder
AKT_PRICE=0                          # placeholder
denom=empty
cons_usd=empty
wd_usd=empty
rate_usd=empty
bal_usd=empty
lease_rows=
lease_count=0
log_stamp(){ printf "[%s] " "$(date -u '+%Y-%m-%d %H:%M:%S')"; }

get_akt_price(){
  CACHE_FILE="/tmp/aktprice.cache"

  if ! test $(find "$CACHE_FILE" -mmin -60 2>/dev/null); then
    usd_per_akt=$(curl -s --connect-timeout 3 --max-time 3 \
      -X GET 'https://api.diadata.org/v1/assetQuotation/Osmosis/ibc-C2CFB1C37C146CF95B0784FD518F8030FEFC76C5800105B1742FB65FFE65F873' \
      -H 'accept: application/json' | jq -r '.Price' 2>/dev/null)

    if [[ $? -ne 0 || "$usd_per_akt" == "null" || -z "$usd_per_akt" ]]; then
      usd_per_akt=$(curl -s --connect-timeout 3 --max-time 3 \
        -X GET "https://api.coingecko.com/api/v3/simple/price?ids=akash-network&vs_currencies=usd" \
        -H "accept: application/json" | jq -r '[.[]][0].usd' 2>/dev/null)
    fi

    if [[ -n "$usd_per_akt" ]]; then
      re='^[0-9]+([.][0-9]+)?$'
      if [[ "$usd_per_akt" =~ $re ]]; then
        if (( $(echo "$usd_per_akt > 0 && $usd_per_akt <= 1000000" | bc -l) )); then
          echo "$usd_per_akt" > "$CACHE_FILE"
        fi
      fi
    fi
  fi

  usd_per_akt=$(cat "$CACHE_FILE" 2>/dev/null)
  echo "${usd_per_akt:-0}"

}

# ── 1) Fetch block height & price ─────────────────────────────────────────────
HEIGHT=$($AKASH_CLI query block --node "$RPC" \
  | jq -r '.block.header.height')

# keep this function intact
RAW_PRICE=$(get_akt_price)
if ! [[ $RAW_PRICE =~ ^[0-9]+(\.[0-9]+)?$ ]] || [[ $RAW_PRICE == 0 ]]; then
  echo "$(log_stamp)[Fatal] invalid AKT price: '$RAW_PRICE'" >&2
  exit 1
fi
AKT_PRICE=$RAW_PRICE



# prepare output files
: > "$WITHDRAW_FILE"
: > "$KILL_FILE"
chmod +x "$WITHDRAW_FILE" "$KILL_FILE"

# ── 2) Core processor ─────────────────────────────────────────────────────────
process_lease(){
  raw="$1"
  #reset
  action=none
  reason=none
  lease_ns=none
  lease_age_days=empty

  # 2a) extract JSON fields
  state=$(jq -r '.lease.state'           <<<"$raw")
  created_at=$(jq -r '.lease.created_at'      <<<"$raw")
  rate_amt=$(jq -r '.lease.price.amount'    <<<"$raw")   # micro-uakt/block
  cons_amt=$(jq -r '.escrow_payment.consumed.amount // empty' <<<"$raw")
  bal_amt=$(jq -r '.escrow_payment.balance.amount // empty'     <<<"$raw")
  wd_amt=$(jq -r '.escrow_payment.withdrawn.amount // empty'   <<<"$raw")
  denom=$(jq -r '.escrow_payment.balance.denom'          <<<"$raw")

  owner=$(jq -r '.lease.lease_id.owner' <<<"$raw")
  dseq=$(jq -r '.lease.lease_id.dseq'   <<<"$raw")
  gseq=$(jq -r '.lease.lease_id.gseq'   <<<"$raw")
  oseq=$(jq -r '.lease.lease_id.oseq'   <<<"$raw")
  key="$owner-$dseq-$gseq-$oseq"

  # Grab the Akash deployment namespace from label
  akash_lease_ns=$(kubectl get ns -l akash.network=true,akash.network/lease.id.provider="$WALLET" -o json \
    | jq -r --arg key "$key" '
      .items[]
      | select(
          (.metadata.labels["akash.network/lease.id.owner"] + "-" +
           .metadata.labels["akash.network/lease.id.dseq"] + "-" +
           .metadata.labels["akash.network/lease.id.gseq"] + "-" +
           .metadata.labels["akash.network/lease.id.oseq"]
          ) == $key
        )
      | .metadata.labels["akash.network/namespace"]
    ')


$DEBUG && echo "Akash namespace for lease $key is = $akash_lease_ns"

lease_count=$((lease_count + 1))

  # debug‐style echo
  $DEBUG && {
    echo
    echo "$(log_stamp)RAW lease: state=$state created_at=$created_at"
    echo "             rate=$rate_amt cons=$cons_amt balance=$bal_amt withdrawn=$wd_amt denom=$denom"
    echo
  }

  # 2b) sanity‐skip malformed
  if [[ -z $state || -z $created_at || -z $rate_amt ]]; then
    echo "$(log_stamp)[Error] Missing fields, skipping." >&2
    return
  fi

  # 2c) compute age (blocks)
  age_blocks=$(( HEIGHT - created_at ))
  lease_age_days=$((age_blocks / ((60 / 6) * 60 * 24)))
  # 2d) convert all micro-uakt → AKT
  #    rate_akt/block, cons_akt, bal_akt, withdrawn_akt
  rate_akt=$(awk "BEGIN{printf $rate_amt / 1e6}")
  cons_akt=$(awk "BEGIN{printf $age_blocks * $rate_akt}")
  bal_akt=$(awk "BEGIN{printf $bal_amt }")
  wd_akt=$(awk "BEGIN{printf $wd_amt / 1e6}")

  # 2e) AKT → USD (only for uakt; ibc treated as USD directly)
  if [[ $denom == "uakt" ]]; then
    rate_usd=$(awk "BEGIN{printf $rate_akt * $AKT_PRICE}")
    cons_usd=$(awk "BEGIN{printf $cons_akt * $AKT_PRICE}")
    bal_usd=$(awk "BEGIN{printf $bal_akt * $AKT_PRICE}")
    wd_usd=$(awk "BEGIN{printf $wd_akt * $AKT_PRICE}")
    cost_day=$(awk "BEGIN{printf $rate_akt * $BLOCKS_PER_DAY}")
    cost_per_withdrawal=$(awk "BEGIN{printf $rate_akt * $WITHDRAWAL_HOURS * $BLOCKS_PER_HOUR}")
  else
    # ibc token: 1 AKT‐unit ≡ 1 USD unit for display
    rate_usd=$rate_akt
    cons_usd=$cons_akt
    bal_usd=$bal_akt
    wd_usd=$wd_akt
    cost_day=$(awk "BEGIN{printf $rate_usd * $BLOCKS_PER_DAY}")
    cost_per_withdrawal=$(awk "BEGIN{printf $rate_usd * $WITHDRAWAL_HOURS * $BLOCKS_PER_HOUR}")
  fi

  # 2f) delta owed = max(consumed – withdrawn, 0)
  delta_akt=$(awk "BEGIN{printf $cons_akt - $wd_akt}")
  delta_usd=$(awk "BEGIN{printf $cons_usd - $wd_usd}")

  # 2g) costs usd
  cost_hr=$(awk "BEGIN{printf $rate_usd * $BLOCKS_PER_HOUR}")
  cost_month=$(awk "BEGIN{printf $rate_usd * $BLOCKS_PER_MONTH}")


  $DEBUG && echo

  # 2i) Decide actions

  withdraw_cmd="kubectl -n akash-services exec -i akash-provider-0 -- bash -c \
'${AKASH_CLI} tx market lease withdraw \
  --provider $WALLET --owner $owner \
  --dseq $dseq --gseq $gseq --oseq $oseq \
  --from $WALLET'"

  kill_cmd="kubectl delete ns $akash_lease_ns"

clean_cmd=$(cat <<EOF
kubectl -n lease get manifests -o json | \
jq -r --arg owner "$owner" --arg dseq "$dseq" --arg gseq "$gseq" --arg oseq "$oseq" \
'.items[] | select(
  .metadata.labels["akash.network/lease.id.owner"] == \$owner and
  .metadata.labels["akash.network/lease.id.dseq"] == \$dseq and
  .metadata.labels["akash.network/lease.id.gseq"] == \$gseq and
  .metadata.labels["akash.network/lease.id.oseq"] == \$oseq
) | .metadata.name' | \
xargs -I{} kubectl -n lease delete manifest {}
EOF
)

# Action logic

if [[ $state == "closed" ]]; then
  if grep -qx "$key" "$HOME/akash-provider-paladin/.withdrawn.tmp"; then
    $DEBUG && echo "lease exists in  withdrawn file"
    closed_on=$(jq -r '.lease.closed_on' <<<"$raw")
    if (( HEIGHT > closed_on + 10   )); then
      if [[ -n "$akash_lease_ns" ]]; then
        echo "$kill_cmd" >> "$KILL_FILE"
        if [[ $action == "none" ]]; then
          if [[ $EXECUTE == "true" ]]; then  action="Killed"; else
            action="Kill_Query"
          fi
            reason="Zombie_Lease"
        fi
      else
      $DEBUG && echo "$(log_stamp)[Info] akash_lease_ns is blank, Manifest deletion required"
      echo "$clean_cmd" >> "$KILL_FILE"
           if [[ $action == "none" ]]; then
                 if [[ $EXECUTE == "true" ]]; then  action="Mani_Deleted"; else
                   action="Mani_Query"
                 fi
             reason="Ghost_Lease"
           fi
      fi

      $DEBUG && echo "$(log_stamp)[Info] Already withdrawn, would X: $key"
      if [[ $action == "none" ]]; then
        action="Skipped"
        reason="Debug+Zombie_Lease"
      fi
    fi
  else
    echo "$withdraw_cmd" >> "$WITHDRAW_FILE"
    echo "$key" >> "$HOME/akash-provider-paladin/.withdrawn.tmp"
    $DEBUG && echo "$(log_stamp)[Info] Scheduled withdrawal: $key"
    if [[ $action == "none" ]]; then
        if [[ $EXECUTE == "true" ]]; then  action="Withdraw"; else
            action="Withdraw_Query"
         fi
      reason="Closed_Lease"
    fi
  fi
fi


# Continue with other state checks, e.g., active lease thresholds
if [[ $state != "closed" ]]; then
  if (( $(awk "BEGIN{print($delta_usd >= $MIN_USD_THRESHOLD)}") )); then
    echo "$withdraw_cmd" | tee -a "$WITHDRAW_FILE"
    if [[ $action == "none" ]]; then
       if [[ $EXECUTE == "true" ]]; then  action="Withdraw"; else
              action="Withdraw_Query"
       fi
    reason="Delta>Min"
    fi
  fi
fi

   # 2k) build display line
    lease_rows+=$(printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%-7.7s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
    "$owner" "$dseq/$gseq/$oseq" "$state" "$action" "$reason" "$bal_usd" "$cost_month"  "$cost_hr" "$cons_usd" "$wd_usd" "$delta_usd" "$denom" "$cost_day" "$cost_per_withdrawal" "$lease_age_days" "\n" "$akash_lease_ns" "\n" "|" "\n"
    )

}

# ── 3) Main Loop: K8s → on‐chain → processor ──────────────────────────────────
echo
echo "$(log_stamp)[Scanning] Provider manifests…"
# read JSON objects into array
mapfile -t manifest_items < <(kubectl -n lease get manifests -o json | jq -c '.items[]')

  if $DEBUG; then
     echo "manifest found locally"
     echo "${manifest_items[@]}"
  fi

for item in "${manifest_items[@]}"; do
  lease_json=$($AKASH_CLI query market lease get \
    --owner "$(jq -r '.metadata.labels."akash.network/lease.id.owner"' <<<"$item")" \
    --dseq  "$(jq -r '.metadata.labels."akash.network/lease.id.dseq"'  <<<"$item")" \
    --gseq  "$(jq -r '.metadata.labels."akash.network/lease.id.gseq"'  <<<"$item")" \
    --oseq  "$(jq -r '.metadata.labels."akash.network/lease.id.oseq"'  <<<"$item")" \
    --provider "$WALLET" --node "$RPC" -o json 2>/dev/null) || {
      echo "$(log_stamp)[Error] failed to fetch lease, skipping" >&2
      continue
    }
  if $DEBUG; then
   echo
   echo "$(log_stamp)[Debug] Raw lease JSON:"
   echo "$lease_json" | yq -P eval
   echo
  fi
  process_lease "$lease_json"
done

  # 4) Optionally execute
  if $EXECUTE; then
        echo "Executing Withdrawal and Kill Lists"

    bash -x <(echo "$WITHDRAW_FILE") || echo "[WARN] WITHDRAW_FILE execution error"
    bash -x <(echo "$KILL_FILE") || echo "[WARN] KILL_FILE execution error"

  fi


echo "[[[[[[[[[]]]]]]]]]]"
echo "[[[[Final Report]]]"
echo "[[[[[[[[[]]]]]]]]]]"
echo
echo "$(log_stamp)[Running Script] --debug=$DEBUG --execute=$EXECUTE --manual=$MANUAL"
echo "$(log_stamp)Wallet: $WALLET | Height: $HEIGHT"
echo "$(log_stamp)USD trigger threshold: \$$MIN_USD_THRESHOLD"
echo "$(log_stamp)AKT price: \$$AKT_PRICE"
echo
echo "Note that all values are USD normalized, except when noted Denom, these will be shown in their native denomination, for practical reasons."
echo "ibc/170 is USDC or to be exact ibc/170C677610AC31DF0904FFE09CD3B5C657492170E7E52372E48756B71E56F2F1 and the other one is sandbox USDC"
echo ""
lease_header=$( printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%-7.7s\t%s\t%s\t%s\n\n" \
  "Owner/Akash_Namespace" "dseq/gseq/oseq" "State" "Action" "Reason" "Balance" "Monthly(USD)" "Hourly" "Consumed" "-Withdrawn" "=Owed_Delta" "Denom" "Daily(Denom)" "Withdrawally(Denom)" "Age_Days" ) \

echo -e "$lease_header\n\n$lease_rows" | column -t


echo
echo "Total leases $lease_count"
echo
echo "$(log_stamp)[Done] Withdrawals → $WITHDRAW_FILE | Kills → $KILL_FILE"
