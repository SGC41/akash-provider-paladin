#!/usr/bin/env bash
set -euo pipefail

# ──────────────────────────────────────────────────────────────
# Akash ETCD Sync Script
# Pulls latest provider.yaml and price_script_generic.sh from ETCD
# and overwrites the local copies at:
#   ~/provider/provider.yaml
#   ~/provider/price_script_generic.sh
# ──────────────────────────────────────────────────────────────

# Configurable paths
LOCAL_DIR=~/provider
PROVIDER_FILE="$LOCAL_DIR/provider.yaml"
PRICE_SCRIPT_FILE="$LOCAL_DIR/price_script_generic.sh"

# ETCD Auth Flags
ETCD_FLAGS="\
--endpoints=https://127.0.0.1:2379 \
--cacert=/etc/ssl/etcd/ssl/ca.pem \
--cert=/etc/ssl/etcd/ssl/node-node1.pem \
--key=/etc/ssl/etcd/ssl/node-node1-key.pem \
--print-value-only"

# ── Confirmation Prompt ────────────────────────────────────────

echo "⚠️  WARNING: This will overwrite the following local files with versions from the ETCD cluster:"
echo "   $PROVIDER_FILE"
echo "   $PRICE_SCRIPT_FILE"
echo
read -rp "Are you sure you want to continue? (Y/N): " REPLY
REPLY=${REPLY,,}  # Convert to lowercase for safety

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

echo "✅ Sync complete. Local files updated."
