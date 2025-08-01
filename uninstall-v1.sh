#!/bin/bash

echo "Removing clear_stuck_pods script..."
rm -f /usr/local/bin/clear_stuck_pods.sh

echo "Removing cron job..."
crontab -l | grep -v "/usr/local/bin/clear_stuck_pods.sh" | crontab -

echo "Cleaning up logs..."
rm -f /var/log/clear-stuck-pods.log

echo "Uninstall complete! The stuck pod cleanup script has been removed."
