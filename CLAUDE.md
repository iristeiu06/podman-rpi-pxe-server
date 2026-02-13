# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a **containerized PXE boot server** designed specifically for network booting Raspberry Pi devices. It provides DHCP (proxy mode), TFTP, and NFS services in a single Podman container, allowing Raspberry Pis to boot entirely from the network without SD cards.

**Key Components:**
- `dnsmasq`: DHCP proxy and TFTP server for boot file delivery
- `NFS-Ganesha`: User-space NFS server (works in containers without kernel modules)
- `rpcbind`: RPC port mapper required for NFS

## Essential Development Commands

### Container Management
```bash
# Initial setup (creates data/ directories)
./run.sh setup

# Build the container image
./run.sh build

# Start the server (requires sudo for network privileges)
sudo ./run.sh start

# Monitor logs in real-time
./run.sh logs

# Access container shell for debugging
./run.sh shell

# Check container and service status
./run.sh status

# Stop the server
sudo ./run.sh stop

# Complete restart
sudo ./run.sh restart
```

### Alternative: Podman Compose
```bash
# Build and start
podman-compose build
sudo podman-compose up -d

# Monitor logs
podman-compose logs -f

# Stop
podman-compose down
```

### Validation Commands
```bash
# Verify services are listening on correct ports
sudo ss -ulnp | grep -E '67|69|2049'

# Test NFS mount from another machine
sudo mount -t nfs <SERVER_IP>:/rpi/rootfs /mnt

# Check for interface IP
ip -4 addr show <interface>
```

## Architecture and Key Concepts

### Multi-Service Container Architecture
The container runs three services with carefully orchestrated startup:

1. **rpcbind** - Starts first, required for NFS (port 111)
2. **NFS-Ganesha** - User-space NFS server (port 2049)
3. **dnsmasq** - DHCP proxy + TFTP server (ports 67, 69, 4011)

Services are managed by `entrypoint.sh:98-150` with proper PID tracking and graceful shutdown via signal handlers.

### Automatic IP Configuration
The entrypoint script (`entrypoint.sh:35-77`) automatically:
- Detects server IP from the network interface specified in `dnsmasq.conf`
- Substitutes `<SERVER_IP>` placeholders in boot configuration files:
  - `data/tftpboot/rpi/cmdline.txt` (kernel boot parameters)
  - `data/nfs/rpi/rootfs/etc/fstab` (filesystem mount table)

### Directory Structure
```
data/                          # Runtime data (gitignored)
├── tftpboot/rpi/             # Boot files served via TFTP
│   ├── kernel*.img           # Pi kernel images
│   ├── *.dtb                 # Device tree blobs
│   ├── cmdline.txt           # Kernel command line (auto-configured)
│   └── config.txt            # Pi boot configuration
└── nfs/rpi/rootfs/           # Root filesystem served via NFS
    ├── bin/, lib/, usr/      # Standard Linux filesystem
    └── etc/fstab             # Mount configuration (auto-configured)
```

### Container Deployment Modes
- **Host networking** (`--network host`): Required for DHCP proxy functionality
- **Privileged mode** (`--privileged`): Required for NFS operations and network services
- **Volume mounts**: Configuration files (read-only) and data directories (read-write)

## Configuration Requirements

### Critical Configuration Files

**`dnsmasq.conf`** - Must be customized before first run:
```conf
interface=eth0                    # Set to your network interface
dhcp-range=10.48.65.0,proxy     # Match your network subnet
```

**`ganesha.conf`** - Optional restrictions for production:
```conf
CLIENT {
    Clients = 10.48.65.0/24;     # Restrict NFS access by subnet
    Access_Type = RW;
    Squash = No_Root_Squash;
}
```

### Raspberry Pi Image Preparation
Images must be extracted and configured for NFS boot:

1. **Extract from .img file:**
   ```bash
   sudo losetup -fP /path/to/image.img
   sudo mount /dev/loop0p1 /mnt/boot     # Boot partition
   sudo mount /dev/loop0p2 /mnt/rootfs   # Root partition
   sudo cp -a /mnt/boot/* ./data/tftpboot/rpi/
   sudo cp -a /mnt/rootfs/* ./data/nfs/rpi/rootfs/
   ```

2. **Boot configuration templates** in `config_files/`:
   - `cmdline.txt`: NFS root kernel parameters
   - `fstab`: NFS mount configuration
   - Both use `<SERVER_IP>` placeholders for automatic substitution

### Client EEPROM Configuration
Raspberry Pi EEPROM must be configured for network boot priority:
```bash
sudo rpi-eeprom-config --edit
# Set: BOOT_ORDER=0xf21
# Set: TFTP_IP=<SERVER_IP>
```

## Troubleshooting Patterns

### Serial Number Directory Links
Some Pi firmware versions look for boot files in serial-specific directories:
```bash
# Get Pi serial number
cat /proc/cpuinfo | grep Serial

# Create symlink in container
./run.sh shell
ln -s /tftpboot/rpi /tftpboot/<serial_number>
```

### Common Port Conflicts
- Port 67 (DHCP): Conflicts with systemd-resolved or other DHCP services
- Port 69 (TFTP): Conflicts with xinetd/tftpd
- Port 2049 (NFS): Conflicts with kernel NFS server

### Network Interface Detection
If automatic IP detection fails (`entrypoint.sh:46-51`):
1. Check `dnsmasq.conf` interface setting
2. Verify interface exists: `ip addr show`
3. Manual fallback uses first non-loopback IP

## Development Context

- **Language**: Bash scripts + YAML configuration
- **Container Runtime**: Podman (not Docker)
- **Target Platform**: Linux (recommended) or WSL2
- **Security Model**: Privileged container with host networking
- **Testing**: Manual validation, no automated test suite
- **Documentation**: Comprehensive README.md with troubleshooting

This is an infrastructure project focused on ease of deployment rather than complex development workflows. Most work involves configuration tuning and shell script modifications.