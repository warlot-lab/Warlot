########################################
# 1) Build therenew bot binary
########################################
FROM golang:1.24.2-alpine AS builder
RUN apk add --no-cache git ca-certificates

WORKDIR /src
# cache dependencies
COPY go.mod go.sum ./
RUN go mod download

# copy all source code
COPY . .

# build only the therenew bot command
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
    go build -ldflags="-s -w" \
    -o /renewbot ./cmd/renewbot

########################################
# 2) Final minimal runtime image
########################################
FROM scratch
# copy CA certs for HTTPS
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/

# copy statically linked binary
COPY --from=builder /renewbot /renewbot

# drop to non-root user
USER 1000

ENTRYPOINT ["/renewbot"]
