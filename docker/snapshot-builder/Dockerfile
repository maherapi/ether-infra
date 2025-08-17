# Ethereum Snapshot Builder
# Creates blockchain snapshots for faster node deployment

FROM alpine:3.19

# Install dependencies
RUN apk add --no-cache \
    bash \
    curl \
    jq \
    tar \
    gzip \
    xz \
    python3 \
    py3-pip \
    ca-certificates \
    rsync \
    wget

# Install Geth for snapshot creation
ARG GETH_VERSION=v1.13.8
RUN wget -O geth.tar.gz "https://gethstore.blob.core.windows.net/builds/geth-linux-amd64-${GETH_VERSION#v}-*.tar.gz" && \
    tar -xzf geth.tar.gz && \
    mv geth-*/geth /usr/local/bin/ && \
    rm -rf geth* && \
    chmod +x /usr/local/bin/geth

# Install Python dependencies for metrics server
RUN pip3 install --no-cache-dir requests

# Create ethereum user
RUN addgroup -g 1000 ethereum && \
    adduser -D -u 1000 -G ethereum ethereum

# Create directories
RUN mkdir -p /workspace /scripts /config && \
    chown -R ethereum:ethereum /workspace /scripts /config

# Copy scripts
COPY docker/snapshot-builder/scripts/ /scripts/
RUN chmod +x /scripts/*.sh

# Health check script for monitoring
COPY docker/snapshot-builder/healthcheck.sh /usr/local/bin/healthcheck.sh
RUN chmod +x /usr/local/bin/healthcheck.sh

# Metrics server script
COPY docker/snapshot-builder/metrics-server.py /usr/local/bin/metrics-server.py
RUN chmod +x /usr/local/bin/metrics-server.py

# Switch to non-root user
USER ethereum

# Expose metrics port
EXPOSE 8080

# Set working directory
WORKDIR /workspace

# Default command
ENTRYPOINT ["/scripts/entrypoint.sh"]
CMD ["create-snapshot"]

# Labels
LABEL maintainer="Ethereum Infrastructure Team <infrastructure@ethereum.dev>"
LABEL description="Ethereum blockchain snapshot builder for fast deployment"
LABEL org.opencontainers.image.source="https://github.com/ethereum/ethereum-node-infrastructure"
LABEL org.opencontainers.image.documentation="https://github.com/ethereum/ethereum-node-infrastructure/blob/main/docs/snapshot-builder.md"
LABEL org.opencontainers.image.licenses="MIT"
