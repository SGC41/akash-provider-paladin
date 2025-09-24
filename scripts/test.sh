#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "$SCRIPT_DIR"

# Load defaults (must define BRANCH and a version variable)
source "$SCRIPT_DIR/default.conf"

# Fallbacks to avoid set -u errors if config is missing values
: "${BRANCH:=stable}"
CURRENT_PALADIN_VERSION="${CURRENT_PALADIN_VERSION:-${PALADIN_VERSION:-${VERSION:-}}}"

log_stamp() {
  echo "[$(date -u +"%Y-%m-%d %H:%M:%S")]"
}

# If no version is found in default.conf, skip comparison
if [[ -z "${CURRENT_PALADIN_VERSION:-}" ]]; then
  echo "$(log_stamp) [log] - [skip] No version found in default.conf (expected CURRENT_PALADIN_VERSION, PALADIN_VERSION, or VERSION)"
  exit 0
fi

# ── Ensure we have a local clone of the repo ──
REPO_DIR="/tmp/akash-provider-paladin"
if [[ ! -d "$REPO_DIR/.git" ]]; then
  git clone --quiet https://github.com/SGC41/akash-provider-paladin.git "$REPO_DIR"
fi

# ── Fetch and reset to the branch from config ──
git -C "$REPO_DIR" fetch --quiet origin "$BRANCH" --tags
git -C "$REPO_DIR" checkout --quiet "$BRANCH"
git -C "$REPO_DIR" reset --hard "origin/$BRANCH" --quiet

# ── Get the latest tag reachable from that branch ──
LATEST_VERSION=$(git -C "$REPO_DIR" describe --tags --abbrev=0 | sed 's/^v//')

echo "$CURRENT_PALADIN_VERSION"
echo "$LATEST_VERSION"

# ── Compare versions ──
if [[ -n "$CURRENT_PALADIN_VERSION" && -n "$LATEST_VERSION" ]]; then
  if [[ "$CURRENT_PALADIN_VERSION" != "$LATEST_VERSION" ]]; then
    lower=$(printf "%s\n%s\n" "$CURRENT_PALADIN_VERSION" "$LATEST_VERSION" | sort -V | head -n1)
    if [[ "$lower" == "$CURRENT_PALADIN_VERSION" ]]; then
      echo "$(log_stamp) [log] - [update] A new version of paladin is available on branch $BRANCH: $LATEST_VERSION (you have $CURRENT_PALADIN_VERSION)"
      echo "$(log_stamp) [log] - [update] Install with curl -fsSLo /tmp/install.sh https://raw.githubusercontent.com/SGC41/akash-provider-paladin/$BRANCH/install.sh && bash /tmp/install.sh"
    fi
  fi
fi
