# Ethereum Delta Sync Container
# Performs incremental sync from snapshots and other nodes

FROM alpine:3.19

# Install dependencies
RUN apk add --no-cache \
    bash \
    curl \
    jq \
    tar \
    gzip \
    ca-certificates \
    rsync \
    wget

# Install Geth for delta sync operations
ARG GETH_VERSION=v1.13.8
RUN wget -O geth.tar.gz "https://gethstore.blob.core.windows.net/builds/geth-linux-amd64-${GETH_VERSION#v}-*.tar.gz" && \
    tar -xzf geth.tar.gz && \
    mv geth-*/geth /usr/local/bin/ && \
    rm -rf geth* && \
    chmod +x /usr/local/bin/geth

# Create ethereum user
RUN addgroup -g 1000 ethereum && \
    adduser -D -u 1000 -G ethereum ethereum

# Create directories
RUN mkdir -p /data /scripts && \
    chown -R ethereum:ethereum /data /scripts

# Copy delta sync scripts
COPY docker/delta-sync/scripts/ /scripts/
RUN chmod +x /scripts/*.sh

# Switch to non-root user
USER ethereum

# Set working directory
WORKDIR /data

# Default command
ENTRYPOINT ["/scripts/delta-sync.sh"]

# Labels
LABEL maintainer="Ethereum Infrastructure Team <infrastructure@ethereum.dev>"
LABEL description="Ethereum delta sync utility for fast node initialization"
LABEL org.opencontainers.image.source="https://github.com/ethereum/ethereum-node-infrastructure"
LABEL org.opencontainers.image.licenses="MIT"
