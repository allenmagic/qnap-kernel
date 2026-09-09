# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a NixOS kernel customization project for the QNAP TS-564 NAS (Intel Celeron N5095) running a complex multi-layer architecture:

**Architecture:**
```
QNAP TS-564 (NixOS Host)
├─ NAS 功能 (存储、NFS、SMB)
├─ cloud-hypervisor VM (Router VM)
│  └─ Alpine/Gentoo + 自定义内核 (路由器功能)
└─ Nix Container
   └─ VPN + VRRP 浮动网关
```

**Key Features:**
- Linux LTS kernel (6.6.x) - 长期稳定支持
- Highly optimized with Tremont-specific compiler flags
- Integration with the external qnap8528 hardware control module
- Full KVM virtualization support (cloud-hypervisor)
- Advanced networking (routing, NAT, VPN, VRRP)
- Container support (Nix containers with network namespace isolation)
- GitHub Actions CI/CD for automated kernel builds with binary caching

## Build Commands

### Local Development

Build the custom kernel:
```bash
nix build .#packages.x86_64-linux.kernel --print-out-paths --verbose

# Check kernel version
nix eval .#packages.x86_64-linux.kernel.version
```

Build and test the entire NixOS module configuration:
```bash
nix build .#nixosModules.default
```

Evaluate the flake to check for syntax errors:
```bash
nix flake check
```

Update flake inputs (nixpkgs and qnap8528):
```bash
nix flake update
```

### CI/CD

The GitHub Actions workflow `.github/workflows/build-kernel.yml` automatically:
- Builds on push to main or PR
- Uses Cachix for binary caching (requires `CACHIX_AUTH_TOKEN` secret)
- Can be manually triggered via workflow_dispatch

## Architecture

### Kernel Customization Strategy

The project uses a **four-layer configuration approach**:

1. **Kernel version selection**:
   - Uses `linuxPackages_latest_lts` (currently Linux 6.6.x LTS)
   - Ensures long-term stability and hardware support
   - See `docs/kernel-version-guide.md` for version selection rationale

2. **Compiler optimization layer** (`stdenv` override):
   - `-march=tremont`: Target N5095 Tremont microarchitecture specifically
   - `-mtune=tremont`: Microarchitecture-specific tuning
   - `-O2`: Balanced optimization (stability over aggressive optimization)
   - `-pipe`: Use pipes rather than temporary files during compilation

3. **Feature-level pruning** (`features` block):
   - Disables entire driver subsystems (iwlwifi, btusb) that are unused on TS-564
   - Keeps essential networking features (netfilter) for Docker/VM networking

4. **Fine-grained config pruning** (`structuredExtraConfig`):
   - Switches from `MCORE2` to `MATOM` CPU optimization
   - Statically compiles all required drivers (`yes` instead of `module`)
   - Disables wireless, Bluetooth, debugging, and unused GPU drivers
   - Enables all storage, USB, networking, and power management features needed for NAS operation

### Key Dependencies

The kernel configuration has a **critical dependency chain** for the qnap8528 module:
- `I2C_I801`: Intel SMBus controller driver (required for MCU communication)
- `PINCTRL_JASPERLAKE`: GPIO pinctrl for Jasper Lake platform
- These must be `yes` (built-in), not `module`, to satisfy qnap8528 symbol dependencies

### Module Integration Flow

```
flake.nix
  └─> nixosModules.default
       └─> modules/kernel-custom.nix
            ├─> myCustomKernel (linuxPackages_latest.extend)
            └─> boot.extraModulePackages
                 └─> qnap8528 (from external flake, compiled against custom kernel)
```

The qnap8528 module is:
- Fetched from external flake input `github:allenmagic/qnap8528`
- Cross-compiled against the custom kernel via `.override { kernel = config.boot.kernelPackages.kernel; }`
- Forced to load early via `boot.kernelModules`
- Configured with `skip_hw_check=1` parameter

### Initrd Optimization

`boot.initrd.availableKernelModules` is forced to minimal set:
- `xhci_pci`: USB boot support
- `ahci`: SATA boot support
- `nvme`: NVMe boot support
- `sdhci_pci`: eMMC boot support

This eliminates probe delays for unused hardware during boot.

## Hardware-Specific Configuration

### TS-564 Critical Drivers (all built-in)

- **Storage**: AHCI (`SATA_AHCI`), MMC/eMMC (`MMC_SDHCI`, `MMC_BLOCK`)
- **Network**: Intel i225/i226 2.5GbE (`IGC`)
- **Graphics**: Intel UHD for QuickSync transcoding (`DRM_I915`)
- **Audio**: Intel HDA + SOF (Sound Open Firmware) stack for HDMI audio
- **Monitoring**: `SENSORS_CORETEMP` (CPU temp), `SENSORS_IT87` (board sensor chip)

### Power Management

- `INTEL_IDLE`: Deep C-state support for idle power savings
- `X86_INTEL_PSTATE`: Modern Intel P-state frequency scaling
- `NO_HZ_IDLE`: Tickless idle for reduced power consumption
- `CPU_FREQ_GOV_POWERSAVE`: Default to powersave governor

## Development Workflow

