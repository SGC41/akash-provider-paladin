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

PALADIN_HOME="${1:-$HOME/akash-provider-paladin}"
FILE="$PALADIN_HOME/provider.yaml"
PRICE_SCRIPT_FILE="$PALADIN_HOME/price_script_generic.sh"
SCRIPT_DIR="$PALADIN_HOME/scripts/"
PROVIDER_HOME="$HOME/provider"
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

# _____________________________________________________
# ── Ensure $PALADIN_HOME and $PROVIDER_HOME exists and required files are present ───────────────
# _____________________________________________________

echo "🧩 Verifying local configuration files in $PALADIN_HOME..."

mkdir -p "$PALADIN_HOME"
mkdir -p "$PROVIDER_HOME"

NEEDS_REFRESH=false

if [[ ! -s "$FILE" ]]; then
  echo "🔍 provider.yaml is missing or empty. Will re-fetch from etcd."
  NEEDS_REFRESH=true
fi

if [[ ! -s "$PRICE_SCRIPT_FILE" ]]; then
  echo "🔍 price_script_generic.sh is missing or empty. Will re-fetch from etcd."
  NEEDS_REFRESH=true
fi

# Ensure price_script_generic.sh is executable
if [[ -f "$PRICE_SCRIPT_FILE" && ! -x "$PRICE_SCRIPT_FILE" ]]; then
  echo "🔧 Making price_script_generic.sh executable..."
  chmod +x "$PRICE_SCRIPT_FILE"
fi

# Re-fetch files from etcd if needed
if $NEEDS_REFRESH; then
  echo "♻️  Fetching missing config files from etcd..."

  echo "📥 Fetching provider.yaml…"
  etcdctl get /akash-provider-paladin/provider.yaml $ETCD_FLAGS > "$FILE"

  echo "📥 Fetching price_script_generic.sh…"
  etcdctl get /akash-provider-paladin/price_script_generic.sh $ETCD_FLAGS > "$PRICE_SCRIPT_FILE"
  chmod +x "$PRICE_SCRIPT_FILE"
fi

# Copy critical files to $PROVIDER_HOME if missing
[[ -f "$PROVIDER_HOME/provider.yaml" ]] || cp "$FILE" "$PROVIDER_HOME/provider.yaml"
[[ -f "$PROVIDER_HOME/price_script_generic.sh" ]] || cp "$PRICE_SCRIPT_FILE" "$PROVIDER_HOME/price_script_generic.sh"

# Copy update* scripts from local scripts dir to provider home if missing
if [[ -d "$SCRIPT_DIR" ]]; then
  for update_script in "$SCRIPT_DIR"/update*; do
    [[ -f "$update_script" ]] || continue
    base_name="$(basename "$update_script")"
    target_path="$PROVIDER_HOME/$base_name"

    if [[ ! -f "$target_path" ]]; then
      cp "$update_script" "$target_path"
      echo "➕ copied $base_name to $PROVIDER_HOME"
    fi
  done
else
  echo "⚠️  Script source directory $SCRIPT_DIR not found — skipping update* copy"
fi

# __________________________


# _________________________________________________________________________
# ── Check ETCD configuration files and error exit if missing ───────────────
#_________________________________________________________________________

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



# ── Helm bootstrap ───────────────────────────────────────────
echo "starting checking helm"

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

echo "helm segment done"

# __________________________
# 
# --local flag part +
# local rpc node health logic check, wants 3hours of stability synced status...
# if verified good will set as active in ~/akash_provider_paladin/provider.yaml
# and rpc rotation will be done, in later code block
#
# needs improvements.
# ______________________________
echo "Checking local RPC for viability"

# 🌐 Define target pod and namespace
POD_NAME="akash-node-1-0"
NAMESPACE="akash-services"

# 🛜 Get pod IP from Kubernetes
RPC_IP=$(kubectl get pod "$POD_NAME" -n "$NAMESPACE" -o jsonpath='{.status.podIP}')

if [[ -z "$RPC_IP" ]]; then
  echo "[rpc] ❌ Pod IP not found — is the pod running?"
  exit 1
fi

# 🧪 Query the node's /status endpoint
STATUS_URL="http://${RPC_IP}:26657/status"
RESPONSE=$(curl -s --max-time 5 "$STATUS_URL")

if [[ -z "$RESPONSE" ]]; then
  echo "[rpc] ❌ No response from node at $RPC_IP:26657"
  exit 1
fi

# 📆 Extract sync info
CATCHING_UP=$(echo "$RESPONSE" | jq -r '.result.sync_info.catching_up')
STARTED_AT=$(echo "$RESPONSE" | jq -r '.result.sync_info.earliest_block_time')

if [[ "$CATCHING_UP" != "false" ]]; then
  echo "[rpc] ⚠️ Node is still catching up — not considered stable"
  exit 0
fi

# ⏱️ Calculate uptime in hours
STARTED_SEC=$(date -d "$STARTED_AT" +%s)
NOW_SEC=$(date +%s)
UPTIME_HR=$(( (NOW_SEC - STARTED_SEC) / 3600 ))

echo "[rpc] ✅ Node has been synced since $STARTED_AT"
echo "[rpc] ⏱️ RPC node has been stable for ~${UPTIME_HR} hours"
echo "local rpc viable"

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
