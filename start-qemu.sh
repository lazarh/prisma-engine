#!/bin/bash
# QEMU ARMv7 VM startup script for building prisma-engine
# Auto-detects host resources and launches a QEMU ARMv7 VM with a virt/board suitable for Debian

set -euo pipefail

IMAGE="${1:-debian-bookworm-armhf.qcow2}"
SSH_PORT="${SSH_PORT:-2222}"

if [ ! -f "$IMAGE" ]; then
    cat <<'EOF'
Error: Disk image '$IMAGE' not found.

To create a Debian Bookworm ARMv7 image:
  1. Download Debian ARMhf netboot (example):
     wget https://deb.debian.org/debian/dists/bookworm/main/installer-armhf/current/images/netboot/vmlinuz
     wget https://deb.debian.org/debian/dists/bookworm/main/installer-armhf/current/images/netboot/initrd.gz

  2. Create empty qcow2 image:
     qemu-img create -f qcow2 debian-bookworm-armhf.qcow2 20G

  3. Start installer (run this script with image path after creating it):
     ./start-qemu.sh debian-bookworm-armhf.qcow2

  4. In the VM, install build essentials:
     apt-get update && apt-get install -y build-essential pkg-config libssl-dev git curl
     curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
     source ~/.cargo/env
     rustup target add armv7-unknown-linux-gnueabihf
EOF
    exit 1
fi

# Detect host resources and choose conservative 'max' values so host stays responsive.
TOTAL_KB=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
TOTAL_MB=$((TOTAL_KB / 1024))
RESERVE_MB=512
if [ "$TOTAL_MB" -gt $((RESERVE_MB + 512)) ]; then
    MEM_MB=$((TOTAL_MB - RESERVE_MB))
else
    MEM_MB=$TOTAL_MB
fi
CPUS=$(nproc --all)

# Default machine and CPU model for ARMv7
MACHINE="virt"
CPU_MODEL="cortex-a15"

# Known machine limits (max CPUs, max RAM in MB for 32-bit guests)
declare -A MACHINE_MAX_CPUS
MACHINE_MAX_CPUS["vexpress-a9"]=4
MACHINE_MAX_CPUS["versatilepb"]=1
# For 'virt' leave the entry unset (or set to 0) to allow full host CPU count

# Cap CPUs to machine maximum when known. If mapping value is 0/unset, allow host CPUs.
MAX_CPUS_VAL=${MACHINE_MAX_CPUS["$MACHINE"]:-0}
if [ "$MAX_CPUS_VAL" -eq 0 ]; then
    MAX_CPUS=$CPUS
else
    MAX_CPUS=$MAX_CPUS_VAL
fi
if [ "$CPUS" -gt "$MAX_CPUS" ]; then
    CPUS_USED=$MAX_CPUS
else
    CPUS_USED=$CPUS
fi

# Cap guest RAM to 4096 MB for 32-bit ARMv7 guests to avoid addressing issues
if [ "$MEM_MB" -gt 4096 ]; then
    MEM_USED=4096
    echo "Note: capping guest RAM to 4096 MB for 32-bit ARMv7 guest (host has ${MEM_MB} MB)."
else
    MEM_USED=$MEM_MB
fi

echo "Starting QEMU ARMv7 VM..."
echo "  Image: $IMAGE"
echo "  RAM: ${MEM_USED} MB (requested ${MEM_MB} MB)"
echo "  CPUs: ${CPUS_USED} (host ${CPUS})"
echo "  SSH port: $SSH_PORT"
echo ""
echo "After VM starts, connect with:"
echo "  ssh -p $SSH_PORT root@localhost"
echo ""
echo "To run the build inside the VM:"
echo "  ./build-and-release.sh"
echo ""

# Check whether netboot kernel/initrd exist in repo. If present, use them to boot the Debian installer.
USE_INSTALLER_KERNEL=false
if [ -f vmlinuz ] && [ -f initrd.gz ]; then
    USE_INSTALLER_KERNEL=true
fi

# If using the installer kernel, switch to vexpress-a9 which matches Debian's netboot kernel
# and enforce its known resource limits (vexpress-a9 can't model >1GB in many qemu builds).
if $USE_INSTALLER_KERNEL; then
    echo "Installer kernel detected: switching machine to vexpress-a9 for compatibility."
    MACHINE="vexpress-a9"
    CPU_MODEL="cortex-a9"
    # cap RAM to 1024MB for vexpress
    if [ "$MEM_MB" -gt 1024 ]; then
        MEM_USED=1024
        echo "Note: capping guest RAM to 1024 MB for vexpress-a9 (host has ${MEM_MB} MB)."
    else
        MEM_USED=$MEM_MB
    fi
    # cap CPUs for vexpress to 4 (some qemu builds are limited to 1, be conservative)
    if [ "$CPUS" -gt 4 ]; then
        CPUS_USED=4
    else
        CPUS_USED=$CPUS
    fi

    # Try to find a matching device tree blob (dtb) on the host to use with the installer kernel.
    DTB=""
    for candidate in "/usr/share/qemu/vexpress-v2p-ca9.dtb" "/usr/share/qemu/arm/"/vexpress*.dtb "/usr/share/qemu/arm-"*.dtb "/usr/lib/qemu/vexpress-v2p-ca9.dtb" "/usr/lib/qemu/"*.dtb; do
        # expand glob safely
        for f in $candidate; do
            if [ -f "$f" ]; then
                basename=$(basename "$f")
                case "$basename" in
                    *vexpress*|*v2p*|*ca9*)
                        DTB="$f"
                        break 3
                        ;;
                esac
            fi
        done
    done

    if [ -n "$DTB" ]; then
        echo "Using DTB: $DTB"
    else
        echo "Warning: no vexpress DTB found on host. Installer kernel may hang without a compatible DTB."
        echo "Proceeding without -dtb; if installer stalls, consider running without kernel/initrd and use an installer image or a prebuilt qcow2." >&2
    fi
fi

# Build qemu command arguments
QEMU_ARGS=(
    -M "$MACHINE"
    -cpu "$CPU_MODEL"
    -m "$MEM_USED"
    -smp "$CPUS_USED"
    -drive "file=$IMAGE,format=qcow2,if=none,id=hd0"
    -device virtio-blk-device,drive=hd0
    -netdev user,id=net0,hostfwd=tcp::${SSH_PORT}-:22
    -device virtio-net-device,netdev=net0
    -serial mon:stdio
    -display none
    -no-reboot
)

# If we found a DTB for installer, add it to QEMU args
if [ -n "${DTB:-}" ]; then
    QEMU_ARGS+=( -dtb "$DTB" )
fi

# When using installer kernel, add kernel/initrd and conservative append options
if $USE_INSTALLER_KERNEL; then
    # Use a slower console baud and force installer to use the user-mode network
    QEMU_ARGS+=( -kernel vmlinuz -initrd initrd.gz -append "console=ttyAMA0,115200 root=/dev/ram0 rw" )
fi

if $USE_INSTALLER_KERNEL; then
    # When using installer kernel, pass typical installer append flags. The installer will use the attached qcow2 as the target disk.
    QEMU_ARGS+=( -kernel vmlinuz -initrd initrd.gz -append "console=ttyAMA0 root=/dev/ram0 rw" )
fi

# Ensure qemu-system-arm is available
if ! command -v qemu-system-arm >/dev/null 2>&1; then
    echo "Error: qemu-system-arm not found in PATH. Install qemu-system-arm package." >&2
    exit 2
fi

# Execute QEMU
set -x
exec qemu-system-arm "${QEMU_ARGS[@]}"

