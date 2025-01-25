#!/bin/bash

# Gost Tunnel Manager
# Created by Network Expert
# Version: 3.2.2

# --------------------- Configuration ---------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'
CONFIG_DIR="/etc/gost"
LOG_DIR="/var/log/gost"
VERSION="3.0.0"
DOWNLOAD_URL="https://github.com/go-gost/gost/releases/download/v${VERSION}/gost_${VERSION}_linux_amd64.tar.gz"

# --------------------- Initial Checks ---------------------
check_root() {
    [[ $EUID -ne 0 ]] && echo -e "${RED}Run as root!${NC}" && exit 1
}

check_deps() {
    declare -A deps=([jq]="jq" [wget]="wget" [tar]="tar")
    for cmd in "${!deps[@]}"; do
        if ! command -v $cmd &>/dev/null; then
            apt-get update && apt-get install -y ${deps[$cmd]}
        fi
    done
}

# --------------------- UI Functions ---------------------
print_header() {
    clear
    echo -e "${BLUE}"
    echo "   ██████   ██████  ███████ ████████ "
    echo "  ██       ██    ██ ██         ██    "
    echo "  ██   ███ ██    ██ ███████    ██    "
    echo "  ██    ██ ██    ██      ██    ██    "
    echo "   ██████   ██████  ███████    ██    "
    echo -e "${NC}${BLUE}═══════════════════════════════${NC}"
    show_network_info
    echo -e "${BLUE}═══════════════════════════════${NC}"
}

show_network_info() {
    ipv4=$(curl -s4 --max-time 3 https://api.ipify.org 2>/dev/null || echo "N/A")
    ipv6=$(curl -s6 --max-time 3 https://api64.ipify.org 2>/dev/null || echo "N/A")
    isp_info=$(curl -s4 --max-time 3 "https://ipapi.co/${ipv4}/org/" 2>/dev/null || echo "Unknown")

    echo -e "${YELLOW}IPv4: ${GREEN}${ipv4:-Not Available}"
    echo -e "${YELLOW}IPv6: ${GREEN}${ipv6:-Not Available}"
    echo -e "${YELLOW}ISP:  ${GREEN}${isp_info:-Unknown}${NC}"
}

# --------------------- Service Management ---------------------
setup_service() {
    local role=$1
    local config=("${!2}")
    
    cat > /etc/systemd/system/gost-${role}.service <<EOF
[Unit]
Description=Gost ${role} Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/gost ${config[@]}
Restart=always
RestartSec=3
SyslogIdentifier=gost-${role}
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable gost-${role}
    systemctl restart gost-${role}
}

delete_service() {
    local service_name=$1
    systemctl stop "$service_name" 2>/dev/null
    systemctl disable "$service_name" 2>/dev/null
    rm -f "/etc/systemd/system/$service_name.service"
    systemctl daemon-reload
    echo -e "${GREEN}Service $service_name deleted successfully!${NC}"
}

edit_service() {
    local service_name=$1
    # Remove .service suffix if present
    service_name=${service_name%.service}

    if [[ ! -f "/etc/systemd/system/$service_name.service" ]]; then
        echo -e "${RED}Service $service_name does not exist!${NC}"
        return
    fi

    # Open the service file in an editor
    nano "/etc/systemd/system/$service_name.service"

    # Reload systemd and restart the service
    systemctl daemon-reload
    systemctl restart "$service_name"
    echo -e "${GREEN}Service $service_name edited and restarted successfully!${NC}"
}

# --------------------- Main Functions ---------------------
install_gost() {
    if [[ -f "/usr/local/bin/gost" ]]; then
        echo -e "${YELLOW}Gost is already installed.${NC}"
        return
    fi

    echo -e "${GREEN}Downloading Gost v${VERSION}...${NC}"
    wget -q --show-progress $DOWNLOAD_URL -O gost.tar.gz || {
        echo -e "${RED}Download failed!${NC}"
        exit 1
    }

    tar -xzf gost.tar.gz
    mv gost_${VERSION}_linux_amd64/gost /usr/local/bin/
    chmod +x /usr/local/bin/gost
    rm -rf gost_${VERSION}_linux_amd64
    rm gost.tar.gz

    mkdir -p "$CONFIG_DIR" "$LOG_DIR"
    chmod 755 "$CONFIG_DIR" "$LOG_DIR"

    echo -e "${GREEN}Gost installed successfully!${NC}"
}

eu_server_setup() {
    read -p "Enter Tunnel server port [4444]: " kcp_port
    kcp_port=${kcp_port:-4444}
    
    read -p "Enter Config port [443]: " target_port
    target_port=${target_port:-443}

    config=("-L=kcp://:${kcp_port}/:${target_port}")
    setup_service "eu-server" config[@]
}

iran_server_setup() {
    read -p "Enter server EU IP: " server_ip
    read -p "Enter server Tunnel port [4444]: " server_port
    server_port=${server_port:-4444}
    
    read -p "Enter Config port [443]: " local_port
    local_port=${local_port:-443}

    config=("-L=tcp://:${local_port}" "-F forward+kcp://${server_ip}:${server_port}")
    setup_service "iran-server" config[@]
}

# --------------------- Menu System ---------------------
main_menu() {
    check_root
    check_deps
    install_gost
    
    while true; do
        print_header
        
        echo -e "\n${CYAN}Main Menu:${NC}"
        echo -e "1. Setup EU Server"
        echo -e "2. Setup Iran Server"
        echo -e "3. Manage Services"
        echo -e "4. Exit"
        
        read -p "$(echo -e ${CYAN}"Choose option [1-4]: "${NC})" choice
        
        case $choice in
            1) eu_server_setup ;;
            2) iran_server_setup ;;
            3) select_service_menu ;;
            4) exit 0 ;;
            *) echo -e "${RED}Invalid choice!${NC}" ;;
        esac
        
        echo -e "\n${YELLOW}Press any key to continue...${NC}"
        read -n1 -s
    done
}

