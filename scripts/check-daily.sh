#!/bin/bash
set pipefail -euo
#
# This script will be called every night at 3AM local, by Paladin Pod.
# It exists to clearly add various script that will run daily.
echo "check-daily v1.0.1 - starting"  

cd $HOME/akash-provider-paladin/scripts

echo "akash-console-prov-on-check.sh starting"
./akash-console-prov-on-check.sh

#check-active....
echo "check-provider-bids.sh starting"
./check-provider-bids.sh

#wallet-check will move excess delta funds of AKT or USDC, to preset cold-wallet, when configured.
echo "check-wallet.sh --execute starting"
./check-wallet.sh --execute

#delete log if more than 1MB
#quick fix, not a great one...
echo "checking log size"
[ $(stat -c%s /var/log/paladin.log) -gt 1048576 ] && rm /var/log/paladin.log && echo "log was larger than 1MiB and was deleted"
