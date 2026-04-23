#!/bin/bash
# =============================================================================
#  cert-expiry-monitor.sh
#  Scans certificates on managed hosts and reports expiry status
#  Usage: ./cert-expiry-monitor.sh [--hosts hosts.txt] [--warn-days 30]
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../utils/common.sh"

# ── Defaults ──────────────────────────────────────────────────────────────────
HOSTS_FILE="${SCRIPT_DIR}/../hosts/hosts.txt"
WARN_DAYS=30
CRIT_DAYS=7
SSH_USER=""
LOG_FILE="/tmp/cert_monitor_$(date +%Y%m%d_%H%M%S).log"

# ── Parse arguments ───────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --hosts)      HOSTS_FILE="$2";  shift 2 ;;
        --warn-days)  WARN_DAYS="$2";   shift 2 ;;
        --crit-days)  CRIT_DAYS="$2";   shift 2 ;;
        --user)       SSH_USER="$2";    shift 2 ;;
        --help)
            echo "Usage: $0 [--hosts FILE] [--warn-days N] [--crit-days N] [--user USER]"
            exit 0 ;;
        *) log_error "Unknown argument: $1"; exit 1 ;;
    esac
done

exec > >(tee -a "$LOG_FILE") 2>&1

# ── Gather credentials ────────────────────────────────────────────────────────
log_section "Certificate Expiry Monitor"
log_info "Log file: ${LOG_FILE}"
log_info "Warn threshold: ${WARN_DAYS} days | Critical threshold: ${CRIT_DAYS} days"

if [[ -z "$SSH_USER" ]]; then
    read -rp "$(echo -e "${BOLD}SSH username: ${RESET}")" SSH_USER
fi

if [[ ! -f "$HOSTS_FILE" ]]; then
    log_error "Hosts file not found: ${HOSTS_FILE}"
    exit 1
fi

# ── Read hosts ────────────────────────────────────────────────────────────────
HOSTS=()
while IFS= read -r line; do
    [[ -z "$line" || "$line" =~ ^# ]] && continue
    HOSTS+=("$line")
done < "$HOSTS_FILE"

log_info "Loaded ${#HOSTS[@]} hosts from ${HOSTS_FILE}"

# ── Scan each host ────────────────────────────────────────────────────────────
log_section "Scanning Hosts"

EXPIRED=()
CRITICAL=()
WARNING=()
OK=()

for host in "${HOSTS[@]}"; do
    if ! is_reachable "$host"; then
        log_warn "${host}: unreachable — skipping"
        FAILED_STEPS+=("${host} (unreachable)")
        continue
    fi

    log_info "Scanning ${host}..."

    # Get all cert files on the remote host
    cert_files=$(ssh_run "$host" "$SSH_USER" \
        "find /etc/ssl /etc/pki /opt -name '*.crt' -o -name '*.pem' 2>/dev/null | head -20")

    if [[ -z "$cert_files" ]]; then
        log_warn "${host}: no certificates found"
        continue
    fi

    while IFS= read -r cert_path; do
        [[ -z "$cert_path" ]] && continue

        # Get expiry date from remote cert
        expiry=$(ssh_run "$host" "$SSH_USER" \
            "openssl x509 -enddate -noout -in '${cert_path}' 2>/dev/null | cut -d= -f2")

        [[ -z "$expiry" ]] && continue

        expiry_epoch=$(date -d "$expiry" +%s 2>/dev/null)
        now_epoch=$(date +%s)
        days=$(( (expiry_epoch - now_epoch) / 86400 ))
        label="${host}:${cert_path}"

        if [[ $days -lt 0 ]]; then
            log_error "EXPIRED: ${label} (${days} days ago)"
            EXPIRED+=("$label")
        elif [[ $days -le $CRIT_DAYS ]]; then
            log_error "CRITICAL: ${label} — ${days} days remaining"
            CRITICAL+=("$label | ${days} days")
        elif [[ $days -le $WARN_DAYS ]]; then
            log_warn  "WARNING:  ${label} — ${days} days remaining"
            WARNING+=("$label | ${days} days")
        else
            log_ok    "OK:       ${label} — ${days} days remaining"
            OK+=("$label")
        fi

    done <<< "$cert_files"
done

# ── Summary report ────────────────────────────────────────────────────────────
log_section "Summary Report"

echo -e "${GREEN}OK (${#OK[@]} certs)${RESET}"
echo -e "${YELLOW}Warning (${#WARNING[@]} certs):${RESET}"
for w in "${WARNING[@]}"; do echo -e "  ${YELLOW}!${RESET} $w"; done
echo -e "${RED}Critical (${#CRITICAL[@]} certs):${RESET}"
for c in "${CRITICAL[@]}"; do echo -e "  ${RED}!!${RESET} $c"; done
echo -e "${RED}Expired (${#EXPIRED[@]} certs):${RESET}"
for e in "${EXPIRED[@]}"; do echo -e "  ${RED}✗${RESET} $e"; done

echo ""
log_info "Full log saved to: ${LOG_FILE}"

# Exit with error code if any critical/expired certs found
[[ ${#EXPIRED[@]} -gt 0 || ${#CRITICAL[@]} -gt 0 ]] && exit 2
[[ ${#WARNING[@]} -gt 0 ]] && exit 1
exit 0
