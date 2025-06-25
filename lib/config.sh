#!/bin/bash
# Configuration management for groupsyncer
# Handles command line parsing and configuration validation

# Global configuration variables
CURRENT_IP=""
RULE_DESCRIPTION=""
PORTS=""
DRY_RUN=false
VERBOSE=false
AWS_PROFILE=""
LOG_FILE="/tmp/security_groups_update_$(date +%Y%m%d_%H%M%S).log"

# Usage function
usage() {
	cat <<EOF
AWS Security Group Rules Updater

Usage: $0 [OPTIONS]

OPTIONS:
    -d, --description DESCRIPTION    Rule description to search for (required)
    -p, --ports PORTS                Comma-separated list of ports to update (default: 22)
    -i, --ip IP_ADDRESS              Use specific IP address instead of auto-detection
    --profile PROFILE                Use specific AWS profile (default: all profiles)
    -n, --dry-run                    Show what would be changed without making changes
    -v, --verbose                    Enable verbose logging
    -l, --log-file FILE              Custom log file path (default: /tmp/security_groups_update_TIMESTAMP.log)
    -h, --help                       Show this help message

EXAMPLES:
    $0 -d "Office" -n                          # Dry run for SSH rules (port 22) with "Office" description
    $0 -d "Home" --profile production          # Update "Home" rules in production profile
    $0 -d "VPN" -i 192.168.1.100              # Update "VPN" rules with specific IP
    $0 -d "Remote" -p "22,80,443" -v          # Update "Remote" rules on ports 22, 80, and 443 with verbose output
    $0 -d "Database" -p "3306,5432"           # Update "Database" rules on MySQL and PostgreSQL ports

EOF
}

# Parse command line arguments
parse_args() {
	while [[ $# -gt 0 ]]; do
		case $1 in
		-d | --description)
			RULE_DESCRIPTION="$2"
			shift 2
			;;
		-p | --ports)
			PORTS="$2"
			shift 2
			;;
		-i | --ip)
			CURRENT_IP="$2"
			shift 2
			;;
		--profile)
			AWS_PROFILE="$2"
			shift 2
			;;
		-n | --dry-run)
			DRY_RUN=true
			shift
			;;
		-v | --verbose)
			VERBOSE=true
			shift
			;;
		-l | --log-file)
			# shellcheck disable=SC2034
			LOG_FILE="$2"
			shift 2
			;;
		-h | --help)
			usage
			exit 0
			;;
		*)
			echo -e "\033[0;31mError: Unknown option $1\033[0m"
			usage
			exit 1
			;;
		esac
	done
}

# Validate configuration
validate_config() {
	if [[ -z "$RULE_DESCRIPTION" ]]; then
		echo -e "\033[0;31mError: Rule description is required. Use -d or --description\033[0m"
		usage
		exit 1
	fi

	# Set default ports if not specified
	if [[ -z "$PORTS" ]]; then
		PORTS="22"
		log_info "No ports specified, defaulting to SSH (port 22)"
	fi

	# Validate port format and values
	if ! validate_ports "$PORTS"; then
		echo -e "\033[0;31mError: Invalid port specification. Use comma-separated numbers (e.g., '22,80,443')\033[0m"
		exit 1
	fi
}

# Validate port specification
validate_ports() {
	local ports_str="$1"

	# Check if ports string contains only numbers, commas, and optional spaces
	if [[ ! "$ports_str" =~ ^[0-9]+(,[[:space:]]*[0-9]+)*$ ]]; then
		return 1
	fi

	# Split ports and validate each one
	IFS=',' read -ra port_array <<<"$ports_str"
	for port in "${port_array[@]}"; do
		# Remove any whitespace
		port=$(echo "$port" | tr -d '[:space:]')
		# Check if port is in valid range (1-65535)
		if [[ $port -lt 1 || $port -gt 65535 ]]; then
			return 1
		fi
	done

	return 0
}

# Check prerequisites
check_prerequisites() {
	log_info "Checking prerequisites..."

	local missing_deps=()

	for cmd in aws jq curl; do
		if ! command -v "$cmd" >/dev/null 2>&1; then
			missing_deps+=("$cmd")
		fi
	done

	if [[ ${#missing_deps[@]} -gt 0 ]]; then
		log_fail "Missing required dependencies: ${missing_deps[*]}"
		log_info "Please install missing dependencies and try again"
		exit 1
	fi

	log_pass "All required dependencies are installed"
}

# Display current configuration
show_config() {
	if [[ "$DRY_RUN" == true ]]; then
		log_warn "DRY RUN MODE - No changes will be made"
	fi

	log_info "Configuration:"
	log_info "  Rule Description: $RULE_DESCRIPTION"
	log_info "  Ports: $PORTS"
	log_info "  Current IP: $CURRENT_IP"
	log_info "  Dry Run: $DRY_RUN"
	log_info "  Verbose: $VERBOSE"
	if [[ -n "$AWS_PROFILE" ]]; then
		log_info "  AWS Profile: $AWS_PROFILE"
	fi
}
