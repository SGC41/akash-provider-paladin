#!/bin/bash
# v2.3.0
# Commands added here will be installed on all control planes in the cluster, during paladin reinstall / upgrades


# needs yq install

sudo apt install wget -y
sudo snap install yq

#provider services check
version=$(provider-services version 2>/dev/null)

if [ "$(printf '%s\n' "$version" 'v0.6.9' | sort -V | head -n1)" != 'v0.6.9' ]; then
  echo "⚠️ Detected outdated version: $version — updating provider-service binary..."
  cd $HOME
  wget https://github.com/akash-network/provider/releases/download/v0.6.9/provider-services_0.6.9_linux_amd64.deb

  dpkg -i provider-services*.deb

  rm /usr/local/bin/provider-services
  provider-services version
  hash -r
fi





#Helm
cd /$HOME
wget --no-clobber https://get.helm.sh/helm-v3.11.0-linux-amd64.tar.gz

tar -zxvf helm-v3.11.0-linux-amd64.tar.gz

install linux-amd64/helm /usr/local/bin/helm

###Remove any potential prior repo instances
helm repo remove akash

helm repo add akash https://akash-network.github.io/helm-charts
