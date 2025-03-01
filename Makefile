GO ?= $(shell command -v go 2> /dev/null)
NPM ?= $(shell command -v npm 2> /dev/null)
CURL ?= $(shell command -v curl 2> /dev/null)
MM_DEBUG ?=
MANIFEST_FILE ?= plugin.json
GOPATH ?= $(shell go env GOPATH)
GO_TEST_FLAGS ?= -race
GO_BUILD_FLAGS ?=
MM_UTILITIES_DIR ?= ../mattermost-utilities
DLV_DEBUG_PORT := 2346
DEFAULT_GOOS := $(shell go env GOOS)
DEFAULT_GOARCH := $(shell go env GOARCH)
BUILD_HASH = $(shell git rev-parse HEAD)
LDFLAGS += -X "main.buildHash=$(BUILD_HASH)"
LDFLAGS+= -X "main.isDebug=$(MM_DEBUG)"
LDFLAGS += -X "main.rudderWriteKey=$(RUDDER_WRITE_KEY)"
LDFLAGS += -X "main.rudderDataplaneURL=$(RUDDER_DATAPLANE_URL)"

export GO111MODULE=on

# We need to export GOBIN to allow it to be set
# for processes spawned from the Makefile
export GOBIN ?= $(PWD)/bin

# You can include assets this directory into the bundle. This can be e.g. used to include profile pictures.
ASSETS_DIR ?= assets

## Define the default target (make all)
.PHONY: default
default: all

# Verify environment, and define PLUGIN_ID, PLUGIN_VERSION, HAS_SERVER and HAS_WEBAPP as needed.
include build/setup.mk

BUNDLE_NAME ?= $(PLUGIN_ID)-$(PLUGIN_VERSION).tar.gz

# Include custom makefile, if present
ifneq ($(wildcard build/custom.mk),)
	include build/custom.mk
endif

## Checks the code style, tests, builds and bundles the plugin.
.PHONY: all
all: check-style test dist

## Propagates plugin manifest information into the server/ and webapp/ folders.
.PHONY: apply
apply:
	./build/bin/manifest apply

## Check go mod files consistency
.PHONY: gomod-check
gomod-check:
	@echo Checking go mod files consistency
	go mod tidy -v && git --no-pager diff --exit-code go.mod go.sum || (echo "Please run \"go mod tidy\" and commit the changes in go.mod and go.sum." && exit 1)

## Runs eslint and golangci-lint
.PHONY: check-style
check-style: apply golangci-lint webapp/node_modules gomod-check
	@echo Checking for style guide compliance

ifneq ($(HAS_WEBAPP),)
	cd webapp && npm run lint
	cd webapp && npm run check-types
endif

golangci-lint: ## Run golangci-lint on codebase
# https://stackoverflow.com/a/677212/1027058 (check if a command exists or not)
	@if ! [ -x "$$(command -v golangci-lint)" ]; then \
		echo "golangci-lint is not installed. Please see https://github.com/golangci/golangci-lint#install for installation instructions."; \
		exit 1; \
	fi; \

ifneq ($(HAS_SERVER),)
	@if ! [ -x "$$(command -v golangci-lint)" ]; then \
		echo "golangci-lint is not installed. Please see https://github.com/golangci/golangci-lint#install for installation instructions."; \
		exit 1; \
	fi; \

	@echo Running golangci-lint
	golangci-lint run ./...
endif

## Builds the server, if it exists, for all supported architectures, unless MM_SERVICESETTINGS_ENABLEDEVELOPER is set
.PHONY: server
server:
ifneq ($(HAS_SERVER),)
	mkdir -p server/dist;
ifeq ($(MM_DEBUG),)
ifneq ($(MM_SERVICESETTINGS_ENABLEDEVELOPER),)
	cd server && env CGO_ENABLED=0 $(GO) build $(GO_BUILD_FLAGS) -ldflags '$(LDFLAGS)' -trimpath -o dist/plugin-$(DEFAULT_GOOS)-$(DEFAULT_GOARCH);
