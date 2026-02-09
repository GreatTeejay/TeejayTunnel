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
    echo -e "${YELLOW}           TEEJAY EXCLUSIVE - IRAN OPTIMIZED ${NC}"
    echo "---------------------------------------------------"
}

install_core() {
    echo -e "${YELLOW}[*] Installing V2Ray Core (Using Mirror for Iran)...${NC}"
    # استفاده از یک اسکریپت جایگزین که معمولاً در ایران بهتر جواب می‌دهد
    curl -L https://raw.githubusercontent.com/v2fly/fxtls/main/install.sh -o install.sh
    
    # اگر گیت‌هاب بسته بود، از این دستور کمکی استفاده کن
    if [ $? -ne 0 ]; then
        echo -e "${RED}[!] Direct download failed. Trying Mirror...${NC}"
        # آدرس جایگزین برای دانلود هسته در ایران
        bash <(curl -L -s https://install.direct/go.sh) || bash <(curl -L -s https://raw.githubusercontent.com/v2fly/fxtls/main/install.sh)
    else
        bash install.sh
    fi
    systemctl enable v2ray
}

setup_iran() {
    display_logo
    # Optimization skipped if it causes issues, only basic forwarding
    sysctl -w net.ipv4.ip_forward=1
    
    install_core
    
    u_id=$(uuidgen)
    read -p "Enter Foreign Server IP: " foreign_ip
    read -p "Enter Ports (e.g., 80,443): " ports
    
    # Config generation... (همون کد قبلی)
    # [بقیه کدهای بخش تنظیمات ایران اینجا قرار می‌گیرد]
    
    systemctl restart v2ray
    echo -e "${GREEN}[+] Done! UUID: ${u_id}${NC}"
}

# [بقیه منو و توابع طبق نسخه قبل...]

while true; do
    display_logo
    echo "1) Setup Iran"
    echo "2) Setup Foreign"
    echo "3) Status"
    echo "5) Exit"
    read -p "Select: " opt
    case $opt in
        1) setup_iran ;;
        2) setup_kharej ;; # تابع خارج رو از کد قبلی اینجا بذار
        3) systemctl status v2ray ;;
        5) exit 0 ;;
    esac
done
