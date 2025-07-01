#!/usr/bin/env bash
set -euxo pipefail

# ───────────────────────────────────────────────────────
# Akash Provider Paladin Installer — Control Plane Bootstrap
# Clones repo, pushes config to etcd, installs Helm chart,
# and deploys RPC rotation installer pods to other control planes.
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

echo "🔄 Cloning or updating the Akash Provider Paladin repository..."

if [[ "$PWD" == "$TARGET_DIR" ]]; then
  echo "📍 Already in $TARGET_DIR. Pulling latest changes..."
  git fetch origin "$BRANCH"
  git reset --hard "origin/$BRANCH"
elif [[ ! -d "$TARGET_DIR" ]]; then
  echo "📂 Directory $TARGET_DIR not found. Cloning repository..."
  git clone -b "$BRANCH" "$REPO" "$TARGET_DIR"
  cd "$TARGET_DIR"
else
  echo "📁 Directory exists. Updating repository..."
  cd "$TARGET_DIR"
  git fetch origin "$BRANCH"
  git reset --hard "origin/$BRANCH"
fi

echo "📌 Current working directory: $(pwd)"

echo "💾 Pushing provider.yaml and price_script_generic.sh to etcd..."

if [[ ! -f "$PROVIDER_SRC" ]]; then
  echo "❌ Missing $PROVIDER_SRC"
  exit 1
fi

if [[ ! -f "$PRICE_SCRIPT_SRC" ]]; then
  echo "❌ Missing $PRICE_SCRIPT_SRC"
  exit 1
fi

etcdctl put /akash-provider-paladin/provider.yaml \
  --cacert="$ETCD_CACERT" \
  --cert="$ETCD_CERT" \
  --key="$ETCD_KEY" < "$PROVIDER_SRC"

etcdctl put /akash-provider-paladin/price_script_generic.sh \
  --cacert="$ETCD_CACERT" \
  --cert="$ETCD_CERT" \
  --key="$ETCD_KEY" < "$PRICE_SCRIPT_SRC"

echo "🚀 Installing or upgrading Helm chart..."
helm upgrade --install akash-provider-paladin "$TARGET_DIR" \
  --namespace akash-services \
  --create-namespace \
  --set buildID="$(date +%s)"

# ───────────────────────────────────────────────────────
# 🛰 Distribute install pods to other control plane nodes
# ───────────────────────────────────────────────────────

echo "🛰 Discovering other control planes..."

CURRENT_NODE=$(kubectl get node -o wide | awk -v host="$(hostname)" '$7 == host { print $1 }')
if [[ -z "$CURRENT_NODE" ]]; then
  echo "❌ Could not determine current node name."
  exit 1
fi

CONTROL_PLANES=$(kubectl get nodes -l node-role.kubernetes.io/control-plane --no-headers | awk '{print $1}')

for NODE in $CONTROL_PLANES; do
  if [[ "$NODE" == "$CURRENT_NODE" ]]; then
    echo "🔁 Skipping current node: $NODE"
    continue
  fi

  echo "📦 Deploying install pod on: $NODE"
  sed "s|<NODE_NAME>|$NODE|g" "$MANIFEST_TEMPLATE" > "$TMP_MANIFEST"
  kubectl apply -f "$TMP_MANIFEST"
done

echo "✅ All install pods launched on remote control planes."
