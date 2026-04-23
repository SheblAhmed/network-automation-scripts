#!/bin/bash
# =============================================================================
#  system-health-check.sh
#  Enterprise infrastructure health check — connectivity, services, certs, Puppet
#  Usage: ./system-health-check.sh [--hosts hosts.txt] [--user USER]
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils/common.sh"

HOSTS_FILE="${SCRIPT_DIR}/hosts/hosts.txt"
SSH_USER=""
WARN_CERT_DAYS=30
LOG_FILE="/tmp/health_check_$(date +%Y%m%d_%H%M%S).log"

# Services to check on each host (space-separated)
SERVICES_TO_CHECK="slapd rsyslog httpd puppet"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --hosts) HOSTS_FILE="$2"; shift 2 ;;
        --user)  SSH_USER="$2";   shift 2 ;;
        --help)
            echo "Usage: $0 [--hosts FILE] [--user USER]"
            exit 0 ;;
        *) log_error "Unknown argument: $1"; exit 1 ;;
    esac
done

exec > >(tee -a "$LOG_FILE") 2>&1

log_section "Enterprise Infrastructure Health Check"
log_info "$(date)"
log_info "Log: ${LOG_FILE}"

if [[ -z "$SSH_USER" ]]; then
    read -rp "$(echo -e "${BOLD}SSH username: ${RESET}")" SSH_USER
fi

if [[ ! -f "$HOSTS_FILE" ]]; then
    log_error "Hosts file not found: ${HOSTS_FILE}"
    exit 1
fi

HOSTS=()
while IFS= read -r line; do
    [[ -z "$line" || "$line" =~ ^# ]] && continue
    HOSTS+=("$line")
done < "$HOSTS_FILE"

log_info "Checking ${#HOSTS[@]} hosts..."

# ── Per-host checks ───────────────────────────────────────────────────────────
for host in "${HOSTS[@]}"; do
    log_section "Host: ${host}"

    # 1. Reachability
    if ! is_reachable "$host"; then
        log_error "${host}: UNREACHABLE"
        record_fail "${host} (unreachable)"
        continue
    fi
    log_ok "${host}: reachable"

    # 2. SSH connectivity
    if ! ssh_run "$host" "$SSH_USER" "echo ok" &>/dev/null; then
        log_error "${host}: SSH failed"
        record_fail "${host} (SSH failed)"
        continue
    fi
    log_ok "${host}: SSH connected"

    # 3. Service status
    for svc in $SERVICES_TO_CHECK; do
        status=$(ssh_run "$host" "$SSH_USER" "systemctl is-active ${svc} 2>/dev/null")
        if [[ "$status" == "active" ]]; then
            log_ok   "  Service ${svc}: running"
            record_pass "${host}/${svc}"
        elif [[ "$status" == "inactive" || "$status" == "dead" ]]; then
            log_warn "  Service ${svc}: stopped"
            record_fail "${host}/${svc} (stopped)"
        else
            log_warn "  Service ${svc}: ${status:-not found}"
        fi
    done

    # 4. Puppet agent last run
    last_run=$(ssh_run "$host" "$SSH_USER" \
        "stat -c '%y' /opt/puppetlabs/puppet/cache/state/last_run_summary.yaml 2>/dev/null | cut -d' ' -f1")
    if [[ -n "$last_run" ]]; then
        log_ok "  Puppet last run: ${last_run}"
    else
        log_warn "  Puppet: no last run data"
    fi

    # 5. Disk usage
    disk=$(ssh_run "$host" "$SSH_USER" "df -h / | awk 'NR==2{print \$5\" used of \"\$2}'")
    log_info "  Disk: ${disk:-unknown}"

    # 6. Load average
    load=$(ssh_run "$host" "$SSH_USER" "uptime | awk -F'load average:' '{print \$2}'")
    log_info "  Load average:${load:-unknown}"

    record_pass "${host} (health check complete)"
done

# ── Final summary ─────────────────────────────────────────────────────────────
print_summary
log_info "Full report: ${LOG_FILE}"
