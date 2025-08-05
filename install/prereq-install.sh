#!/bin/bash
# v2.3.1
# Commands added here will be installed on all control planes in the cluster, during paladin reinstall / upgrades

sudo apt install wget jq -y
sudo snap install yq

#provider services check, needs improvements, but functional.
version=$(provider-services version 2>/dev/null)

current="${version#v}"
baseline="0.7.0-rc8"

min=$(printf '%s\n' "$current" "$baseline" \
      | sort -V \
      | head -n1)

if [ "$min" != "$baseline" ]; then
  echo "⚠️ Detected outdated version: $version — updating to v$baseline…"
  cd "$HOME"
  wget --no-clobber \
    "https://github.com/akash-network/provider/releases/download/v${baseline}/provider-services_${baseline}_linux_amd64.deb"

  dpkg -i provider-services*.deb
  rm /usr/local/bin/provider-services
  provider-services version
  hash -r

else
  echo "Your version ($version) is ≥ v$baseline — no update needed."
fi


#Helm
cd /$HOME
wget --no-clobber https://get.helm.sh/helm-v3.11.0-linux-amd64.tar.gz

tar -zxvf helm-v3.11.0-linux-amd64.tar.gz

install linux-amd64/helm /usr/local/bin/helm

###Remove any potential prior repo instances
helm repo remove akash

helm repo add akash https://akash-network.github.io/helm-charts
