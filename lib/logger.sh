#!/bin/bash
# Logger utilities for groupsyncer
# Provides colored logging functions with file output

# Color Constants
readonly LOG_GREEN='\033[0;32m'
readonly LOG_RED='\033[0;31m'
readonly LOG_YELLOW='\033[1;33m'
readonly LOG_BLUE='\033[0;34m'
readonly LOG_NC='\033[0m'

# Standard Logging Functions
log_pass() {
	echo -e "${LOG_GREEN}✓ ${LOG_NC} $1" | tee -a "$LOG_FILE"
}

log_fail() {
	echo -e "${LOG_RED}✗ ${LOG_NC} $1" | tee -a "$LOG_FILE"
}

log_warn() {
	echo -e "${LOG_YELLOW}⚠ ${LOG_NC} $1" | tee -a "$LOG_FILE"
}

log_info() {
	echo -e "${LOG_BLUE}ℹ ${LOG_NC} $1" | tee -a "$LOG_FILE"
}

# Verbose Logging Functions
log_verbose() {
	if [[ "$VERBOSE" == true ]]; then
		if [[ "${SILENT_MODE:-false}" == true ]]; then
			echo -e "${LOG_BLUE}[DEBUG] ${LOG_NC} $1" >>"$LOG_FILE"
		else
			echo -e "${LOG_BLUE}[DEBUG] ${LOG_NC} $1" | tee -a "$LOG_FILE"
		fi
	fi
}

# Verbose logging that only logs to file if VERBOSE is disabled
log_verbose_silent() {
	if [[ "$VERBOSE" == true ]]; then
		echo -e "${LOG_BLUE}[DEBUG] ${LOG_NC} $1" >>"$LOG_FILE"
	fi
}

# Silent Logging Functions
# For use in background processing
log_pass_silent() {
	echo -e "${LOG_GREEN}✓ ${LOG_NC} $1" >>"$LOG_FILE"
}

log_fail_silent() {
	echo -e "${LOG_RED}✗ ${LOG_NC} $1" >>"$LOG_FILE"
}

log_warn_silent() {
	echo -e "${LOG_YELLOW}⚠ ${LOG_NC} $1" >>"$LOG_FILE"
}

log_info_silent() {
	echo -e "${LOG_BLUE}ℹ ${LOG_NC} $1" >>"$LOG_FILE"
}

# Section Logging Functions
# Create bordered section headers for better organization
log_section() {
	local title="$1"
	local title_length=${#title}
	local border_length=$((title_length + 2))
	local border
	border=$(printf '═%.0s' $(seq 1 $border_length))

	echo -e "\n${LOG_BLUE}╔${border}╗${LOG_NC}" | tee -a "$LOG_FILE"
	echo -e "${LOG_BLUE}║ ${title} ║${LOG_NC}" | tee -a "$LOG_FILE"
	echo -e "${LOG_BLUE}╚${border}╝${LOG_NC}" | tee -a "$LOG_FILE"
}

# Log File Initialization
init_log_file() {
	local script_name="$1"
	echo "AWS Security Group SSH Rules Updater - $(date)" >"$LOG_FILE"
	echo "Command: $script_name $*" >>"$LOG_FILE"
	echo "================================" >>"$LOG_FILE"
}
