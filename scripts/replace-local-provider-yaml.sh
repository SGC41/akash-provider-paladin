#!/usr/bin/env bash
set -euo pipefail

export ETCDCTL_API=3

# ──────────────────────────────────────────────────────────────
# Akash ETCD Sync Script
# Pulls latest provider.yaml and price_script_generic.sh from ETCD
# and overwrites the local copies at:
#   ~/provider/provider.yaml
#   ~/provider/price_script_generic.sh
# ──────────────────────────────────────────────────────────────

# Configurable paths
LOCAL_DIR="$HOME/provider"
PROVIDER_FILE="$LOCAL_DIR/provider.yaml"
PRICE_SCRIPT_FILE="$LOCAL_DIR/price_script_generic.sh"

# ──────────────────────────────────────────────────────────────
# Dynamically select etcd certs based on node shortname
# ──────────────────────────────────────────────────────────────
NODE_SHORT=$(hostname -s)
ETCD_CACERT="/etc/ssl/etcd/ssl/ca.pem"
ETCD_CERT="/etc/ssl/etcd/ssl/node-${NODE_SHORT}.pem"
ETCD_KEY="/etc/ssl/etcd/ssl/node-${NODE_SHORT}-key.pem"

# Verify cert/key artifacts are present and readable
for f in "$ETCD_CACERT" "$ETCD_CERT" "$ETCD_KEY"; do
  [[ -r "$f" ]] || { echo "❌ Cannot read etcd file: $f" >&2; exit 1; }
done

# ETCD endpoints and flags
ETCD_FLAGS="\
--cacert=$ETCD_CACERT \
--cert=$ETCD_CERT \
--key=$ETCD_KEY \
--print-value-only"

# ── Confirmation Prompt ────────────────────────────────────────
echo "⚠️  WARNING: This will overwrite the following local files with versions from the ETCD cluster:"
echo "   $PROVIDER_FILE"
echo "   $PRICE_SCRIPT_FILE"
echo
read -rp "Are you sure you want to continue? (Y/N): " REPLY
REPLY=${REPLY,,}  # to lowercase

if [[ "$REPLY" != "y" && "$REPLY" != "yes" ]]; then
  echo "❌ Aborted. No files were changed."
  exit 0
fi

echo "🚀 Proceeding with ETCD sync..."

# ── Ensure output directory exists ──────────────────────────────
mkdir -p "$LOCAL_DIR"

# ── Fetch files from ETCD ──────────────────────────────────────
echo "📥 Fetching provider.yaml..."
etcdctl get /akash-provider-paladin/provider.yaml $ETCD_FLAGS > "$PROVIDER_FILE"

echo "📥 Fetching price_script_generic.sh..."
etcdctl get /akash-provider-paladin/price_script_generic.sh $ETCD_FLAGS > "$PRICE_SCRIPT_FILE"
chmod +x "$PRICE_SCRIPT_FILE"

echo "✅ Sync complete. Local files updated."
