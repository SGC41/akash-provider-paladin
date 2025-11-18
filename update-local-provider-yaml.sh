#!/bin/bash
#
#  v2.11.21

set -uo pipefail

source "$HOME/akash-provider-paladin/scripts/default.conf"
if [[ $CLUSTER != TRUE ]]; then
  echo "This script is for HA cluster control planes only"
  exit 0
fi


PROVIDER_SRC="$HOME/akash-provider-paladin/provider.yaml"
PRICE_SCRIPT_SRC="$HOME/akash-provider-paladin/price_script_generic.sh"

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
# Download from etcd
# ───────────────────────────────────────────────────────
echo "💾 Downloading provider.yaml and price_script_generic.sh from etcd…"
# auto-detect etcd TLS certs
NODE_SHORT=$(hostname -s)
GET_FLAGS="\
--cacert=/etc/ssl/etcd/ssl/ca.pem \
--cert=/etc/ssl/etcd/ssl/node-${NODE_SHORT}.pem \
--key=/etc/ssl/etcd/ssl/node-${NODE_SHORT}-key.pem \
--print-value-only"

# ── HELPERS ─────────────────────────────────────────────────

  echo "[rpc] Fetching provider.yaml & price script from etcd"
  etcdctl get /akash-provider-paladin/provider.yaml  $GET_FLAGS  > "$PROVIDER_SRC"
  etcdctl get /akash-provider-paladin/price_script_generic.sh  $GET_FLAGS  > "$PRICE_SCRIPT_SRC"
  chmod +x "$PRICE_SCRIPT_SRC"

echo "✅ Sync complete. Local files updated."

