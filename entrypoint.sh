#!/bin/bash
set -e

echo "=== Starting PXE Boot Server for Raspberry Pi ==="

# Function to handle shutdown gracefully
cleanup() {
    echo "Shutting down services..."
    kill -TERM "$DNSMASQ_PID" 2>/dev/null || true
    kill -TERM "$GANESHA_PID" 2>/dev/null || true
    kill -TERM "$RPCBIND_PID" 2>/dev/null || true
    exit 0
}

trap cleanup SIGTERM SIGINT

# Check if configuration files exist
if [ ! -f /etc/dnsmasq.conf ]; then
    echo "ERROR: /etc/dnsmasq.conf not found"
    exit 1
fi

if [ ! -f /etc/ganesha/ganesha.conf ]; then
    echo "ERROR: /etc/ganesha/ganesha.conf not found"
    exit 1
fi

# Display network info
echo ""
echo "=== Network Configuration ==="
ip addr show | grep -E "inet |link/ether" | head -10
echo ""

# =============================================================================
# Auto-detect SERVER_IP and update boot configuration files
# =============================================================================
# echo "=== Configuring Server IP ==="

# # Get interface from dnsmasq.conf or use default
# INTERFACE=$(grep "^interface=" /etc/dnsmasq.conf 2>/dev/null | cut -d= -f2 | head -1)
# if [ -z "$INTERFACE" ]; then
#     INTERFACE="enxe2015074f51e"
# fi

# # Get IP address of the interface
# SERVER_IP=$(ip -4 addr show "$INTERFACE" 2>/dev/null | grep -oP 'inet \K[\d.]+' | head -1)

# if [ -z "$SERVER_IP" ]; then
#     # Fallback: try to get any non-loopback IP
#     SERVER_IP=$(ip -4 addr show | grep -oP 'inet \K[\d.]+' | grep -v '^127\.' | head -1)
# fi

# if [ -z "$SERVER_IP" ]; then
#     echo "WARNING: Could not detect server IP address"
#     echo "         You may need to manually configure cmdline.txt and fstab"
# else
#     echo "Detected server IP: $SERVER_IP (interface: $INTERFACE)"

#     # Update cmdline.txt if it exists and contains placeholder
#     CMDLINE_FILE="/tftpboot/cmdline.txt"
#     if [ -f "$CMDLINE_FILE" ]; then
#         if grep -q '<SERVER_IP>\|SERVER_IP' "$CMDLINE_FILE"; then
#             sed -i "s/<SERVER_IP>/$SERVER_IP/g; s/SERVER_IP/$SERVER_IP/g" "$CMDLINE_FILE"
#             echo "Updated $CMDLINE_FILE with server IP"
#         fi
#     fi

#     # Update fstab if it exists and contains placeholder
#     FSTAB_FILE="/nfs/rpi/rootfs/etc/fstab"
#     if [ -f "$FSTAB_FILE" ]; then
#         if grep -q '<SERVER_IP>\|SERVER_IP' "$FSTAB_FILE"; then
#             sed -i "s/<SERVER_IP>/$SERVER_IP/g; s/SERVER_IP/$SERVER_IP/g" "$FSTAB_FILE"
#             echo "Updated $FSTAB_FILE with server IP"
#         fi
#     fi
# fi
# echo ""

# Check for required directories
echo "=== Checking directories ==="
if [ -d /tftpboot/rpi ]; then
    TFTP_FILES=$(find /tftpboot/rpi -type f | wc -l)
    echo "TFTP: /tftpboot/rpi contains $TFTP_FILES files"
else
    echo "WARNING: /tftpboot/rpi does not exist - create it and add boot files"
    mkdir -p /tftpboot/rpi
fi

if [ -d /nfs/rpi/rootfs ]; then
    NFS_FILES=$(ls /nfs/rpi/rootfs 2>/dev/null | wc -l)
    echo "NFS: /nfs/rpi/rootfs contains $NFS_FILES top-level entries"
else
    echo "WARNING: /nfs/rpi/rootfs does not exist - create it and add rootfs"
    mkdir -p /nfs/rpi/rootfs
fi
echo ""

# Start rpcbind (required for NFS)
echo "Starting rpcbind..."
mkdir -p /run/rpcbind
rpcbind -w
RPCBIND_PID=$!
sleep 1

# Start NFS-Ganesha
echo "Starting NFS-Ganesha..."
mkdir -p /var/run/ganesha
ganesha.nfsd -F -L /dev/stdout -f /etc/ganesha/ganesha.conf &
GANESHA_PID=$!
sleep 2

# Verify NFS is running
if kill -0 $GANESHA_PID 2>/dev/null; then
    echo "NFS-Ganesha started successfully (PID: $GANESHA_PID)"
else
    echo "ERROR: NFS-Ganesha failed to start"
    exit 1
fi

# Start dnsmasq (DHCP + TFTP)
echo "Starting dnsmasq..."
dnsmasq --keep-in-foreground --log-facility=/dev/stdout &
DNSMASQ_PID=$!
sleep 1

# Verify dnsmasq is running
if kill -0 $DNSMASQ_PID 2>/dev/null; then
    echo "dnsmasq started successfully (PID: $DNSMASQ_PID)"
else
    echo "ERROR: dnsmasq failed to start"
    exit 1
fi

echo ""
echo "=== PXE Boot Server Ready ==="
echo "Services running:"
echo "  - DHCP/TFTP (dnsmasq): ports 67, 69, 4011"
echo "  - NFS (Ganesha): port 2049"
echo ""
echo "Server IP: ${SERVER_IP:-unknown}"
echo ""
echo "Mount the root filesystem from clients using:"
echo "  mount -t nfs ${SERVER_IP:-<server-ip>}:/rpi/rootfs /mnt"
echo ""

# Wait for any process to exit
wait -n $GANESHA_PID $DNSMASQ_PID

# If any process exits, clean up
echo "A service has stopped unexpectedly"
cleanup