else
	cd server && env CGO_ENABLED=0 GOOS=linux GOARCH=amd64 $(GO) build $(GO_BUILD_FLAGS) -ldflags '$(LDFLAGS)' -trimpath -o dist/plugin-linux-amd64;
	cd server && env CGO_ENABLED=0 GOOS=linux GOARCH=arm64 $(GO) build $(GO_BUILD_FLAGS) -ldflags '$(LDFLAGS)' -trimpath -o dist/plugin-linux-arm64;
	cd server && env CGO_ENABLED=0 GOOS=darwin GOARCH=amd64 $(GO) build $(GO_BUILD_FLAGS) -ldflags '$(LDFLAGS)' -trimpath -o dist/plugin-darwin-amd64;
	cd server && env CGO_ENABLED=0 GOOS=darwin GOARCH=arm64 $(GO) build $(GO_BUILD_FLAGS) -ldflags '$(LDFLAGS)' -trimpath -o dist/plugin-darwin-arm64;
	cd server && env CGO_ENABLED=0 GOOS=freebsd GOARCH=amd64 $(GO) build $(GO_BUILD_FLAGS) -ldflags '$(LDFLAGS)' -trimpath -o dist/plugin-freebsd-amd64;
	cd server && env CGO_ENABLED=0 GOOS=openbsd GOARCH=amd64 $(GO) build $(GO_BUILD_FLAGS) -ldflags '$(LDFLAGS)' -trimpath -o dist/plugin-openbsd-amd64;
endif
else
	$(info DEBUG mode is on; to disable, unset MM_DEBUG)
ifneq ($(MM_SERVICESETTINGS_ENABLEDEVELOPER),)
	cd server && env CGO_ENABLED=0 $(GO) build $(GO_BUILD_FLAGS) -ldflags '$(LDFLAGS)' -gcflags "all=-N -l" -trimpath -o dist/plugin-$(DEFAULT_GOOS)-$(DEFAULT_GOARCH);
else
	cd server && env CGO_ENABLED=0 GOOS=linux GOARCH=amd64 $(GO) build $(GO_BUILD_FLAGS) -ldflags '$(LDFLAGS)' -gcflags "all=-N -l" -trimpath -o dist/plugin-linux-amd64;
	cd server && env CGO_ENABLED=0 GOOS=linux GOARCH=arm64 $(GO) build $(GO_BUILD_FLAGS) -ldflags '$(LDFLAGS)' -gcflags "all=-N -l" -trimpath -o dist/plugin-linux-arm64;
	cd server && env CGO_ENABLED=0 GOOS=darwin GOARCH=amd64 $(GO) build $(GO_BUILD_FLAGS) -ldflags '$(LDFLAGS)' -gcflags "all=-N -l" -trimpath -o dist/plugin-darwin-amd64;
	cd server && env CGO_ENABLED=0 GOOS=darwin GOARCH=arm64 $(GO) build $(GO_BUILD_FLAGS) -ldflags '$(LDFLAGS)' -gcflags "all=-N -l" -trimpath -o dist/plugin-darwin-arm64;
	cd server && env CGO_ENABLED=0 GOOS=freebsd GOARCH=amd64 $(GO) build $(GO_BUILD_FLAGS) -ldflags '$(LDFLAGS)' -gcflags "all=-N -l" -trimpath -o dist/plugin-freebsd-amd64;
	cd server && env CGO_ENABLED=0 GOOS=openbsd GOARCH=amd64 $(GO) build $(GO_BUILD_FLAGS) -ldflags '$(LDFLAGS)' -gcflags "all=-N -l" -trimpath -o dist/plugin-openbsd-amd64;
endif
endif
endif

## Builds the server on ci -- only build for linux-amd64, freebsd-amd64 and openbsd-amd64 (for now)
.PHONY: server-ci
server-ci:
ifneq ($(HAS_SERVER),)
	mkdir -p server/dist;
ifeq ($(MM_DEBUG),)
	cd server && env CGO_ENABLED=0 GOOS=linux GOARCH=amd64 $(GO) build $(GO_BUILD_FLAGS) -ldflags '$(LDFLAGS)' -trimpath -o dist/plugin-linux-amd64;
	cd server && env CGO_ENABLED=0 GOOS=freebsd GOARCH=amd64 $(GO) build $(GO_BUILD_FLAGS) -ldflags '$(LDFLAGS)' -trimpath -o dist/plugin-freebsd-amd64;
	cd server && env CGO_ENABLED=0 GOOS=openbsd GOARCH=amd64 $(GO) build $(GO_BUILD_FLAGS) -ldflags '$(LDFLAGS)' -trimpath -o dist/plugin-openbsd-amd64;
else
	$(info DEBUG mode is on; to disable, unset MM_DEBUG)
	cd server && env CGO_ENABLED=0 GOOS=linux GOARCH=amd64 $(GO) build $(GO_BUILD_FLAGS) -ldflags '$(LDFLAGS)' -gcflags "all=-N -l" -trimpath -o dist/plugin-linux-amd64;
	cd server && env CGO_ENABLED=0 GOOS=freebsd GOARCH=amd64 $(GO) build $(GO_BUILD_FLAGS) -ldflags '$(LDFLAGS)' -gcflags "all=-N -l" -trimpath -o dist/plugin-freebsd-amd64;
	cd server && env CGO_ENABLED=0 GOOS=openbsd GOARCH=amd64 $(GO) build $(GO_BUILD_FLAGS) -ldflags '$(LDFLAGS)' -gcflags "all=-N -l" -trimpath -o dist/plugin-openbsd-amd64;
