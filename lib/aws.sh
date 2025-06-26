#!/bin/bash
# AWS operations for groupsyncer
# Handles all AWS CLI interactions and security group management

# Get AWS profiles to process
get_aws_profiles() {
	# If a specific profile was provided via -p option, use only that profile
	if [[ -n "$AWS_PROFILE" ]]; then
		echo "$AWS_PROFILE"
		return 0
	fi

	# Otherwise, get all available profiles
	local profiles
	if ! profiles=$(aws configure list-profiles 2>/dev/null); then
		log_fail "No AWS profiles configured"
		exit 1
	fi

	echo "$profiles"
}

# Check if profile is accessible
check_profile_access() {
	local profile=$1

	log_verbose_silent "Checking access for profile: $profile"

	if ! aws sts get-caller-identity --profile "$profile" >/dev/null 2>&1; then
		log_warn "Cannot access profile '$profile' - may need MFA or credentials refresh"
		return 1
	fi

	return 0
}

# Find security groups with matching rules for specified ports
find_matching_security_groups() {
	local profile=$1

	log_verbose_silent "Searching for security groups in profile: $profile"

	local security_groups
	if ! security_groups=$(timeout 60s aws ec2 describe-security-groups --profile "$profile" --output json --max-items 1000 2>/dev/null); then
		log_fail "Failed to describe security groups for profile: $profile (timeout or error)"
		return 1
	fi

	# Convert PORTS string to array for jq processing
	local ports_array
	IFS=',' read -ra ports_array <<<"$PORTS"

	# Build jq filter for multiple ports
	local port_conditions=""
	for i in "${!ports_array[@]}"; do
		local port=$(echo "${ports_array[$i]}" | tr -d '[:space:]')
		if [[ $i -gt 0 ]]; then
			port_conditions+=" or "
		fi
		port_conditions+="(.FromPort == $port and .ToPort == $port)"
	done

	# Find security groups with rules containing the description on specified ports
	local matching_groups
	if ! matching_groups=$(echo "$security_groups" | jq -r --arg desc "$RULE_DESCRIPTION" "
		.SecurityGroups[] |
		select(.IpPermissions[]? |
			select($port_conditions) |
			.IpRanges[]? |
			select(.Description != null and (.Description | contains(\$desc)))
		) |
		.GroupId
	" 2>/dev/null); then
		log_verbose_silent "jq command failed for profile: $profile"
		matching_groups=""
	fi

	if [[ -z "$matching_groups" ]]; then
		log_info "No security groups found with rules containing '$RULE_DESCRIPTION' on ports '$PORTS' in profile: $profile" >&2
		return 0
	fi

	echo "$matching_groups"
}

# Get current rules for specified ports in a security group
get_current_rules() {
	local profile=$1
	local group_id=$2

	# Convert PORTS string to array for jq processing
	local ports_array
	IFS=',' read -ra ports_array <<<"$PORTS"

	# Build jq filter for multiple ports
	local port_conditions=""
	for i in "${!ports_array[@]}"; do
		local port=$(echo "${ports_array[$i]}" | tr -d '[:space:]')
		if [[ $i -gt 0 ]]; then
			port_conditions+=" or "
		fi
		port_conditions+="(.FromPort == $port and .ToPort == $port)"
	done

	aws ec2 describe-security-groups \
		--profile "$profile" \
		--group-ids "$group_id" \
		--output json 2>/dev/null |
		jq -r --arg desc "$RULE_DESCRIPTION" "
		.SecurityGroups[0].IpPermissions[] |
		select($port_conditions) as \$permission |
		\$permission.IpRanges[] |
		select(.Description != null and (.Description | contains(\$desc))) |
		(\$permission.FromPort | tostring) + \" \" + .CidrIp + \" \" + (.Description // \"\")
	" 2>/dev/null || echo ""
}

# Update rule for a security group
update_rule() {
	local profile=$1
	local group_id=$2
	local port=$3
	local old_cidr=$4
	local description=$5
	local silent=${6:-false}
	local new_cidr="${CURRENT_IP}/32"

	if [[ "$silent" == true ]]; then
		log_info_silent "Updating security group: $group_id"
		log_info_silent "  Profile: $profile"
		log_info_silent "  Port: $port"
		log_info_silent "  Description: $description"
		log_info_silent "  Old CIDR: $old_cidr"
		log_info_silent "  New CIDR: $new_cidr"
	else
		log_info "Updating security group: $group_id"
		log_info "  Profile: $profile"
		log_info "  Port: $port"
		log_info "  Description: $description"
		log_info "  Old CIDR: $old_cidr"
		log_info "  New CIDR: $new_cidr"
	fi

	if [[ "$old_cidr" == "$new_cidr" ]]; then
		if [[ "$silent" == true ]]; then
			log_pass_silent "  No update needed - IP address unchanged"
		else
			log_pass "  No update needed - IP address unchanged"
		fi
		return 0
	fi

	if [[ "$DRY_RUN" == true ]]; then
		if [[ "$silent" == true ]]; then
			log_warn_silent "  DRY RUN - Would update rule"
		else
			log_warn "  DRY RUN - Would update rule"
		fi
		return 0
	fi

	# Remove old rule
	if [[ "$silent" == true ]]; then
		log_verbose_silent "  Removing old rule: $old_cidr"
	else
		log_verbose "  Removing old rule: $old_cidr"
	fi

	if ! aws ec2 revoke-security-group-ingress \
		--profile "$profile" \
		--group-id "$group_id" \
		--protocol tcp \
		--port "$port" \
		--cidr "$old_cidr" \
		>/dev/null 2>&1; then
		if [[ "$silent" == true ]]; then
			log_fail_silent "  Failed to remove old rule: $old_cidr"
		else
			log_fail "  Failed to remove old rule: $old_cidr"
		fi
		return 1
	fi

	# Add new rule
	if [[ "$silent" == true ]]; then
		log_verbose_silent "  Adding new rule: $new_cidr"
	else
		log_verbose "  Adding new rule: $new_cidr"
	fi

	if ! aws ec2 authorize-security-group-ingress \
		--profile "$profile" \
		--group-id "$group_id" \
		--ip-permissions "IpProtocol=tcp,FromPort=$port,ToPort=$port,IpRanges=[{CidrIp=${new_cidr},Description='${description}'}]" \
		>/dev/null 2>&1; then
		if [[ "$silent" == true ]]; then
			log_fail_silent "  Failed to add new rule: $new_cidr"
		else
			log_fail "  Failed to add new rule: $new_cidr"
		fi

		# Try to restore old rule
		if [[ "$silent" == true ]]; then
			log_warn_silent "  Attempting to restore old rule: $old_cidr"
		else
			log_warn "  Attempting to restore old rule: $old_cidr"
		fi

		aws ec2 authorize-security-group-ingress \
			--profile "$profile" \
			--group-id "$group_id" \
			--ip-permissions "IpProtocol=tcp,FromPort=$port,ToPort=$port,IpRanges=[{CidrIp=${old_cidr},Description='${description}'}]" \
			>/dev/null 2>&1 || {
			if [[ "$silent" == true ]]; then
				log_fail_silent "  Failed to restore old rule"
			else
				log_fail "  Failed to restore old rule"
			fi
		}

		return 1
	fi

	if [[ "$silent" == true ]]; then
		log_pass_silent "  Successfully updated rule"
	else
		log_pass "  Successfully updated rule"
	fi
	return 0
}

# Process a single profile
process_profile() {
	local profile=$1
	local groups_updated=0
	local groups_failed=0

	log_info_silent "Processing profile: $profile"

	# Temporarily disable exit on error for this function
	set +e

	if ! check_profile_access "$profile"; then
		set -e
		echo "0 0"
		return 1
	fi

	local matching_groups
	matching_groups=$(find_matching_security_groups "$profile")
	local find_exit_code=$?

	if [[ $find_exit_code -ne 0 ]] || [[ -z "$matching_groups" ]]; then
		set -e
		echo "0 0"
		return 0
	fi

	while read -r group_id; do
		if [[ -n "$group_id" ]]; then
			log_info_silent "Processing security group: $group_id"

			local rules
			rules=$(get_current_rules "$profile" "$group_id")

			if [[ -z "$rules" ]]; then
				log_warn_silent "  No matching rules found in $group_id"
				continue
			fi

			local rules_updated=0
			while read -r rule_line; do
				if [[ -n "$rule_line" ]]; then
					local port
					local cidr
					local description
					port=$(echo "$rule_line" | cut -d' ' -f1)
					cidr=$(echo "$rule_line" | cut -d' ' -f2)
					description=$(echo "$rule_line" | cut -d' ' -f3-)

					if update_rule "$profile" "$group_id" "$port" "$cidr" "$description" true; then
						((rules_updated++))
					else
						((groups_failed++))
					fi
				fi
			done <<<"$rules"

			if [[ $rules_updated -gt 0 ]]; then
				((groups_updated++))
			fi
		fi
	done <<<"$matching_groups"

	log_info_silent "Profile '$profile' summary: $groups_updated groups updated, $groups_failed groups failed"

	# Re-enable exit on error
	set -e

	echo "$groups_updated $groups_failed"
}
