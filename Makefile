# Binaries and directories
BINARY_NAME := worker
BUILD_DIR   := bin
PKG         := ./cmd/worker

# Docker image
IMAGE_NAME  := commoncrawl-chunks-export-worker
IMAGE_TAG   := latest

# Go tooling
GO          := go
GOCMD       := $(GO)
GOTEST      := $(GO) test
GOLINT      := golangci-lint
GOLINT_CFG  := .golangci.yml

# AWS region and S3 bucket (can be overridden via env)
AWS_REGION  ?= us-east-1
S3_BUCKET   ?= commoncrawl

# Default target
.PHONY: all
all: build

# Build binary
.PHONY: build
build:
	@echo "→ Building binary..."
	@mkdir -p $(BUILD_DIR)
	@CGO_ENABLED=0 GOOS=linux GOARCH=amd64 $(GOCMD) build \
		-ldflags="-s -w" \
		-o $(BUILD_DIR)/$(BINARY_NAME) $(PKG)

# Run locally (assumes AWS creds in env)
.PHONY: run
run: build
	@echo "→ Running locally..."
	@AWS_REGION=$(AWS_REGION) S3_BUCKET=$(S3_BUCKET) \
		$(BUILD_DIR)/$(BINARY_NAME)

# Run tests
.PHONY: test
test:
	@echo "→ Running tests..."
	@$(GOTEST) ./... -cover

# Lint code
.PHONY: lint
lint:
	@echo "→ Running linter..."
	@$(GOLINT) run --config=$(GOLINT_CFG)

# Clean build outputs
.PHONY: clean
clean:
	@echo "→ Cleaning..."
	@rm -rf $(BUILD_DIR)

# Build and push Docker image
.PHONY: docker
docker: build
	@echo "→ Building Docker image..."
	@docker build -t $(IMAGE_NAME):$(IMAGE_TAG) .
	@echo "→ Tagging image..."
	@docker tag $(IMAGE_NAME):$(IMAGE_TAG) $(IMAGE_NAME):$(IMAGE_TAG)

# Push Docker image to registry (assumes you're already logged in)
.PHONY: docker-push
docker-push:
	@echo "→ Pushing Docker image..."
	@docker push $(IMAGE_NAME):$(IMAGE_TAG)

# Show help
.PHONY: help
help:
	@echo "Makefile commands:"
	@echo "  make           → build binary (default)"
	@echo "  make run       → build & run locally"
	@echo "  make test      → run all tests"
	@echo "  make lint      → run linter"
	@echo "  make clean     → remove binaries"
	@echo "  make docker    → build Docker image"
	@echo "  make docker-push → push Docker image"
	@echo "  make help      → show this help message"
