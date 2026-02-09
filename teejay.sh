#!/bin/bash

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration Files
TUNNEL_CONF="/etc/teejay_tunnel.conf"

# Helper Functions
function print_logo() {
    clear
    echo -e "${CYAN}"
    echo "  _______ ______ ______      _   _ __   __"
    echo " |__   __|  ____|  ____|    | | | |  \\ /  |"
    echo "    | |  | |__  | |__       | | | | \\ V / "
    echo "    | |  |  __| |  __|  _   | | | |  > <  "
    echo "    | |  | |____| |____| |__| |_| | / . \ "
    echo "    |_|  |______|______|\\____/\\___|/_/ \\_\\"
    echo -e "${NC}"
    echo -e "${YELLOW}       EXCLUSIVE TUNNEL SOLUTION${NC}"
    echo -e "${BLUE}       Optimized for High Latency Networks${NC}"
    echo "------------------------------------------------"
}

function check_root() {
    if [[ $EUID -ne 0 ]]; then
       echo -e "${RED}This script must be run as root${NC}" 
       exit 1
    fi
}

function get_public_ip() {
    # Try to get IP without external tools like curl if possible, but curl is standard.
    # If network is restricted, we ask user to confirm.
    DETECTED_IP=$(ip -4 addr | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v "127.0.0" | head -n 1)
    echo -e "Detected Local IP: ${GREEN}$DETECTED_IP${NC}"
    read -p "Is this your Public IP? (y/n): " confirm
    if [[ $confirm == "y" ]]; then
        LOCAL_IP=$DETECTED_IP
    else
        read -p "Enter your Public IP manually: " LOCAL_IP
    fi
}

function setup_tunnel() {
    ROLE=$1 # "master" (Iran) or "slave" (Kharej)
    
    print_logo
    echo -e "${GREEN}>>> Setup Tunnel ($ROLE Side)${NC}"
    
    get_public_ip
    
    read -p "Enter REMOTE Server IP: " REMOTE_IP
    
    echo -e "${YELLOW}--- Private IP Configuration ---${NC}"
    echo "Example: 10.10.10.1 for Iran, 10.10.10.2 for Kharej"
    read -p "Enter Local Private IP (e.g., 10.10.10.1): " PRIVATE_IP_LOCAL
    read -p "Enter Remote Private IP (e.g., 10.10.10.2): " PRIVATE_IP_REMOTE
    
    # Save Config
    echo "LOCAL_IP=$LOCAL_IP" > $TUNNEL_CONF
    echo "REMOTE_IP=$REMOTE_IP" >> $TUNNEL_CONF
    echo "PRIVATE_IP_LOCAL=$PRIVATE_IP_LOCAL" >> $TUNNEL_CONF
    echo "PRIVATE_IP_REMOTE=$PRIVATE_IP_REMOTE" >> $TUNNEL_CONF
    
    # Create Tunnel Script
    cat <<EOF > /usr/local/bin/teejay-up.sh
#!/bin/bash
# Clear old tunnel if exists
ip tunnel del tj-tun0 2>/dev/null

# Create IPIP Tunnel (Lighter than GRE)
ip tunnel add tj-tun0 mode ipip remote $REMOTE_IP local $LOCAL_IP ttl 255
ip link set tj-tun0 up
ip addr add $PRIVATE_IP_LOCAL/30 dev tj-tun0

# Optimize MTU/MSS for Iran Network
ip link set dev tj-tun0 mtu 1300
iptables -t mangle -A POSTROUTING -p tcp --tcp-flags SYN,RST SYN -o tj-tun0 -j TCPMSS --set-mss 1260

echo "Tunnel Interface tj-tun0 Created."
EOF
    
    chmod +x /usr/local/bin/teejay-up.sh
    bash /usr/local/bin/teejay-up.sh

    # Create Keepalive Watchdog (The Optimization)
    echo -e "${BLUE}Installing Watchdog Service (Anti-Disconnect)...${NC}"
    
    cat <<EOF > /usr/local/bin/teejay-watchdog.sh
#!/bin/bash
REMOTE="$PRIVATE_IP_REMOTE"
while true; do
    if ! ping -c 3 -W 2 \$REMOTE > /dev/null; then
        echo "\$(date): Connection lost, restarting tunnel..."
        /usr/local/bin/teejay-up.sh
        # Re-apply firewall rules if needed (calls the forward script if exists)
        if [ -f /usr/local/bin/teejay-fwd.sh ]; then
            bash /usr/local/bin/teejay-fwd.sh
        fi
    fi
    sleep 20
done
EOF
    chmod +x /usr/local/bin/teejay-watchdog.sh

    # Systemd Service
    cat <<EOF > /etc/systemd/system/teejay-tunnel.service
[Unit]
Description=TeeJay Exclusive Tunnel Watchdog
After=network.target

[Service]
ExecStart=/usr/local/bin/teejay-watchdog.sh
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable teejay-tunnel
    systemctl start teejay-tunnel

    echo -e "${GREEN}Tunnel Setup Complete with Watchdog!${NC}"
    read -p "Press Enter to return..."
}

