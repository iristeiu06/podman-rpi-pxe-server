FROM debian:bookworm-slim

LABEL description="NFS, TFTP & DHCP server for Raspberry Pi network boot"

# Install required packages
RUN apt-get update && apt-get install -y \
    bash \
    dnsmasq \
    nfs-ganesha \
    nfs-ganesha-vfs \
    rpcbind \
    procps \
    iproute2 \
    && rm -rf /var/lib/apt/lists/*

# Create directories
RUN mkdir -p /tftpboot/rpi \
    && mkdir -p /nfs/rpi/rootfs \
    && mkdir -p /etc/ganesha \
    && mkdir -p /run/rpcbind

# Copy configuration files
COPY dnsmasq.conf /etc/dnsmasq.conf
COPY ganesha.conf /etc/ganesha/ganesha.conf
COPY entrypoint.sh /entrypoint.sh

RUN chmod +x /entrypoint.sh

# Expose ports
# DHCP: 67/udp (server), 68/udp (client)
# TFTP: 69/udp
# NFS: 2049/tcp+udp
# RPC/Portmap: 111/tcp+udp
# PXE proxy: 4011/udp
EXPOSE 67/udp 68/udp 69/udp 2049/tcp 2049/udp 111/tcp 111/udp 4011/udp

# Volumes for boot files and root filesystem
VOLUME ["/tftpboot", "/nfs"]

ENTRYPOINT ["/entrypoint.sh"]
