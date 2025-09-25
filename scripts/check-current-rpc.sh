#!/usr/bin/env bash
# v2.9.1

log_stamp() {
  echo "[$(date -u +"%Y-%m-%d %H:%M:%S")]"
}


echo "$(log_stamp) [log] - checking akash-provider-rpc.conf - paladin rpc memory"

check_rpc() {
  local status="${1%/}/status" resp catch t0 now
  resp=$(curl -s --max-time 5 "$status") || return 1
  [[ -z $resp ]] && return 1
  catch=$(jq -r .result.sync_info.catching_up <<<"$resp")
  [[ $catch != "false" ]] && return 1
  t0=$(jq -r .result.sync_info.earliest_block_time <<<"$resp")
  t0=$(date -d "$t0" +%s); now=$(date +%s)
  echo $(( (now - t0) / 3600 ))
}

RAW=$(kubectl exec -n akash-services akash-provider-0 -c provider -- \
  printenv AKASH_NODE 2>/dev/null)

stored_rpc_node_url="blank"

echo "$(log_stamp) [log] - Pulled RPC NODE $RAW"

  if [[ "$RAW" == "http://akash-node-1:26657" ]]; then
    echo "$(log_stamp) [log] - Local RPC detected, getting ip"
    # ── Fetch provider host_uri from blockchain ────────────────
    NODE_IP=$(kubectl -n akash-services get ep akash-node-1 -o jsonpath='{.subsets[0].addresses[0].ip}')
    probe_url="http://${NODE_IP}:26657"
  else
    probe_url="$RAW"
  fi

echo "$(log_stamp) [log] - $probe_url"
[ -f /tmp/akash-provider-rpc.conf ] && stored_rpc_node_url=$(< /tmp/akash-provider-rpc.conf) && echo "$(log_stamp) [log] - Found RPC file, loading"
if [[ "$stored_rpc_node_url" != "$probe_url" ]]; then
          echo "$(log_stamp) [log] - paladin tmp stored rpc not same as current, updating tmp/akash-provider-rpc.conf"
          echo "$probe_url" > /tmp/akash-provider-rpc.conf
else
echo "$(log_stamp) [log] - akash-provider-rpc.conf verified"
fi

