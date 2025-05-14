# Akash Provider Paladin v2.0
Paladin will help keep providers operational, right now its very basic, but i'm sure it will evolve over time.

This script solves the issue with pods getting stuck on down nodes.
Which can lead to provider downtime, persistent storage crashes and many other issues.
Lists all terminating and error state pods across all namespaces and deletes them every 30 minutes.

Now runs its own pod called akash-provider-paladin, which cannot get stuck and handles the stuck pod checks and deletions.
100% cluster support.

will be adding more features soon.

Installation simply run the curl command from a single control plane node.
```shell
curl -fsSL https://raw.githubusercontent.com/SGC41/akash-provider-paladin/dev/install.sh | sh
```
Uninstall Paladin v1

```shell
curl -fsSL https://raw.githubusercontent.com/SGC41/akash-provider-paladin/dev/install.sh | sh
```

Manual install.
go figure.... basically just follow the script... if it works... :P

Check its logs for details on what its doing.
```
kubectl logs akash-provider-paladin-0 -n akash-services
```
