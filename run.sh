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

    echo ""
    echo -e "${GREEN}Directory structure created:${NC}"
    echo "  data/"
    echo "  ├── tftpboot/  <- Copy boot files here (kernel, dtbs, config.txt, cmdline.txt)"
    echo "  └── nfs/"
    echo "      └── rpi/"
    echo "          └── rootfs/ <- Copy root filesystem here"
    echo ""
    echo -e "${YELLOW}Next steps:${NC}"
    echo "1. Edit dnsmasq.conf:"
    echo "   - Set 'interface' to your network interface (check with 'ip addr')"
    echo "   - Set 'dhcp-range' to match your network"
    echo ""
    echo "2. Copy your Raspberry Pi image files:"
    echo "   - Mount your .img file and copy boot partition to data/tftpboot/rpi/"
    echo "   - Copy rootfs partition to data/nfs/rpi/rootfs/"
    echo ""
    echo "3. Update cmdline.txt in data/tftpboot/rpi/:"
    echo "   console=serial0,115200 console=tty1 root=/dev/nfs nfsroot=<SERVER_IP>:/rpi/rootfs,vers=4 rw ip=dhcp rootwait"
    echo ""
    echo "4. Update fstab in data/nfs/rpi/rootfs/etc/fstab:"
    echo "   <SERVER_IP>:/rpi/rootfs  /  nfs  defaults,noatime  0  0"
    echo ""
    echo "5. Build and start the container:"
    echo "   ./run.sh build"
    echo "   ./run.sh start"
    echo ""
}

build_image() {
    echo -e "${GREEN}Building PXE server container image...${NC}"
    podman build -t rpi-pxe-server:latest .
}

start_container() {
    check_root
    echo -e "${GREEN}Starting PXE server container...${NC}"

    # Check if container already exists
    if podman container exists rpi-pxe-server 2>/dev/null; then
        echo "Container already exists, starting..."
        podman start rpi-pxe-server
    else
        echo "Creating and starting container..."
        podman run -d \
            --name rpi-pxe-server \
            --hostname pxe-server \
            --network host \
            --privileged \
            --security-opt apparmor=unconfined \
            --security-opt seccomp=unconfined \
            --user root \
            --env DNSMASQ_USER=root \
            -v "$SCRIPT_DIR/data/tftpboot:/tftpboot:Z" \
            -v "$SCRIPT_DIR/data/nfs:/nfs:Z" \
            -v "$SCRIPT_DIR/dnsmasq.conf:/etc/dnsmasq.conf:ro,Z" \
            -v "$SCRIPT_DIR/ganesha.conf:/etc/ganesha/ganesha.conf:ro,Z" \
            --restart unless-stopped \
            rpi-pxe-server:latest
    fi

    echo ""
    echo -e "${GREEN}Container started. Check logs with: ./run.sh logs${NC}"
}

stop_container() {
    echo -e "${YELLOW}Stopping PXE server container...${NC}"
    podman stop rpi-pxe-server 2>/dev/null || echo "Container not running"
}

restart_container() {
    stop_container
    sleep 2
    start_container
}

show_logs() {
    podman logs -f rpi-pxe-server
}

open_shell() {
    podman exec -it rpi-pxe-server /bin/bash
}

show_status() {
    echo -e "${GREEN}Container status:${NC}"
    podman ps -a --filter name=rpi-pxe-server --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    echo ""

    if podman container exists rpi-pxe-server 2>/dev/null; then
        if podman inspect rpi-pxe-server --format '{{.State.Running}}' 2>/dev/null | grep -q true; then
            echo -e "${GREEN}Services should be listening on:${NC}"
            echo "  - DHCP: port 67/udp"
            echo "  - TFTP: port 69/udp"
            echo "  - NFS:  port 2049/tcp+udp"
            echo ""
            echo "Check with: ss -ulnp | grep -E '67|69|2049'"
        fi
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