endif
endif

## Ensures NPM dependencies are installed without having to run this all the time.
webapp/node_modules: $(wildcard webapp/package.json)
ifneq ($(HAS_WEBAPP),)
	cd webapp && node skip_integrity_check.js
	cd webapp && $(NPM) install
	touch $@
endif

## Builds the webapp, if it exists.
.PHONY: webapp
webapp: webapp/node_modules
ifneq ($(HAS_WEBAPP),)
ifeq ($(MM_DEBUG),)
	cd webapp && $(NPM) run build;
else
	cd webapp && $(NPM) run debug;
endif
endif

## Builds the webapp on ci -- dependencies are handled by the npm-dependencies step in ci
.PHONY: webapp-ci
webapp-ci:
	cd webapp && $(NPM) run build

## Generates a tar bundle of the plugin for install.
.PHONY: bundle
bundle:
	rm -rf dist/
	mkdir -p dist/$(PLUGIN_ID)
	./build/bin/manifest dist
ifneq ($(wildcard $(ASSETS_DIR)/.),)
	cp -r $(ASSETS_DIR) dist/$(PLUGIN_ID)/
endif
ifneq ($(HAS_PUBLIC),)
	cp -r public dist/$(PLUGIN_ID)/
endif
ifneq ($(HAS_SERVER),)
	mkdir -p dist/$(PLUGIN_ID)/server
	cp -r server/dist dist/$(PLUGIN_ID)/server/
endif
ifneq ($(HAS_WEBAPP),)
	mkdir -p dist/$(PLUGIN_ID)/webapp
	cp -r webapp/dist dist/$(PLUGIN_ID)/webapp/
endif
	cd dist && tar -cvzf $(BUNDLE_NAME) $(PLUGIN_ID)

	@echo plugin built at: dist/$(BUNDLE_NAME)

## Builds and bundles the plugin.
.PHONY: dist
dist:	apply server webapp bundle

## Builds and bundles the plugin on ci.
.PHONY: dist-ci
dist-ci:	apply server-ci webapp-ci bundle

## Builds and installs the plugin to a server.
.PHONY: deploy
deploy: dist
	./build/bin/pluginctl deploy $(PLUGIN_ID) dist/$(BUNDLE_NAME)

## Builds and installs the plugin to a server, updating the webapp automatically when changed.
.PHONY: watch
watch: apply server bundle
ifeq ($(MM_DEBUG),)
	cd webapp && $(NPM) run build:watch
else
	cd webapp && $(NPM) run debug:watch
endif

## Installs a previous built plugin with updated webpack assets to a server.
.PHONY: deploy-from-watch
deploy-from-watch: bundle
	./build/bin/pluginctl deploy $(PLUGIN_ID) dist/$(BUNDLE_NAME)

## Setup dlv for attaching, identifying the plugin PID for other targets.
.PHONY: setup-attach
setup-attach:
	$(eval PLUGIN_PID := $(shell ps aux | grep "plugins/${PLUGIN_ID}" | grep -v "grep" | awk -F " " '{print $$2}'))
	$(eval NUM_PID := $(shell echo -n ${PLUGIN_PID} | wc -w))

	@if [ ${NUM_PID} -gt 2 ]; then \
		echo "** There is more than 1 plugin process running. Run 'make kill reset' to restart just one."; \
		exit 1; \
	fi

## Check if setup-attach succeeded.
.PHONY: check-attach
check-attach:
	@if [ -z ${PLUGIN_PID} ]; then \
		echo "Could not find plugin PID; the plugin is not running. Exiting."; \
		exit 1; \
	else \
		echo "Located Plugin running with PID: ${PLUGIN_PID}"; \
	fi

## Attach dlv to an existing plugin instance.
.PHONY: attach
attach: setup-attach check-attach
	dlv attach ${PLUGIN_PID}

## Attach dlv to an existing plugin instance, exposing a headless instance on $DLV_DEBUG_PORT.
.PHONY: attach-headless
attach-headless: setup-attach check-attach
	dlv attach ${PLUGIN_PID} --listen :$(DLV_DEBUG_PORT) --headless=true --api-version=2 --accept-multiclient

## Detach dlv from an existing plugin instance, if previously attached.
.PHONY: detach
detach: setup-attach
	@DELVE_PID=$(shell ps aux | grep "dlv attach ${PLUGIN_PID}" | grep -v "grep" | awk -F " " '{print $$2}') && \
	if [ "$$DELVE_PID" -gt 0 ] > /dev/null 2>&1 ; then \
		echo "Located existing delve process running with PID: $$DELVE_PID. Killing." ; \
		kill -9 $$DELVE_PID ; \
	fi

