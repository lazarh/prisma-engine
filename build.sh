#!/bin/bash
# Build script for Prisma engines on armv7
# Run this on your Cubieboard4 or other armv7 device

set -e

PRISMA_VERSION=${PRISMA_VERSION:-6.7.0}
OUTPUT_DIR=${OUTPUT_DIR:-./engines}

echo "Building Prisma engines v${PRISMA_VERSION} for armv7"
echo "Output directory: ${OUTPUT_DIR}"

# Install dependencies if needed
if ! command -v cargo &> /dev/null; then
    echo "Installing Rust..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source "$HOME/.cargo/env"
fi

# Add armv7 target
rustup target add armv7-unknown-linux-gnueabihf || true

# Clone prisma-engines
if [ ! -d prisma-engines ]; then
    echo "Cloning prisma-engines..."
    git clone --depth 1 --branch ${PRISMA_VERSION} https://github.com/prisma/prisma-engines.git
fi

cd prisma-engines

# Build each engine
echo "Building query-engine..."
cargo build --release -p query-engine

echo "Building migration-engine..."
cargo build --release -p migration-engine

echo "Building introspection-engine..."
cargo build --release -p introspection-engine

echo "Building prisma-fmt..."
cargo build --release -p prisma-fmt

# Create output directory
mkdir -p ${OUTPUT_DIR}

# Copy binaries
echo "Copying engines to ${OUTPUT_DIR}..."
cp target/release/query-engine ${OUTPUT_DIR}/
cp target/release/migration-engine ${OUTPUT_DIR}/
cp target/release/introspection-engine ${OUTPUT_DIR}/
cp target/release/prisma-fmt ${OUTPUT_DIR}/

# Make executable
chmod +x ${OUTPUT_DIR}/*

echo "Done! Engines are in ${OUTPUT_DIR}/"
ls -la ${OUTPUT_DIR}/
