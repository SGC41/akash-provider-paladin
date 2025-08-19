#!/bin/bash
set pipefail -euo
#
# This script will be called every night at 3AM local, by Paladin Pod.
# It exists to clearly add various script that will run daily.
cd $HOME/akash-provider-paladin/scripts

./akash-console-prov-on-check.sh
#check-active....
./check-provider-bids.sh

#wallet-check will move excess delta funds of AKT or USDC, to preset cold-wallet, when configured.
./check-wallet.sh --execute

#delete log if more than 1MB
#quick fix, not a great one...
[ $(stat -c%s /var/log/paladin.log) -gt 1048576 ] && rm /var/log/paladin.log
