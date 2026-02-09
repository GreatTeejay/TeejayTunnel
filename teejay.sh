#!/bin/bash

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# --- Logo Function ---
display_logo() {
    clear
    echo -e "${BLUE}"
    echo "  _______ ______ ______      _         __     __"
    echo " |__   __|  ____|  ____|    | |      /\\ \ \   / /"
    echo "    | |  | |__  | |__       | |     /  \\ \ \_/ / "
    echo "    | |  |  __| |  __|  _   | |    / /\ \\ \   /  "
    echo "    | |  | |____| |____| |__| |   / ____ \\ | |   "
    echo "    |_|  |______|______|\\____/   /_/    \\_\\|_|   "
    echo -e "${NC}"
    echo -e "${YELLOW}           TEEJAY EXCLUSIVE - FINAL VERSION 2026 ${NC}"
    echo "---------------------------------------------------"
}

# --- System Optimization ---
optimize_system() {
    echo -e "${YELLOW}[*] Optimizing Network Parameters (BBR & TCP)...${NC}"
    cat <<EOF > /etc/sysctl.d/teejay.conf
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.ipv4.ip_forward=1
net.core.rmem_max=67108864
net.core.wmem_max=67108864
net.ipv4.tcp_rmem=4096 87380 67108864
net.ipv4.tcp_wmem=4096 65536 67108864
EOF
    sysctl --system > /dev/null
}

# --- Installation ---
install_core() {
    echo -e "${YELLOW}[*] Installing dependencies and V2Ray Core...${NC}"
    apt update && apt install -y curl jq uuid-runtime
    curl -L https://raw.githubusercontent.com/v2fly/fxtls/main/install.sh | bash
    systemctl enable v2ray
}

# --- Setup Iran (Bridge) ---
setup_iran() {
    display_logo
    optimize_system
    install_core
    
    u_id=$(uuidgen)
    echo -e "${BLUE}Unique Secret Key Generated: ${u_id}${NC}"
    
    read -p "Enter Foreign Server IP: " foreign_ip
    read -p "Enter Ports to Forward (comma separated, e.g., 80,443,2082): " ports
    
    cat <<EOF > /usr/local/etc/v2ray/config.json
{
  "reverse": { "bridges": [ { "tag": "bridge", "domain": "teejay.internal" } ] },
  "inbounds": [
    {
      "tag": "tunnel",
      "port": 40040,
      "protocol": "vmess",
      "settings": { "clients": [ { "id": "${u_id}" } ] },
      "streamSettings": { "network": "grpc", "grpcSettings": { "serviceName": "teejay-grpc" } }
    }
EOF

    IFS=',' read -ra ADDR <<< "$ports"
    for port in "${ADDR[@]}"; do
        cat <<EOF >> /usr/local/etc/v2ray/config.json
    ,{ "port": ${port}, "protocol": "dokodemo-door", "settings": { "address": "127.0.0.1" }, "tag": "in-${port}" }
EOF
    done

    echo "  ], \"routing\": { \"rules\": [" >> /usr/local/etc/v2ray/config.json
    for port in "${ADDR[@]}"; do
        echo " { \"type\": \"field\", \"inboundTag\": [\"in-${port}\"], \"outboundTag\": \"bridge\" }," >> /usr/local/etc/v2ray/config.json
    done
    echo " { \"type\": \"field\", \"inboundTag\": [\"tunnel\"], \"outboundTag\": \"portal\" } ] } }" >> /usr/local/etc/v2ray/config.json

    systemctl restart v2ray
    echo -e "---------------------------------------------------"
    echo -e "${GREEN}[+] Iran Server is READY!${NC}"
    echo -e "${YELLOW}!!! COPY THIS KEY !!!${NC}"
    echo -e "UUID: ${BLUE}${u_id}${NC}"
    echo -e "---------------------------------------------------"
    read -p "Press Enter after you copied the UUID..."
}

# --- Setup Foreign (Portal) ---
setup_kharej() {
    display_logo
    optimize_system
    install_core
    
    read -p "Enter Iran Server IP: " iran_ip
    read -p "Enter UUID: " u_id
    
    cat <<EOF > /usr/local/etc/v2ray/config.json
{
  "reverse": { "portals": [ { "tag": "portal", "domain": "teejay.internal" } ] },
  "outbounds": [
    {
      "tag": "tunnel",
      "protocol": "vmess",
      "settings": {
        "vnext": [ { "address": "${iran_ip}", "port": 40040, "users": [ { "id": "${u_id}" } ] } ]
      },
      "streamSettings": { "network": "grpc", "grpcSettings": { "serviceName": "teejay-grpc" } }
    },
    { "protocol": "freedom", "tag": "direct" }
  ],
  "routing": {
    "rules": [ { "type": "field", "outboundTag": "portal", "inboundTag": ["tunnel"] } ]
  }
}
EOF

    systemctl restart v2ray
    echo -e "${GREEN}[+] Reverse Connection established from Foreign to Iran.${NC}"
    read -p "Press Enter to return to menu..."
}

# --- Main Logic ---
while true; do
    display_logo
    echo -e "1) Setup Iran ${BLUE}(Listener/Bridge)${NC}"
    echo -e "2) Setup Foreign ${BLUE}(Connector/Portal)${NC}"
    echo -e "3) Status ${BLUE}(Check Services)${NC}"
    echo -e "4) CronJob ${BLUE}(Enable Persistence)${NC}"
    echo -e "5) Exit ${RED}(Quit)${NC}"
    echo "---------------------------------------------------"
    read -p "Select an option: " opt
    
    case $opt in
        1) setup_iran ;;
        2) setup_kharej ;;
        3) systemctl status v2ray | grep -E "Active|Main PID" ; read -p "Press Enter..." ;;
        4) (crontab -l 2>/dev/null; echo "*/10 * * * * systemctl restart v2ray") | crontab - && echo "CronJob set successfully." ; sleep 2 ;;
        5) exit 0 ;;
        *) echo "Invalid option" ; sleep 1 ;;
    esac
done
