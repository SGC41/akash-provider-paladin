#!/usr/bin/env bash
set -euo pipefail

# ───────────────────────────────────────────────────────
# Akash Provider Paladin Installer — Control Plane Bootstrap
# v2.5.4
# ───────────────────────────────────────────────────────
REPO="https://github.com/SGC41/akash-provider-paladin.git"
TARGET_DIR="$HOME/akash-provider-paladin"
MANIFEST_TEMPLATE="$TARGET_DIR/install/install-cp-pod-template.yaml"
TMP_MANIFEST="/tmp/secondary-cp-install.yaml"

# ── Dynamic etcd cert detection ──────────────────────────────
NODE_SHORT=$(hostname -s)
ETCD_CACERT="/etc/ssl/etcd/ssl/ca.pem"
ETCD_CERT="/etc/ssl/etcd/ssl/node-${NODE_SHORT}.pem"
ETCD_KEY="/etc/ssl/etcd/ssl/node-${NODE_SHORT}-key.pem"

for f in "$ETCD_CACERT" "$ETCD_CERT" "$ETCD_KEY"; do
  [[ -r "$f" ]] || { echo "❌ Cannot read etcd file: $f" >&2; exit 1; }
done

PROVIDER_SRC="$HOME/provider/provider.yaml"
PRICE_SCRIPT_SRC="$HOME/provider/price_script_generic.sh"

#BRANCH flags

BRANCH="stable" # default
for arg in "$@"; do
  case $arg in
    -b=*|--branch=*)
      BRANCH="${arg#*=}"
      shift
      ;;
  esac
done
echo "🚀 Installing Paladin from branch: $BRANCH"
echo "   Want a different branch use --branch=unstable or such"

# ───────────────────────────────────────────────────────
# Clone or update repo cleanly
# ───────────────────────────────────────────────────────

if [[ "$PWD" == "$TARGET_DIR"* ]]; then
  echo "⚠️ Running from inside $TARGET_DIR — changing to $HOME"
  cd "$HOME"
fi

if [[ ! -d "$TARGET_DIR/.git" ]]; then
  echo "📂 Cloning repository..."
  git clone -b "$BRANCH" "$REPO" "$TARGET_DIR"
else
  echo "🔄 Updating existing repo... custom files and folders will remain"
  cd "$TARGET_DIR"
  git fetch origin "$BRANCH"
  git reset --hard "origin/$BRANCH"
fi

          #prereq shared install - new feature.
          if "$HOME/akash-provider-paladin/install/prereq-install.sh"; then
            echo "Subscript ran successfully"
          else
            echo "Error - prereq install failed"
            exit 1
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



[[ -f "$PROVIDER_SRC" ]] || { echo "❌ Missing file: $PROVIDER_SRC"; exit 1; }
[[ -f "$PRICE_SCRIPT_SRC" ]] || { echo "❌ Missing file: $PRICE_SCRIPT_SRC"; exit 1; }


# ───────────────────────────────────────────────────────
# Check for existing config in etcd and act accordingly
# ───────────────────────────────────────────────────────

KEY="/akash-provider-paladin/provider.yaml"

# Try to fetch the key’s value (silencing stderr)
value=$(etcdctl get "$KEY" \
  --cacert="$ETCD_CACERT" \
  --cert="$ETCD_CERT" \
  --key="$ETCD_KEY" 2>/dev/null)

if [[ -n "$value" ]]; then
  echo "✅ Key exists in etcd at $KEY, pulling it to akash-provider-paladin folder"
  cd $HOME/akash-provider-paladin
  echo "📂 Now in: $(pwd)"
  ls -1

  $HOME/akash-provider-paladin/update-local-provider-yaml.sh

else
  echo "⚠️ Key not found in etcd at $KEY—pushing it now..."
  
  etcdctl put /akash-provider-paladin/provider.yaml \
    --cacert="$ETCD_CACERT" \
    --cert="$ETCD_CERT" \
    --key="$ETCD_KEY" < "$PROVIDER_SRC"

  etcdctl put /akash-provider-paladin/price_script_generic.sh \
    --cacert="$ETCD_CACERT" \
    --cert="$ETCD_CERT" \
    --key="$ETCD_KEY" < "$PRICE_SCRIPT_SRC"

fi

# ______________________________
# Cronjob injection and clean
# _________________________________

echo "[*] installing cronjob on local control plane..."

          CRONLINE_CMD='/bin/bash $HOME/akash-provider-paladin/scripts/rpc-rotate.sh'
          NEW_CRONLINE_CMD='/bin/bash $HOME/akash-provider-paladin/scripts/ticker-control-plane.sh'
          CRONTAB_FILE='/var/spool/cron/crontabs/root'
          NEW_CRONLINE="*/1 * * * * [ -f /tmp/control-plane.do ] && $NEW_CRONLINE_CMD >> /var/log/paladin.log 2>&1 && rm -f /tmp/control>

          sed -i '/akash-provider-paladin/d' /var/spool/cron/crontabs/root && \
          echo "$NEW_CRONLINE" >> "$CRONTAB_FILE"


