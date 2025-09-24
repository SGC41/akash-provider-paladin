
echo "checking rpc node"
 RAW=$(kubectl exec -n akash-services akash-provider-0 -c provider -- \
            printenv AKASH_NODE_1_PORT_26657_TCP 2>/dev/null)

          if [[ -z "$RAW" ]]; then
            echo "No AKASH_NODE_1_PORT_26657_TCP found"
            exit 1
          fi

          HOST=$(echo "$RAW" | sed -E 's#^tcp://([^:]+):([0-9]+)$#\1#')
          PORT=$(echo "$RAW" | sed -E 's#^tcp://([^:]+):([0-9]+)$#\2#')

          if [[ "$PORT" == "26657" ]]; then
            SCHEME="http"
          elif [[ "$PORT" == "440" ]]; then
            SCHEME="https"
          else
            SCHEME="https"
          fi

          rpc_node_url="${SCHEME}://${HOST}:${PORT}"
stored_rpc_node_url="blank"
[ -f /host/tmp/akash-provider-rpc.conf ] && stored_rpc_node_url=$(< /host/tmp/akash-provider-rpc.conf)
if [["$stored_rpc_node_url" !=  "$rpc_node_url" ]]; then
          echo "paladin tmp stored rpc not same as current, updating tmp/akash-provider-rpc.conf"
          echo "$rpc_node_url" > /tmp/akash-provider-rpc.conf
else
echo "akash-provider-rpc.conf verified"
fi

