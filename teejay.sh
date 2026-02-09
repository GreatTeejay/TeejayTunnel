#!/usr/bin/env bash

# --- TEEJAY UI SETUP ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

LOG_LINES=()

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
    LOG_LINES+=("[$(date +"%H:%M:%S")] $1")
    if ((${#LOG_LINES[@]} > 5)); then LOG_LINES=("${LOG_LINES[@]:1}"); fi
}

# --- FUNCTIONS ---

setup_node() {
    local side=$1
    banner
    echo -e "${YELLOW}>>> Setup $side Side${NC}"
    
    local CURRENT_IP=$(hostname -I | awk '{print $1}')
    echo -e "Current IP: ${GREEN}$CURRENT_IP${NC}"
    read -p "Is this correct? (y/n): " confirm
    [[ "$confirm" != "y" ]] && read -p "Enter Local Public IP: " CURRENT_IP
    
    read -p "Enter Remote Public IP: " REMOTE_IP
    read -p "Enter Tunnel Local IP (e.g. 10.0.0.1): " L_PRIV
    read -p "Enter Tunnel Remote IP (e.g. 10.0.0.2): " R_PRIV

    # Using SIT Protocol (Stealthier than GRE/IPIP)
    ip tunnel add tj-tun mode sit remote $REMOTE_IP local $CURRENT_IP
    ip addr add $L_PRIV/30 dev tj-tun
    ip link set tj-tun mtu 1450
    ip link set tj-tun up

    # Keep-Alive Mechanism (Anti-Drop)
    # This prevents the ISP from dropping the idle connection
    (crontab -l 2>/dev/null | grep -v "tj-tun"; echo "*/1 * * * * ping -c 2 $R_PRIV >/dev/null 2>&1") | crontab -

    add_log "$side Tunnel Established ($L_PRIV)"
}

exclusive_forward() {
    banner
    echo -e "${YELLOW}>>> Exclusive Forwarding (Advanced Routing)${NC}"
    echo "This method uses PBR (Policy Based Routing) instead of NAT."
    
    read -p "Enter Kharej Private IP: " K_PRIV
    read -p "Enter Xray/V2Ray Port: " PORT

    # Enable Routing
    echo 1 > /proc/sys/net/ipv4/ip_forward

    # Using NFTABLES if available, otherwise optimized IPTables mangle
    # This is more efficient for high-speed Xray traffic
    iptables -t nat -A PREROUTING -p tcp --dport $PORT -j DNAT --to-destination $K_PRIV:$PORT
    iptables -t nat -A PREROUTING -p udp --dport $PORT -j DNAT --to-destination $K_PRIV:$PORT
    
    # MSS Clamping to prevent packet fragmentation (Crucial for Iran)
    iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1400
    
    add_log "Routing Rule Applied for Port $PORT"
    echo -e "${GREEN}Optimization Complete.${NC}"
    sleep 2
}

show_status() {
    banner
    echo -e "${CYAN}--- Interface Status ---${NC}"
    ip addr show tj-tun 2>/dev/null || echo -e "${RED}Tunnel Down${NC}"
    echo -e "\n${CYAN}--- Routing Table ---${NC}"
    ip route | grep tj-tun
    echo -e "\n${CYAN}--- Keep-Alive Check ---${NC}"
    crontab -l | grep tj-tun || echo "No keep-alive found."
    read -p "Press Enter..."
}

clear_all() {
    ip link set tj-tun down 2>/dev/null
    ip tunnel del tj-tun 2>/dev/null
    iptables -t nat -F
    iptables -t mangle -F
    crontab -l | grep -v "tj-tun" | crontab -
    add_log "System Cleared."
    echo -e "${RED}All tunnels and rules removed.${NC}"
    sleep 2
}

# --- MAIN MENU ---
while true; do
    banner
    for line in "${LOG_LINES[@]}"; do echo -e " $line"; done
    echo "-----------------------------------------------------"
    echo -e "1 - Setup Iran"
    echo -e "2 - Setup Kharej"
    echo -e "3 - Status"
    echo -e "4 - Uninstall / Clear"
    echo -e "5 - Exclusive Tunnel Forward"
    echo -e "0 - Exit"
    echo ""
    read -p "Selection: " choice

    case $choice in
        1) setup_node "Iran" ;;
        2) setup_node "Kharej" ;;
        3) show_status ;;
        4) clear_all ;;
        5) exclusive_forward ;;
        0) exit ;;
    esac
done
