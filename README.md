# akash-provider-paladin
Paladin will help keep providers operational, right now its very basic, but i'm sure it will evolve over time.

This script solves the issue with pods getting stuck on down nodes.
Which can lead to provider downtime, persistent storage crashes and many other issues.
Lists all terminating and error state pods across all namespaces and deletes them every 30 minutes.


Installation simply run the curl command on a single control plane node.
```shell
curl -fsSL https://raw.githubusercontent.com/SGC41/akash-provider-paladin/refs/heads/main/install.sh | sh
```
