# syntax=docker/dockerfile:1

ARG SERVER_VERSION=6.1
ARG FILE_ID=7722629
ARG NEOFORGE_VERSION=21.1.219

# ── installer stage (runs natively on build host; output is pure Java) ────────
FROM --platform=$BUILDPLATFORM eclipse-temurin:21-jdk AS installer

ARG SERVER_VERSION
ARG FILE_ID
ARG NEOFORGE_VERSION

RUN apt-get update && apt-get install -y unzip

COPY "curseforge.com/minecraft/modpacks/all-the-mods-10/files/${FILE_ID}/Server-Files-${SERVER_VERSION}.zip" \
     /tmp/Server-Files-${SERVER_VERSION}.zip

RUN mkdir -p /opt/server \
 && unzip /tmp/Server-Files-${SERVER_VERSION}.zip -d /opt/server \
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
