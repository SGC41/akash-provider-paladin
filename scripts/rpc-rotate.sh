#!/usr/bin/env bash
set -euo pipefail

export ETCDCTL_API=3

# ──────────────────────────────────────────────────────────────
# rpc-rotate.sh
# Rotates the active `node:` entry in provider.yaml,
# injects RPC-rotation comments and public fallbacks,
# supports “--local” revert-to-local mode.
# ──────────────────────────────────────────────────────────────

# ── Arg parsing ──────────────────────────────────────────────
LOCAL_MODE=false
if [[ "${1:-}" == "--local" ]]; then
  LOCAL_MODE=true
  shift
fi

PROVIDER_HOME="${1:-$HOME/akash-provider-paladin}"
FILE="$PROVIDER_HOME/provider.yaml"
PRICE_SCRIPT_FILE="$PROVIDER_HOME/price_script_generic.sh"
SCRIPT_DIR="$PROVIDER_HOME/scripts/"
DATE_TAG="$(date +%m-%d)"
BACKUP="$FILE.$DATE_TAG"

# ── Dynamic etcd cert detection ──────────────────────────────
NODE_SHORT=$(hostname -s)
ETCD_CACERT="/etc/ssl/etcd/ssl/ca.pem"
ETCD_CERT="/etc/ssl/etcd/ssl/node-${NODE_SHORT}.pem"
ETCD_KEY="/etc/ssl/etcd/ssl/node-${NODE_SHORT}-key.pem"

for f in "$ETCD_CACERT" "$ETCD_CERT" "$ETCD_KEY"; do
  [[ -r "$f" ]] || { echo "❌ Cannot read etcd file: $f" >&2; exit 1; }
done

ETCD_FLAGS="\
--cacert=${ETCD_CACERT} \
--cert=${ETCD_CERT} \
--key=${ETCD_KEY} \
--print-value-only"

# ── Ensure local directory exists ────────────────────────────
mkdir -p "$PROVIDER_HOME"


# ── Check ETCD configuration files and error exit if missing ───────────────
echo "🧪 Checking etcd for provider.yaml…"
if ! etcdctl get /akash-provider-paladin/provider.yaml $ETCD_FLAGS --print-value-only | grep -q .; then
  echo "⚠️  etcd missing provider.yaml — ending RPC rotate script" ; exit 1
fi

echo "🧪 Checking etcd for price_script_generic.sh…"
if ! etcdctl get /akash-provider-paladin/price_script_generic.sh $ETCD_FLAGS --print-value-only | grep -q .; then
  echo "⚠️  etcd missing price_script_generic.sh — ending RPC rotate script" ; exit 1
fi

# ── Fetch current configs from ETCD ──────────────────────────
echo "📥 Fetching provider.yaml…"
etcdctl get /akash-provider-paladin/provider.yaml $ETCD_FLAGS > "$FILE"

echo "📥 Fetching price_script_generic.sh…"
etcdctl get /akash-provider-paladin/price_script_generic.sh $ETCD_FLAGS > "$PRICE_SCRIPT_FILE"
chmod +x "$PRICE_SCRIPT_FILE"



# ── “--local” revert logic ──────────────────────────────────# ── Helm bootstrap ───────────────────────────────────────────
HELM_VERSION="v3.11.0"
REQUIRED_HELM_BIN="/usr/local/bin/helm"

check_helm() {
  if ! command -v helm &>/dev/null; then
    echo "[helm] Not found — installing Helm $HELM_VERSION..."
    install_helm
  else
    local current_ver
    current_ver="$(helm version --short 2>/dev/null | sed 's/^v//' | cut -d+ -f1)"
    # Compare major.minor only for sanity
    if [[ "$current_ver" =~ ^3\.[0-9]+$ ]]; then
      echo "[helm] Found Helm $current_ver — skipping install"
      return
    fi
    echo "[helm] Unexpected Helm version '$current_ver' — reinstalling $HELM_VERSION..."
    install_helm
  fi
}

install_helm() {
  cd /tmp
  wget -q "https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz"
  tar -xzf "helm-${HELM_VERSION}-linux-amd64.tar.gz"
  install linux-amd64/helm "$REQUIRED_HELM_BIN"
  rm -rf linux-amd64 "helm-${HELM_VERSION}-linux-amd64.tar.gz"
  echo "[helm] Installed Helm $HELM_VERSION at $REQUIRED_HELM_BIN"
}

# Initialize Akash Helm repo cleanly
check_helm
helm repo remove akash &>/dev/null || true
helm repo add akash https://akash-network.github.io/helm-charts

#helm check and or install done

