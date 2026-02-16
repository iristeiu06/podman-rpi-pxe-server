# Raspberry Pi PXE Boot Server (Podman Container)

This container provides NFS, TFTP, and DHCP services for network booting a Raspberry Pi (both 4 and 5).

## Components

- **dnsmasq**: DHCP (proxy mode) and TFTP server
- **NFS-Ganesha**: User-space NFS server (works in containers without kernel modules)

## Requirements

- Linux host (recommended) or WSL2 on Windows
- Podman installed
- Root/sudo access for network services
- Raspberry Pi and server on the same network (Ethernet)

## Configurations Before Starting
Verify that each of the following configuration are set correctly

### ``dnsmasq.conf``

Use `ip addr` on the host to find the correct interface name
```bash
interface=<INTERFACE>
```

Replace with network address (proxy mode - works with existing DHCP)
```bash
# OPTION A: Proxy Mode
dhcp-range=<NETWORK_ADDRESS>,proxy
```

```bash
# OPTION B 
# Adjust IP range and lease time for your network
dhcp-range=10.48.65.100,10.48.65.150,12h
dhcp-option=option:router,10.48.65.1
dhcp-option=option:dns-server,8.8.8.8,8.8.4.4
```

### ``ganesha.conf`` (optional)

The default configuration exports `/nfs/rpi/rootfs` to all clients. 

Restrict access to a subnet:

```bash
EXPORT{ 
    ...

    CLIENT {
        Clients = 10.48.65.0/24;  # Only allow this subnet
        Access_Type = RW;
        Squash = No_Root_Squash;
    }

    ...
}
```


## Quick Start

```bash
# 1. Setup directories
./run.sh setup

# 2. Edit configuration (see Configuration section below)
nano dnsmasq.conf

# 3. Build the container
./run.sh build

# 4. Start the server
sudo ./run.sh start

# 5. Check logs
./run.sh logs
```

## Preparing Pi Files

### Option 1: Setup directories

- Copy Kuiper Image in the current folder (where is also the ./run.sh script)
- Run the cmd `sudo ./run.sh setup`. 
    - It will automatically mount the partitions and copy the boot files and rootfs in the newly created folders `data/tftpboot/`, respectively `data/nfs/rpi/rootfs`. 
    - Also, it will replace the `cmdline.txt` and `fstab` with the custom files used for network boot.

### Option 2: Manualy copy files from an existing image

```bash
# Mount the Pi image
sudo losetup -fP /path/to/your-image.img
sudo mkdir -p /mnt/pi-boot /mnt/pi-rootfs
sudo mount /dev/loop0p1 /mnt/pi-boot
sudo mount /dev/loop0p2 /mnt/pi-rootfs

# Copy to container data directories
sudo cp -a /mnt/pi-boot/* ./data/tftpboot/
sudo cp -a /mnt/pi-rootfs/* ./data/nfs/rpi/rootfs/

# Cleanup
sudo umount /mnt/pi-boot /mnt/pi-rootfs
sudo losetup -d /dev/loop0
```

<ins>**Configure boot for NFS**</ins>

- Edit `data/tftpboot/cmdline.txt`:
```
console=serial0,115200 console=tty1 root=/dev/nfs nfsroot=<SERVER_IP>:/rpi/rootfs,vers=4 rw ip=dhcp rootwait
```

- Edit `data/nfs/rpi/rootfs/etc/fstab`:
```
proc            /proc           proc    defaults          0       0
<SERVER_IP>:/rpi/rootfs  /  nfs  defaults,noatime  0  0
```

**Note**: The `<SERVER_IP>` placeholder is automatically configured at setup time. If not, it can be manually replaced or left as `<SERVER_IP>` and the entrypoint script will substitute the correct IP address based on the network interface configured in `dnsmasq.conf`.

## Directory Structure

```
podman-pxe-server/
├── Containerfile          # Container build file
├── dnsmasq.conf           # DHCP/TFTP configuration
├── ganesha.conf           # NFS configuration
├── entrypoint.sh          # Container startup script
├── podman-compose.yml     # Compose file (alternative to run.sh)
├── run.sh                 # Helper script
├── README.md              # This file
└── data/                  # Created by setup
    ├── tftpboot/          # Boot files (kernel, dtbs, etc.)
    └── nfs/
        └── rpi/
            └── rootfs/    # Root filesystem
```

## Commands

```bash
sudo ./run.sh setup     # Create directories, copy boot files and rootfs, and show instructions
sudo ./run.sh build     # Build container image
sudo ./run.sh start     # Start the container (use sudo)
sudo ./run.sh stop      # Stop the container
sudo ./run.sh restart   # Restart the container
sudo ./run.sh logs      # View container logs
sudo ./run.sh shell     # Open shell in container
sudo ./run.sh status    # Show container status
```

## Using podman-compose (alternative)

```bash
# Build
podman-compose build

# Start
sudo podman-compose up -d

# Stop
podman-compose down

# Logs
podman-compose logs -f
```

## Raspberry Pi EEPROM Configuration

On the Pi (boot with SD card first):

```bash
sudo rpi-eeprom-config --edit
```

Set:
```
BOOT_ORDER=0xf21
```

Then reboot, shut down, remove SD card, and power on.

## Troubleshooting

### Check services are listening
```bash
sudo ss -ulnp | grep -E '67|69|2049'
```

### Monitor DHCP/TFTP requests
```bash
./run.sh logs
```

### Test NFS mount from another machine
```bash
sudo mount -t nfs <SERVER_IP>:/rpi/rootfs /mnt
```

### Pi not finding boot files
The Pi may look for files in a serial-number directory. Create a symlink:
```bash
# Get Pi serial (on the Pi)
cat /proc/cpuinfo | grep Serial

# Create symlink in container
./run.sh shell
ln -s /tftpboot /tftpboot/<serial>
```

### Container won't start
- Run the commands with `sudo`
- Ensure no other service uses ports 67, 69, 2049
- Check for SELinux issues: `sudo setenforce 0` (temporary)
- Run with verbose logging: `podman logs rpi-pxe-server`

## Network Ports

| Port | Protocol | Service      |
|------|----------|--------------|
| 67   | UDP      | DHCP         |
| 69   | UDP      | TFTP         |
| 4011 | UDP      | PXE (ProxyDHCP) |
| 2049 | TCP/UDP  | NFS          |
