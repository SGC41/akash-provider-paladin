#!/usr/bin/env bash
# Paladin v2.11.8
# ticker-control-plane.sh v2.8.0
# Creator: SGC | DCnorse
#
# Similiar to ticker.sh but the version that runs on the control planes.
# runs as a cronjob, which is injected into all control planes during installation of paladin.
# Is used by the Paladin pod, to activate its hosting control plane.
# this script will execute, scripts existing inside $HOME/akash-provider-paladin/scripts/
# any other scripts cannot be executed remotely, for obvious security reasons.
#
# didn't want create any security issues, so have tried to keep inside the existing security framework.
# paladin pod is a regular pod in the akash-services namespace, and will only live on control planes.
# which it will then interact with via a mounted /tmp /host/tmp folder

# duno how secure this actually is, but wasn't able to find a better solution at the time.
# and really in theory i would assume the paladin pod is as secure as the provider pod.
# so most likely fine... if anyone has any concerns or notes, let me know.
#
# the script runs often, which is why i wanted to keep it small and simple.
# maybe i shouldn't  write all this lol
# flags for scripts can be passed through the control plane ticker.
# i forget the syntax, been a bit of a project to make all this work.
# tho looking at the script... pretty sure it just passes the lines from the file
# checks that there is a script, if so it runs it with the flag asked.
#
# basic

set -uo pipefail

# Lock on FD 9 - makes sure ticker control plane doesn't run multiple times.
exec 9>/tmp/ticker-control-plane.lock
flock -n 9 || { echo "ticker-control-plane already running"; exit 0; }

DO_FILE="/tmp/control-plane.do"
DO_UPDATE_FILE="$HOME/akash-provider-paladin/.update.do"
UPDATE_DONE_FILE="$HOME/akash-provider-paladin/.update.done"
SCRIPTS_DIR="$HOME/akash-provider-paladin/scripts"
CONFIG="$HOME/akash-provider-paladin/provider.yaml"

log_stamp() {
  echo "[$(date -u +"%Y-%m-%d %H:%M:%S")]"
}
echo "########################################################"
echo 
echo "$(log_stamp) -  Paladin scheduled execution" 
echo 
echo "########################################################"
#Update check
if [[ -f "$DO_UPDATE_FILE" || ! -f "$UPDATE_DONE_FILE" ]]; then
  echo "$(log_stamp) [log] 📨  Updated since last execution or new control plane, running /install/prereq-intall.sh"
  $HOME/akash-provider-paladin/install/prereq-install.sh
  rm $DO_UPDATE_FILE
  touch $UPDATE_DONE_FILE
fi

if [[ ! -f "$CONFIG" ]]; then
$HOME/akash-provider-paladin/update-local-provider-yaml.sh
fi

if [[ -f "$DO_FILE" ]]; then
  echo "$(log_stamp) [log] 📨 Executing control instructions from $DO_FILE..."

  while IFS= read -r line; do
    # Skip blank lines or comments
    [[ -z "$line" || "$line" =~ ^# ]] && continue

    # Split line into assignment and flags
    IFS=';' read -r assignment raw_flags <<< "$line"

    # Extract script name and run status
    script_key=$(echo "$assignment" | cut -d'=' -f1 | xargs)
    status=$(echo "$assignment" | cut -d'=' -f2 | xargs)

    # Sanitize script name to use as filename
#    script_name=$(echo "$script_key" | tr '-' '_' | tr '[:upper:]' '[:lower:]')
    script_name=$(echo "$script_key")
    script_path="$SCRIPTS_DIR/${script_name}.sh"
    # Parse up to 5 flags safely
    flags=()
    for flag in $raw_flags; do
      [[ ${#flags[@]} -lt 5 ]] && flags+=("$flag")
    done
#    echo "Loaded $script_name request from control-plane.do file"
     echo "$(log_stamp) [log] [✓] Loaded $script_name → ${flags[*]} from control-plane.do file"
    # Execute if allowed
    if [[ "$status" == "true" ]]; then
      if [[ -x "$script_path" ]]; then
        echo "$(log_stamp) [Info] [✓] Running $script_name → ${flags[*]}"
        "$script_path" "${flags[@]}"
      else
        echo "$(log_stamp) [Warn] [✗] Script not found or not executable: $script_path" >&2
      fi
    fi
  done < "$DO_FILE"
else
  echo "$(log_stamp) [Info] [!] No control file found at $DO_FILE — skipping."
fi
echo "$(log_stamp) [Info]  Scheduled Executions completed."
echo ""
