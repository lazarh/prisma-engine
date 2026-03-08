#!/bin/bash
# QEMU ARMv7 VM startup script for building prisma-engine
# Specs: ARMv7 (virt), 4096 MB RAM, 8 CPUs

set -e

IMAGE="${1:-debian-bookworm-armhf.qcow2}"
SSH_PORT="${SSH_PORT:-2222}"

if [ ! -f "$IMAGE" ]; then
    echo "Error: Disk image '$IMAGE' not found."
    echo ""
    echo "To create a Debian Bookworm ARMv7 image:"
    echo "  1. Download Debian ARMhf netinst:"
    echo "     wget https://deb.debian.org/debian/dists/bookworm/main/installer-armhf/current/images/netboot/vmlinuz"
    echo "     wget https://deb.debian.org/debian/dists/bookworm/main/installer-armhf/current/images/netboot/initrd.gz"
    echo ""
    echo "  2. Create empty qcow2 image:"
    echo "     qemu-img create -f qcow2 debian-bookworm-armhf.qcow2 20G"
    echo ""
    echo "  3. Start installer (run this script with image path after creating it):"
    echo "     ./start-qemu.sh debian-bookworm-armhf.qcow2"
    echo ""
    echo "  4. In the VM, install build essentials:"
    echo "     apt-get update && apt-get install -y build-essential pkg-config libssl-dev git curl"
    echo "     curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y"
    echo "     source ~/.cargo/env"
    echo "     rustup target add armv7-unknown-linux-gnueabihf"
    exit 1
fi

echo "Starting QEMU ARMv7 VM..."
echo "  Image: $IMAGE"
echo "  RAM: 4096 MB"
echo "  CPUs: 8"
echo "  SSH port: $SSH_PORT"
echo ""
echo "After VM starts, connect with:"
echo "  ssh -p $SSH_PORT root@localhost"
echo ""
echo "To run the build:"
echo "  ./build-and-release.sh"

exec qemu-system-arm \
    -M virt \
    -cpu cortex-a15 \
    -m 4096 \
    -smp 8 \
    -kernel vmlinuz \
    -initrd initrd.gz \
    -append "console=ttyAMA0 rw" \
    -drive file="$IMAGE",format=qcow2,if=virtio \
    -netdev user,id=net0,hostfwd=tcp::$SSH_PORT-:22 \
    -device virtio-net-pci,netdev=net0 \
    -nographic
