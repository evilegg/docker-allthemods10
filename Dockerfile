# syntax=docker/dockerfile:1

FROM eclipse-temurin:21-jdk

ARG SERVER_VERSION=6.1
ARG FILE_ID=7722629
ARG NEOFORGE_VERSION=21.1.219

LABEL version="${SERVER_VERSION}"

ENV SERVER_VERSION=${SERVER_VERSION}
ENV NEOFORGE_VERSION=${NEOFORGE_VERSION}

RUN apt-get update && apt-get install -y curl unzip jq && \
    adduser --uid 99 --gid 100 --home /data --disabled-password minecraft

COPY launch.sh /launch.sh
RUN chmod +x /launch.sh

COPY "curseforge.com/minecraft/modpacks/all-the-mods-10/files/${FILE_ID}/Server-Files-${SERVER_VERSION}.zip" \
     /opt/server-cache/Server-Files-${SERVER_VERSION}.zip

USER minecraft

VOLUME /data
WORKDIR /data

EXPOSE 25565/tcp

CMD ["/launch.sh"]
