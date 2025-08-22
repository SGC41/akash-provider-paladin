# CONFIG points to provider.yaml in your env
# Example: CONFIG="/root/akash-provider-paladin/config/provider.yaml"
source $HOME/akash-provider-paladin/default.conf
# Read current value (strip possible quotes)
COLD_WALLET=$(yq -r '.paladin_cold_wallet // ""' "$CONFIG" | tr -d '"')

# If a cold wallet already exists (non-empty), we’re done with this block
if [[ -n "$COLD_WALLET" ]]; then
    echo "Cold wallet already set to: $COLD_WALLET"
    # Continue with the rest of the script
else
    # Prompt until valid wallet or empty entry
    while true; do
        read -rp "Enter cold wallet address (leave empty to skip): " USER_INPUT
        if [[ -z "$USER_INPUT" ]]; then
            echo "No cold wallet will be set."
            break
        fi

        # Strip quotes just in case
        USER_INPUT_CLEAN=$(echo "$USER_INPUT" | tr -d '"')

        # Validate with provider-services
        if provider-services keys parse "$USER_INPUT_CLEAN" >/dev/null 2>&1; then
            echo "Valid Akash wallet address detected: $USER_INPUT_CLEAN"

            # Ensure the other paladin config lines exist; append if missing
            grep -q '^paladin_provider_wallet_max_allowed_akt:' "$CONFIG" \
                || echo "paladin_provider_wallet_max_allowed_akt: 20" >> "$CONFIG"
            grep -q '^paladin_provider_wallet_max_allowed_akt_delta:' "$CONFIG" \
                || echo "paladin_provider_wallet_max_allowed_akt_delta: 50" >> "$CONFIG"

            grep -q '^paladin_provider_wallet_max_allowed_usdc:' "$CONFIG" \
                || echo "paladin_provider_wallet_max_allowed_usdc: 20" >> "$CONFIG"
            grep -q '^paladin_provider_wallet_max_allowed_usdc_delta:' "$CONFIG" \
                || echo "paladin_provider_wallet_max_allowed_usdc_delta: 50" >> "$CONFIG"

            # Now set/update the cold wallet line
            if grep -Eq '^\s*paladin_cold_wallet:' "$CONFIG"; then
                # Replace existing line (handles quotes or no quotes)
                sed -i -E "s|^\s*paladin_cold_wallet:.*|paladin_cold_wallet: \"$USER_INPUT_CLEAN\"|" "$CONFIG"
            else
                echo "paladin_cold_wallet: \"$USER_INPUT_CLEAN\"" >> "$CONFIG"
            fi
            break
        else
            echo "Invalid Akash wallet address: $USER_INPUT_CLEAN"
            echo "Please try again or press Enter to skip."
        fi
    done
fi
