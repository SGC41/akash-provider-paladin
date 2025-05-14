#!/bin/bash
set -e

# Define the repository URL, branch, and target directory.
REPO="https://github.com/SGC41/akash-provider-paladin.git"
BRANCH="dev"
TARGET_DIR="$HOME/akash-provider-paladin"

echo "Cloning or updating the Akash Provider Paladin repository..."

if [ "$PWD" = "$TARGET_DIR" ]; then
  echo "Already in $TARGET_DIR. Updating the repository..."
  git fetch origin "$BRANCH"
  git reset --hard "origin/$BRANCH"
elif [ ! -d "$TARGET_DIR" ]; then
  echo "Directory $TARGET_DIR does not exist. Cloning repository..."
  git clone -b "$BRANCH" "$REPO" "$TARGET_DIR"
  cd "$TARGET_DIR"
else
  echo "Directory $TARGET_DIR exists. Updating repository..."
  cd "$TARGET_DIR"
  git fetch origin "$BRANCH"
  git reset --hard "origin/$BRANCH"
fi

echo "Current directory: $(pwd)"

echo "Installing or upgrading Helm chart..."
# --create-namespace ensures that the target namespace will be created if it doesn't exist.
helm upgrade --install akash-provider-paladin "$TARGET_DIR" --namespace akash-services --create-namespace


