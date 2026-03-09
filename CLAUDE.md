# CLAUDE.md — docker-allthemods10

## Project Purpose

Docker image for a headless [All the Mods 10](https://www.curseforge.com/minecraft/modpacks/all-the-mods-10) Minecraft server.
Designed for Unraid (uid 99 / gid 100), but usable anywhere with a `/data` volume.
Current published version: **5.5** (label in Dockerfile).

## Key Files

| File              | Role                                                                                                 |
| ----------------- | ---------------------------------------------------------------------------------------------------- |
| `Dockerfile`      | Builds the image: installs Java 21 JDK + curl/unzip/jq, copies `launch.sh`, creates `minecraft` user |
| `launch.sh`       | Container entrypoint — downloads + installs server on first run, then launches it                    |
| `curseforge.com/` | **Pre-cached** modpack archives (see below)                                                          |
| `data/`           | Placeholder for the runtime `/data` volume mount                                                     |

## Pre-Cached Files

Locally cached server zips live under:

```
curseforge.com/minecraft/modpacks/all-the-mods-10/files/<file-id>/
```

| Version | File ID | Cached Files                                                                 |
| ------- | ------- | ---------------------------------------------------------------------------- |
| 5.5     | 7558573 | `Server-Files-5.5.zip`, `All the Mods 10-5.5.zip`                            |
| 6.0     | 7676054 | `Server-Files-6.0.1.zip`, `All the Mods 10-6.0.zip`                          |
| 6.1     | 7722629 | `Server-Files-6.1.zip`, `Server-Files-6.1.tar.gz`, `All the Mods 10-6.1.zip` |

## How launch.sh Works (Runtime)

1. Writes `eula.txt` (requires `EULA=true` env var).
2. **First run only** — if `Server-Files-$SERVER_VERSION.zip` is absent in `/data`:
   - Removes old modpack dirs (`config`, `kubejs`, `mods`, etc.)
   - Downloads `ServerFiles-$SERVER_VERSION.zip` from `mediafilez.forgecdn.net`
   - Unzips to `/data`, flattening any subdirectory
   - Downloads the NeoForge installer jar from `maven.neoforged.net`
   - Runs `java -jar neoforge-...-installer.jar --installServer`
3. Applies env-var overrides to `user_jvm_args.txt` / `server.properties`.
4. Populates `whitelist.json` and `ops.json` via `playerdb.co` UUID lookups.
5. Runs `./run.sh` (the NeoForge server launcher).

## Refactoring Goal

**Avoid re-downloading files at build time / first container start.**
The pre-cached zips in `curseforge.com/` should be `COPY`-ed into the image so
`launch.sh` can use them directly instead of fetching from the internet.

Key changes needed:

- `Dockerfile`: `COPY` the relevant `Server-Files-$VERSION.zip` into the image
  (e.g. to `/opt/server-cache/`) and also pre-stage the NeoForge installer jar.
- `launch.sh`: Before curling, check if the file already exists at the cache path
  and copy/link it instead of downloading.

## Environment Variables

| Variable           | Default / Example                              |
| ------------------ | ---------------------------------------------- |
| `EULA`             | must be `true`                                 |
| `JVM_OPTS`         | `-Xms2048m -Xmx4096m`                          |
| `MOTD`             | `All the Mods 10-5.5 Server Powered by Docker` |
| `ALLOW_FLIGHT`     | `true`/`false`                                 |
| `MAX_PLAYERS`      | `5`                                            |
| `ONLINE_MODE`      | `true`/`false`                                 |
| `ENABLE_WHITELIST` | `true`/`false`                                 |
| `WHITELIST_USERS`  | `User1, User2`                                 |
| `OP_USERS`         | `User1, User2`                                 |

## Version Variables (in launch.sh)

```bash
NEOFORGE_VERSION=21.1.219
SERVER_VERSION=5.5
```

Both must be bumped together when upgrading the modpack.

## Notes

- Port `25565/tcp` exposed.
- `/data` must be a persistent volume — all world data, configs, and mods live there.
- The install guard is `[[ -f "Server-Files-$SERVER_VERSION.zip" ]]` in `/data`.
  Deleting that file triggers a full reinstall on next start.
- `.tmp_msg` is in `.gitignore` (global convention).