if [[ "$LOCAL_MODE" == true ]]; then
  echo "[rpc][local] revert mode: probing local RPC…"
  if curl --fail --silent --max-time 3 http://localhost:26657/status \
       | grep -q '"catching_up": false'; then

    now=$(date +%s)
    TS_FILE="/tmp/local_rpc_healthy_since"

    if [[ ! -f "$TS_FILE" ]]; then
      echo "$now" > "$TS_FILE"
      echo "[rpc][local] first healthy stamp at $(date -d "@$now")"
      exit 0
    fi

    last=$(<"$TS_FILE")
    elapsed=$(( now - last ))

    if (( elapsed >= 3*3600 )); then
      echo "[rpc][local] healthy for $((elapsed/3600))h — reverting to local RPC"
      # comment out all node: lines
      mapfile -t lines < <(
        grep -En '^[[:space:]]*#?node:' "$FILE" | grep -v '^[[:space:]]*##'
      )
      for entry in "${lines[@]}"; do
        ln="${entry%%:*}"
        sed -i "${ln}s|^[[:space:]]*node:|#node:|" "$FILE"
      done
      # unblock your local node
      ln=$(
        grep -En "^#?node:.*localhost.*localnode" "$FILE" \
        | head -n1 | cut -d: -f1
      )
      if [[ -n "$ln" ]]; then
        sed -i "${ln}s|^#node:|node:|" "$FILE"
        echo "[rpc][local] activated localnode (line $ln)"
      else
        echo "[rpc][local] ⚠️  no localnode entry found"
      fi

      rm -f "$TS_FILE"
      "$SCRIPT_DIR/update-provider-configuration.sh"
      exit 0
    else
      remain=$(( (3*3600 - elapsed)/60 ))
      echo "[rpc][local] warming up: $remain min until revert"
      exit 0
    fi
  else
    echo "[rpc][local] probe failed — resetting timer"
    rm -f /tmp/local_rpc_healthy_since
    exit 0
  fi
fi

# ── Daily backup ────────────────────────────────────────────
if [[ ! -e "$BACKUP" ]]; then
  cp "$FILE" "$BACKUP"
  echo "🛡️  backed up to $BACKUP"
else
  echo "🛡️  backup exists: $BACKUP"
fi

# ── Top-level header injection ──────────────────────────────
if ! grep -qF "RPC Rotation Configuration" "$FILE"; then
  tmp="$(mktemp)"
  {
    echo "# ── RPC Rotation Configuration (managed by rpc-rotate.sh) ──"
    echo
    cat "$FILE"
  } > "$tmp"
  mv "$tmp" "$FILE"
  echo "✏️  inserted top-level header"
else
  echo "✅ header already present"
fi

# ── Node list header & skip comments ───────────────────────
if ! grep -qF "# RPC node list" "$FILE"; then
  first_line=$(
    grep -nE '^[[:space:]]*#?node:' "$FILE" \
      | head -n1 | cut -d: -f1
  )
  if [[ -n "$first_line" ]]; then
    sed -i "${first_line}i # RPC node list (managed by rpc-rotate.sh)" "$FILE"
    sed -i "${first_line}i # Nodes prefixed with ## are skipped permanently" "$FILE"
    sed -i "${first_line}i # Local node is probed nightly and may be unblocked" "$FILE"
    echo "✏️  inserted node-list header"
  fi
else
  echo "✅ node-list header already present"
fi

# ── Public fallback injection ───────────────────────────────
fallbacks=(
  "https://rpc-akash.ecostake.com:443"
  "https://akash-rpc.europlots.com:443"
  "https://akash-rpc.polkachu.com:443"
  "https://rpc.akashnet.net:443"
)
last_line=$(
  grep -En '^[[:space:]]*#?node:' "$FILE" \
    | tail -n1 | cut -d: -f1
)
for url in "${fallbacks[@]}"; do
  if ! grep -qF "$url" "$FILE"; then
    sed -i "$((last_line+1))i #node: $url" "$FILE"
    echo "➕ inserted fallback: $url"
    last_line=$((last_line+1))
  fi
done

# ── Rotation logic ─────────────────────────────────────────
mapfile -t nodes < <(
  grep -En '^[[:space:]]*#?node:' "$FILE" | grep -v '^[[:space:]]*##'
)
if (( ${#nodes[@]} == 0 )); then
  echo "❌ no node: entries in $FILE" >&2
  exit 1
fi

active=-1
for i in "${!nodes[@]}"; do
  if [[ ${nodes[$i]} =~ ^([0-9]+):[[:space:]]*node: ]]; then
    active=$i
    break
  fi
done

next=0
(( active >= 0 )) && next=$(( (active + 1) % ${#nodes[@]} ))

# comment out all
for entry in "${nodes[@]}"; do
  ln="${entry%%:*}"
  sed -i "${ln}s|^[[:space:]]*node:|#node:|" "$FILE"
done

# activate next
ln="${nodes[$next]%%:*}"
sed -i "${ln}s|^#node:|node:|" "$FILE"
echo "🔁 rotated to line $ln"

"$SCRIPT_DIR/update-provider-configuration.sh"

# ── Push updated config back to etcd ─────────────────────────
echo "[rpc] uploading updated provider.yaml…"
etcdctl --cacert="$ETCD_CACERT" \
        --cert="$ETCD_CERT" \
        --key="$ETCD_KEY" \
        put /akash-provider-paladin/provider.yaml < "$FILE"

echo "[rpc] uploading updated price_script_generic.sh…"
etcdctl --cacert="$ETCD_CACERT" \
        --cert="$ETCD_CERT" \
        --key="$ETCD_KEY" \
        put /akash-provider-paladin/price_script_generic.sh < "$PRICE_SCRIPT_FILE"

echo "[rpc] etcd update complete ✅"
