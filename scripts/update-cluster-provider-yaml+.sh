echo "[rpc] pushing updated files to etcd..."

etcdctl put /akash-provider-paladin/provider.yaml "$(cat ~/provider/provider.yaml)" \
  --cacert=/etc/ssl/etcd/ssl/ca.pem \
  --cacert=/etc/ssl/etcd/ssl/ca.pem \
  --cert=/etc/ssl/etcd/ssl/node-node1.pem \
  --key=/etc/ssl/etcd/ssl/node-node1-key.pem

etcdctl put /akash-provider-paladin/price_script_generic.sh "$(cat ~/provider/price_script_generic.sh)" \
  --cacert=/etc/ssl/etcd/ssl/ca.pem \
  --cacert=/etc/ssl/etcd/ssl/ca.pem \
  --cert=/etc/ssl/etcd/ssl/node-node1.pem \
  --key=/etc/ssl/etcd/ssl/node-node1-key.pem

echo "provider.yaml and price_script_generic.sh etcd update complete ✅"
