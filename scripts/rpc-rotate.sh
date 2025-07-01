#!/usr/bin/env bash
set -euo pipefail

# rpc-rotate.sh
# Rotates the active `node:` entry in provider.yaml,
# injects RPC-rotation comments and public fallbacks,
# and supports a “--local” mode to revert to your local RPC.

#grab current provider.yaml and price script
etcdctl get /akash-provider-paladin/provider.yaml > ~/akash-provider-paladin/provider/provider.yaml \
  --cacert=/etc/ssl/etcd/ssl/ca.pem \
  --cacert=/etc/ssl/etcd/ssl/ca.pem \
  --cert=/etc/ssl/etcd/ssl/node-node1.pem \
  --key=/etc/ssl/etcd/ssl/node-node1-key.pem \
  --print-value-only

etcdctl get /akash-provider-paladin/price_script_generic.sh > ~/akash-provider-paladin/provider/price_script_generic.sh \
  --cacert=/etc/ssl/etcd/ssl/ca.pem \
  --cacert=/etc/ssl/etcd/ssl/ca.pem \
  --cert=/etc/ssl/etcd/ssl/node-node1.pem \
  --key=/etc/ssl/etcd/ssl/node-node1-key.pem \
  --print-value-only

# ─── Arg parsing ─────────────────────────────────────
LOCAL_MODE=false
if [[ "${1:-}" == "--local" ]]; then
  LOCAL_MODE=true
  shift
fi

# ─── Configuration ────────────────────────────────────
PROVIDER_HOME="${1:-$HOME/provider}"
FILE="$PROVIDER_HOME/provider.yaml"
DATE_TAG="$(date +%m-%d)"
BACKUP="$FILE.$DATE_TAG"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Local-RPC recovery settings
LOCAL_NODE_NAME="localnode"                   # adjust if yours is named differently
HEALTH_TIMESTAMP_FILE="/tmp/local_rpc_healthy_since"
MIN_HEALTH_DURATION=$((3 * 3600))             # 3 h
# ──────────────────────────────────────────────────────

# 1) Sanity check
if [[ ! -f "$FILE" ]]; then
  echo "❌ ERROR: cannot find $FILE" >&2
  exit 1
fi

# 2) “--local” revert logic
if [[ "$LOCAL_MODE" == true ]]; then
  echo "[rpc][local] revert mode: probing local RPC…"

  # a) Health + sync check
  if curl --fail --silent --max-time 3 http://localhost:26657/status \
       | grep -q '"catching_up": false'; then

    now=$(date +%s)

    # b) First healthy stamp?
    if [[ ! -f "$HEALTH_TIMESTAMP_FILE" ]]; then
      echo "$now" > "$HEALTH_TIMESTAMP_FILE"
      echo "[rpc][local] first healthy stamp at $(date -d "@$now")"
      exit 0
    fi

    last=$(<"$HEALTH_TIMESTAMP_FILE")
    elapsed=$(( now - last ))

    # c) Healthy ≥ 3 h → revert
    if (( elapsed >= MIN_HEALTH_DURATION )); then
      echo "[rpc][local] healthy for $((elapsed/3600)) h—reverting to local RPC"

      # comment out all candidate lines
      mapfile -t all_nodes < <(
        grep -En '^[[:space:]]*#?node:' "$FILE" | grep -v '^[[:space:]]*##'
      )
      for entry in "${all_nodes[@]}"; do
        ln="${entry%%:*}"
        sed -i "${ln}s|^[[:space:]]*node:|#node:|" "$FILE"
      done

      # find & uncomment your localnode line
      line=$(
        grep -En "^#?node:.*localhost.*${LOCAL_NODE_NAME}" "$FILE" \
        | head -n1 | cut -d: -f1
      )
      if [[ -n "$line" ]]; then
        sed -i "${line}s|^#node:|node:|" "$FILE"
        echo "[rpc][local] activated localnode (line $line)"
      else
        echo "[rpc][local] ⚠️  localnode entry not found—no changes made"
      fi

      rm -f "$HEALTH_TIMESTAMP_FILE"
      "$SCRIPT_DIR/update-provider-configuration.sh"
      exit 0

    else
      remain=$(( (MIN_HEALTH_DURATION - elapsed) / 60 ))
      echo "[rpc][local] warming up: $remain min until eligible"
      exit 0
    fi

  else
    echo "[rpc][local] probe failed—resetting timer"
    rm -f "$HEALTH_TIMESTAMP_FILE"
    exit 0
  fi
fi

