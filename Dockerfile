# ─────────────────────────────────────────────────────────────────
# Stage 1: Build
# ─────────────────────────────────────────────────────────────────
FROM swift:5.10-jammy AS build

WORKDIR /build

# Copy package manifests first for layer caching
COPY Package.swift Package.resolved* ./
RUN swift package resolve

# Copy source
COPY Sources ./Sources
COPY Tests  ./Tests

# Build in release mode
RUN swift build -c release --static-swift-stdlib

# ─────────────────────────────────────────────────────────────────
# Stage 2: Run
# ─────────────────────────────────────────────────────────────────
FROM ubuntu:22.04

WORKDIR /app

# Runtime dependencies only
RUN apt-get update && apt-get install -y \
    libssl-dev \
    libsqlite3-dev \
    ca-certificates \
    dnsutils \
    whois \
    && rm -rf /var/lib/apt/lists/*

# Copy compiled binary
COPY --from=build /build/.build/release/App ./App

# Copy static assets (landing page, etc.)
COPY Public ./Public

# Vapor listens on $PORT (Railway/Render/Fly.io all set this)
# Fall back to 8080 if not set
ENV PORT=8080
EXPOSE 8080

CMD ["sh", "-c", "./App serve --env production --hostname 0.0.0.0 --port ${PORT:-8080}"]
