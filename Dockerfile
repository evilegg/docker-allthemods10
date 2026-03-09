# syntax=docker/dockerfile:1

ARG SERVER_VERSION=6.1
ARG FILE_ID=7722629
ARG NEOFORGE_VERSION=21.1.219

# ── optional local zip cache ──────────────────────────────────────────────────
# Empty by default. Override at build time with:
#   --build-context staged-zip=curseforge.com/.../files/<FILE_ID>/
# The installer stage will use the local file instead of downloading.
FROM scratch AS staged-zip

# ── installer stage ───────────────────────────────────────────────────────────
FROM eclipse-temurin:21-jdk AS installer

ARG SERVER_VERSION
ARG NEOFORGE_VERSION
ARG DOWNLOAD_URL=

RUN apt-get update && apt-get install -y curl unzip

# Use local zip if present in staged-zip context; otherwise download from CDN.
RUN --mount=type=bind,from=staged-zip,target=/staged \
    ZIP="/staged/Server-Files-${SERVER_VERSION}.zip"; \
    if [ -f "$ZIP" ]; then \
        cp "$ZIP" /tmp/server.zip; \
    elif [ -n "$DOWNLOAD_URL" ]; then \
        curl -fLo /tmp/server.zip "$DOWNLOAD_URL"; \
    else \
        echo "ERROR: no local zip and no DOWNLOAD_URL provided." >&2 && exit 1; \
    fi

RUN mkdir -p /opt/server \
 && unzip /tmp/server.zip -d /opt/server \
 && cd /opt/server \
 && java -jar neoforge-${NEOFORGE_VERSION}-installer.jar --installServer \
 && rm -f /opt/server/neoforge-${NEOFORGE_VERSION}-installer.jar \
          /opt/server/neoforge-${NEOFORGE_VERSION}-installer.jar.log

# ── runtime image ─────────────────────────────────────────────────────────────
FROM eclipse-temurin:21-jdk

ARG SERVER_VERSION
ARG NEOFORGE_VERSION

LABEL version="${SERVER_VERSION}"

ENV SERVER_VERSION=${SERVER_VERSION}
ENV NEOFORGE_VERSION=${NEOFORGE_VERSION}

RUN apt-get update && apt-get install -y curl jq && \
    adduser --uid 99 --gid 100 --home /data --disabled-password minecraft

COPY launch.sh /launch.sh
RUN chmod +x /launch.sh

COPY --from=installer --chown=99:100 /opt/server /opt/server

USER minecraft

VOLUME /data
WORKDIR /data

EXPOSE 25565/tcp

ENTRYPOINT ["/launch.sh"]
CMD ["./run.sh"]