select_service_menu() {
    while true; do
        print_header
        
        # Get the list of active services
        services=($(systemctl list-units --type=service --state=running "gost-*" --no-pager --no-legend | awk '{print $1}'))
        
        if [ ${#services[@]} -eq 0 ]; then
            echo -e "${RED}No active services found!${NC}"
            read -n1 -s -p "Press any key to continue..."
            return
        fi

        # Display the list of active services
        echo -e "\n${CYAN}Active Services:${NC}"
        for i in "${!services[@]}"; do
            echo "$((i+1)). ${services[$i]}"
        done
        echo -e "$(( ${#services[@]} + 1 )). Back to Main Menu"

        # Prompt the user to select a service
        read -p "$(echo -e ${CYAN}"Select a service by number [1-$((${#services[@]} + 1))]: "${NC})" service_num

        # Validate the input
        if [[ $service_num -lt 1 || $service_num -gt $((${#services[@]} + 1)) ]]; then
            echo -e "${RED}Invalid selection!${NC}"
            read -n1 -s -p "Press any key to continue..."
            continue
        fi

        # If the user selects the last option, return to the main menu
        if [[ $service_num -eq $((${#services[@]} + 1)) ]]; then
            break
        fi

        # Get the selected service name
        selected_service=${services[$((service_num-1))]}

        # Go to the service management menu for the selected service
        service_menu "$selected_service"
    done
}

service_menu() {
    local service_name=$1

    while true; do
        print_header
        
        # Get the status of the service
        service_status=$(systemctl is-active "$service_name")
        service_status_full=$(systemctl status "$service_name" | grep "Active:" | cut -d ':' -f 2- | xargs)
        
        # Display the service status in the header
        echo -e "\n${CYAN}Managing Service: ${GREEN}$service_name${NC}"
        echo -e "${YELLOW}Status: ${GREEN}$service_status_full${NC}"
        
        echo -e "\n${CYAN}Options:${NC}"
        echo -e "1. Start Service"
        echo -e "2. Stop Service"
        echo -e "3. Restart Service"
        echo -e "4. View Service Status"
        echo -e "5. Delete Service"
        echo -e "6. Edit Service"
        echo -e "7. Back to Service Selection"
        
        read -p "$(echo -e ${CYAN}"Choose option [1-7]: "${NC})" choice
        
        case $choice in
            1) 
                systemctl start "$service_name"
                echo -e "${GREEN}Service $service_name started successfully!${NC}"
            ;;
            2) 
                systemctl stop "$service_name"
                echo -e "${GREEN}Service $service_name stopped successfully!${NC}"
            ;;
            3) 
                systemctl restart "$service_name"
                echo -e "${GREEN}Service $service_name restarted successfully!${NC}"
            ;;
            4) 
                trap 'echo -e "\nReturning to menu..."' SIGINT
                systemctl status "$service_name" -l
                trap - SIGINT
            ;;
            5)
                delete_service "$service_name"
                break  # پس از حذف سرویس، به منوی قبلی برگرد
            ;;
            6)
                edit_service "$service_name"
            ;;
            7) break ;;
            *) echo -e "${RED}Invalid choice!${NC}" ;;
        esac
        
        echo -e "\n${YELLOW}Press any key to continue...${NC}"
        read -n1 -s
    done
}

# --------------------- Start Application ---------------------
main_menu