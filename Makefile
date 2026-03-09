IMAGE            ?= evilegg/all-the-mods
SERVER_VERSION   ?= 6.1
FILE_ID          ?= 7722629
NEOFORGE_VERSION ?= 21.1.219
TAG              ?= 10.$(SERVER_VERSION)

BUILD_ARGS = \
	--build-arg SERVER_VERSION=$(SERVER_VERSION) \
	--build-arg FILE_ID=$(FILE_ID) \
	--build-arg NEOFORGE_VERSION=$(NEOFORGE_VERSION)

.PHONY: all dist

all:
	docker build $(BUILD_ARGS) -t $(IMAGE):$(TAG) .

dist:
	docker buildx build $(BUILD_ARGS) \
		--platform linux/amd64,linux/arm64 \
		-t $(IMAGE):$(TAG) \
		--push .
