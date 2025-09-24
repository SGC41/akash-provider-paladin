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

if [[ -z "$RAW" ]]; then
  echo "No AKASH_NODE_1_PORT_26657_TCP found"
  exit 1
fi

HOST=$(echo "$RAW" | sed -E 's#^tcp://([^:]+):([0-9]+)$#\1#')
PORT=$(echo "$RAW" | sed -E 's#^tcp://([^:]+):([0-9]+)$#\2#')

if [[ "$PORT" == "26657" ]]; then
  SCHEME="http"
elif [[ "$PORT" == "440" ]]; then
  SCHEME="https"
else
  SCHEME="http"
fi

probe_url="${SCHEME}://${HOST}:${PORT}"
echo "$probe_url"

hrs=$(check_rpc "$probe_url") || {
  echo "[rpc] $probe_url failed health check — skipping"
  exit 1
}

echo "[rpc] Activating $probe_url RPC node Synced for (${hrs}h)"
