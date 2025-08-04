# Akash Provider Paladin v2.3.0 - 
might have some bugs, but think it should be pretty functional now.
Paladin will help keep providers operational.
- v2.3.0
     Dynamic Withdrawal, based on USD owed delta on individual lease basis.

     Akash Console Provider is Online Check and automatic fix.

     Custom Script Support

     Provider blockchain bid check, and automatic provider pod bounce

     Lease monitoring and automatic removal, if leases are not being paid or exist as active on the blockchain.

     Lots of small fixes and improvements.

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
curl -fsSL https://raw.githubusercontent.com/SGC41/akash-provider-paladin/stable/install.sh | bash
```

Note that there are some required knowledge when using Paladin.
without it, you will have trouble changing your provider.yaml permanently.

Paladin will at times change the provider.yaml, if it rotates RPC through nodes.

https://github.com/SGC41/akash-provider-paladin/blob/stable/docs/getting_started.txt

Uninstall, not that i can see why anyone would ever want that :D
but incase it runs amok.... and so people don't have to dig around after it.

This might be the only way for one to easily shut it down, as its made to be resilient.
```
helm uninstall akash-provider-paladin
```



Paladin Pod Shutdown Command
Again shouldn't really be needed
```
kubectl scale deployment akash-provider-paladin-0 --replicas=0 -n akash-services
```
Paladin Pod Start Up
```
 kubectl scale deployment akash-provider-paladin-0 --replicas=1 -n akash-services
```


Uninstall Paladin v1

```shell
curl -fsSL https://raw.githubusercontent.com/SGC41/akash-provider-paladin/stable/uninstall-v1.sh | bash
```

Check its logs for details on what the pod is doing.
Do keep in mind, some more critical tasks will be handled outside the pod.
The Control Plane that the Paladin pod runs on will run critical commands.
the pod is the cluster able controller part of Paladin.

In its disabled state, one can fully revert any changes.
Simply run the regular helm upgrade command for the Akash Provider.
from your default Akash Provider location.

Example:
```
cd ~/provider
helm upgrade akash-provider akash/provider -n akash-services -f provider.yaml  --set bidpricescript="$(cat price_script_generic.sh | openssl base64 -A)"
```

Ref:
```
https://akash.network/docs/providers/build-a-cloud-provider/akash-cli/akash-cloud-provider-build-with-helm-charts/#step-9---provider-bid-customization
```
Scaling down for maintenance.
```
https://akash.network/docs/providers/provider-faq-and-guide/maintenance-logs-and-troubleshooting/
```

```
kubectl logs akash-provider-paladin-0 -n akash-services
```

Notes:
Versioning is a bit sloppy (still learning), the kubectl log can only show logs for the pod, which isn't everything, since RPC rotates happen on control planes.
each control plane will log its RPC-rotate.sh runs in /var/log/rpc-rotate.log

if you are running v1, you should manually remove it or use the uninstall script for v1.
on V2.0 or later just rerun the install and it will upgrade to the latest version.
Enjoy.  and let me know if there are any issues.


