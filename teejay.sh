#!/usr/bin/env bash

# --- PRE-SETUP ---
export LC_ALL=C
LOG_LINES=()
LOG_MAX=8

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# --- UI & LOGGING ---
banner() {
    clear
    echo -e "${CYAN}╔═════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║  ████████╗███████╗███████╗██╗ █████╗ ██╗   ██╗      ║${NC}"
    echo -e "${BLUE}║  ╚══██╔══╝██╔════╝██╔════╝██║██╔══██╗╚██╗ ██╔╝      ║${NC}"
    echo -e "${BLUE}║     ██║   █████╗  █████╗  ██║███████║ ╚████╔╝       ║${NC}"
    echo -e "${BLUE}║     ██║   ██╔══╝  ██╔══╝  ██║██╔══██║  ╚██╔╝        ║${NC}"
    echo -e "${BLUE}║     ██║   ███████╗███████╗██║██║  ██║   ██║         ║${NC}"
    echo -e "${BLUE}║     ╚═╝   ╚══════╝╚══════╝╚═╝╚═╝  ╚═╝   ╚═╝         ║${NC}"
    echo -e "${YELLOW}║                EXCLUSIVE TUNNEL SYSTEM              ║${NC}"
    echo -e "${CYAN}╚═════════════════════════════════════════════════════╝${NC}"
}

