FROM node:22-bookworm

RUN apt-get update && apt-get install -y \
    build-essential \
    pkg-config \
    libssl-dev \
    git \
    curl \
    && rm -rf /var/lib/apt/lists/*

ENV PRISMA_VERSION=6.7.0

WORKDIR /build

RUN git clone --depth 1 --branch $PRISMA_VERSION https://github.com/prisma/prisma-engines.git

WORKDIR /build/prisma-engines

RUN cargo build --release -p query-engine && \
    cargo build --release -p migration-engine && \
    cargo build --release -p introspection-engine && \
    cargo build --release -p prisma-fmt

FROM debian:bookworm-slim

COPY --from=0 /build/prisma-engines/target/release/query-engine /engines/
COPY --from=0 /build/prisma-engines/target/release/migration-engine /engines/
COPY --from=0 /build/prisma-engines/target/release/introspection-engine /engines/
COPY --from=0 /build/prisma-engines/target/release/prisma-fmt /engines/

RUN chmod +x /engines/*

CMD ["ls", "-la", "/engines/"]