function show_status() {
    print_logo
    if [ -f $TUNNEL_CONF ]; then
        source $TUNNEL_CONF
        echo -e "Local Private IP: ${CYAN}$PRIVATE_IP_LOCAL${NC}"
        echo -e "Remote Private IP: ${CYAN}$PRIVATE_IP_REMOTE${NC}"
        echo -e "Tunnel Status (Interface):"
        ip addr show tj-tun0 | grep inet
        echo "-----------------------------------"
        echo -e "${YELLOW}Testing Connectivity (Ping)...${NC}"
        ping -c 4 $PRIVATE_IP_REMOTE
    else
        echo -e "${RED}No configuration found!${NC}"
    fi
    read -p "Press Enter to return..."
}

function setup_forwarding() {
    print_logo
    echo -e "${GREEN}>>> Setup Port Forwarding (IPTABLES)${NC}"
    echo -e "${YELLOW}Note: This should be run on the IRAN server.${NC}"
    
    if [ ! -f $TUNNEL_CONF ]; then
        echo -e "${RED}Please setup the tunnel first!${NC}"
        read -p "Press Enter..."
        return
    fi
    
    source $TUNNEL_CONF
    
    read -p "Enter Local Port (Iran Port to connect to): " L_PORT
    read -p "Enter Destination Port (Xray Port on Kharej): " D_PORT
    
    # Using the PRIVATE IP of Kharej as destination
    DEST_IP=$PRIVATE_IP_REMOTE
    
    echo -e "${BLUE}Applying IPTABLES rules (NAT)...${NC}"
    
    cat <<EOF > /usr/local/bin/teejay-fwd.sh
#!/bin/bash
# Enable IP Forwarding
sysctl -w net.ipv4.ip_forward=1 > /dev/null

# Flush existing specific rules to avoid duplicates (Simple flush)
# Ideally, we should manage chains, but for simplicity:
iptables -t nat -D PREROUTING -p tcp --dport $L_PORT -j DNAT --to-destination $DEST_IP:$D_PORT 2>/dev/null
iptables -t nat -D PREROUTING -p udp --dport $L_PORT -j DNAT --to-destination $DEST_IP:$D_PORT 2>/dev/null
iptables -t nat -D POSTROUTING -j MASQUERADE 2>/dev/null

# Add Rules
iptables -t nat -A PREROUTING -p tcp --dport $L_PORT -j DNAT --to-destination $DEST_IP:$D_PORT
iptables -t nat -A PREROUTING -p udp --dport $L_PORT -j DNAT --to-destination $DEST_IP:$D_PORT
iptables -t nat -A POSTROUTING -j MASQUERADE

echo "Forwarding: :$L_PORT -> $DEST_IP:$D_PORT set."
EOF
    
    chmod +x /usr/local/bin/teejay-fwd.sh
    bash /usr/local/bin/teejay-fwd.sh
    
    echo -e "${GREEN}Port Forwarding Active!${NC}"
    echo -e "Connect your client to: ${LOCAL_IP}:${L_PORT}"
    read -p "Press Enter to return..."
}

function uninstall_all() {
    echo -e "${RED}Uninstalling TeeJay Tunnel...${NC}"
    systemctl stop teejay-tunnel
    systemctl disable teejay-tunnel
    rm /etc/systemd/system/teejay-tunnel.service
    rm /usr/local/bin/teejay*
    ip tunnel del tj-tun0
    rm $TUNNEL_CONF
    echo -e "${GREEN}Cleaned up successfully.${NC}"
    read -p "Press Enter..."
}

# Main Loop
check_root

while true; do
    print_logo
    echo "1 - Setup Iran (Master)"
    echo "2 - Setup Kharej (Slave)"
    echo "3 - Status (Ping Test)"
    echo "4 - Tunnel & Port Forward (Iran Side)"
    echo "5 - Uninstall / Clear"
    echo "0 - Exit"
    echo "------------------------------------------------"
    read -p "Select Option: " choice
    
    case $choice in
        1) setup_tunnel "master" ;;
        2) setup_tunnel "slave" ;;
        3) show_status ;;
        4) setup_forwarding ;;
        5) uninstall_all ;;
        0) exit 0 ;;
        *) echo "Invalid option" ;;
    esac
done
