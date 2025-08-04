#!/bin/bash
set pipefail -euo
#
# This script will be called every night at 3AM local, by Paladin Pod.
# It exists to clearly add various script that will run daily.
cd $HOME/akash-provider-paladin/scripts

./akash-console-prov-on-check.sh
#check-active....
./check-provider-bids.sh

#delete log if more than 1MB
#quick fix, not a great one...
find /var/log/paladin.log -type f -size +1M
