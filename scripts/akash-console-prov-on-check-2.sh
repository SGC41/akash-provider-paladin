#!/bin/bash
# v2.2.9
# Simple Description of funtions
#
# changed from 1hr to 16 minutes, and will change checks from 30 to 20.
# Pulls Online State and Last seen from Console API if the provider is online the check is passed
# If the provider is offline, the script proceeds to attempt to diagnose, if its recorded as being down due to the Akash Console issue.
#
# To do this it pulls the domain of the provider, from the blockchain / RPC node, sanetizes it and compares it to the domain in the provider.yaml
# if these are identical, the local provider API is considered viable, verifying that its possible to be related to the issue.
# and it jumps to the next step
# if not then there is clearly another issue, so it will probe a bit more, looking at provider pod uptime, if its been up for over 1 hour the script will end
# if the provider pod doesn't exist, it will spin it up via the paladin pod ticker like below.

# STEP
# It now compares the current time to the lastSeen from the Console API, if its been down for over 1 hour, it will assume the provider is affected by
# akash console offline provider is really online issue.

# to solve the issue, it will scale down the provider pod for up to 30 minutes before scaling it up again, the paladin pod ticker will handle it.
# so it will happen at top off or half hour.

#export AKASH_NODE="http://$(kubectl -n akash-services get ep akash-node-1 -o jsonpath='{.subsets[0].addresses[0].ip}'):26657"

# Set provider.yaml file path
PROVIDER_YAML_FILE="$HOME/akash-provider-paladin/provider.yaml"

# Extract wallet address from provider.yaml
PROVIDER=$(yq -r '.from' "$PROVIDER_YAML_FILE")


log_stamp() {
  echo "[$(date -u +"%Y-%m-%d %H:%M:%S")]"
}


# Verify wallet address starts with "akash"
if ! [[ "$PROVIDER" =~ ^akash ]]; then
  echo "$(log_stamp) [log] [Error] Unable to retrieve wallet address from provider.yaml"
  echo "$(log_stamp) [log] [Info] Wallet address must start with 'akash', but got: $PROVIDER"
  exit 1
fi

#Look for untrigger scale up provider command.
if [[ -f "$HOME/akash-provider-paladin/.start-provider.tmp" ]]; then
  echo "$(log_stamp) [log] [Info] [✓] Trigger file found — starting provider action"
  kubectl scale statefulsets akash-provider --replicas=1 -n akash-services
  rm -f "$HOME/akash-provider-paladin/.start-provider.tmp"
  exit 0
else
  echo "$(log_stamp) [log] [Info] […] Trigger file not found — skipping provider action"
fi


# Set API endpoint
API_ENDPOINT="https://console-api.akash.network/v1/providers/${PROVIDER}"

# Fetch API response
  TMP_FILE=$(mktemp)
  curl -X GET \
    "$API_ENDPOINT" \
    -H 'accept: application/json' \
    > "$TMP_FILE" && echo "Successfully fetched provider data from Akash Console API."

  # Extract provider info using jq from Akash Console API data
  PROVIDER_INFO=$(cat "$TMP_FILE")

  # Check if provider info was found
  if [ -z "$PROVIDER_INFO" ]; then
    echo "$(log_stamp) [log] [Warn] Provider not found in Akash Console API"
    exit 1
  fi

  # Extract online status and last online date
  IS_ONLINE=$(jq -r '.isOnline' <<< "$PROVIDER_INFO")
  LAST_ONLINE_DATE=$(jq -r '.lastOnlineDate' <<< "$PROVIDER_INFO")
  CONSOLE_CURRENT_LEASES=$(jq -r '.leaseCount' <<< "$PROVIDER_INFO")
  # Print results
  echo "$(log_stamp) [log] [Info]Provider is online: $IS_ONLINE"
  echo "$(log_stamp) [log] [Info]Last online date: $LAST_ONLINE_DATE"
  echo "$(log_stamp) [log] [Info]Current recorded Akash Console leases: $CONSOLE_CURRENT_LEASES"
  # Clean up temporary file
  rm "$TMP_FILE"


