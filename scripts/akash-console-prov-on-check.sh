#!/bin/bash
# v2.7.2
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

# might need a rewrite.... needs debug and check flags
# should most likely try to do rpc-rotate, if in the fixing akash console online issue state, and if that hasn't succeeded.
# first it should be a rpc-rotate.sh --check ... later maybe any, but check is most likely fine and if tht fails then maybe just without the check.

#fuck it... lets just make it cry for help.

# export AKASH_NODE="http://$(kubectl -n akash-services get ep akash-node-1 -o jsonpath='{.subsets[0].addresses[0].ip}'):26657"
# export NODE_IP=$(kubectl -n akash-services get ep akash-node-1 -o jsonpath='{.subsets[0].addresses[0].ip}')
# export PROVIDER=$(yq -r '.from' "$PROVIDER_YAML_FILE")
# provider-services query provider get "$PROVIDER" -o json --node "http://${NODE_IP}:26657" | jq


# Set provider.yaml file path
PROVIDER_YAML_FILE="$HOME/akash-provider-paladin/provider.yaml"

# Extract wallet address from provider.yaml
PROVIDER=$(yq -r '.from' "$PROVIDER_YAML_FILE")

LAST_FIX_ATTEMPT="$HOME/akash-provider-paladin/.last_fix_akash_console_offline_issue.tmp"

log_stamp() {
  echo "[$(date -u +"%Y-%m-%d %H:%M:%S")]"
}


# Verify wallet address starts with "akash"
if ! [[ "$PROVIDER" =~ ^akash ]]; then
  echo "$(log_stamp) [log] [Error] Unable to retrieve wallet address from provider.yaml"
  echo "$(log_stamp) [log] [Info] Wallet address must start with 'akash', but got: $PROVIDER"
  exit 0
fi

#Look for untrigger scale up provider command.
if [[ -f "$HOME/akash-provider-paladin/.start-provider.tmp" ]]; then
  echo "$(log_stamp) [log] [Info] [✓] Trigger file found — starting provider action"
  kubectl scale statefulsets akash-provider --replicas=1 -n akash-services
  rm -f "$HOME/akash-provider-paladin/.start-provider.tmp"
  exit 0
