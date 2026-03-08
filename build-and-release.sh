#!/bin/bash
# Build script for Prisma engines for armv7
# This script builds all engines and creates a zip file
#
# Usage:
#   ./build-and-release.sh                    # Build in current directory
#   BUILD_DIR=/mnt/sdcard/build ./build-and-release.sh   # Build on SD card

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Allow building in a different directory (useful for devices with limited / space)
BUILD_DIR=${BUILD_DIR:-$SCRIPT_DIR}

# Create BUILD_DIR if it doesn't exist
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

PRISMA_VERSION=${PRISMA_VERSION:-6.7.0}
OUTPUT_DIR=${OUTPUT_DIR:-$BUILD_DIR/engines}

echo "=========================================="
echo "Prisma Engine Builder for armv7"
echo "=========================================="
echo "Version: ${PRISMA_VERSION}"
echo "Build directory: ${BUILD_DIR}"
echo ""

# Build with limited parallelism to reduce memory usage
export CARGO_BUILD_JOBS=2
export MAKEFLAGS="-j2"

# Create swap file if needed (building prisma-engines needs lots of memory)
if [ ! -f /swapfile ]; then
    echo "Creating swap file..."
    fallocate -l 2G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=2048
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
fi
ARCH=$(uname -m)
echo "Running on architecture: ${ARCH}"

if [ "$ARCH" != "armv7l" ] && [ "$ARCH" != "arm" ]; then
    echo "Warning: Not running on armv7! Cross-compilation may not produce working binaries."
fi

# Install build dependencies if needed
if ! command -v cc &> /dev/null; then
    echo "Installing build tools..."
    apt-get update && apt-get install -y build-essential pkg-config libssl-dev
fi

# Install Rust if needed (minimal install - armv7 only)
if ! command -v cargo &> /dev/null; then
    echo "Installing Rust (armv7 only)..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable --profile minimal
    source "$HOME/.cargo/env"
    rustup target add armv7-unknown-linux-gnueabihf
else
    # Ensure armv7 target is installed
    rustup target add armv7-unknown-linux-gnueabihf 2>/dev/null || true
fi

# Create output directory
mkdir -p ${OUTPUT_DIR}

# Clone or update prisma-engines
if [ ! -d prisma-engines ]; then
    echo "Cloning prisma-engines..."
    git clone --depth 1 --branch ${PRISMA_VERSION} https://github.com/prisma/prisma-engines.git
else
    echo "Updating prisma-engines..."
    cd prisma-engines
    git fetch --depth 1 origin tag ${PRISMA_VERSION} || git fetch --depth 1 origin ${PRISMA_VERSION}
    git checkout ${PRISMA_VERSION}
    cd ..
fi

cd prisma-engines

# Build each engine
echo ""
echo "=========================================="
echo "Building Rust engines..."
echo "=========================================="

echo "Building query-engine..."
cargo build --release -p query-engine
cp target/release/query-engine ../${OUTPUT_DIR}/

echo "Building migration-engine..."
cargo build --release -p migration-engine
cp target/release/migration-engine ../${OUTPUT_DIR}/

echo "Building introspection-engine..."
cargo build --release -p introspection-engine
cp target/release/introspection-engine ../${OUTPUT_DIR}/

echo "Building prisma-fmt..."
cargo build --release -p prisma-fmt
cp target/release/prisma-fmt ../${OUTPUT_DIR}/

cd ..

# Make engines executable
chmod +x ${OUTPUT_DIR}/*

echo ""
echo "=========================================="
echo "Building Node-API library..."
echo "=========================================="

# Install Node.js dependencies for prisma generate
if [ ! -d node_modules ]; then
    echo "Installing npm dependencies..."
    npm install
fi

# Generate Prisma client to get Node-API library
echo "Running prisma generate..."
npx prisma generate

# Copy Node-API library
if [ -f node_modules/.prisma/client/runtime/libquery_engine_napi.so.node ]; then
    cp node_modules/.prisma/client/runtime/libquery_engine_napi.so.node ${OUTPUT_DIR}/
    echo "Copied libquery_engine_napi.so.node"
else
    echo "Warning: libquery_engine_napi.so.node not found!"
    echo "You may need to install @prisma/client and run prisma generate"
fi

# List all engines
echo ""
echo "=========================================="
echo "Engine files:"
echo "=========================================="
ls -la ${OUTPUT_DIR}/

# Create release archive
echo ""
echo "=========================================="
echo "Creating release archive..."
echo "=========================================="

RELEASE_FILE="prisma-engines-${PRISMA_VERSION}-armv7.zip"
cd ${OUTPUT_DIR}
zip -r ../${RELEASE_FILE} *
cd ..

echo "Created: ${RELEASE_FILE}"
echo "Location: ${BUILD_DIR}/${RELEASE_FILE}"

echo ""
echo "=========================================="
echo "Done!"
echo "=========================================="
echo "Upload ${RELEASE_FILE} to GitHub Releases"