# 3) Daily backup (no overwrite)
if [[ ! -e "$BACKUP" ]]; then
  cp "$FILE" "$BACKUP"
  echo "🛡️  backed up original to $BACKUP"
else
  echo "🛡️  backup already exists: $BACKUP"
fi

# 4) Top-level RPC rotation config (prepend once)
if ! grep -qF "RPC Rotation Configuration" "$FILE"; then
  tmp="$(mktemp)"
  {
    echo "# ────────────────────────────────────────────"
    echo "# RPC Rotation Configuration"
    echo "# Managed by Akash-Provider-Paladin"
    echo "# Rotates active node entries and injects fallbacks"
    echo "# ────────────────────────────────────────────"
    echo
    cat "$FILE"
  } > "$tmp"
  mv "$tmp" "$FILE"
  echo "✏️  inserted top-level RPC rotation config block"
else
  echo "✅ top-level RPC rotation config already present"
fi

# 5) Inject header + skip comments above first node: (once)
if ! grep -qF "# RPC node list" "$FILE"; then
  first_line=$(
    grep -nE '^[[:space:]]*#?node:' "$FILE" \
      | head -n1 | cut -d: -f1
  )
  if [[ -n "$first_line" ]]; then
    sed -i "${first_line}i # RPC node list (managed by Paladin Script rpc-rotate.sh)" "$FILE"
    sed -i "${first_line}i # RPC nodes starting with ## are permanently skipped in rotation." "$FILE"
    sed -i "${first_line}i # Local RPC node is checked at 3am local time and if good, will be activated" "$FILE"
    echo "✏️  inserted header + skip comments above node lines"
  else
    echo "⚠️  no node: lines found—skipping header injection"
  fi
else
  echo "✅ header + skip comments already present"
fi

# 6) Ensure public RPC fallbacks
fallbacks=(
  "https://rpc-akash.ecostake.com:443"
  "https://akash-rpc.europlots.com:443"
  "https://akash-rpc.polkachu.com:443"
  "https://rpc.akashnet.net:443"
)
last_node_line=$(
  grep -En '^[[:space:]]*#?node:' "$FILE" | tail -n1 | cut -d: -f1
)
if [[ -n "$last_node_line" ]]; then
  for url in "${fallbacks[@]}"; do
    if ! grep -qF "$url" "$FILE"; then
      sed -i "$((last_node_line+1))i #node: $url" "$FILE"
      echo "➕ inserted fallback node: $url"
      last_node_line=$((last_node_line+1))
    fi
  done
else
  echo "⚠️  no node: lines found—skipping fallback insertion"
fi

# 7) Rotation logic
mapfile -t nodes < <(
  grep -En '^[[:space:]]*#?node:' "$FILE" | grep -v '^[[:space:]]*##'
)
if (( ${#nodes[@]} == 0 )); then
  echo "❌ ERROR: no node: lines found in $FILE" >&2
  exit 1
fi

active=-1
for i in "${!nodes[@]}"; do
  if [[ ${nodes[$i]} =~ ^([0-9]+):[[:space:]]*node: ]]; then
    active=$i; break
  fi
done
next=0
if (( active >= 0 )); then
  next=$(( (active + 1) % ${#nodes[@]} ))
fi

for entry in "${nodes[@]}"; do
  ln="${entry%%:*}"
  sed -i "${ln}s|^[[:space:]]*node:|#node:|" "$FILE"
done

ln="${nodes[$next]%%:*}"
sed -i "${ln}s|^#node:|node:|" "$FILE"

echo "🔁 rotated RPC node in $FILE (activated line $ln)"
"$SCRIPT_DIR/update-provider-configuration.sh"

echo "[rpc] pushing updated files back to etcd..."

etcdctl put /akash-provider-paladin/provider.yaml "$(cat ~/akash-provider-paladin/provider.yaml)" \
  --cacert=/etc/ssl/etcd/ssl/ca.pem \
  --cacert=/etc/ssl/etcd/ssl/ca.pem \
  --cert=/etc/ssl/etcd/ssl/node-node1.pem \
  --key=/etc/ssl/etcd/ssl/node-node1-key.pem

etcdctl put /akash-provider-paladin/price_script_generic.sh "$(cat ~/akash-provider-paladin/price_script_generic.sh)" \
  --cacert=/etc/ssl/etcd/ssl/ca.pem \
  --cacert=/etc/ssl/etcd/ssl/ca.pem \
  --cert=/etc/ssl/etcd/ssl/node-node1.pem \
  --key=/etc/ssl/etcd/ssl/node-node1-key.pem

echo "[rpc] etcd update complete ✅"