add_log() {
    local ts=$(date +"%H:%M:%S")
    LOG_LINES+=("[$ts] $1")
    ((${#LOG_LINES[@]} > LOG_MAX)) && LOG_LINES=("${LOG_LINES[@]:1}")
}

render_logs() {
    echo -e "${YELLOW}┌──────────────────────── ACTION LOG ────────────────────────┐${NC}"
    for line in "${LOG_LINES[@]}"; do
        printf "${CYAN}│${NC} %-58s ${CYAN}│${NC}\n" "$line"
    done
    echo -e "${YELLOW}└────────────────────────────────────────────────────────────┘${NC}"
}

# --- VALIDATION ENGINE ---
trim() { sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' <<<"$1"; }

is_valid_ipv4() {
    local ip=$1
    [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
    IFS='.' read -r a b c d <<< "$ip"
    for octet in $a $b $c $d; do
        ((octet < 0 || octet > 255)) && return 1
    done
    return 0
}

ask_until_valid() {
    local prompt=$1
    local validator=$2
    local var_name=$3
    local input=""
    while true; do
        banner
        render_logs
        echo -e "${YELLOW}Input Required:${NC}"
        read -p "$prompt " input
        input=$(trim "$input")
        if [ -z "$input" ]; then
            add_log "Empty input, try again."
            continue
        fi
        if $validator "$input"; then
            eval "$var_name=\"$input\""
            add_log "Set $var_name to $input"
            break
        else
            add_log "Invalid input: $input"
        fi
    done
}

# Dummy validator for anything
any_val() { return 0; }
is_int() { [[ "$1" =~ ^[0-9]+$ ]]; }

# --- CORE LOGIC ---

setup_tunnel() {
    local side=$1 # Iran or Kharej
    banner
    
    local DEFAULT_IP=$(hostname -I | awk '{print $1}')
    local LOCAL_PUBLIC_IP
    
    # Confirm Local IP
    while true; do
        banner
        echo -e "Detected Local IP: ${GREEN}$DEFAULT_IP${NC}"
        read -p "Use this IP? (y/n): " confirm
        if [[ "$confirm" == "y" ]]; then
            LOCAL_PUBLIC_IP=$DEFAULT_IP
            break
        else
            ask_until_valid "Enter Local Public IP:" is_valid_ipv4 LOCAL_PUBLIC_IP
            break
        fi
    done

    ask_until_valid "Enter Remote Public IP:" is_valid_ipv4 REMOTE_PUBLIC_IP
    ask_until_valid "Enter Private IP (e.g., 10.0.0.1):" is_valid_ipv4 LOCAL_PRIV_IP
    ask_until_valid "Enter Remote Private IP (e.g., 10.0.0.2):" is_valid_ipv4 REMOTE_PRIV_IP

    # Persistence via Systemd
    add_log "Creating Systemd service for persistence..."
    cat <<EOF > /etc/systemd/system/teejay-tun.service
[Unit]
Description=TEEJAY Exclusive SIT Tunnel
After=network.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStartPre=-/sbin/ip tunnel del tj-tun
ExecStart=/sbin/ip tunnel add tj-tun mode sit remote $REMOTE_PUBLIC_IP local $LOCAL_PUBLIC_IP
ExecStart=/sbin/ip addr add $LOCAL_PRIV_IP peer $REMOTE_PRIV_IP dev tj-tun
ExecStart=/sbin/ip link set tj-tun mtu 1420
ExecStart=/sbin/ip link set tj-tun up
# MSS Clamping to prevent drops
ExecStart=/sbin/iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
ExecStop=/sbin/ip link set tj-tun down
ExecStop=/sbin/ip tunnel del tj-tun
ExecStop=/sbin/iptables -t mangle -D FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now teejay-tun.service
    
    # Keep Alive Cron
    (crontab -l 2>/dev/null | grep -v "tj-tun"; echo "*/1 * * * * ping -c 1 $REMOTE_PRIV_IP >/dev/null 2>&1") | crontab -
    
    add_log "$side Tunnel Established Successfully."
    read -p "Success! Press Enter to continue..."
}

tunnel_forward() {
    banner
    render_logs
    ask_until_valid "Enter Ports to Forward (e.g., 443,2053):" any_val PORTS
    ask_until_valid "Enter Remote Private IP (The other side):" is_valid_ipv4 REMOTE_PRIV
    
    echo 1 > /proc/sys/net/ipv4/ip_forward
    
    IFS=',' read -ra ADDR <<< "$PORTS"
    for port in "${ADDR[@]}"; do
        iptables -t nat -A PREROUTING -p tcp --dport $port -j DNAT --to-destination $REMOTE_PRIV:$port
        iptables -t nat -A PREROUTING -p udp --dport $port -j DNAT --to-destination $REMOTE_PRIV:$port
        iptables -t nat -A POSTROUTING -j MASQUERADE
        add_log "Port $port forwarded to $REMOTE_PRIV"
    done
    read -p "Forwarding rules applied. Press Enter..."
}

status_check() {
    banner
    echo -e "${YELLOW}>>> Network Interface:${NC}"
    ip addr show tj-tun 2>/dev/null || echo -e "${RED}Interface tj-tun not found.${NC}"
    echo -e "\n${YELLOW}>>> Internal Ping Test:${NC}"
    R_IP=$(ip addr show tj-tun 2>/dev/null | grep peer | awk '{print $4}' | cut -d/ -f1)
    if [ ! -z "$R_IP" ]; then
        ping -c 2 $R_IP
    else
        echo -e "${RED}Tunnel is not linked.${NC}"
    fi
    read -p "Press Enter..."
}

uninstall() {
    systemctl stop teejay-tun.service 2>/dev/null
    systemctl disable teejay-tun.service 2>/dev/null
    rm /etc/systemd/system/teejay-tun.service 2>/dev/null
    iptables -t nat -F
    crontab -l | grep -v "tj-tun" | crontab -
    add_log "Cleanup completed."
    read -p "System wiped. Press Enter..."
}

# --- MENU ---
while true; do
    banner
    render_logs
    echo -e "${CYAN}1 - Setup Iran Server${NC}"
    echo -e "${CYAN}2 - Setup Kharej Server${NC}"
    echo -e "${CYAN}3 - Status & Ping Test${NC}"
    echo -e "${CYAN}4 - Uninstall / Clear All${NC}"
    echo -e "${CYAN}5 - Port Forwarding${NC}"
    echo -e "${RED}0 - Exit${NC}"
    echo ""
    read -p "Choice: " choice
    case $choice in
        1) setup_tunnel "Iran" ;;
        2) setup_tunnel "Kharej" ;;
        3) status_check ;;
        4) uninstall ;;
        5) tunnel_forward ;;
        0) exit 0 ;;
        *) add_log "Invalid Option";;
    esac
done
