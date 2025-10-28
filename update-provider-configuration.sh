#!/bin/bash
#
#  v2.9.5
# reduced sleep during downtime to 5 seconds

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

sleep 1
echo "verifying provider service has been stopped"
kubectl -n akash-services get statefulsets && kubectl -n akash-services get pods -l app=akash-provide

sleep 1
echo "# updating"
#helm upgrade --install akash-provider akash/provider -n akash-services \
#  --version 11.6.4 \
#  -f "$PROVIDER_YAML" \
#  --set bidpricescript="$(openssl base64 -A < "$PRICE_SCRIPT")"

helm upgrade --install akash-provider akash/provider -n akash-services \
  -f "$PROVIDER_YAML" \
  --set bidpricescript="$(openssl base64 -A < "$PRICE_SCRIPT")"


sleep 3
echo "Start Provider"
kubectl -n akash-services scale statefulsets akash-provider --replicas=1

sleep 15
echo "step to verify it's been started."
kubectl -n akash-services get statefulsets && kubectl -n akash-services get pods -l app=akash-provide

# This turned out not to be useful, since code in other scripts wasn't viable.
#echo "saving new rpc node to tmp/akash-provider-rpc.conf"
# RAW=$(kubectl exec -n akash-services akash-provider-0 -c provider -- \
#            printenv AKASH_NODE_1_PORT_26657_TCP 2>/dev/null)

 #         if [[ -z "$RAW" ]]; then
 #           echo "No AKASH_NODE_1_PORT_26657_TCP found"
 #           exit 1
 #         fi

 #         HOST=$(echo "$RAW" | sed -E 's#^tcp://([^:]+):([0-9]+)$#\1#')
 #         PORT=$(echo "$RAW" | sed -E 's#^tcp://([^:]+):([0-9]+)$#\2#')

 #         if [[ "$PORT" == "26657" ]]; then
 #           SCHEME="http"
 #         elif [[ "$PORT" == "440" ]]; then
 #           SCHEME="https"
 #         else
 #           SCHEME="https"
 #         fi

  #        rpc_node_url="${SCHEME}://${HOST}:${PORT}"
  #        echo "$rpc_node_url" > /tmp/akash-provider-rpc.conf

