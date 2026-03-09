IMAGE      ?= evilegg/all-the-mods
IMAGE_DATA ?= evilegg/all-the-mods-data

-include download-urls.mk

# Build parameters — derived from DEFAULT_VERSION when not overridden on CLI.
SERVER_VERSION   ?= $(VERSION_SRV_$(DEFAULT_VERSION))
FILE_ID          ?= $(VERSION_FILE_$(DEFAULT_VERSION))
NEOFORGE_VERSION ?= $(VERSION_NF_$(DEFAULT_VERSION))
TAG              ?= 10.$(SERVER_VERSION)

CDN_URL := $(DOWNLOAD_URL_$(FILE_ID))

# Local pre-cached zip (not required; skipped in CI)
LOCAL_ZIP := curseforge.com/minecraft/modpacks/all-the-mods-10/files/$(FILE_ID)/Server-Files-$(SERVER_VERSION).zip

BUILD_ARGS = \
	--build-arg SERVER_VERSION=$(SERVER_VERSION) \
	--build-arg NEOFORGE_VERSION=$(NEOFORGE_VERSION) \
	--build-arg DOWNLOAD_URL=$(CDN_URL)

.PHONY: all dist help _stage-zip

# Stage the server zip into .build/ before every build.
# Copies from local cache if present; otherwise creates an empty placeholder
# so the Dockerfile falls through to the CDN download at build time.
_stage-zip:
	@mkdir -p .build
	@if [ -f "$(LOCAL_ZIP)" ]; then \
		echo "Staging $(LOCAL_ZIP)"; \
		cp "$(LOCAL_ZIP)" .build/server.zip; \
	else \
		echo "No local zip found; will download from CDN during build"; \
		touch .build/server.zip; \
	fi

all: _stage-zip ## Build data + runtime images for local architecture
	docker build --target data    $(BUILD_ARGS) -t $(IMAGE_DATA):$(TAG) .
	docker build --target runtime $(BUILD_ARGS) -t $(IMAGE):$(TAG) .

dist: _stage-zip ## Build data + runtime images for all arches and push
	docker buildx build --target data    $(BUILD_ARGS) \
		--platform linux/amd64,linux/arm64 \
		-t $(IMAGE_DATA):$(TAG) \
		--push .
	docker buildx build --target runtime $(BUILD_ARGS) \
		--platform linux/amd64,linux/arm64 \
		-t $(IMAGE):$(TAG) \
		--push .

help: ## Show this help
	@printf "Usage:\n  make <target>\n"
	@printf "\nGeneral targets:\n"
	@awk 'BEGIN {FS=":.*##"}; /^[a-zA-Z][a-zA-Z0-9_-]*:.*##/ {printf "  %-22s %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@printf "\nVersion targets (defined in download-urls.mk):\n"
	@$(foreach v,$(VERSIONS),\
		printf "  %-22s Build ATM10 %s data+runtime for local arch\n" "$(v)" "$(VERSION_SRV_$(v))"; \
		printf "  %-22s Build ATM10 %s data+runtime for all arches and push\n" "dist-$(v)" "$(VERSION_SRV_$(v))";)

# ── per-version targets (auto-generated from VERSIONS in download-urls.mk) ────

define VERSION_template
.PHONY: $(1) dist-$(1)
$(1):
	$(MAKE) all SERVER_VERSION=$(VERSION_SRV_$(1)) FILE_ID=$(VERSION_FILE_$(1)) NEOFORGE_VERSION=$(VERSION_NF_$(1))
dist-$(1):
	$(MAKE) dist SERVER_VERSION=$(VERSION_SRV_$(1)) FILE_ID=$(VERSION_FILE_$(1)) NEOFORGE_VERSION=$(VERSION_NF_$(1))
endef

$(foreach v,$(VERSIONS),$(eval $(call VERSION_template,$(v))))
