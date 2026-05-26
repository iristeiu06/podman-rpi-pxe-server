#!/bin/bash
# Run the PXE server container with Podman

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_usage() {
    echo -e "Every command has to be run with ${GREEN}sudo${NC}"
    echo ""
    echo "Usage: sudo $0 [command]"
    echo ""
    echo "Commands:"
    echo "  build               Build the container image"
    echo "  init                Initialize directories (creates empty structure): backup, staging, data/tftpboot, data/nfs/rpi/rootfs"
    echo "  logs                Show container logs"
    echo "  restart             Restart the PXE server"
    echo "  restore [backup_dir]  Restore boot/modules from a backup directory (default: latest backup in backup/)"
    echo "  shell               Open a shell in the running container"
    echo "  setup [image.img]   Extract boot files and rootfs from image (default: kuiper_image.img)"
    echo "  stop                Stop the PXE server"
    echo "  start               Start the PXE server"
    echo "  status              Show container status"
    echo ""
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${YELLOW}Warning: Some operations may require root privileges${NC}"
    fi
}

init_directory() {
    echo -e "${GREEN}Initializing directory structure...${NC}"
    mkdir -p backup staging data/tftpboot data/nfs/rpi/rootfs
    echo "Directories created:"
    echo "  backup/           <- Backups of existing boot/modules will be stored here"
    echo "  staging/          <- Place boot/modules tarballs here for deployment"
    echo "  data/tftpboot/    <- Boot files (kernel, dtbs, config.txt, cmdline.txt, overlays) go here"
    echo "  data/nfs/rpi/rootfs/ <- Root filesystem goes here"
}

setup_directories() {
    local IMG_FILE="${1:-kuiper_image.img}"

    if [ ! -f "$IMG_FILE" ]; then
        echo -e "${RED}Error: Image file '$IMG_FILE' not found${NC}"
        exit 1
    fi

    echo -e "${GREEN}Setting up from image: $IMG_FILE${NC}"

    # Clean existing data before extraction
    echo -e "${YELLOW}Cleaning existing data directories...${NC}"
    rm -rf data/tftpboot/*
    rm -rf data/nfs/rpi/rootfs/*

    mkdir -p data/tftpboot/
    mkdir -p data/nfs/rpi/rootfs

    LOOP_DEVICE=$(sudo losetup -fP --show "$IMG_FILE")
    mkdir -p /mnt/pi-boot /mnt/pi-rootfs
    sudo mount ${LOOP_DEVICE}p1 /mnt/pi-boot
    sudo mount ${LOOP_DEVICE}p2 /mnt/pi-rootfs

    # Copy to data directories
    sudo cp -a /mnt/pi-boot/* ./data/tftpboot/
    sudo cp -a /mnt/pi-rootfs/* ./data/nfs/rpi/rootfs/

    # Cleanup
    sudo umount /mnt/pi-boot /mnt/pi-rootfs
    sudo losetup -d ${LOOP_DEVICE}

    cp config_files/cmdline.txt data/tftpboot/cmdline.txt
    cp config_files/fstab data/nfs/rpi/rootfs/etc/fstab

    # Create /boot/firmware mount point for bind mount in container
    mkdir -p data/nfs/rpi/rootfs/boot/firmware

    # Create kernel pseudo-filesystem mountpoints that the Kuiper image lacks
    # Without these, systemd fails to mount mqueue/debugfs/tracefs/configfs at boot
    sudo mkdir -p \
        data/nfs/rpi/rootfs/dev/mqueue \
        data/nfs/rpi/rootfs/sys/kernel/debug \
        data/nfs/rpi/rootfs/sys/kernel/tracing \
        data/nfs/rpi/rootfs/sys/kernel/config

    echo ""
    echo -e "${GREEN}Directory structure created:${NC}"
    echo "  data/"
    echo "  ├── tftpboot/  <- Check for boot files here (kernel, dtbs, config.txt, cmdline.txt, overlays)"
    echo "  └── nfs/"
    echo "      └── rpi/"
    echo "          └── rootfs/ <- Check root filesystem here"
    echo ""
    echo -e "${YELLOW}Next steps:${NC}"
    echo "1. Edit dnsmasq.conf:"
    echo "   - Set 'interface' to your network interface (check with 'ip addr')"
    echo "   - Set 'dhcp-range' to match your network"
    echo ""
    echo "2. Build and start the container:"
    echo "   sudo ./run.sh build"
    echo "   sudo ./run.sh start"
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

restore_backup() {
    local BACKUP_DIR="${1:-}"
    if [ -z "$BACKUP_DIR" ]; then
        BACKUP_DIR=$(ls -td backup/backup_* | head -n 1)
        echo "No backup directory specified, using latest: $BACKUP_DIR"
    fi

    if [ ! -d "$BACKUP_DIR" ]; then
        echo -e "${RED}Error: Backup directory '$BACKUP_DIR' not found${NC}"
        exit 1
    fi

    echo -e "${GREEN}Restoring from backup: $BACKUP_DIR${NC}"

    if [ -d "$BACKUP_DIR/tftpboot" ]; then
        cp -a "$BACKUP_DIR/tftpboot"/* data/tftpboot/
        echo "Restored tftpboot files"
    else
        echo "No tftpboot backup found in $BACKUP_DIR"
    fi

    if [ -d "$BACKUP_DIR/modules" ]; then
        cp -a "$BACKUP_DIR/modules"/* data/nfs/rpi/rootfs/lib/modules/
        echo "Restored kernel modules"
    else
        echo "No modules backup found in $BACKUP_DIR"
    fi

    echo "Restore complete. Restarting container..."
    restart_container
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
    init)
        init_directory
        ;;
    logs)
        show_logs
        ;;
    restart)
        restart_container
        ;;
    restore)
        restore_backup "$2"
        ;;
    setup)
        setup_directories "$2"
        ;;
    shell)
        open_shell
        ;;
    status)
        show_status
        ;;
    start)
        start_container
        ;;
    stop)
        stop_container
        ;;
    *)
        print_usage
        exit 1
        ;;
esac