## Ensure gotestsum is installed and available as a tool for testing.
gotestsum:
	$(GO) install gotest.tools/gotestsum@v1.7.0

## Runs any lints and unit tests defined for the server and webapp, if they exist.
.PHONY: test
test: apply webapp/node_modules gotestsum
ifneq ($(HAS_SERVER),)
	$(GOBIN)/gotestsum -- -v $(GO_TEST_FLAGS) ./server/...
endif
ifneq ($(HAS_WEBAPP),)
	cd webapp && $(NPM) run test;
endif
ifneq ($(wildcard ./build/sync/plan/.),)
	cd ./build/sync && $(GOBIN)/gotestsum -- -v $(GO_TEST_FLAGS) ./...
endif

## Runs any lints and unit tests defined for the server and webapp, if they exist, optimized
## for a CI environment.
.PHONY: test-ci
test-ci: apply webapp/node_modules gotestsum
ifneq ($(HAS_SERVER),)
	$(GOBIN)/gotestsum --format standard-verbose --junitfile report.xml -- ./...
endif
ifneq ($(HAS_WEBAPP),)
	cd webapp && $(NPM) run test;
endif

## Creates a coverage report for the server code.
.PHONY: coverage
coverage: apply webapp/node_modules
ifneq ($(HAS_SERVER),)
	$(GO) test $(GO_TEST_FLAGS) -coverprofile=server/coverage.txt ./server/...
	$(GO) tool cover -html=server/coverage.txt
endif

## Runs e2e tests.
.PHONY: test-e2e
test-e2e: e2e/node_modules
	cd e2e && npm i && npx playwright test

## Runs e2e tests and updates snapshots.
.PHONY: test-e2e-update-snapshots
test-e2e-update-snapshots:
	cd e2e && npm i && npx playwright test --update-snapshots

## Extract strings for translation from the source code.
.PHONY: i18n-extract
i18n-extract:
ifneq ($(HAS_WEBAPP),)
ifeq ($(HAS_MM_UTILITIES),)
	@echo "You must clone github.com/mattermost/mattermost-utilities repo in .. to use this command"
else
	cd $(MM_UTILITIES_DIR) && npm install && npm run babel && node mmjstool/build/index.js i18n extract-webapp --webapp-dir $(PWD)/webapp
endif
endif

## Disable the plugin.
.PHONY: disable
disable: detach
	./build/bin/pluginctl disable $(PLUGIN_ID)

## Enable the plugin.
.PHONY: enable
enable:
	./build/bin/pluginctl enable $(PLUGIN_ID)

## Reset the plugin, effectively disabling and re-enabling it on the server.
.PHONY: reset
reset: detach
	./build/bin/pluginctl reset $(PLUGIN_ID)

## Kill all instances of the plugin, detaching any existing dlv instance.
.PHONY: kill
kill: detach
	$(eval PLUGIN_PID := $(shell ps aux | grep "plugins/${PLUGIN_ID}" | grep -v "grep" | awk -F " " '{print $$2}'))

	@for PID in ${PLUGIN_PID}; do \
		echo "Killing plugin pid $$PID"; \
		kill -9 $$PID; \
	done; \

## Clean removes all build artifacts.
.PHONY: clean
clean:
	rm -fr dist/
ifneq ($(HAS_SERVER),)
	rm -fr server/coverage.txt
	rm -fr server/dist
endif
ifneq ($(HAS_WEBAPP),)
	rm -fr webapp/junit.xml
	rm -fr webapp/dist
	rm -fr webapp/node_modules
endif
	rm -fr build/bin/
	rm -fr e2e/tests-results/

## Sync directory with a starter template
sync:
ifndef STARTERTEMPLATE_PATH
	@echo STARTERTEMPLATE_PATH is not set.
	@echo Set STARTERTEMPLATE_PATH to a local clone of https://github.com/mattermost/mattermost-plugin-starter-template and retry.
	@exit 1
endif
	cd ${STARTERTEMPLATE_PATH} && go run ./build/sync/main.go ./build/sync/plan.yml $(PWD)

# Help documentation à la https://marmelab.com/blog/2016/02/29/auto-documented-makefile.html
help:
	@cat Makefile build/*.mk | grep -v '\.PHONY' |  grep -v '\help:' | grep -B1 -E '^[a-zA-Z0-9_.-]+:.*' | sed -e "s/:.*//" | sed -e "s/^## //" |  grep -v '\-\-' | sed '1!G;h;$$!d' | awk 'NR%2{printf "\033[36m%-30s\033[0m",$$0;next;}1' | sort
