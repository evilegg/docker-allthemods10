# CLAUDE.md — docker-allthemods10

## Project Purpose

Docker image set for a headless [All the Mods 10](https://www.curseforge.com/minecraft/modpacks/all-the-mods-10) Minecraft server.
Designed for Unraid (uid 99 / gid 100), but usable anywhere with a `/data` volume.

## Two-Image Architecture

Two images are built per version:

| Image                              | Purpose                                                                      |
| ---------------------------------- | ---------------------------------------------------------------------------- |
| `evilegg/all-the-mods-data:10.X.Y` | Init container — seeds a named volume with the pre-installed NeoForge server |
| `evilegg/all-the-mods:10.X.Y`      | Runtime — lightweight Java + `launch.sh`, mounts the seeded volume           |

Deploy both with `docker-compose.yml`.
The init container runs once and exits; the server container starts after it completes successfully.

## Key Files

| File                 | Role                                                                              |
| -------------------- | --------------------------------------------------------------------------------- |
| `Dockerfile`         | Multi-stage build: `installer` → `data`, `installer` → `runtime`                  |
| `scripts/seed.sh`    | Data image entrypoint — seeds `/data`, then overlays `overrides/`                 |
| `scripts/launch.sh`  | Runtime entrypoint — applies env overrides, manages whitelist/ops, execs `run.sh` |
| `scripts/world.sh`   | Host-side CLI for world management (push / reset / pull)                          |
| `scripts/test.sh`    | Integration tests for the overrides/ feature                                      |
| `Makefile`           | Build automation; `make 10-X.Y` builds both images for local arch                 |
| `download-urls.mk`   | CDN fallback URLs keyed by FILE_ID (fill in before building without local cache)  |
| `docker-compose.yml` | Compose file wiring init + server containers                                      |
| `curseforge.com/`    | **Pre-cached** modpack archives (gitignored; see below)                           |
| `overrides/`         | **Build-time file injection** (gitignored; see below)                             |

## Dockerfile Stages

- **`installer`** — runs NeoForge installer inside `eclipse-temurin:21-jdk`; produces `/opt/server/`
- **`data`** (`--target data`) — Alpine base, ships `/opt/server/` and `/opt/overrides/`; `seed.sh` seeds `/data` then overlays overrides
- **`runtime`** (`--target runtime`) — `eclipse-temurin:21-jdk` + curl/jq + `launch.sh`; no server files

## Pre-Cached Files

Locally cached server zips live under:

```
curseforge.com/minecraft/modpacks/all-the-mods-10/files/<file-id>/
```

| Version | File ID | Server Zip               |
| ------- | ------- | ------------------------ |
| 5.5     | 7558573 | `Server-Files-5.5.zip`   |
| 6.0.1   | 7676054 | `Server-Files-6.0.1.zip` |
| 6.1     | 7722629 | `Server-Files-6.1.zip`   |

## How launch.sh Works (Runtime)

1. Writes `eula.txt` (requires `EULA=true` env var; exits with code 99 otherwise).
2. Exits with an error if `/data/libraries` is absent (init container must run first).
3. Applies env-var overrides to `user_jvm_args.txt` and `server.properties`.
4. Populates `whitelist.json` and `ops.json` via `playerdb.co` UUID lookups.
5. `chmod 755 run.sh` then `exec "$@"` (default CMD is `./run.sh`, making it PID 1).

## Environment Variables

| Variable           | Default / Example         |
| ------------------ | ------------------------- |
| `EULA`             | must be `true`            |
| `JVM_OPTS`         | `-Xms2048m -Xmx4096m`     |
| `MOTD`             | server description string |
| `ALLOW_FLIGHT`     | `true`/`false`            |
| `MAX_PLAYERS`      | `5`                       |
| `ONLINE_MODE`      | `true`/`false`            |
| `ENABLE_WHITELIST` | `true`/`false`            |
| `WHITELIST_USERS`  | `User1, User2`            |
| `OP_USERS`         | `User1, User2`            |

## Makefile Targets

```
make 10-6.1       # build data + runtime images for version 6.1, local arch
make dist-10-6.1  # build + push data + runtime for all arches (requires buildx)
make all          # build default version (currently 6.1) for local arch
make dist         # build + push default version for all arches
make help         # list all targets
```

## World Management (scripts/world.sh)

`scripts/world.sh` is a host-side CLI that operates on the Docker data volume via throwaway Alpine containers.
It stops the server automatically before destructive operations.

```
./scripts/world.sh push <dir>          # Copy a local world dir into /data/world (stops server)
./scripts/world.sh reset               # Delete all world/DIM dirs from the volume (stops server)
./scripts/world.sh pull [file.tar.gz]  # Archive world dirs to a local .tar.gz (stops server)
```

Options: `--volume <name>`, `--project <name>`, `--restart`

The volume name is auto-detected from `docker compose config`.
`pull` will prefer the latest `.zip` from `/data/backups/` if a backup mod is present
(see: TODO evaluate FTB Backups 2 for ATM10).

### Build-time file injection (overrides/)

Place files under `overrides/` to inject them into `/data` at seed time.
The directory structure is preserved:

```
overrides/world/           → /data/world/
overrides/mods/extra.jar   → /data/mods/extra.jar
overrides/server.properties → /data/server.properties
```

The Makefile stages `overrides/` into `.build/overrides/` before every build.
`seed.sh` overlays `/opt/overrides/` onto `/data/` after seeding the server files.

By default, existing files in `/data/` are overwritten and a warning is logged.
Set `OVERRIDES_NOCLOBBER=true` on the init container to skip existing files instead.

`overrides/` is gitignored — it may contain large world saves or binary mods.

## scripts/ Convention

All helper scripts live in `scripts/`.
Every script must follow this interface:

- **Header comment** — first lines after `#!/...` document purpose, usage, and options in the same format as the existing scripts.
- **`usage()` function** — prints `Usage:` block to stderr via `cat >&2 <<'EOF' ... EOF`, then exits 0 (for `--help`) or 1 (for invalid invocation).
- **`-h | --help | --usage`** — handled in argument parsing before any side effects.

Container entrypoints (`seed.sh`, `launch.sh`) use `case "${1:-}" in` before `set -e`/`set -x` so the flag is checked without interference from strict-mode exits.
Host-side scripts (`world.sh`, `test.sh`) use a `while [[ $# -gt 0 ]]; do case "$1" in` loop.

## Notes

- Port `25565/tcp` exposed by the runtime image.
- `/data` must be a persistent volume — world data, configs, and mods live there.
- The init container is idempotent: it checks for `libraries/` before copying.
  Re-running it on an already-seeded volume is a no-op.
- `.tmp_msg` is in `.gitignore` (global convention).
