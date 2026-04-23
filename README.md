# network-automation-scripts

# Network Automation Scripts

> A collection of production-tested Bash scripts for network infrastructure automation — certificate deployment, PKI management, configuration automation, and system hardening. Built for enterprise environments running Cisco, FortiGate, CentOS, and Linux-based systems.

---

## Overview

This repository contains automation scripts developed and used in a real enterprise network environment serving 100+ users. Scripts cover certificate lifecycle management, Puppet-based configuration automation, and infrastructure maintenance tasks.

---

## Scripts

### 1. PKI Certificate Deployment — Automatic (Puppet)

`cert-deploy-auto.sh`

Automates certificate deployment across enterprise systems using Puppet Master/Agent on CentOS. Handles LDAP and Syslog services with full verification and rollback support.

**Features:**
- Puppet Master/Agent orchestration
- Automatic certificate push to all registered agents
- Pre/post deployment verification
- Error detection with guided remediation
- Full deployment log with timestamps

**Usage:**
```bash
chmod +x cert-deploy-auto.sh
sudo ./cert-deploy-auto.sh
```

---

### 2. PKI Certificate Deployment — Manual

`cert-deploy-manual.sh`

Manual certificate deployment for systems not managed by Puppet — workstations, standalone servers, and edge devices.

**Covers:**
- LogInsight (syslog-server-logbackup)
- SMAC workstation certificates (httpd)
- MCC workstation certificates
- Firefox CA import across all workstations

**Usage:**
```bash
chmod +x cert-deploy-manual.sh
sudo ./cert-deploy-manual.sh
```

---

### 3. System Health Check

`system-health-check.sh`

Quick infrastructure health check script — verifies connectivity, service status, certificate expiry dates, and Puppet agent status across all managed nodes.

**Checks:**
- Certificate expiry warnings (30/7/1 day thresholds)
- Puppet agent last run status
- Critical service status (LDAP, Syslog, HTTP)
- Network reachability to key hosts

**Usage:**
```bash
chmod +x system-health-check.sh
./system-health-check.sh
```

---

### 4. Certificate Expiry Monitor

`cert-expiry-monitor.sh`

Scans all certificates on managed systems and reports expiry status. Outputs a color-coded summary with days remaining.

**Usage:**
```bash
./cert-expiry-monitor.sh --hosts hosts.txt --warn-days 30
```

---

## Requirements

- Bash 4.0+
- CentOS 7/8 or RHEL-compatible
- Puppet Master/Agent (for automatic deployment scripts)
- SSH access with sudo privileges to target hosts
- OpenSSL (for certificate inspection)

---

## Environment

These scripts were developed for and tested in:

| Component | Technology |
|-----------|-----------|
| Config management | Puppet Master/Agent |
| OS | CentOS 7/8 |
| PKI | Internal CA (EJBCA) |
| Services | OpenLDAP, Syslog, Apache httpd |
| Firewall | FortiGate, Cisco Firepower |

---

## Security Notes

- Scripts prompt for credentials at runtime — no hardcoded passwords
- All actions are logged to `/tmp/` with timestamps
- Dry-run mode available on destructive operations
- Certificate private keys are never logged

---

## Repository Structure

```
network-automation-scripts/
├── certificates/
│   ├── cert-deploy-auto.sh       # Puppet-based automatic deployment
│   ├── cert-deploy-manual.sh     # Manual deployment for non-Puppet hosts
│   └── cert-expiry-monitor.sh    # Expiry monitoring and alerting
├── monitoring/
│   └── system-health-check.sh   # Infrastructure health check
├── utils/
│   └── common.sh                 # Shared functions and color helpers
├── hosts/
│   └── hosts.txt.example         # Example hosts file format
└── docs/
    └── deployment-guide.md       # Step-by-step deployment guide
```

---

## Contributing

Scripts are battle-tested in production. If you adapt them for your environment, feel free to open a PR with improvements.

---

*Developed over 10+ years of enterprise network engineering experience.*
