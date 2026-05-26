#!/bin/bash
set -euo pipefail

PXE_DIR="/home/nuc1/workspace/ioana/podman-rpi-pxe-server"
BACKUP_DIR="${PXE_DIR}/backup/backup_$(date +%Y%m%d_%H%M%S)"
STAGING_DIR="${PXE_DIR}/staging"
TFTPBOOT_DIR="${PXE_DIR}/data/tftpboot"
NFS_DIR="${PXE_DIR}/data/nfs/rpi/rootfs"

BOOT_TARBALL="${STAGING_DIR}/rpi_latest_boot_64bit.tar.gz"
MODULES_TARBALL="${STAGING_DIR}/rpi_modules_64bit.tar.gz"

if [ ! -f "$BOOT_TARBALL" ] || [ ! -f "$MODULES_TARBALL" ]; then
    echo "Tarballs not found in ${STAGING_DIR}, nothing to deploy."
    exit 0
fi

mkdir -p "$BACKUP_DIR"

if [ -d "$TFTPBOOT_DIR" ]; then
    cp -a "$TFTPBOOT_DIR" "$BACKUP_DIR/"
fi
if [ -d "$NFS_DIR/lib/modules" ]; then
    cp -a "$NFS_DIR/lib/modules" "$BACKUP_DIR/"
fi
echo "Backup created at $BACKUP_DIR"

mkdir -p "$TFTPBOOT_DIR"
tar -xzf "$BOOT_TARBALL" -C "$TFTPBOOT_DIR"
chown -R root:root "$TFTPBOOT_DIR"

mkdir -p "$NFS_DIR/lib/modules"
tar -xzf "$MODULES_TARBALL" -C "$NFS_DIR/lib/modules/"
chown -R root:root "$NFS_DIR/lib/modules"

rm -f "$BOOT_TARBALL" "$MODULES_TARBALL"
echo "Deploy complete."
