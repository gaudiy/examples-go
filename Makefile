# See https://tech.davis-hansson.com/p/make/
SHELL := bash
.DELETE_ON_ERROR:
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := all
MAKEFLAGS += --warn-undefined-variables
MAKEFLAGS += --no-builtin-rules
MAKEFLAGS += --no-print-directory
BIN=$(abspath .tmp/bin)
export PATH := $(BIN):$(PATH)
export GOBIN := $(abspath $(BIN))
COPYRIGHT_YEARS := 2022-2023
LICENSE_IGNORE := --ignore /testdata/
# Set to use a different compiler. For example, `GO=go1.18rc1 make test`.
GO ?= go

.PHONY: help
help: ## Describe useful make targets
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "%-30s %s\n", $$1, $$2}'

.PHONY: all
all: ## Build, test, and lint (default)
	$(MAKE) test
	$(MAKE) lint

.PHONY: clean
clean: ## Delete intermediate build artifacts
	@# -X only removes untracked files, -d recurses into directories, -f actually removes files/dirs
	git clean -Xdf

.PHONY: test
test: build ## Run unit tests
	$(GO) test -vet=off -race -cover ./...

.PHONY: build
build: generate ## Build all packages
	$(GO) build ./...

.PHONY: lint
lint: $(BIN)/golangci-lint $(BIN)/buf ## Lint Go and protobuf
	test -z "$$($(BIN)/buf format -d . | tee /dev/stderr)"
	$(GO) vet ./...
	golangci-lint run
	buf lint

.PHONY: lintfix
lintfix: $(BIN)/golangci-lint $(BIN)/buf ## Automatically fix some lint errors
	golangci-lint run --fix
	buf format -w .

.PHONY: generate
generate: $(BIN)/buf $(BIN)/protoc-gen-go $(BIN)/protoc-gen-connect-go $(BIN)/license-header ## Regenerate code and licenses
	rm -rf internal/gen
	PATH=$(BIN) $(BIN)/buf generate
	license-header \
		--license-type apache \
		--copyright-holder "The Connect Authors" \
		--year-range "$(COPYRIGHT_YEARS)" $(LICENSE_IGNORE)

.PHONY: upgrade
upgrade: ## Upgrade dependencies
	go get -u -t ./... && go mod tidy -v

.PHONY: checkgenerate
checkgenerate:
	@# Used in CI to verify that `make generate` doesn't produce a diff.
	test -z "$$(git status --porcelain | tee /dev/stderr)"

$(BIN)/buf: Makefile
	@mkdir -p $(@D)
	$(GO) install github.com/bufbuild/buf/cmd/buf@v1.26.1

$(BIN)/license-header: Makefile
	@mkdir -p $(@D)
	$(GO) install github.com/bufbuild/buf/private/pkg/licenseheader/cmd/license-header@v1.26.1

$(BIN)/golangci-lint: Makefile
	@mkdir -p $(@D)
	$(GO) install github.com/golangci/golangci-lint/cmd/golangci-lint@v1.54.1

$(BIN)/protoc-gen-go: Makefile
	@mkdir -p $(@D)
	$(GO) install google.golang.org/protobuf/cmd/protoc-gen-go

$(BIN)/protoc-gen-connect-go: Makefile go.mod
	@mkdir -p $(@D)
	$(GO) install connectrpc.com/connect/cmd/protoc-gen-connect-go

##@ docker
GCP_PROJECT ?= gaudiy-develop-tokyo
SERVICE_NAME = connect-go-demoserver
GIT_REVISION ?= $(shell git rev-parse --short=12 --verify HEAD)
VERSION=$(shell echo $$VERSION)

DOCKER_BUILDER = desktop-linux
DOCKER_BUILD_TARGET = ${SERVICE_NAME}
DOCKER_BUILD_TAG = ${GIT_REVISION}
DOCKER_BUILD_TYPE ?= docker
DOCKER_BUILD_FLAGS ?= --platform linux/amd64 --build-arg VERSION=${VERSION} --build-arg GIT_REVISION_FULL=${GIT_REVISION_FULL} --secret id=GITHUB_TOKEN --target ${DOCKER_BUILD_TARGET} --output type=${DOCKER_BUILD_TYPE},name=asia-northeast1-docker.pkg.dev/${GCP_PROJECT}/${SERVICE_NAME}/server:${DOCKER_BUILD_TAG}

.PHONY: docker/build
docker/build:
	@GITHUB_TOKEN=${GITHUB_TOKEN} docker builder --builder=${DOCKER_BUILDER} build --pull --rm ${DOCKER_BUILD_FLAGS} .
