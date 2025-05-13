########################################
# 1) Build your Go RPC binary
########################################
FROM golang:1.24.2-alpine AS builder
RUN apk add --no-cache git ca-certificates openssl

WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN go build -ldflags="-s -w" -o /warlot-publisher ./cmd/server

########################################
# 2) Prepare Sui & Walrus tools
########################################
FROM debian:bookworm-slim AS tools
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl ca-certificates bash libstdc++6 \
    && rm -rf /var/lib/apt/lists/*

# Download & install Sui CLI
RUN curl -fsSL \
    https://github.com/MystenLabs/sui/releases/download/mainnet-v1.47.1/sui-mainnet-v1.47.1-ubuntu-x86_64.tgz \
    -o /tmp/sui.tgz \
    && tar -xzf /tmp/sui.tgz -C /usr/local/bin --strip-components=1 \
    && rm /tmp/sui.tgz

# Install Walrus CLI
RUN curl -sSf https://docs.wal.app/setup/walrus-install.sh | bash -s -- -n testnet \
    && mv ~/.local/bin/walrus /usr/local/bin/ \
    && chmod +x /usr/local/bin/walrus



########################################
# 3) Final runtime image (Debian-Bookworm)
########################################
FROM debian:bookworm-slim AS runtime

# 3a) Install bash, certificates, libstdc++, curl; create non-root user w/ home
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
    bash \
    ca-certificates \
    libstdc++6 \
    curl \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd -r appuser --gid 1000 \
    && useradd -r -g appuser --uid 1000 -m -d /home/appuser appuser

# Tell processes where the home actually is
ENV HOME=/home/appuser

# Make appuser’s home the working directory
WORKDIR /home/appuser

# 3b) Ensure the Sui config dir exists and is writable
RUN mkdir -p /home/appuser/.sui \
    && chown -R appuser:appuser /home/appuser

# 3c) Copy your Go server binary
COPY --from=builder /warlot-publisher /usr/local/bin/warlot-publisher

# 3d) Copy TLS certs into the runtime image
COPY --from=builder /src/server.crt /home/appuser/server.crt
COPY --from=builder /src/server.key /home/appuser/server.key
RUN chown appuser:appuser /home/appuser/server.crt /home/appuser/server.key



# 3d) Copy Sui & Walrus CLIs
COPY --from=tools /usr/local/bin/sui*    /usr/local/bin/
COPY --from=tools /usr/local/bin/walrus  /usr/local/bin/

# 3e) Copy & set permissions on entrypoint
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh \
    && chown appuser:appuser /usr/local/bin/entrypoint.sh \
    && chown appuser:appuser /usr/local/bin/warlot-publisher

# 3f) Drop to non-root
USER appuser

EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
