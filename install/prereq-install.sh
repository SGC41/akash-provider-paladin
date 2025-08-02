#!/bin/bash
# v2.3.0
# Commands added here will be installed on all control planes in the cluster, during paladin reinstall / upgrades


# needs yq install

sudo apt install yq wget -y

#Helm
cd /$HOME
wget --no-clobber https://get.helm.sh/helm-v3.11.0-linux-amd64.tar.gz

tar -zxvf helm-v3.11.0-linux-amd64.tar.gz

install linux-amd64/helm /usr/local/bin/helm

###Remove any potential prior repo instances
helm repo remove akash

helm repo add akash https://akash-network.github.io/helm-charts
