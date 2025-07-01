#!/bin/bash
#
#  v2.2.5

set -euo pipefail

cd $HOME/akash-provider-paladin
kubectl -n akash-services get statefulsets && kubectl -n akash-services scale statefulsets akash-provider --replicas=0

sleep 4
#Steps to Verify the akash-provider Service Has Been Stopped
echo verifying provider service has been stopped
kubectl -n akash-services get statefulsets && kubectl -n akash-services get pods -l app=akash-provide

sleep 4
echo #updating 
helm upgrade --install akash-provider akash/provider -n akash-services -f $HOME/akash-provider-paladin/provider.yaml --set bidpricescript="$(cat $HOME/akash-provider-paladin/price_script_generic.sh | openssl base64 -A)" 

echo Start Provider
kubectl -n akash-services scale statefulsets akash-provider --replicas=1

sleep 15
echo step to verify its been started.
kubectl -n akash-services get statefulsets && kubectl -n akash-services get pods -l app=akash-provide

