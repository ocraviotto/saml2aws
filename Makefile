NAME=saml2aws
ARCH=$(shell uname -m)
VERSION=2.27.2
ITERATION := 1

SOURCE_FILES?=$$(go list ./... | grep -v /vendor/)
TEST_PATTERN?=.
TEST_OPTIONS?=

BIN_DIR := $(CURDIR)/bin

LINUX_BUILD_OPS := -tags="hidraw" -osarch="linux/i386" -osarch="linux/amd64"
WINDOWS_BUILD_OPS := -osarch="windows/i386" -osarch="windows/amd64"
DARWIN_BUILD_OPS := -osarch="darwin/amd64"

# Partially based on https://stackoverflow.com/questions/714100/os-detecting-makefile/52062069#52062069
ifeq '$(findstring ;,$(PATH))' ';'
	UNAME := Windows
else
	UNAME := $(shell uname 2>/dev/null || echo Unknown)
endif

ci: prepare test

prepare: prepare.metalinter
	GOBIN=$(BIN_DIR) go install github.com/buildkite/github-release
	GOBIN=$(BIN_DIR) go install github.com/mitchellh/gox
	GOBIN=$(BIN_DIR) go install github.com/axw/gocov/gocov
	GOBIN=$(BIN_DIR) go install golang.org/x/tools/cmd/cover

# Gometalinter is deprecated and broken dependency so let's use with GO111MODULE=off
prepare.metalinter:
	GO111MODULE=off go get -u github.com/alecthomas/gometalinter
	GO111MODULE=off gometalinter --fast --install

mod:
	@go mod download
	@go mod tidy

define compile
	@$(BIN_DIR)/gox -ldflags "-X main.Version=$(VERSION)" \
	$(1) \
	-output "build/{{.Dir}}_$(VERSION)_{{.OS}}_{{.Arch}}/$(NAME)" \
	${SOURCE_FILES}
endef

linux: mod
	$(call compile,$(LINUX_BUILD_OPS))

windows: mod
	$(call compile,$(WINDOWS_BUILD_OPS))

darwin: mod
	@if [ "$(UNAME)" = "Darwin" ]; then \
		$(call compile,$(DARWIN_BUILD_OPS)); \
	else \
		echo "\nWARNING: Trying to compile Darwin on a non-Darwin OS\nOS Detected: $(UNAME)"; \
	fi

compile: clean linux windows darwin

# Run all the linters
lint:
	@gometalinter --vendor ./...

# gofmt and goimports all go files
fmt:
	find . -name '*.go' -not -wholename './vendor/*' | while read -r file; do gofmt -w -s "$$file"; goimports -w "$$file"; done

install: mod
	go install -ldflags "-X main.Version=$(VERSION)" ./cmd/saml2aws

dist:
	$(eval FILES := $(shell ls build))
	@rm -rf dist && mkdir dist
	@for f in $(FILES); do \
		(cd $(shell pwd)/build/$$f && tar -cvzf ../../dist/$$f.tar.gz *); \
		(cd $(shell pwd)/dist && shasum -a 512 $$f.tar.gz > $$f.sha512); \
		echo $$f; \
	done

release:
	@$(BIN_DIR)/github-release "v$(VERSION)" dist/* --commit "$(git rev-parse HEAD)" --github-repository versent/$(NAME)

test:
	@$(BIN_DIR)/gocov test $(SOURCE_FILES) | $(BIN_DIR)/gocov report

clean:
	@rm -fr ./build

packages:
	rm -rf package && mkdir package
	rm -rf stage && mkdir -p stage/usr/bin
	cp build/saml2aws_*_linux_amd64/saml2aws stage/usr/bin
	fpm --name $(NAME) -a x86_64 -t rpm -s dir --version $(VERSION) --iteration $(ITERATION) -C stage -p package/$(NAME)-$(VERSION)_$(ITERATION).rpm usr
	fpm --name $(NAME) -a x86_64 -t deb -s dir --version $(VERSION) --iteration $(ITERATION) -C stage -p package/$(NAME)-$(VERSION)_$(ITERATION).deb usr
	shasum -a 512 package/$(NAME)-$(VERSION)_$(ITERATION).rpm > package/$(NAME)-$(VERSION)_$(ITERATION).rpm.sha512
	shasum -a 512 package/$(NAME)-$(VERSION)_$(ITERATION).deb > package/$(NAME)-$(VERSION)_$(ITERATION).deb.sha512

generate-mocks:
	mockery -dir pkg/prompter --all
	mockery -dir pkg/provider/okta -name U2FDevice

.PHONY: default prepare.metalinter prepare mod compile lint fmt dist release test clean generate-mocks
