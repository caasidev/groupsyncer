#!/bin/bash
# IP detection utilities for groupsyncer
# Handles automatic detection of current public IP address

# Detect current public IP
detect_current_ip() {
	if [[ -n "$CURRENT_IP" ]]; then
		log_info "Using provided IP address: $CURRENT_IP"
		if ! validate_ip "$CURRENT_IP"; then
			log_fail "Invalid IP address format: $CURRENT_IP"
			exit 1
		fi
		return 0
	fi

	log_info "Detecting current public IP address..."

	local ip_services=(
		"https://checkip.amazonaws.com"
		"https://ipinfo.io/ip"
		"https://api.ipify.org"
	)

	for service in "${ip_services[@]}"; do
		if CURRENT_IP=$(curl -s --connect-timeout 5 "$service" 2>/dev/null | tr -d '\n\r'); then
			if validate_ip "$CURRENT_IP"; then
				log_pass "Detected IP address: $CURRENT_IP (via $service)"
				return 0
			fi
		fi
		log_verbose "Failed to get IP from $service"
	done

	# Fallback to dig
	if command -v dig >/dev/null 2>&1; then
		if CURRENT_IP=$(dig +short myip.opendns.com @resolver1.opendns.com 2>/dev/null | tail -1); then
			if validate_ip "$CURRENT_IP"; then
				log_pass "Detected IP address: $CURRENT_IP (via dig)"
				return 0
			fi
		fi
	fi

	log_fail "Could not detect current IP address"
	log_info "Please specify IP address manually with -i option"
	exit 1
}

# Validate IP address format
validate_ip() {
	local ip="$1"

	# Check basic format and each octet is ≤ 255
	if [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
		local IFS='.'
		local -a octets
		read -ra octets <<<"$ip"
		for octet in "${octets[@]}"; do
			((octet > 255)) && return 1
		done
		return 0
	fi
	return 1
}
