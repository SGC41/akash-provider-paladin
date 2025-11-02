#!/usr/bin/env bash
# v2.9.6
# Commands added here will be installed on all control planes in the cluster, during paladin reinstall / upgrades

sudo apt install wget jq -y
sudo snap install yq
sudo apt install curl -y

#provider services check, needs improvements, but functional.
version=$(provider-services version 2>/dev/null)

current="${version#v}"
gittag="v0.10.1"
gittag="${gittag#v}"

min=$(printf '%s\n' "$current" "$gittag" \
      | sort -V \
      | head -n1)

echo "Checking provider-services binary"

if [ "$min" != "$gittag" ]; then
  echo "⚠️ Detected outdated version: $version — updating to v$gittag…"
  cd "$HOME"
  wget --no-clobber \
    "https://github.com/akash-network/provider/releases/download/v${gittag}/provider-services_${gittag}_linux_amd64.deb"

  dpkg -i provider-services*.deb
  rm -f /usr/local/bin/provider-services
  provider-services version
  hash -r

else
  echo "Your version ($version) is ≥ v$gittag — no update needed."
fi

#log setup
sudo mkdir -p /var/log/akash-provider-paladin
sudo chown root:root /var/log/akash-provider-paladin
sudo chmod 755 /var/log/akash-provider-paladin

#Helm
cd /$HOME
wget --no-clobber https://get.helm.sh/helm-v3.11.0-linux-amd64.tar.gz

tar -zxvf helm-v3.11.0-linux-amd64.tar.gz

install linux-amd64/helm /usr/local/bin/helm

###Remove any potential prior repo instances
helm repo remove akash

helm repo add akash https://akash-network.github.io/helm-charts
