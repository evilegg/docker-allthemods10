# syntax=docker/dockerfile:1

ARG SERVER_VERSION=6.1
ARG FILE_ID=7722629
ARG NEOFORGE_VERSION=21.1.219

# ── installer stage ───────────────────────────────────────────────────────────
FROM eclipse-temurin:21-jdk AS installer

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
