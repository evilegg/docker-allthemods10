IMAGE            ?= evilegg/all-the-mods
SERVER_VERSION   ?= 6.1
FILE_ID          ?= 7722629
NEOFORGE_VERSION ?= 21.1.219
TAG              ?= 10.$(SERVER_VERSION)

# CDN URL derived from FILE_ID (CurseForge split: NNNN/NNN/filename)
FILE_ID_HIGH := $(shell expr $(FILE_ID) / 1000)
FILE_ID_LOW  := $(shell expr $(FILE_ID) % 1000)
CDN_URL      := https://mediafilez.forgecdn.net/files/$(FILE_ID_HIGH)/$(FILE_ID_LOW)/Server-Files-$(SERVER_VERSION).zip

# Local pre-cached zip (not required; skipped in CI)
LOCAL_ZIP := curseforge.com/minecraft/modpacks/all-the-mods-10/files/$(FILE_ID)/Server-Files-$(SERVER_VERSION).zip

# Pass local zip via build context if present, otherwise pass CDN URL
ZIP_SOURCE := $(if $(wildcard $(LOCAL_ZIP)),\
	--build-context staged-zip=$(dir $(LOCAL_ZIP)),\
	--build-arg DOWNLOAD_URL=$(CDN_URL))

BUILD_ARGS = \
	--build-arg SERVER_VERSION=$(SERVER_VERSION) \
	--build-arg NEOFORGE_VERSION=$(NEOFORGE_VERSION)

.PHONY: all dist

all:
	docker build $(BUILD_ARGS) $(ZIP_SOURCE) -t $(IMAGE):$(TAG) .

dist:
	docker buildx build $(BUILD_ARGS) $(ZIP_SOURCE) \
		--platform linux/amd64,linux/arm64 \
		-t $(IMAGE):$(TAG) \
		--push .
