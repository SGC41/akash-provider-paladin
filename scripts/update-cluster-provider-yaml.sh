#!/usr/bin/env bash
set -euo pipefail

export ETCDCTL_API=3

# ───────────────────────────────────────────────────────
# Paths to user-edited files
# ───────────────────────────────────────────────────────
PROVIDER_SRC="$HOME/provider/provider.yaml"
PRICE_SCRIPT_SRC="$HOME/provider/price_script_generic.sh"

# ───────────────────────────────────────────────────────
# Dynamically select etcd certs based on node shortname
# ───────────────────────────────────────────────────────
NODE_SHORT=$(hostname -s)
ETCD_CACERT="/etc/ssl/etcd/ssl/ca.pem"
ETCD_CERT="/etc/ssl/etcd/ssl/node-${NODE_SHORT}.pem"
ETCD_KEY="/etc/ssl/etcd/ssl/node-${NODE_SHORT}-key.pem"

# Ensure cert/key artifacts are present and readable
for f in "$ETCD_CACERT" "$ETCD_CERT" "$ETCD_KEY"; do
  [[ -r "$f" ]] || { echo "❌ Cannot read etcd file: $f" >&2; exit 1; }
done

# ───────────────────────────────────────────────────────
# Validate user source files
# ───────────────────────────────────────────────────────
for src in "$PROVIDER_SRC" "$PRICE_SCRIPT_SRC"; do
  if [[ ! -s "$src" ]]; then
    echo "❌ Missing or empty file: $src" >&2
    exit 1
  fi
done

# ───────────────────────────────────────────────────────
# Upload to etcd
# ───────────────────────────────────────────────────────
echo "💾 Uploading provider.yaml to etcd…"
etcdctl \
  --cacert="$ETCD_CACERT" \
  --cert="$ETCD_CERT" \
  --key="$ETCD_KEY" \
  put /akash-provider-paladin/provider.yaml < "$PROVIDER_SRC"

echo "💾 Uploading price_script_generic.sh to etcd…"
etcdctl \
  --cacert="$ETCD_CACERT" \
  --cert="$ETCD_CERT" \
  --key="$ETCD_KEY" \
  put /akash-provider-paladin/price_script_generic.sh < "$PRICE_SCRIPT_SRC"

echo "✅ All updates pushed successfully."
