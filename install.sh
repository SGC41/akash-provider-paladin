#!/bin/bash
set -e

# Define the repository URL and branch
REPO="https://github.com/SGC41/akash-provider-paladin.git"
BRANCH="dev"

echo "Cloning or updating the Akash Provider Paladin repository..."
if [ ! -d "akash-provider-paladin" ]; then
  git clone -b "$BRANCH" "$REPO"
else
  cd akash-provider-paladin
  echo "Pulling latest changes from branch $BRANCH..."
  git fetch origin "$BRANCH"
  git reset --hard "origin/$BRANCH"
  cd ..
fi

# Change into the cloned repo directory
cd ~/akash-provider-paladin

echo "Installing or upgrading Helm chart..."
# --create-namespace ensures that the target namespace will be created if it doesn't exist
helm upgrade --install akash-provider-paladin ~/akash-provider-paladin --namespace akash-services --create-namespace

echo "Installation complete!"

