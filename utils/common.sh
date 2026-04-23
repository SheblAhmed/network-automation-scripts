#!/bin/bash
# =============================================================================
#  common.sh — Shared utility functions for network automation scripts
#  Author: Crypto & Network Engineer
# =============================================================================

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# ── Logging helpers ───────────────────────────────────────────────────────────
log_info()    { echo -e "${CYAN}[INFO]${RESET}    $(date '+%Y-%m-%d %H:%M:%S')  $*"; }
log_ok()      { echo -e "${GREEN}[OK]${RESET}      $(date '+%Y-%m-%d %H:%M:%S')  $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${RESET}    $(date '+%Y-%m-%d %H:%M:%S')  $*"; }
log_error()   { echo -e "${RED}[ERROR]${RESET}   $(date '+%Y-%m-%d %H:%M:%S')  $*"; }
log_section() {
    echo -e "\n${BOLD}${CYAN}══════════════════════════════════════════════════${RESET}"
    echo -e "${BOLD}${CYAN}  $*${RESET}"
    echo -e "${BOLD}${CYAN}══════════════════════════════════════════════════${RESET}"
}

# ── SSH helpers ───────────────────────────────────────────────────────────────
# Run a command on a remote host via SSH
# Usage: ssh_run <host> <user> <command>
ssh_run() {
    local host="$1"
    local user="$2"
    local cmd="$3"
    ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no \
        -o BatchMode=yes "${user}@${host}" "${cmd}" 2>/dev/null
}

# Check if a host is reachable
# Usage: is_reachable <host>
is_reachable() {
    local host="$1"
    ping -c 1 -W 2 "${host}" &>/dev/null
}

# ── Certificate helpers ───────────────────────────────────────────────────────
# Get days until a certificate expires
# Usage: cert_days_remaining <cert_file_or_host:port>
cert_days_remaining() {
    local target="$1"
    local expiry

    if [[ -f "$target" ]]; then
        expiry=$(openssl x509 -enddate -noout -in "$target" 2>/dev/null | cut -d= -f2)
    else
        expiry=$(echo | openssl s_client -connect "$target" 2>/dev/null \
            | openssl x509 -enddate -noout 2>/dev/null | cut -d= -f2)
    fi

    if [[ -z "$expiry" ]]; then
        echo "-1"
        return
    fi

    local expiry_epoch now_epoch
    expiry_epoch=$(date -d "$expiry" +%s 2>/dev/null || date -j -f "%b %d %T %Y %Z" "$expiry" +%s)
    now_epoch=$(date +%s)
    echo $(( (expiry_epoch - now_epoch) / 86400 ))
}

# Print certificate expiry status with color coding
# Usage: check_cert_expiry <label> <cert_file_or_host:port> [warn_days] [crit_days]
check_cert_expiry() {
    local label="$1"
    local target="$2"
    local warn_days="${3:-30}"
    local crit_days="${4:-7}"
    local days
    days=$(cert_days_remaining "$target")

    if [[ "$days" -lt 0 ]]; then
        log_error "${label}: could not read certificate"
    elif [[ "$days" -le "$crit_days" ]]; then
        log_error "${label}: EXPIRES IN ${days} DAYS — CRITICAL"
    elif [[ "$days" -le "$warn_days" ]]; then
        log_warn  "${label}: expires in ${days} days — warning"
    else
        log_ok    "${label}: ${days} days remaining"
    fi
}

# ── Puppet helpers ────────────────────────────────────────────────────────────
# Check Puppet agent last run status on a remote host
# Usage: check_puppet_agent <host> <user>
check_puppet_agent() {
    local host="$1"
    local user="$2"
    local last_run

    last_run=$(ssh_run "$host" "$user" \
        "sudo puppet agent --last_run_summary 2>/dev/null | grep -i 'last run'")

    if [[ -z "$last_run" ]]; then
        log_warn "Puppet agent on ${host}: no last run data"
    else
        log_ok   "Puppet agent on ${host}: ${last_run}"
    fi
}

# Trigger Puppet agent run on a remote host
# Usage: trigger_puppet_run <host> <user>
trigger_puppet_run() {
    local host="$1"
    local user="$2"
    log_info "Triggering Puppet run on ${host}..."
    ssh_run "$host" "$user" "sudo puppet agent -t" && \
        log_ok "Puppet run completed on ${host}" || \
        log_error "Puppet run failed on ${host}"
}

# ── Service helpers ───────────────────────────────────────────────────────────
# Check if a systemd service is running on a remote host
# Usage: check_service <host> <user> <service_name>
check_service() {
    local host="$1"
    local user="$2"
    local service="$3"
    local status

    status=$(ssh_run "$host" "$user" "systemctl is-active ${service}")

    if [[ "$status" == "active" ]]; then
        log_ok   "${service} on ${host}: running"
    else
        log_error "${service} on ${host}: ${status}"
    fi
}

# ── Validation helpers ────────────────────────────────────────────────────────
# Confirm a step with the user before proceeding
# Usage: confirm_step "Are you sure?"
confirm_step() {
    local prompt="${1:-Continue?}"
    read -rp "$(echo -e "${YELLOW}${prompt} [y/N]: ${RESET}")" answer
    [[ "${answer,,}" == "y" ]]
}

# Require root or sudo
require_sudo() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run with sudo or as root."
        exit 1
    fi
}

# ── Summary helpers ───────────────────────────────────────────────────────────
FAILED_STEPS=()
PASSED_STEPS=()

record_pass() { PASSED_STEPS+=("$1"); }
record_fail() { FAILED_STEPS+=("$1"); }

print_summary() {
    log_section "Deployment Summary"
    echo -e "${GREEN}Passed (${#PASSED_STEPS[@]}):${RESET}"
    for s in "${PASSED_STEPS[@]}"; do echo -e "  ${GREEN}✓${RESET} $s"; done

    if [[ ${#FAILED_STEPS[@]} -gt 0 ]]; then
        echo -e "\n${RED}Failed (${#FAILED_STEPS[@]}):${RESET}"
        for s in "${FAILED_STEPS[@]}"; do echo -e "  ${RED}✗${RESET} $s"; done
        echo -e "\n${RED}Deployment completed with errors. Review above.${RESET}"
        return 1
    else
        echo -e "\n${GREEN}All steps completed successfully.${RESET}"
        return 0
    fi
}
