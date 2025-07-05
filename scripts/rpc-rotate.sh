#!/usr/bin/env bash
# rpc-rotate.sh v2.3.0

set -euo pipefail
export ETCDCTL_API=3

# ── Paths & Config ─────────────────────────────────────────
PALADIN_HOME="${1:-$HOME/akash-provider-paladin}"
CFG="$PALADIN_HOME/provider.yaml"
PRICE="$PALADIN_HOME/price_script_generic.sh"
SCRIPTS="$PALADIN_HOME/scripts"
STATE="$PALADIN_HOME/.last_rpc_rotate"

TODAY=$(date +%F)
MIN_HOURS=3

LOCAL_POD="akash-node-1-0"
LOCAL_NS="akash-services"
LOCAL_ALIAS="http://localhost:26657"

NODE=$(hostname -s)
CA="/etc/ssl/etcd/ssl/ca.pem"
CERT="/etc/ssl/etcd/ssl/node-${NODE}.pem"
KEY="/etc/ssl/etcd/ssl/node-${NODE}-key.pem"
ETCD_FLAGS="--cacert=$CA --cert=$CERT --key=$KEY"

# ── Sync provider.yaml & price_script from etcd ────────────
fetch_and_prep() {
  mkdir -p "$PALADIN_HOME"
  etcdctl $ETCD_FLAGS get /akash-provider-paladin/provider.yaml \
    --print-value-only > "$CFG"
  etcdctl $ETCD_FLAGS get /akash-provider-paladin/price_script_generic.sh \
    --print-value-only > "$PRICE"
  chmod +x "$PRICE"
}

# ── Annotate provider.yaml (if needed) ─────────────────────
annotate_provider_yaml() {
  grep -qF "# RPC node list" "$CFG" || {
    ln=$(grep -nE '^[[:space:]]*#?node:' "$CFG" | head -1 | cut -d: -f1)
    [[ -n "$ln" ]] && {
      sed -i "${ln}i # RPC node list (managed by rpc-rotate.sh)" "$CFG"
      sed -i "${ln}i # Nodes prefixed with ## are skipped permanently" "$CFG"
      sed -i "${ln}i # Local node is probed nightly and may be unblocked" "$CFG"
    }
  }

  grep -qF "RPC Rotation Configuration" "$CFG" || {
    tmp="$(mktemp)"
    {
      echo "# ── RPC Rotation Configuration (managed by rpc-rotate.sh) ──"
      echo
      cat "$CFG"
    } > "$tmp"
    mv "$tmp" "$CFG"
  }
}

# ── Health-check a given RPC node URL ──────────────────────
check_rpc() {
  local status="${1%/}/status" resp catch t0 now
  resp=$(curl -s --max-time 5 "$status") || return 1
  [[ -z $resp ]] && return 1
  catch=$(jq -r .result.sync_info.catching_up <<<"$resp")
  [[ $catch != "false" ]] && return 1
  t0=$(jq -r .result.sync_info.earliest_block_time <<<"$resp")
  t0=$(date -d "$t0" +%s); now=$(date +%s)
  echo $(( (now - t0)/3600 ))
}

# ── Smart circular rotation with pod IP health check ───────
rotate_rpc() {
  local entries active_idx=-1 url line ln_active ln_next hrs ip next_idx probe_url

  mapfile -t entries < <(
    grep -nE '^[[:space:]]*#?node:' "$CFG" |
    grep -v -E '^[[:space:]]*#([[:space:]]*#)+[[:space:]]*node:'
  )

  (( ${#entries[@]} == 0 )) && {
    echo "[rpc] No eligible node entries"
    return 1
  }

  for i in "${!entries[@]}"; do
    [[ "${entries[i]}" =~ ^[0-9]+:[[:space:]]*node: ]] && {
      active_idx=$i; break
    }
  done

  for ((offset=1; offset<=${#entries[@]}; offset++)); do
    next_idx=$(( (active_idx + offset) % ${#entries[@]} ))
    ln_active="${entries[active_idx]%%:*}"
    ln_next="${entries[next_idx]%%:*}"
    line="${entries[next_idx]#*:}"

    [[ $line =~ node:[[:space:]]*\"?([^\"[:space:]]+)\"? ]] || continue
    url="${BASH_REMATCH[1]}"
    probe_url="$url"

    if [[ "$url" =~ localhost || "$url" =~ akash-node-1 ]]; then
      ip=$(kubectl get pod "$LOCAL_POD" -n "$LOCAL_NS" \
           -o jsonpath='{.status.podIP}' 2>/dev/null || echo "")
      if [[ -n "$ip" ]]; then
        echo "[rpc] Substituting $url → $ip for health check"
        probe_url="http://${ip}:26657"
      else
        echo "[rpc] Could not resolve pod IP for akash-node-1-0"
      fi
    fi

    hrs=$(check_rpc "$probe_url") || {
      echo "[rpc] $probe_url failed health check — skipping"
      continue
    }

    echo "[rpc] Activating $url (${hrs}h)"
    (( active_idx >= 0 )) && sed -i "${ln_active}s|^[[:space:]]*node:|#node:|" "$CFG"
    sed -i "${ln_next}s|^[[:space:]]*#[[:space:]]*node:|node:|" "$CFG"

    "$SCRIPTS/update-provider-configuration.sh"
    etcdctl $ETCD_FLAGS put /akash-provider-paladin/provider.yaml < "$CFG"
    etcdctl $ETCD_FLAGS put /akash-provider-paladin/price_script_generic.sh < "$PRICE"
    return 0
  done

  echo "[rpc] ❌ no healthy nodes found"
  return 1
}

# ── Entry Point ─────────────────────────────────────────────
fetch_and_prep
annotate_provider_yaml

if [[ ! -f "$STATE" || "$(cat "$STATE")" != "$TODAY" ]]; then
  echo "[rpc] First run today → prefer local"
  if rotate_rpc; then
    echo "$TODAY" > "$STATE"; exit 0
  fi
  echo "[rpc] Rotation attempt failed on first run"
else
  echo "[rpc] Subsequent run → rotating"
  rotate_rpc
fi
