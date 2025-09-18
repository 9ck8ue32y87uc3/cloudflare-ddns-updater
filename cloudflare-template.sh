#!/bin/bash
## DDNS Updater for Cloudflare (IPv4 & IPv6)
## Written in pure BASH, with Slack & Discord notifications

############## CLOUDFLARE CREDENTIALS ##############
auth_email=""           # Email used to login at 'https://dash.cloudflare.com'
auth_method="token"     # "global" for Global API Key, "token" for Scoped API Token
auth_key=""             # Your API Token or Global API Key
zone_identifier=""      # Found in the "Overview" tab of your domain

############## DNS RECORD CONFIGURATION ##############
record_name=""          # Record to sync
ttl=3600                # DNS TTL (seconds, 1 for Auto)
proxy="false"           # Cloudflare proxy true/false

############## SCRIPT CONFIGURATION #################
static_IPv6_mode="false"     # If true, looks for specific IPv6 suffix
last_notable_hexes="ffff:ffff"
log_header="DDNS Updater"

############## WEBHOOKS CONFIGURATION ##############
sitename=""             # Site title
slackchannel=""         # Slack Channel #example
slackuri=""             # Slack WebHook URI
discorduri=""           # Discord WebHook URI

###########################################
##  FUNCTION TO FETCH PUBLIC IPv4
###########################################
fetch_ipv4() {
    local REGEX_IPV4="^(0*(1?[0-9]{1,2}|2([0-4][0-9]|5[0-5]))\.){3}0*(1?[0-9]{1,2}|2([0-4][0-9]|5[0-5]))$"
    local IP_SERVICES=(
        "https://api.ipify.org"
        "https://ipv4.icanhazip.com"
        "https://ipinfo.io/ip"
    )
    for service in "${IP_SERVICES[@]}"; do
        local RAW_IP=$(curl -s $service)
        if [[ $RAW_IP =~ $REGEX_IPV4 ]]; then
            echo "$BASH_REMATCH"
            return 0
        fi
    done
    return 1
}

###########################################
##  FUNCTION TO FETCH PUBLIC IPv6
###########################################
fetch_ipv6() {
    local ipv6_regex="(([0-9a-fA-F]{1,4}:){7,7}[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,7}:|([0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,5}(:[0-9a-fA-F]{1,4}){1,2}|([0-9a-fA-F]{1,4}:){1,4}(:[0-9a-fA-F]{1,4}){1,3}|([0-9a-fA-F]{1,4}:){1,3}(:[0-9a-fA-F]{1,4}){1,4}|([0-9a-fA-F]{1,4}:){1,2}(:[0-9a-fA-F]{1,4}){1,5}|[0-9a-fA-F]{1,4}:((:[0-9a-fA-F]{1,4}){1,6})|:((:[0-9a-fA-F]{1,4}){1,7}|:)|fe80:(:[0-9a-fA-F]{0,4}){0,4}%[0-9a-zA-Z]{1,}|::(ffff(:0{1,4}){0,1}:){0,1}((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])|([0-9a-fA-F]{1,4}:){1,4}:((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9]))"

    if $static_IPv6_mode; then
        if command -v ip &>/dev/null; then
            ip -6 -o addr show scope global primary -deprecated | grep -oE "$ipv6_regex" | grep -oE ".*($last_notable_hexes)$"
        else
            ifconfig | grep -oE "$ipv6_regex" | grep -oE ".*($last_notable_hexes)$"
        fi
    else
        local ip_line=$(curl -s -6 https://cloudflare.com/cdn-cgi/trace | grep '^ip')
        if [[ $ip_line =~ ^ip=($ipv6_regex)$ ]]; then
            echo "${BASH_REMATCH[1]}"
        else
            curl -s -6 https://api64.ipify.org || curl -s -6 https://ipv6.icanhazip.com
        fi
    fi
}

###########################################
##  SET AUTH HEADER
###########################################
set_auth_header() {
    if [[ "$auth_method" == "global" ]]; then
        echo "X-Auth-Key:"
    else
        echo "Authorization: Bearer"
    fi
}

###########################################
##  UPDATE FUNCTION
###########################################
update_record() {
    local type=$1
    local ip=$2
    local auth_header=$3

    # Fetch existing record
    local record=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$zone_identifier/dns_records?type=$type&name=$record_name" \
        -H "X-Auth-Email: $auth_email" \
        -H "$auth_header $auth_key" \
        -H "Content-Type: application/json")

    if [[ $record == *"\"count\":0"* ]]; then
        logger -s "$log_header: $type record does not exist (${ip} for $record_name)"
        return 1
    fi

    # Extract old IP
    local old_ip
    if [[ $type == "A" ]]; then
        old_ip=$(echo "$record" | sed -E 's/.*"content":"(([0-9]{1,3}\.){3}[0-9]{1,3})".*/\1/')
    else
        old_ip=$(echo "$record" | sed -E 's/.*"content":"(.+)".*/\1/')
    fi

    if [[ "$ip" == "$old_ip" ]]; then
        logger "$log_header: $type IP ($ip) for $record_name unchanged."
        return 0
    fi

    # Get record ID
    local record_id=$(echo "$record" | sed -E 's/.*"id":"([A-Za-z0-9_]+)".*/\1/')

    # Update record
    local update=$(curl -s -X PATCH "https://api.cloudflare.com/client/v4/zones/$zone_identifier/dns_records/$record_id" \
        -H "X-Auth-Email: $auth_email" \
        -H "$auth_header $auth_key" \
        -H "Content-Type: application/json" \
        --data "{\"type\":\"$type\",\"name\":\"$record_name\",\"content\":\"$ip\",\"ttl\":$ttl,\"proxied\":$proxy}")

    # Log & notify
    if [[ $update == *"\"success\":false"* ]]; then
        logger -s "$log_header: $type DDNS update FAILED ($ip) for $record_id"
        notify_slack_discord "$type DDNS Update Failed: $record_name ($ip)" 
        return 1
    else
        logger "$log_header: $type DDNS updated ($ip)"
        notify_slack_discord "$type Updated: $record_name new IP $ip"
        return 0
    fi
}

###########################################
##  SLACK & DISCORD NOTIFICATION
###########################################
notify_slack_discord() {
    local message=$1
    if [[ $slackuri != "" ]]; then
        curl -s -L -X POST $slackuri \
            --data-raw "{
                \"channel\": \"$slackchannel\",
                \"text\": \"$sitename $message\"
            }"
    fi
    if [[ $discorduri != "" ]]; then
        curl -s -i -H "Accept: application/json" -H "Content-Type:application/json" -X POST \
            --data-raw "{
                \"content\": \"$sitename $message\"
            }" $discorduri
    fi
}

###########################################
## MAIN EXECUTION
###########################################
auth_header=$(set_auth_header)

# IPv4
ipv4=$(fetch_ipv4)
if [[ -n "$ipv4" ]]; then
    update_record "A" "$ipv4" "$auth_header"
else
    logger -s "$log_header: Failed to fetch IPv4"
fi

# IPv6
ipv6=$(fetch_ipv6)
if [[ -n "$ipv6" ]]; then
    update_record "AAAA" "$ipv6" "$auth_header"
else
    logger -s "$log_header: Failed to fetch IPv6"
fi
