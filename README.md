# Prisma Engines for armv7

Precompiled [Prisma](https://www.prisma.io/) engines for 32-bit ARM (armv7).

## Motivation

Prisma officially only supports `amd64` (x86_64) and `arm64` (aarch64). This repository provides precompiled engines for `armv7` (armv7l) systems like Raspberry Pi 1-3, Cubieboard4, and other 32-bit ARM devices.

## Downloads

Download the engine files from the [Releases](https://github.com/lazarh/prisma-engine/releases) page.

## What's Included

- `query-engine` - Query execution engine
- `migration-engine` - Database migration engine
- `introspection-engine` - Database introspection engine
- `prisma-fmt` - Prisma schema formatter
- `libquery_engine_napi.so.node` - Node-API query engine library

## Usage

### Method 1: Environment Variables

Download all engine files and place them in a directory (e.g., `./prisma-engines/`). Then set these environment variables:

```bash
export PRISMA_QUERY_ENGINE_BINARY=./prisma-engines/query-engine
export PRISMA_MIGRATION_ENGINE_BINARY=./prisma-engines/migration-engine
export PRISMA_INTROSPECTION_ENGINE_BINARY=./prisma-engines/introspection-engine
export PRISMA_FMT_BINARY=./prisma-engines/prisma-fmt
export PRISMA_QUERY_ENGINE_LIBRARY=./prisma-engines/libquery_engine_napi.so.node
```

### Method 2: Docker Multi-platform Build

Build on your armv7 device or use QEMU:

```bash
docker build -t myapp .
docker run -e PRISMA_QUERY_ENGINE_LIBRARY=/app/engines/libquery_engine_napi.so.node myapp
```

## Building from Source

### On Cubieboard4 (native armv7)

```bash
# Clone this repository
git clone https://github.com/lazarh/prisma-engine.git
cd prisma-engine

# Run the build script
chmod +x build.sh
./build.sh
```

The script will:
1. Install Rust if needed
2. Clone prisma-engines
3. Build all 4 engine binaries
4. Output to ./engines/

### Cross-compilation

Use Docker with QEMU:

```bash
docker run --rm --privileged multiarch/qemu-user-static --reset -p yes
docker buildx build --platform linux/arm/v7 -t prisma-engine .
```

## Supported Versions

- Prisma 6.7.0 (current)
- Node.js 22.x (recommended for armv7)

## Note on Node-API Library

The `libquery_engine_napi.so.node` (Node-API binding) is built as part of the `@prisma/client` package during `prisma generate`. After running `prisma generate` on armv7, this file will be in `node_modules/.prisma/client/runtime/`.

Copy it to your engines directory:
```bash
cp node_modules/.prisma/client/runtime/libquery_engine_napi.so.node ./engines/
```

## License

Apache 2.0 - Same as Prisma
