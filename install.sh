#!/usr/bin/env bash
set -euxo pipefail

# ───────────────────────────────────────────────────────
# Akash Provider Paladin Installer — Control Plane Bootstrap
# ───────────────────────────────────────────────────────

REPO="https://github.com/SGC41/akash-provider-paladin.git"
BRANCH="dev"
TARGET_DIR="$HOME/akash-provider-paladin"
MANIFEST_TEMPLATE="$TARGET_DIR/install/install-cp-pod-template.yaml"
TMP_MANIFEST="/tmp/secondary-cp-install.yaml"

ETCD_CACERT="/etc/ssl/etcd/ssl/ca.pem"
ETCD_CERT="/etc/ssl/etcd/ssl/node-node1.pem"
ETCD_KEY="/etc/ssl/etcd/ssl/node-node1-key.pem"

PROVIDER_SRC="$HOME/provider/provider.yaml"
PRICE_SCRIPT_SRC="$HOME/provider/price_script_generic.sh"

# ───────────────────────────────────────────────────────
# Clone or update repo cleanly
# ───────────────────────────────────────────────────────

if [[ "$PWD" == "$TARGET_DIR"* ]]; then
  echo "⚠️ Running from inside $TARGET_DIR — restarting clean"
  cd "$HOME"
  rm -rf "$TARGET_DIR"
fi

if [[ ! -d "$TARGET_DIR/.git" ]]; then
  echo "📂 Cloning repository..."
  git clone -b "$BRANCH" "$REPO" "$TARGET_DIR"
else
  echo "🔄 Updating existing repo..."
  cd "$TARGET_DIR"
  git fetch origin "$BRANCH"
  git reset --hard "origin/$BRANCH"
fi

cd "$TARGET_DIR"
echo "📌 Working directory: $(pwd)"

# Dynamically select etcd certs based on node shortname
NODE_SHORTNAME=$(hostname -s)

ETCD_CERT="/etc/ssl/etcd/ssl/node-${NODE_SHORTNAME}.pem"
ETCD_KEY="/etc/ssl/etcd/ssl/node-${NODE_SHORTNAME}-key.pem"
ETCD_CACERT="/etc/ssl/etcd/ssl/ca.pem"

# Verify certs exist before proceeding
for FILE in "$ETCD_CERT" "$ETCD_KEY" "$ETCD_CACERT"; do
  [[ -f "$FILE" ]] || { echo "❌ Missing required etcd cert/key: $FILE"; exit 1; }
done


# ───────────────────────────────────────────────────────
# Upload config to etcd
# ───────────────────────────────────────────────────────

echo "💾 Pushing provider.yaml and price_script_generic.sh to etcd..."

[[ -f "$PROVIDER_SRC" ]] || { echo "❌ Missing file: $PROVIDER_SRC"; exit 1; }
[[ -f "$PRICE_SCRIPT_SRC" ]] || { echo "❌ Missing file: $PRICE_SCRIPT_SRC"; exit 1; }

etcdctl put /akash-provider-paladin/provider.yaml \
  --cacert="$ETCD_CACERT" \
  --cert="$ETCD_CERT" \
  --key="$ETCD_KEY" < "$PROVIDER_SRC"

etcdctl put /akash-provider-paladin/price_script_generic.sh \
  --cacert="$ETCD_CACERT" \
  --cert="$ETCD_CERT" \
  --key="$ETCD_KEY" < "$PRICE_SCRIPT_SRC"

# ───────────────────────────────────────────────────────
# Helm install or upgrade
# ───────────────────────────────────────────────────────

echo "🚀 Installing or upgrading Helm chart..."
helm upgrade --install akash-provider-paladin "$TARGET_DIR" \
  --namespace akash-services \
  --create-namespace \
  --set buildID="$(date +%s)"

# ───────────────────────────────────────────────────────
# Deploy install pods to other control plane nodes
# ───────────────────────────────────────────────────────

echo "🛰 Discovering other control planes..."

CURRENT_NODE=$(kubectl get node -o wide | awk -v host="$(hostname)" '$7 == host { print $1 }' || true)

if [[ -z "$CURRENT_NODE" ]]; then
  echo "❌ Could not determine current control plane node name."
  exit 1
fi

CONTROL_PLANES=$(kubectl get nodes -l node-role.kubernetes.io/control-plane --no-headers | awk '{print $1}')

for NODE in $CONTROL_PLANES; do
  if [[ "$NODE" == "$CURRENT_NODE" ]]; then
    echo "🔁 Skipping self: $NODE"
    continue
  fi

  echo "📦 Deploying install pod on: $NODE"
  sed "s|<NODE_NAME>|$NODE|g" "$MANIFEST_TEMPLATE" > "$TMP_MANIFEST"
  kubectl apply -f "$TMP_MANIFEST"
done

echo "✅ All install pods launched on remote control planes."
