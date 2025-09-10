# Akash Provider Paladin v2.8.0
Paladin will help keep providers operational and safe.

Please report bugs, should be pretty functional now.
Minor releases will usually be bug fixes, have an issue run the install command again.


Installation simply run the curl command from a single control plane node.
```shell
curl -fsSLo /tmp/install.sh https://raw.githubusercontent.com/SGC41/akash-provider-paladin/stable/install.sh \
 && bash /tmp/install.sh
```

Note that there are some required knowledge when using Paladin.
without it, you will have trouble changing your provider.yaml permanently.

Paladin will at times change the provider.yaml, if it rotates RPC through nodes.

https://github.com/SGC41/akash-provider-paladin/blob/stable/docs/getting_started.txt

add ``` --branch=unstable``` to install a different branch.
ie. /install --branch=unstable

Uninstall, not that i can see why anyone would ever want that :D
but incase it runs amok.... and so people don't have to dig around after it.

This might be the only way for one to easily shut it down, as its made to be resilient.
```
helm uninstall akash-provider-paladin -n akash-services
```


Paladin will help keep providers operational.
- v2.8.0
     Changed ticker.sh to reduce provider pod restart detection delay. 

- v2.7.4
     Added Host provider node to paladin pod logs.

- v2.7.1
     Another critical fix, which should fix akash-console-prov-online-check.sh edge case... where it will stop and then restart the provider pod within a minute
     when trying to mitigate the akash console provider offline - online issue .... undead provider, i'm considering that state coined.
     
     Now it will start by doing a 15-16 minutes shutdown.... if that won't fix it, it will wait 2 hours and then try again, which in my experience fixes the issue.
     if this doesn't work, it will wait with trying again until the next day.

     the issue will only happen, when paladin is trying to fix the akash console undead provider issue.
     so is a rather niche case, but needed to be fixed, not happy with the akash-console-prov-online-check.sh script.

     but this is how it will stay for now, might see if i can make it a lot better in the future...
     is one of the earlier scripts added to paladin, and it really shows in how easy it is to make sense of.

- v2.7.0
     Added custom exclusion to clear-stuck-pods.sh and it will also attempt a graceful deletion, before force deleting a pod.
     Moved the run of the aformentioned script, from ticker.sh (paladin pod)  to ticker-control-plane.sh.
     This allows for imrpoved logging and easier customization of scripts, since they will be run on the host control-plane of paladin pod.
     Paladin pod basically just being a cluster timer / tigger that will activate the scripts on the control-planes, when needed.

- v2.6.0
     Critical fix permanent, with failover for looping withdrawal attempts on unkilled closed leases.
     Improved logging, logs will now be placed in /var/log/akash-provider-paladin/today's monthly day and any older than 23 days are deleted.

- v2.5.15
     Updated Install command, for prompt support.

- v2.5.8
     Asks for cold wallet during install and automatically appends it to provider.yaml

- v2.5.6  
     feature from 2.5.0 now works. 

     added edit-price.sh . for editing price script in the correct way for paladin.
     fixed so the install will only, leave one paladin entry in the crontab.
     paladin pod should now restart less, not that it matters much.

- v2.5.3
     Lots of more bug fixes for rare happen stances.

- v2.5.0
     Paladin pod will now favor running on, the control plane the install command was run on.
     This simplifies logging and other cluster related annoyances.
     The pod will still move freely between the control planes, if issues should arise.

     But this way logs will usually be in the same place...

     Also improved branch selection, so i won't push the wrong branch install script again.

- v2.4.0
     Cold wallet feature added.
     Now the warm provider wallet can overflow into a cold wallet, for extra security of earned funds.
     Check getting_started.txt or the new script file for add cold wallet, minimum's and delta's to the provider.yaml

- v2.3.3 - added edit-yaml.sh
     easier / faster way to perform edits on provider.yaml in the correct akash paladin sequence.
     tho its recommended to be familiar with the process, if one needs to use it one day.

- v2.3.2 - more bug fixes
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

most if not all, non timing related logging will be accessible here.
23 days worth of logs will be kept, change the date if you need an older one. 

Note -  Logs will be created on the control-plane that hosted the paladin pod at the time of events.
        However... the pod favors the control-plane it was installed on, and thus logs will usually be there.
```
nano /var/log/akash-provider-paladin/$(date +\%d)-this-month.log
```

The Paladin pod logs are nearly useless, since its only a cluster timer, to avoid split brain behavior and pod downtime.

```
kubectl logs akash-provider-paladin-0 -n akash-services
```

Notes:
Versioning is a bit sloppy (still learning), the kubectl log can only show logs for the pod, which isn't everything, since scripts run on control planes.
each control plane can log, but logging will happen on the control plane, hosting the akash-provider-paladin will log be saved in /var/log/akash-provider-paladin/
The akash-provider-paladin pod will now favor the control plane it was installed on, and thus logs wil usually exist on that control plane.

if you are running v1, you should manually remove it or use the uninstall script for v1.
on V2.0 or later just rerun the install and it will upgrade to the latest version.
Enjoy.  and let me know if there are any issues.


