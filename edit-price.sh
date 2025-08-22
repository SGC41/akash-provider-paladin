#!/usr/bin/env bash

cd $HOME/akash-provider-paladin
$HOME/akash-provider-paladin/update-local-provider-yaml.sh && \
echo "Opening Provider.yaml for editing" && \
nano $HOME/akash-provider-paladin/price_script_generic.sh && \
$HOME/akash-provider-paladin/update-cluster-provider-yaml.sh && \

read -p "Do you want to run the Helm upgrade sequence pushing your new price_script_generic to the provider? [Y/n] ?" choice
choice=${choice:-Y}  # Default to Y if empty

case "$choice" in
  [Yy]* )
    echo "Restarting provider using update-provider-configuration.sh"
    $HOME/akash-provider-paladin/update-provider-configuration.sh
    ;;
  [Nn]* )
    echo "Aborted."
    exit 1
    ;;
  * )
    echo "Please answer Y or N."
    exit 1
    ;;
esac
