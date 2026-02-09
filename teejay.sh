#!/bin/bash

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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
    echo -e "${YELLOW}           TEEJAY EXCLUSIVE - INDEPENDENT VERSION ${NC}"
    echo "---------------------------------------------------"
}

install_core() {
    if [ -f "/usr/local/bin/v2ray" ]; then
        echo -e "${GREEN}[*] V2Ray is already installed.${NC}"
        return
    fi

    echo -e "${YELLOW}[*] Installing V2Ray Core manually...${NC}"
    apt update && apt install -y curl unzip uuid-runtime

    # Downloading the binary directly
    V2RAY_URL="https://github.com/v2fly/v2ray-core/releases/latest/download/v2ray-linux-64.zip"
    curl -L -o v2ray.zip "$V2RAY_URL"

    if [ $? -ne 0 ]; then
        echo -e "${RED}[!] Download failed. Please check your internet connection.${NC}"
        exit 1
    fi

    mkdir -p /usr/local/bin /usr/local/etc/v2ray /var/log/v2ray
    unzip -o v2ray.zip -d /usr/local/bin
    chmod +x /usr/local/bin/v2ray

    # CREATING SYSTEMD SERVICE MANUALLY
    echo -e "${YELLOW}[*] Creating V2Ray systemd service...${NC}"
    cat <<EOF > /etc/systemd/system/v2ray.service
[Unit]
Description=V2Ray Service by TEEJAY
After=network.target nss-lookup.target

[Service]
User=root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=/usr/local/bin/v2ray run -config /usr/local/etc/v2ray/config.json
Restart=on-failure
RestartPreventExitStatus=23

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable v2ray
    echo -e "${GREEN}[+] V2Ray core and service installed successfully.${NC}"
}

setup_iran() {
    display_logo
    install_core
    
    u_id=$(uuidgen)
    read -p "Enter Foreign Server IP: " foreign_ip
    read -p "Enter Ports to Forward (comma separated, e.g., 80,443): " ports
    
    mkdir -p /usr/local/etc/v2ray
    cat <<EOF > /usr/local/etc/v2ray/config.json
{
  "reverse": { "bridges": [ { "tag": "bridge", "domain": "teejay.internal" } ] },
  "inbounds": [
    {
      "tag": "tunnel", "port": 40040, "protocol": "vmess",
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
    echo -e "${GREEN}[+] Iran Server Ready!${NC}"
    echo -e "UUID: ${BLUE}${u_id}${NC}"
    echo -e "---------------------------------------------------"
    read -p "Press Enter to return..."
}

setup_kharej() {
    display_logo
    install_core
    read -p "Enter Iran Server IP: " iran_ip
    read -p "Enter UUID: " u_id
    
    mkdir -p /usr/local/etc/v2ray
    cat <<EOF > /usr/local/etc/v2ray/config.json
{
  "reverse": { "portals": [ { "tag": "portal", "domain": "teejay.internal" } ] },
  "outbounds": [
    {
      "tag": "tunnel", "protocol": "vmess",
      "settings": { "vnext": [ { "address": "${iran_ip}", "port": 40040, "users": [ { "id": "${u_id}" } ] } ] },
      "streamSettings": { "network": "grpc", "grpcSettings": { "serviceName": "teejay-grpc" } }
    },
    { "protocol": "freedom", "tag": "direct" }
  ],
  "
