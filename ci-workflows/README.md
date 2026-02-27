# CI/CD Workflow Files

This directory contains GitHub Actions workflow files and patches for the
cross-repo CI/CD pipeline: Kernel Build → Image Build → PXE Deploy.

## Directory Structure

```
ci-workflows/
├── linux/                          → analogdevicesinc/linux repo
│   └── .github/workflows/
│       └── gmsl-kernel-build.yml   → New workflow: build GMSL kernel
│
├── adi-kuiper-gen/                 → analogdevicesinc/adi-kuiper-gen repo
│   ├── .github/workflows/
│   │   └── gmsl-kuiper-build.yml   → New workflow: build Kuiper image + deploy
│   └── patches/
│       ├── build-docker.sh.patch               → Volume mount for boot artifacts
│       └── 02.rpi-boot-files-run.sh.patch      → Local boot files code path
│
└── README.md                       → This file
```

## How to Apply

### 1. Linux repo (analogdevicesinc/linux, branch gmsl/rpi-6.13.y)

Copy the workflow file:
```bash
cp ci-workflows/linux/.github/workflows/gmsl-kernel-build.yml \
   /path/to/linux/.github/workflows/
```

Add the `CROSS_REPO_PAT` secret to the linux repo (Settings → Secrets → Actions):
- A GitHub PAT with `repo` scope from a user with access to both repos

### 2. adi-kuiper-gen repo (analogdevicesinc/adi-kuiper-gen, branch gmsl-rpi-6.13.y)

Copy the workflow file:
```bash
cp ci-workflows/adi-kuiper-gen/.github/workflows/gmsl-kuiper-build.yml \
   /path/to/adi-kuiper-gen/.github/workflows/
```

Apply the patches:
```bash
cd /path/to/adi-kuiper-gen
git apply /path/to/ci-workflows/adi-kuiper-gen/patches/build-docker.sh.patch
git apply /path/to/ci-workflows/adi-kuiper-gen/patches/02.rpi-boot-files-run.sh.patch
```

Add the following secrets to the adi-kuiper-gen repo:
- `CROSS_REPO_PAT` — GitHub PAT with `repo` scope (same as linux repo)
- `PXE_SSH_KEY` — SSH private key for the PXE server
- `PXE_HOST` — PXE server hostname or IP
- `PXE_USER` — SSH username for the PXE server
- `PXE_DEPLOY_PATH` — Path to podman-pxe-server directory on the server

### 3. podman-pxe-server (this repo)

The `run.sh` has already been updated to:
- Accept an optional image filename: `./run.sh setup my_image.img`
- Clean existing data directories before extraction
- Validate that the image file exists

## Pipeline Flow

1. Push to `gmsl/rpi-6.13.y` in linux repo
2. `gmsl-kernel-build.yml` builds RPi4 + RPi5 kernels in parallel
3. `package` job merges boot files + modules into tarballs
4. `repository_dispatch` triggers `adi-kuiper-gen`
5. `gmsl-kuiper-build.yml` downloads artifacts, builds Kuiper image
6. Image is SCP'd to PXE server, `./run.sh setup` extracts it
7. RPi can PXE boot with the new kernel
