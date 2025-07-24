# ---------- BUILD STAGE ----------
FROM golang:1.20-alpine AS builder

# Install git (for go modules) and certs
RUN apk add --no-cache git ca-certificates

WORKDIR /src

# Copy go.mod and your checksum file, rename it, download deps
COPY go.mod go.sum.go ./
RUN mv go.sum.go go.sum \
 && go mod download

# Copy the rest of the source
COPY . .

# Build the worker binary
WORKDIR /src/cmd/worker
RUN CGO_ENABLED=0 GOOS=linux go build \
    -ldflags="-s -w" \
    -o /app/worker

# ---------- RUNTIME STAGE ----------
FROM alpine:3.17

# Non-root user for safety
RUN addgroup -S app && adduser -S app -G app

WORKDIR /app

# Copy the statically-built binary
COPY --from=builder /app/worker .

# Drop back to unprivileged user
USER app

# (Optional) if you have config files, copy them here:
# COPY config.yaml .

# Entrypoint
ENTRYPOINT ["./worker"]
