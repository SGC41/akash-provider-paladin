#!/usr/bin/env bash

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
  printenv AKASH_NODE_1_PORT_26657_TCP 2>/dev/null)

# If the variable is empty, bail out
if [[ -z "$RAW" ]]; then
  echo "No AKASH_NODE_1_PORT_26657_TCP found"
  exit
fi

# Extract host and port from tcp://host:port
HOST=$(echo "$RAW" | sed -E 's#^tcp://([^:]+):([0-9]+)$#\1#')
PORT=$(echo "$RAW" | sed -E 's#^tcp://([^:]+):([0-9]+)$#\2#')

# Decide scheme based on port
if [[ "$PORT" == "26657" ]]; then
  SCHEME="http"
elif [[ "$PORT" == "440" ]]; then
  SCHEME="https"
else
  SCHEME="http"   # default fallback
fi


echo "${SCHEME}://${HOST}:${PORT}"
check_rpc "${SCHEME}://${HOST}:${PORT}"

 hrs=$(check_rpc "$probe_url") || {
      echo "$(log_stamp)[rpc] $probe_url failed health check — skipping"
      (( force_next_idx >= 0 )) && return 1
      continue
    }

    echo "$(log_stamp)[rpc] Activating $url RPC node Synced for (${hrs}h)"
