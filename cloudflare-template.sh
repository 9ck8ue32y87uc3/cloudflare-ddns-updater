#!/bin/bash
# ==============================================
# Cloudflare DDNS Updater – Pure Bash
# Update your DNS A record automatically
# Sends optional Slack & Discord notifications
# ==============================================

# ------------------------------
# Configuration
# ------------------------------
auth_email=""         # Cloudflare email
auth_method="token"   # "global" or "token"
auth_key=""           # API key or token
zone_identifier=""    # Cloudflare zone ID
record_name=""        # DNS record to update
ttl=3600              # DNS TTL (seconds)
proxy="false"         # Cloudflare proxy: true/false
sitename=""           # Site name for notifications
slackchannel=""       # Slack channel
slackuri=""           # Slack webhook URL
discorduri=""         # Discord webhook URL

# ------------------------------
# Logging function
# ------------------------------
log() {
    echo "[DDNS] $1"
    logger -s "[DDNS] $1"
}

# ------------------------------
# Get public IP
# ------------------------------
get_public_ip() {
    local services=("https://api.ipify.org" "https://ipv4.icanhazip.com" "https://ipinfo.io/ip")
    local regex="^(0*(1?[0-9]{1,2}|2([0-4][0-9]|5[0-5]))\.){3}0*(1?[0-9]{1,2}|2([0-4][0-9]|5[0-5]))$"

    for s in "${services[@]}"; do
        local ip=$(curl -s "$s")
        if [[ $ip =~ $regex ]]; then
            echo "$ip"
            return 0
        else
            log "IP service $s failed"
        fi
    done

    return 1
}

# ------------------------------
# Get proper auth header
# ------------------------------
get_auth_header() {
    if [[ "$auth_method" == "global" ]]; then
        echo "X-Auth-Key: $auth_key"
    else
        echo "Authorization: Bearer $auth_key"
    fi
}

# ------------------------------
# Fetch A record from Cloudflare
# ------------------------------
fetch_record() {
    curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$zone_identifier/dns_records?type=A&name=$record_name" \
        -H "X-Auth-Email: $auth_email" \
        -H "$(get_auth_header)" \
        -H "Content-Type: application/json"
}

# ------------------------------
# Update A record in Cloudflare
# ------------------------------
update_record() {
    local record_id=$1
    local new_ip=$2

    curl -s -X PATCH "https://api.cloudflare.com/client/v4/zones/$zone_identifier/dns_records/$record_id" \
        -H "X-Auth-Email: $auth_email" \
        -H "$(get_auth_header)" \
        -H "Content-Type: application/json" \
        --data "{\"type\":\"A\",\"name\":\"$record_name\",\"content\":\"$new_ip\",\"ttl\":$ttl,\"proxied\":$proxy}"
}

# ------------------------------
# Notify Slack & Discord
# ------------------------------
notify() {
    local message="$1"

    [[ -n "$slackuri" ]] && \
    curl -s -X POST "$slackuri" \
        --data-raw "{\"channel\":\"$slackchannel\",\"text\":\"$message\"}"

    [[ -n "$discorduri" ]] && \
    curl -s -H "Content-Type: application/json" -X POST \
        --data-raw "{\"content\":\"$message\"}" "$discorduri"
}

# ------------------------------
# Main Logic
# ------------------------------
log "Starting DDNS update check..."

CURRENT_IP=$(get_public_ip) || { log "Failed to fetch public IP"; exit 1; }
log "Current IP: $CURRENT_IP"

RECORD_JSON=$(fetch_record)

# Check if record exists
if [[ $RECORD_JSON == *"\"count\":0"* ]]; then
    log "Record $record_name does not exist"
    exit 1
fi

OLD_IP=$(echo "$RECORD_JSON" | sed -E 's/.*"content":"(([0-9]{1,3}\.){3}[0-9]{1,3})".*/\1/')
RECORD_ID=$(echo "$RECORD_JSON" | sed -E 's/.*"id":"([A-Za-z0-9_]+)".*/\1/')

if [[ "$CURRENT_IP" == "$OLD_IP" ]]; then
    log "IP unchanged ($CURRENT_IP). Nothing to update."
    exit 0
fi

log "Updating record $record_name from $OLD_IP to $CURRENT_IP..."
UPDATE_RESULT=$(update_record "$RECORD_ID" "$CURRENT_IP")

if [[ "$UPDATE_RESULT" == *"\"success\":false"* ]]; then
    log "Update failed!"
    notify "$sitename DDNS Update Failed: $record_name ($RECORD_ID) ($CURRENT_IP)"
    exit 1
else
    log "Record updated successfully"
    notify "$sitename Updated: $record_name's new IP is $CURRENT_IP"
    exit 0
fi