#old disabled malfunctioning
#CRONLINE="*/1 * * * * [ -f /tmp/control-plane.do ] && /bin/bash \"$TARGET_DIR/scripts/ticker-control-plane.sh\" >> /var/log/paladin.log 2>&1 && rm -f /tmp/control-plane.do"
#SCRIPT_PATH="$TARGET_DIR/scripts/rpc-rotate.sh"

# Remove any existing cron jobs that reference the script (regardless of timing)
#crontab -l 2>/dev/null | grep -v "$SCRIPT_PATH" | { cat; echo "$CRONLINE"; } | crontab -

# ───────────────────────────────────────────────────────


# Discover current node reliably
HOST_SHORT=$(hostname -s)
HOST_FULL=$(hostname)
CURRENT_NODE=""
for H in "$HOST_SHORT" "$HOST_FULL"; do
  CURRENT_NODE=$(kubectl get nodes \
    -l "kubernetes.io/hostname=$H" \
    -o custom-columns=NAME:.metadata.name --no-headers 2>/dev/null || true)
  [[ -n "$CURRENT_NODE" ]] && break
done

if [[ -z "$CURRENT_NODE" ]]; then
  echo "❌ Cannot detect this node’s k8s name" >&2
  exit 1
fi
echo "✔️ Running on: $CURRENT_NODE"


#echo "🚀 Installing or upgrading Helm chart..."
#helm upgrade --install akash-provider-paladin "$TARGET_DIR" \
#  --namespace akash-services \
#  --set buildID="$(date +%s)" \
#&& kubectl delete pod akash-provider-paladin-0 -n akash-services \
#&& echo "Paladin local install completed"

echo "🚀 Installing or upgrading Helm chart..."
#helm upgrade --install akash-provider-paladin "$TARGET_DIR" \
#  --namespace akash-services \
#  --set buildID="$(date +%s)" \
#  --set birthNode="$CURRENT_NODE" \
#  --set affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[0].matchExpressions[0].key=kubernetes.io/hostname \
#  --set affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[0].matchExpressions[0].operator=In \
#  --set affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[0].matchExpressions[0].values[0]="$CURRENT_NODE" \
#&& kubectl delete pod akash-provider-paladin-0 -n akash-services \
helm upgrade --install akash-provider-paladin "$TARGET_DIR" \
  --namespace akash-services \
  --set buildID="$(date +%s)" \
  --set birthNode="$CURRENT_NODE" \
  \
  # Hard requirement: must be a control-plane node
  --set affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[0].matchExpressions[0].key=node-role.kubernetes.io/control-plane \
  --set affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[0].matchExpressions[0].operator=Exists \
  \
  # Soft preference: strongly prefer the birth node
  --set affinity.nodeAffinity.preferredDuringSchedulingIgnoredDuringExecution[0].weight=100 \
  --set affinity.nodeAffinity.preferredDuringSchedulingIgnoredDuringExecution[0].preference.matchExpressions[0].key=kubernetes.io/hostname \
  --set affinity.nodeAffinity.preferredDuringSchedulingIgnoredDuringExecution[0].preference.matchExpressions[0].operator=In \
  --set affinity.nodeAffinity.preferredDuringSchedulingIgnoredDuringExecution[0].preference.matchExpressions[0].values[0]="$CURRENT_NODE" \
&& kubectl delete pod akash-provider-paladin-0 -n akash-services \

&& echo "Paladin local install completed"


# ───────────────────────────────────────────────────────
# Pre-deploy cleanup: remove any existing installer pods
# ───────────────────────────────────────────────────────

echo "🧹 Cleaning up any Pending installer pods…"
kubectl delete pods \
  -n akash-services \
  -l app=paladin-installer \
  --ignore-not-found

# ───────────────────────────────────────────────────────
# Deploy install pods to control-plane nodes (as before)
# ───────────────────────────────────────────────────────
echo "🛰 Deploying installer pods to each control plane…"

# Fetch all control-plane nodes
CONTROL_PLANES=$(kubectl get nodes \
  -l node-role.kubernetes.io/control-plane \
  -o custom-columns=NAME:.metadata.name --no-headers)

# Apply installer to every other control-plane
for NODE in $CONTROL_PLANES; do
  if [[ "$NODE" == "$CURRENT_NODE" ]]; then
    echo "🔁 Skipping self: $NODE"
    continue
  fi

  POD_NAME="install-secondary-cp-$NODE"
  echo "📦 Deploying $POD_NAME on $NODE"

  sed -e "s|<NODE_NAME>|$NODE|g" \
      -e "s|install-secondary-cp-<NODE_NAME>|$POD_NAME|g" \
      "$MANIFEST_TEMPLATE" > "$TMP_MANIFEST"

  kubectl apply -f "$TMP_MANIFEST"
done

echo "✅ All installer pods launched in akash-services namespace."
