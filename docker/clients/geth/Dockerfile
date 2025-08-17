# Ethereum Geth Client - Optimized for Production
FROM golang:1.21-alpine AS builder

# Install build dependencies
RUN apk add --no-cache \
    git \
    make \
    gcc \
    musl-dev \
    linux-headers

# Set working directory
WORKDIR /app

# Clone Geth repository
ARG GETH_VERSION=v1.13.8
RUN git clone --depth 1 --branch ${GETH_VERSION} https://github.com/ethereum/go-ethereum.git .

# Build Geth
RUN make geth

# Final stage - minimal Alpine image
FROM alpine:3.19

# Install runtime dependencies
RUN apk add --no-cache \
    ca-certificates \
    curl \
    jq \
    bash \
    tzdata

# Create ethereum user
RUN addgroup -g 1000 ethereum && \
    adduser -D -u 1000 -G ethereum ethereum

# Copy Geth binary from builder
COPY --from=builder /app/build/bin/geth /usr/local/bin/

# Create data directory
RUN mkdir -p /data && \
    chown -R ethereum:ethereum /data

# Health check script
COPY docker/clients/geth/healthcheck.sh /usr/local/bin/healthcheck.sh
RUN chmod +x /usr/local/bin/healthcheck.sh

# Set up health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD /usr/local/bin/healthcheck.sh

# Switch to non-root user
USER ethereum

# Expose ports
EXPOSE 8545 8546 30303 30303/udp 6060

# Set working directory
WORKDIR /data

# Default command
ENTRYPOINT ["/usr/local/bin/geth"]
CMD ["--help"]

# Labels
LABEL maintainer="Ethereum Infrastructure Team <infrastructure@ethereum.dev>"
LABEL description="Optimized Ethereum Geth client for production use"
LABEL version="${GETH_VERSION}"
LABEL org.opencontainers.image.source="https://github.com/ethereum/go-ethereum"
LABEL org.opencontainers.image.documentation="https://geth.ethereum.org/docs/"
LABEL org.opencontainers.image.licenses="LGPL-3.0"