else
  echo "$(log_stamp) [log] [Info] […] Trigger file not found — skipping start provider action"
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
    exit 0
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


      #Akash Console Fix Wait.
      if [[ ! -f "$LAST_FIX_ATTEMPT" || "$(cut -d' ' -f3 "$LAST_FIX_ATTEMPT")" == "2_HOUR_WAIT" ]]; then
	#checks if 2 hours have passed.
          if [[ ! -f "$LAST_FIX_ATTEMPT" || $(( $(date +%s) - $(date -d "$(cut -d' ' -f1-2 "$LAST_FIX_ATTEMPT")" +%s) )) -ge $((105*60)) ]]; then
            echo "105 minute wait for akash console fix reached, creating .start-provider.tmp file, so that next run will start the provider" > $HOME/akash-provider-paladin/.start-provider.tmp && \
            echo "$NOW DAILY_DONE" > "$LAST_FIX_ATTEMPT"
            exit 0
          fi
          echo "akash-console-prov-on-check.sh still in 2 hour hold, defined by .last_fix_akash_console_offline_issue.tmp"

          exit 0

      fi

  # find  working RPC node
  #  update provider.yaml from etcd, so its valid
  # grab rpc node from provider.yaml
  # if local make replace domain name with ip
  $HOME/akash-provider-paladin/

  RPC_NODE_ACTIVE=$(yq -r '.node // "https://rpc-akash.ecostake.com:443"' "$PROVIDER_YAML_FILE")

  if [[ "$RPC_NODE_ACTIVE" == "http://akash-node-1:26657" ]]; then
    # ── Fetch provider host_uri from blockchain ────────────────
    NODE_IP=$(kubectl -n akash-services get ep akash-node-1 -o jsonpath='{.subsets[0].addresses[0].ip}')
    BLOCKCHAIN_PROVIDER_URL=$(provider-services query provider get "$PROVIDER" -o json --node "http://${NODE_IP}:26657" | jq -r '.host_uri')
  else
    BLOCKCHAIN_PROVIDER_URL=$(provider-services query provider get "$PROVIDER" -o json --node "$RPC_NODE_ACTIVE" | jq -r '.host_uri')
  fi


  #RPC_NODE_ACTIVE=$(yq -r '.node // "https://rpc-akash.ecostake.com:443"' "$PROVIDER_YAML_FILE")
  #if RPC_NODE_ACTIVE == "http://akash-node-1:26657" then 
  #
  ## ── Fetch provider host_uri from blockchain ────────────────
  #NODE_IP=$(kubectl -n akash-services get ep akash-node-1 -o jsonpath='{.subsets[0].addresses[0].ip}')
  #BLOCKCHAIN_PROVIDER_URL=$(provider-services query provider get "$PROVIDER" -o json --node "http://${NODE_IP}:26657" | jq -r '.host_uri')
  #else
  #BLOCKCHAIN_PROVIDER_URL=$(provider-services query provider get "$PROVIDER" -o json --node "$RPC_NODE_ACTIVE" | jq -r '.host_uri')
  #fi
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

    exit 0
  fi

  # ── Check time delta ───────────────────────────────────────
  NOW=$(date -u +"%Y-%m-%d %H:%M:%S")
  TODAY=$(cut -d' ' -f1 "$NOW")   # time only
  LAST_UNIX=$(date -d "$LAST_ONLINE_DATE" +"%s")
  NOW_UNIX=$(date +"%s")
  OFFLINE_DURATION=$((NOW_UNIX - LAST_UNIX))
  if [[ $OFFLINE_DURATION -gt 1020 ]]; then

    if [[ ! -f "$LAST_FIX_ATTEMPT" || "$(cut -d' ' -f1 "$LAST_FIX_ATTEMPT")" != "$TODAY" ]]; then

      echo "$(log_stamp) [log] [Info][🚨] Provider has been offline > 17 minutes"
        if [[ ! -f "$LAST_FIX_ATTEMPT" || "$(cut -d' ' -f3 "$LAST_FIX_ATTEMPT")" == "DAILY_DONE" ]]; then

            echo "3 or more attempts to mitigate the akash console issue today."
            echo "stopping for today, will retry tomorrow"
		exit 0
        else
            # ── Spin down provider pod ────────────────────────────────
            # -- other stuff might try to keep it running, so have to make sure its down...
            echo "scaling down provider and time stamping .last_fix_akash_console_offline_issue"
            kubectl -n akash-services scale statefulsets akash-provider --replicas=0 && echo "$NOW" > "$LAST_FIX_ATTEMPT"
            kubectl -n akash-services get statefulsets
            echo "creating trigger start provider and sleeping for 16 minutes before checking again, tested 7min a few times didn't seem to work"

            sleep 4
            echo "showing verification provider service has been stopped"
            kubectl -n akash-services get statefulsets && kubectl -n akash-services get pods -l app=akash-provide
        fi
    else
      echo "2 or more attempts to fix akash console offline issue today."
      echo "leaving the provider in its current state, when two hours have passed provider will be spun down for 15 minutes."
      echo "this should hopefully resolve the issue with akash console"
      echo "$NOW 2_HOUR_WAIT" > "$LAST_FIX_ATTEMPT"
      exit 0
    fi

# disabled because 16 minutes failed
    echo "start-provider" > $HOME/akash-provider-paladin/.start-provider.tmp
#    sleep 960 && kubectl -n akash-services scale statefulsets akash-provider --replicas=1 && rm $HOME/akash-provider-paladin/.start-provider.tmp && \
#   echo "showing verification provider service is still stopped after sleep and then starting" && \
#    kubectl -n akash-services get statefulsets && kubectl -n akash-services get pods -l app=akash-provide && \
#    echo "provider akash console online state should hopefully now be recovered"

#    sleep 15
#    echo "step to verify it's been started."
#    kubectl -n akash-services get statefulsets && kubectl -n akash-services get pods -l app=akash-provide

#    echo "insert secondary check here... or loop or add as function"
# ?? i don't think so    echo "$(log_stamp) [log] [Event] Akash Console Provider online issue detected, provider spun down until next Paladin check."

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
  rm -f "$LAST_FIX_ATTEMPT"
fi

