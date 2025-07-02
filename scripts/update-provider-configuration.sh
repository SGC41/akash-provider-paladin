#!/bin/bash
#
#  v2.2.5

set -euo pipefail

DEFAULT_HOME="$HOME/akash-provider-paladin"
CURRENT_DIR="$(pwd)"

PROVIDER_YAML="$DEFAULT_HOME/provider.yaml"
PRICE_SCRIPT="$DEFAULT_HOME/price_script_generic.sh"

# Override if run from a folder containing provider.yaml and price script
if [[ -f "$CURRENT_DIR/provider.yaml" && -f "$CURRENT_DIR/price_script_generic.sh" ]]; then
  PROVIDER_YAML="$CURRENT_DIR/provider.yaml"
  PRICE_SCRIPT="$CURRENT_DIR/price_script_generic.sh"
  echo "⚙️  Running in local override mode from $CURRENT_DIR"
fi

cd "$DEFAULT_HOME"
kubectl -n akash-services get statefulsets && kubectl -n akash-services scale statefulsets akash-provider --replicas=0

sleep 4
echo "verifying provider service has been stopped"
kubectl -n akash-services get statefulsets && kubectl -n akash-services get pods -l app=akash-provide

sleep 4
echo "# updating"
helm upgrade --install akash-provider akash/provider -n akash-services \
  -f "$PROVIDER_YAML" \
  --set bidpricescript="$(openssl base64 -A < "$PRICE_SCRIPT")"

echo "Start Provider"
kubectl -n akash-services scale statefulsets akash-provider --replicas=1

sleep 15
echo "step to verify it's been started."
kubectl -n akash-services get statefulsets && kubectl -n akash-services get pods -l app=akash-provide