When modifying the kernel configuration:

1. **Add new features**: Edit `structuredExtraConfig` in `modules/kernel-custom.nix`
2. **Test locally**: Run `nix build .#packages.x86_64-linux.kernel`
3. **Verify size impact**: Check output size with `du -sh result/`
4. **Test on hardware**: Deploy to TS-564 and verify boot + functionality
5. **Update qnap8528 dependency**: If kernel symbols change, may need to update external module

### Critical: Preserve Essential Features When Pruning

**⚠️ When optimizing/pruning the kernel, ALWAYS preserve these features:**

- **USB Support** (`USB_SUPPORT`, `USB_XHCI_HCD`, `HID`):
  - Required for USB peripherals (keyboards, mice, storage devices)
  - USB 3.0 ports on TS-564
  - Essential for hardware management and recovery

- **HDMI/Display** (`DRM_I915`):
  - Intel UHD Graphics driver
  - Required for HDMI output
  - Critical for hardware transcoding (QuickSync) in Jellyfin/Plex
  - Powers media server functionality

- **Audio Stack** (complete chain):
  - `SOUND`, `SND`, `SND_SOC` (base sound subsystem)
  - `SND_HDA_INTEL` (Intel HDA codec)
  - `SND_SOC_SOF_*` (Sound Open Firmware stack)
  - `SND_SOC_INTEL_SOUNDWIRE_LINK_BASELINE`
  - Required for HDMI audio output
  - Used for media playback and streaming

- **Virtualization Support** (⚠️ CRITICAL - Router VM 依赖):
  - `KVM`, `KVM_INTEL` (Intel VT-x support)
  - `VHOST_NET`, `VHOST_VSOCK` (cloud-hypervisor 高性能网络)
  - `VIRTIO_*` (complete virtio driver stack)
  - Required for cloud-hypervisor Router VM

- **Advanced Networking** (⚠️ CRITICAL - Router + VPN 功能):
  - `TUN`, `VETH`, `BRIDGE`, `MACVLAN`, `IPVLAN` (virtual networking)
  - `WIREGUARD` (VPN support)
  - `IP_ADVANCED_ROUTER`, `IP_MULTIPLE_TABLES` (policy routing)
  - `NF_NAT`, `NETFILTER` (NAT and firewall)
  - `IP_MULTICAST`, `IP_MROUTE` (VRRP multicast support)
  - Required for Router VM and VPN gateway container

- **Container Support** (⚠️ CRITICAL - Nix Container):
  - `NAMESPACES`, `NET_NS`, `USER_NS`, `PID_NS` (isolation)
  - `CGROUPS`, `MEMCG`, `BLK_CGROUP` (resource control)
  - `OVERLAY_FS` (container storage)
  - Required for VPN + VRRP gateway container

These features are already correctly configured in `modules/kernel-optimized-final.nix`. Do not disable or convert them to modules when optimizing.

## Reference: Active Kernel Modules

See `docs/lsmod-reference.txt` for a complete list of currently loaded modules on the production TS-564 system. This list serves as a reference when pruning kernel features:

- Modules in this list should have their corresponding kernel config options preserved
- When adding new hardware support, check if related modules appear in this list
- Periodically update this reference after system updates or hardware changes

To regenerate the reference list on your TS-564:
```bash
lsmod > docs/lsmod-reference.txt
```

## Multi-Layer Architecture Specifics

### cloud-hypervisor VM (Router)
The Router VM runs on cloud-hypervisor with Alpine/Gentoo and a custom kernel. Host kernel requirements:
- vhost-net for high-performance networking
- virtio drivers for all device types
- TAP/TUN for VM networking
- Optional: VFIO for network card passthrough

### Nix Container (VPN Gateway)
The VPN gateway container provides:
- WireGuard or OpenVPN termination
- VRRP (keepalived) for floating IP
- Network namespace isolation

**Network topology**: Physical NIC → Bridge → Router VM + VPN Container

## Important Notes

- **Cachix setup**: Replace `your-qnap-cache` in both `flake.nix` and `.github/workflows/build-kernel.yml` with actual Cachix cache name
- **Symbol dependencies**: When adding kernel features, check if qnap8528 module needs corresponding changes
- **Build time**: Full kernel build takes ~20-40 minutes on GitHub Actions runners
- **Testing**: Always test kernel boots on actual hardware before deploying to production NAS
- **Module reference**: Keep `docs/lsmod-reference.txt` updated to reflect actual hardware usage
- **Virtualization**: Ensure KVM and vhost modules are loaded before starting VMs
- **Networking**: IP forwarding must be enabled in sysctl for routing functionality

## Reference Documentation

See `docs/` directory for detailed guides:
- `kernel-version-guide.md` - Kernel version selection (LTS vs latest)
- `multi-layer-architecture.md` - Complete architecture and networking setup
- `advanced-optimizations.md` - Compiler flags, performance tuning options
- `localmodconfig-guide.md` - Using localmodconfig for optimal kernel size
- `config-analysis.md` - Analysis of current hardware and loaded modules
- `commands-reference.md` - All commonly used commands
- `SUMMARY.md` - Project summary and next steps
