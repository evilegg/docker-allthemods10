# syntax=docker/dockerfile:1

ARG JAVA_VERSION=21
ARG SERVER_VERSION=6.1
ARG NEOFORGE_VERSION=21.1.219

# ── installer stage ───────────────────────────────────────────────────────────
FROM eclipse-temurin:${JAVA_VERSION}-jdk AS installer

ARG SERVER_VERSION
ARG NEOFORGE_VERSION
ARG DOWNLOAD_URL=

RUN apt-get update && apt-get install -y curl unzip

# .build/server.zip is pre-staged by the Makefile.
# If it is non-empty the local file is used; otherwise download from CDN.
COPY .build/server.zip /tmp/server.zip
RUN if [ -s /tmp/server.zip ]; then \
        echo "Using pre-staged server zip"; \
    elif [ -n "$DOWNLOAD_URL" ]; then \
        curl -fLo /tmp/server.zip "$DOWNLOAD_URL"; \
    else \
        echo "ERROR: .build/server.zip is empty and no DOWNLOAD_URL provided." >&2 && exit 1; \
    fi

# Unzip and normalize: some CurseForge server zips land files at the archive
# root, others nest them inside a single subdirectory.  Flatten the latter.
RUN mkdir -p /opt/server /tmp/unpack \
 && unzip /tmp/server.zip -d /tmp/unpack \
 && files=$(find /tmp/unpack -maxdepth 1 -mindepth 1 -type f | wc -l) \
 && dirs=$(find /tmp/unpack -maxdepth 1 -mindepth 1 -type d | wc -l) \
 && if [ "$files" -eq 0 ] && [ "$dirs" -eq 1 ]; then \
        cp -r /tmp/unpack/*/. /opt/server/; \
    else \
        cp -r /tmp/unpack/. /opt/server/; \
    fi \
 && cd /opt/server \
 && java -jar neoforge-${NEOFORGE_VERSION}-installer.jar --installServer \
 && rm -f neoforge-${NEOFORGE_VERSION}-installer.jar \
          neoforge-${NEOFORGE_VERSION}-installer.jar.log

# ── data image ────────────────────────────────────────────────────────────────
# Lightweight init container: seeds a named volume with the installed server.
# Run with user 99:100 so copied files are owned by the minecraft user.
FROM alpine AS data

ARG SERVER_VERSION
LABEL version="${SERVER_VERSION}"

COPY --from=installer /opt/server /opt/server

# .build/overrides/ is staged by the Makefile from the local overrides/ directory.
# Its contents are overlaid onto /data at seed time by seed.sh.
COPY .build/overrides/ /opt/overrides/

COPY scripts/seed.sh /seed.sh
RUN chmod +x /seed.sh

CMD ["/seed.sh"]

# ── runtime image ─────────────────────────────────────────────────────────────
# Lightweight server container: just Java + launch.sh.
# Expects /data to be pre-seeded by the data init container.
FROM eclipse-temurin:${JAVA_VERSION}-jdk AS runtime

ARG SERVER_VERSION
LABEL version="${SERVER_VERSION}"

RUN apt-get update && apt-get install -y curl jq && \
    adduser --uid 99 --gid 100 --home /data --disabled-password minecraft

COPY scripts/launch.sh /launch.sh
RUN chmod +x /launch.sh

USER minecraft

VOLUME /data
WORKDIR /data

EXPOSE 25565/tcp

ENTRYPOINT ["/launch.sh"]
CMD ["./run.sh"]