# This part will be triggered if Console offline provider online issue is suspected.
if [[ "$IS_ONLINE" == "false" ]]; then
  echo "$(log_stamp) [log] [Info][⚠] Akash Console reports provider as offline"

  # ── Fetch provider host_uri from blockchain ────────────────
  NODE_IP=$(kubectl -n akash-services get ep akash-node-1 -o jsonpath='{.subsets[0].addresses[0].ip}')
  BLOCKCHAIN_PROVIDER_URL=$(provider-services query provider get "$PROVIDER" -o json --node "http://${NODE_IP}:26657" | jq -r '.host_uri')

  # ── Sanitize URL (strip protocol) ──────────────────────────
  # old  BLOCKCHAIN_DOMAIN=$(echo "$BLOCKCHAIN_PROVIDER_URL" | sed -E 's|^https?://||')

  BLOCKCHAIN_DOMAIN=$(echo "$BLOCKCHAIN_PROVIDER_URL" \
    | sed -E 's|^[a-zA-Z]+://||' \
    | sed -E 's|:[0-9]+.*$||' \
    | sed -E 's|^provider\.||' \
    | tr '[:upper:]' '[:lower:]'
  )


  # ── Compare against provider.yaml domain ───────────────────
  CONFIG_PATH="$HOME/akash-provider-paladin/provider.yaml"
  LOCAL_DOMAIN=$(yq -r '.domain' "$CONFIG_PATH" | sed -E 's|^https?://||' | sed 's|"||g')

  if [[ "$BLOCKCHAIN_DOMAIN" == "$LOCAL_DOMAIN" ]]; then
    echo "$(log_stamp) [log] [Info][✓] Provider local API appears reachable"
    echo "$(log_stamp) [log] [Info][ℹ] Continuing provider status verification..."
  else
    echo "$(log_stamp) [log] [Info][✗] Mismatch: Blockchain host_uri ($BLOCKCHAIN_DOMAIN) vs provider.yaml ($LOCAL_DOMAIN)"
    echo "$(log_stamp) [log] [Info][!] Provider API not responding"
       # inset script block performs check that provider api is running and if not initiates temporary provider pod scale down
       # this seems to make the provider be registered as online with Akash Console, when spun back up after an unknown amount of time.
        echo "$(log_stamp) [log] [Info]Provider Pod Check with Age Info"
        # Target StatefulSet
        TARGET="akash-provider"
        NAMESPACE="akash-services"

        # Fetch READY status and AGE from kubectl
        readiness=$(kubectl -n "$NAMESPACE" get statefulsets "$TARGET" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "")
        replicas=$(kubectl -n "$NAMESPACE" get statefulsets "$TARGET" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "")
        created_at=$(kubectl -n "$NAMESPACE" get statefulsets "$TARGET" -o jsonpath='{.metadata.creationTimestamp}' 2>/dev/null || echo "")

        # Check if pod is spun up
        if [[ "$readiness" == "$replicas" && "$replicas" != "" ]]; then
          echo "$(log_stamp) [log] [Info][✓] Provider pod '$TARGET' is running → READY: $readiness/$replicas"

        # Calculate uptime
          created_unix=$(date -d "$created_at" +"%s")
          now_unix=$(date +"%s")
          seconds_up=$((now_unix - created_unix))

        # Convert to days / hours
          uptime_days=$((seconds_up / 86400))
          uptime_hours=$(((seconds_up % 86400) / 3600))

          echo "$(log_stamp) [log] [Info][🕒] Uptime: ${uptime_days}d ${uptime_hours}h"
          echo "$(log_stamp) [log] [Info]STATUS=true"
        else
          echo "$(log_stamp) [log] [Info][✗] Provider pod '$TARGET' is NOT running → READY: $readiness/$replicas"
          echo "$(log_stamp) [log] [Info]STATUS=false"
          echo "$(log_stamp) [log] [Info]StartProviderPOD" >> /tmp/ticker.do
        fi

        #end of injected script block

    exit 1
  fi

  # ── Check time delta ───────────────────────────────────────
  LAST_UNIX=$(date -d "$LAST_ONLINE_DATE" +"%s")
  NOW_UNIX=$(date +"%s")
  OFFLINE_DURATION=$((NOW_UNIX - LAST_UNIX))
  if [[ $OFFLINE_DURATION -gt 960 ]]; then
    echo "$(log_stamp) [log] [Info][🚨] Provider has been offline > 16 minutes"

    # ── Spin down provider pod ────────────────────────────────
    kubectl -n akash-services scale statefulsets akash-provider --replicas=0
    kubectl -n akash-services get statefulsets

    echo "start-provider" > $HOME/akash-provider-paladin/.start-provider.tmp && sleep 1800 && kubectl -n akash-services scale statefulsets akash-provider --replicas=1 && rm $HOME/akash-provider-paladin/.start-provider.tmp
    echo "$(log_stamp) [log] [Event] Akash Console Provider online issue detected, provider spun down until next Paladin check."

    # ── Register note in etcd memory store ─────────────────── not working
    #ISSUE_KEY="AKASH-CONSOLE-OFFLINE-ISSUE"
    #EXISTING=$(kubectl -n akash-services get configmap akash-provider-paladin-memory -o jsonpath="{.data.$ISSUE_KEY}" || echo "")


    #if [[ "$EXISTING" != "true" ]]; then
    #  kubectl -n akash-services patch configmap akash-provider-paladin-memory \
    #    --type merge \
    #    -p "{\"data\": {\"$ISSUE_KEY\": \"true\"}}"
    #  echo "$(log_stamp) [log] [Info][✓] Memory note registered for: $ISSUE_KEY"
    #else
    #  echo "$(log_stamp) [log] [Info][ℹ] Note already set: $ISSUE_KEY"
    #fi
  else
    echo "$(log_stamp) [log] [Info][⏱] Offline duration is under 15 minutes — holding"
  fi
else
  echo "$(log_stamp) [log] [Info][✓] Provider is online — no action needed"
fi
