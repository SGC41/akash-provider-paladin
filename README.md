# Akash Provider Paladin v2.2.6
Paladin will help keep providers operational.
- v2.2.5 cluster install
- v2.2 Feature added RPC rotation aka RPC node failover.
- v2.0 Cluster Support

This script solves the issue with pods getting stuck on down nodes.
Which can lead to provider downtime, persistent storage crashes and many other issues.
Lists all terminating and error state pods across all namespaces and deletes them every 30 minutes.

Now runs its own pod called akash-provider-paladin, which cannot get stuck and handles the stuck pod checks and deletions.
100% cluster support.

will be adding more features over time.

Installation simply run the curl command from a single control plane node.
```shell
curl -fsSL https://raw.githubusercontent.com/SGC41/akash-provider-paladin/main/install.sh | bash
```
Uninstall Paladin v1

```shell
curl -fsSL https://raw.githubusercontent.com/SGC41/akash-provider-paladin/main/uninstall-v1.sh | bash
```

Check its logs for details on what its doing.
```
kubectl logs akash-provider-paladin-0 -n akash-services
```

Notes:
Versioning is a bit sloppy (still learning), the kubectl log can only show logs for the pod, which isn't everything, since RPC rotates happen on control planes.
each control plane will log its RPC-rotate.sh runs in /var/log/rpc-rotate.log

if you are running v1, you should manually remove it or use the uninstall script for v1.
on V2.0 or later just rerun the install and it will upgrade to the latest version.
Enjoy.  and let me know if there are any issues.
