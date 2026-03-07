#!/bin/bash
# Build and release script for Prisma engines
# This script builds all engines and creates a GitHub release

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

PRISMA_VERSION=${PRISMA_VERSION:-6.7.0}
OUTPUT_DIR=${OUTPUT_DIR:-./engines}
REPO_OWNER=${REPO_OWNER:-lazarh}
REPO_NAME=${REPO_NAME:-prisma-engine}

echo "=========================================="
echo "Prisma Engine Builder for armv7"
echo "=========================================="
echo "Version: ${PRISMA_VERSION}"
echo ""

# Check if we're on armv7
ARCH=$(uname -m)
echo "Running on architecture: ${ARCH}"

if [ "$ARCH" != "armv7l" ] && [ "$ARCH" != "arm" ]; then
    echo "Warning: Not running on armv7! Cross-compilation may not produce working binaries."
    echo "Press Ctrl+C to abort, or Enter to continue..."
    read
fi

# Check for GitHub CLI
if ! command -v gh &> /dev/null; then
    echo "Installing GitHub CLI..."
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
    sudo apt-get update
    sudo apt-get install -y gh
fi

# Check authentication
echo "Checking GitHub authentication..."
if ! gh auth status &> /dev/null; then
    echo "Please authenticate with GitHub:"
    gh auth login
fi

# Install Rust if needed
if ! command -v cargo &> /dev/null; then
    echo "Installing Rust..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source "$HOME/.cargo/env"
fi

# Add armv7 target if on aarch64 or x86_64
if [ "$ARCH" = "aarch64" ]; then
    rustup target add armv7-unknown-linux-gnueabihf || true
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

# Create GitHub release
echo ""
echo "=========================================="
echo "Creating GitHub release..."
echo "=========================================="

# Check if release exists
if gh release view ${PRISMA_VERSION} --repo ${REPO_OWNER}/${REPO_NAME} &> /dev/null; then
    echo "Release ${PRISMA_VERSION} already exists. Deleting..."
    gh release delete ${PRISMA_VERSION} --repo ${REPO_OWNER}/${REPO_NAME} --yes
fi

# Create release
gh release create ${PRISMA_VERSION} \
    --title "Prisma ${PRISMA_VERSION} for armv7" \
    --notes "Precompiled Prisma engines for 32-bit ARM (armv7).

## Files included:
$(ls -1 ${OUTPUT_DIR} | sed 's/^/- /')

## Usage:
Download the zip and extract to your project directory, then set environment variables:
\`\`\`bash
export PRISMA_QUERY_ENGINE_BINARY=./query-engine
export PRISMA_MIGRATION_ENGINE_BINARY=./migration-engine
export PRISMA_INTROSPECTION_ENGINE_BINARY=./introspection-engine
export PRISMA_FMT_BINARY=./prisma-fmt
export PRISMA_QUERY_ENGINE_LIBRARY=./libquery_engine_napi.so.node
\`\`\`

Built on: $(date)" \
    --repo ${REPO_OWNER}/${REPO_NAME} \
    ${RELEASE_FILE}

echo ""
echo "=========================================="
echo "Done!"
echo "=========================================="
echo "Release URL: https://github.com/${REPO_OWNER}/${REPO_NAME}/releases/tag/${PRISMA_VERSION}"
