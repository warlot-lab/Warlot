########################################
# 1) Build Go indexer binary
########################################
FROM golang:1.24.2-alpine AS builder
RUN apk add --no-cache git ca-certificates

WORKDIR /src
# cache dependencies
COPY go.mod go.sum ./
RUN go mod download

# copy your entire module
COPY . .

# build only the indexer command
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
    go build -ldflags="-s -w" \
    -o /indexer ./cmd/indexer

########################################
# 2) Final minimal runtime image
########################################
FROM scratch
# bring in CA certs so HTTPS calls work 
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/

# copy your statically-built indexer binary
COPY --from=builder /indexer /indexer

# drop to non-root user for safety
USER 1000

ENTRYPOINT ["/indexer"]
