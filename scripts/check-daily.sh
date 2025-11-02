#!/bin/bash
set pipefail -euo
#
# This script will be called every night at 3AM local, by Paladin Pod.
# It exists to clearly add various script that will run daily.
echo "check-daily v1.1.0 - starting"  

cd $HOME/akash-provider-paladin/scripts

echo "akash-console-prov-on-check.sh starting"
./akash-console-prov-on-check.sh

#check-active....
echo "check-provider-bids.sh starting"
./check-provider-bids.sh

#wallet-check will move excess delta funds of AKT or USDC, to preset cold-wallet, when configured.
echo "check-wallet.sh --execute starting"
./check-wallet.sh --execute

#delete log if more than 1MB, outdated switched to day of the month.
#quick fix, not a great one...

echo "Cleaning logs older than 23 days"
find /var/log/akash-provider-paladin -maxdepth 1 -type f -name "*.log" -mtime +23 -exec rm -v {} \;

