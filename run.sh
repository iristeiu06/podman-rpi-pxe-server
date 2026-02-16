#!/bin/bash
# Run the PXE server container with Podman

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_usage() {
    echo "Usage: $0 [command]"
    echo ""
    echo "Commands:"
    echo "  build     Build the container image"
    echo "  start     Start the PXE server"
    echo "  stop      Stop the PXE server"
    echo "  restart   Restart the PXE server"
    echo "  logs      Show container logs"
    echo "  shell     Open a shell in the running container"
    echo "  status    Show container status"
    echo "  setup     Create data directories and show next steps"
    echo ""
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${YELLOW}Warning: Some operations may require root privileges${NC}"
    fi
}

setup_directories() {
    echo -e "${GREEN}Creating data directories...${NC}"
    mkdir -p data/tftpboot/
    mkdir -p data/nfs/rpi/rootfs

    LOOP_DEVICE=$(losetup -fP --show kuiper_image.img)
    mkdir -p /mnt/pi-boot /mnt/pi-rootfs
    mount ${LOOP_DEVICE}p1 /mnt/pi-boot
    mount ${LOOP_DEVICE}p2 /mnt/pi-rootfs

    # Copy to container data directories
    sudo cp -a /mnt/pi-boot/* ./data/tftpboot/
    sudo cp -a /mnt/pi-rootfs/* ./data/nfs/rpi/rootfs/

    # Cleanup
    sudo umount /mnt/pi-boot /mnt/pi-rootfs
    sudo losetup -d ${LOOP_DEVICE}

    cp config_files/cmdline.txt data/tftpboot/cmdline.txt
    cp config_files/fstab data/nfs/rpi/rootfs/etc/fstab

    echo "=== Configuring Server IP ==="

    # Get interface from dnsmasq.conf or use default
    INTERFACE=$(grep "^interface=" dnsmasq.conf 2>/dev/null | cut -d= -f2 | head -1)
    if [ -z "$INTERFACE" ]; then
        INTERFACE="eth0"
    fi

    # Get IP address of the interface
    SERVER_IP=$(ip -4 addr show "$INTERFACE" 2>/dev/null | grep -oP 'inet \K[\d.]+' | head -1)

    if [ -z "$SERVER_IP" ]; then
        # Fallback: try to get any non-loopback IP
        SERVER_IP=$(ip -4 addr show | grep -oP 'inet \K[\d.]+' | grep -v '^127\.' | head -1)
    fi

    if [ -z "$SERVER_IP" ]; then
        echo "WARNING: Could not detect server IP address"
        echo "Manually replace <SERVER_IP> with host's IP in cmdline.txt in data/tftpboot/"
        echo "and in fstab in data/nfs/rpi/rootfs/etc/"
    else
        echo "Detected server IP: $SERVER_IP (interface: $INTERFACE)"

        # Update cmdline.txt if it exists and contains placeholder
        CMDLINE_FILE="data/tftpboot/cmdline.txt"
        if [ -f "$CMDLINE_FILE" ]; then
            if grep -q '<SERVER_IP>\|SERVER_IP' "$CMDLINE_FILE"; then
                sed -i "s/<SERVER_IP>/$SERVER_IP/g; s/SERVER_IP/$SERVER_IP/g" "$CMDLINE_FILE"
                echo "Updated $CMDLINE_FILE with server IP"
            fi
        fi

        # Update fstab if it exists and contains placeholder
        FSTAB_FILE="data/nfs/rpi/rootfs/etc/fstab"
        if [ -f "$FSTAB_FILE" ]; then
            if grep -q '<SERVER_IP>\|SERVER_IP' "$FSTAB_FILE"; then
                sed -i "s/<SERVER_IP>/$SERVER_IP/g; s/SERVER_IP/$SERVER_IP/g" "$FSTAB_FILE"
                echo "Updated $FSTAB_FILE with server IP"
            fi
        fi
    fi
    echo ""

    echo ""
    echo -e "${GREEN}Directory structure created:${NC}"
    echo "  data/"
    echo "  ├── tftpboot/  <- Check for boot files here (kernel, dtbs, config.txt, cmdline.txt)"
    echo "  └── nfs/"
    echo "      └── rpi/"
    echo "          └── rootfs/ <- Check root filesystem here"
    echo ""
    echo -e "${YELLOW}Next steps:${NC}"
    echo "1. Edit dnsmasq.conf:"
    echo "   - Set 'interface' to your network interface (check with 'ip addr')"
    echo "   - Set 'dhcp-range' to match your network"
    echo ""
    echo "2. Copy Raspberry Pi image files, if not already copied:"
    echo "   - Mount your .img file and copy boot partition to data/tftpboot/"
    echo "   - Copy rootfs partition to data/nfs/rpi/rootfs/"
    echo ""
    echo "3. Build and start the container:"
    echo "   ./run.sh build"
    echo "   ./run.sh start"
    echo ""
}

build_image() {
    echo -e "${GREEN}Building PXE server container image...${NC}"
    podman-compose build
}

start_container() {
    check_root
    echo -e "${GREEN}Starting PXE server container...${NC}"
    podman-compose up -d
    echo ""
    echo -e "${GREEN}Container started. Check logs with: ./run.sh logs${NC}"
}

stop_container() {
    echo -e "${YELLOW}Stopping PXE server container...${NC}"
    podman-compose down
    podman-compose rm -f rpi-pxe-server
}

restart_container() {
    echo -e "${YELLOW}Restarting PXE server container...${NC}"
    podman-compose restart
}

show_logs() {
    podman-compose logs -f
}

open_shell() {
    podman-compose exec pxe-server /bin/bash
}

show_status() {
    echo -e "${GREEN}Container status:${NC}"
    podman-compose ps
    echo ""

    if podman-compose ps --quiet 2>/dev/null | grep -q .; then
        echo -e "${GREEN}Services should be listening on:${NC}"
        echo "  - DHCP: port 67/udp"
        echo "  - TFTP: port 69/udp"
        echo "  - PXE:  port 4011/udp"
        echo "  - NFS:  port 2049/tcp+udp"
        echo ""
        echo "Check with: ss -ulnp | grep -E '67|69|2049'"
    fi
}

# Main
case "${1:-}" in
    build)
        build_image
        ;;
    start)
        start_container
        ;;
    stop)
        stop_container
        ;;
    restart)
        restart_container
        ;;
    logs)
        show_logs
        ;;
    shell)
        open_shell
        ;;
    status)
        show_status
        ;;
    setup)
        setup_directories
        ;;
    *)
        print_usage
        exit 1
        ;;
esac
