# pack.conf defines PACK_SLUG, IMAGE, IMAGE_DATA, JAVA_VERSION.
# Edit that file when forking this template for a new modpack.
include pack.conf

# versions.mk is auto-generated from versions.conf — edit that file, not this one.
# GNU Make will build versions.mk on demand then re-exec if it is missing.
include versions.mk

# Build parameters — derived from DEFAULT_VERSION when not overridden on CLI.
SERVER_VERSION   ?= $(VERSION_SRV_$(DEFAULT_VERSION))
FILE_ID          ?= $(VERSION_FILE_$(DEFAULT_VERSION))
NEOFORGE_VERSION ?= $(VERSION_NF_$(DEFAULT_VERSION))
TAG              ?= $(SERVER_VERSION)

CDN_URL := $(DOWNLOAD_URL_$(FILE_ID))

# Local pre-cached zip (not required; skipped in CI)
LOCAL_ZIP := curseforge.com/minecraft/modpacks/$(PACK_SLUG)/files/$(FILE_ID)/Server-Files-$(SERVER_VERSION).zip

BUILD_ARGS = \
	--build-arg SERVER_VERSION=$(SERVER_VERSION) \
	--build-arg NEOFORGE_VERSION=$(NEOFORGE_VERSION) \
	--build-arg JAVA_VERSION=$(JAVA_VERSION) \
	--build-arg DOWNLOAD_URL=$(CDN_URL)

.PHONY: all dist help compose-env _stage-zip _stage-overrides

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

# Stage overrides/ into .build/overrides/ before every build.
# Place files under overrides/ to inject them into /data at seed time.
# The directory is gitignored; see CLAUDE.md for usage.
_stage-overrides:
	@mkdir -p .build/overrides
	@if [ -d overrides ]; then \
		echo "Staging overrides/"; \
		cp -r overrides/. .build/overrides/; \
	else \
		echo "No overrides/ directory; data image will include no overrides"; \
	fi

all: _stage-zip _stage-overrides ## Build data + runtime images for local architecture
	docker build --target data    $(BUILD_ARGS) -t $(IMAGE_DATA):$(TAG) .
	docker build --target runtime $(BUILD_ARGS) -t $(IMAGE):$(TAG) .

dist: _stage-zip _stage-overrides ## Build data + runtime images for all arches and push
	docker buildx build --target data    $(BUILD_ARGS) \
		--platform linux/amd64,linux/arm64 \
		-t $(IMAGE_DATA):$(TAG) \
		--push .
	docker buildx build --target runtime $(BUILD_ARGS) \
		--platform linux/amd64,linux/arm64 \
		-t $(IMAGE):$(TAG) \
		--push .

compose-env: ## Write .env for docker-compose.yml from current pack + default version
	@printf 'IMAGE=%s\nIMAGE_DATA=%s\nTAG=%s\n' \
		'$(IMAGE)' '$(IMAGE_DATA)' '$(TAG)' > .env
	@echo "Wrote .env (IMAGE=$(IMAGE), IMAGE_DATA=$(IMAGE_DATA), TAG=$(TAG))"

help: ## Show this help
	@printf "Usage:\n  make <target>\n"
	@printf "\nGeneral targets:\n"
	@awk 'BEGIN {FS=":.*##"}; /^[a-zA-Z][a-zA-Z0-9_-]*:.*##/ {printf "  %-22s %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@printf "\nVersion targets (defined in versions.conf):\n"
	@$(foreach v,$(VERSIONS),\
		printf "  %-22s Build %s data+runtime for local arch\n" "$(v)" "$(VERSION_SRV_$(v))"; \
		printf "  %-22s Build %s data+runtime for all arches and push\n" "dist-$(v)" "$(VERSION_SRV_$(v))";)

# ── per-version targets (auto-generated from VERSIONS in versions.conf) ────────

define VERSION_template
.PHONY: $(1) dist-$(1)
$(1):
	$(MAKE) all SERVER_VERSION=$(VERSION_SRV_$(1)) FILE_ID=$(VERSION_FILE_$(1)) NEOFORGE_VERSION=$(VERSION_NF_$(1))
dist-$(1):
	$(MAKE) dist SERVER_VERSION=$(VERSION_SRV_$(1)) FILE_ID=$(VERSION_FILE_$(1)) NEOFORGE_VERSION=$(VERSION_NF_$(1))
endef

$(foreach v,$(VERSIONS),$(eval $(call VERSION_template,$(v))))

# ── generate versions.mk from versions.conf ────────────────────────────────────

versions.mk: versions.conf
	awk '!/^[[:space:]]*#/ && NF==5 { \
	  printf "VERSIONS += %s\n",           $$1; \
	  printf "VERSION_SRV_%s  := %s\n",   $$1, $$2; \
	  printf "VERSION_FILE_%s := %s\n",   $$1, $$3; \
	  printf "VERSION_NF_%s   := %s\n",   $$1, $$4; \
	  printf "DOWNLOAD_URL_%s := %s\n\n", $$3, $$5; \
	  last=$$1 \
	} END { printf "DEFAULT_VERSION := %s\n", last }' $< > $@
