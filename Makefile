IMAGE            ?= evilegg/all-the-mods
SERVER_VERSION   ?= 6.1
FILE_ID          ?= 7722629
NEOFORGE_VERSION ?= 21.1.219
TAG              ?= 10.$(SERVER_VERSION)

-include download-urls.mk
CDN_URL := $(DOWNLOAD_URL_$(FILE_ID))

# Local pre-cached zip (not required; skipped in CI)
LOCAL_ZIP := curseforge.com/minecraft/modpacks/all-the-mods-10/files/$(FILE_ID)/Server-Files-$(SERVER_VERSION).zip

# Pass local zip via build context if present, otherwise pass CDN URL
ZIP_SOURCE := $(if $(wildcard $(LOCAL_ZIP)),\
	--build-context staged-zip=$(dir $(LOCAL_ZIP)),\
	--build-arg DOWNLOAD_URL=$(CDN_URL))

BUILD_ARGS = \
	--build-arg SERVER_VERSION=$(SERVER_VERSION) \
	--build-arg NEOFORGE_VERSION=$(NEOFORGE_VERSION)

.PHONY: all dist help

all: ## Build image for local architecture
	docker build $(BUILD_ARGS) $(ZIP_SOURCE) -t $(IMAGE):$(TAG) .

dist: ## Build for linux/amd64 + linux/arm64 and push to registry
	docker buildx build $(BUILD_ARGS) $(ZIP_SOURCE) \
		--platform linux/amd64,linux/arm64 \
		-t $(IMAGE):$(TAG) \
		--push .

help: ## Show this help
	@printf "Usage:\n  make <target>\n"
	@printf "\nGeneral targets:\n"
	@awk 'BEGIN {FS=":.*##"}; /^[a-zA-Z][a-zA-Z0-9_-]*:.*##/ {printf "  %-22s %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@printf "\nVersion targets:\n"
	@$(foreach n,$(VERSION_NAMES),\
		printf "  %-22s Build ATM10 %s for local arch\n" "$(n)" "$(subst 10-,,$(n))"; \
		printf "  %-22s Build ATM10 %s for all arches and push\n" "dist-$(n)" "$(subst 10-,,$(n))";)

# ── named version targets ─────────────────────────────────────────────────────

define VERSION_template
.PHONY: $(1) dist-$(1)
$(1):
	$(MAKE) all SERVER_VERSION=$(2) FILE_ID=$(3) NEOFORGE_VERSION=$(4)
dist-$(1):
	$(MAKE) dist SERVER_VERSION=$(2) FILE_ID=$(3) NEOFORGE_VERSION=$(4)
endef

# name        server_version  file_id   neoforge_version
VERSION_NAMES :=
$(eval $(call VERSION_template,10-5.5,5.5,7558573,21.1.219))
$(eval VERSION_NAMES += 10-5.5)
$(eval $(call VERSION_template,10-6.0.1,6.0.1,7676054,21.1.219))
$(eval VERSION_NAMES += 10-6.0.1)
$(eval $(call VERSION_template,10-6.1,6.1,7722629,21.1.219))
$(eval VERSION_NAMES += 10-6.1)
