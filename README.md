# All the Mods 10 — Docker Server

Docker image set for a headless [All the Mods 10](https://www.curseforge.com/minecraft/modpacks/all-the-mods-10) Minecraft server.
Designed for [Unraid](https://unraid.net) (uid 99 / gid 100), but usable anywhere with a persistent `/data` volume.

## How it works

Two images are built per version:

| Image                              | Role                                                                         |
| ---------------------------------- | ---------------------------------------------------------------------------- |
| `evilegg/all-the-mods-data:10.X.Y` | Init container — seeds a named volume with the pre-installed NeoForge server |
| `evilegg/all-the-mods:10.X.Y`      | Runtime — lightweight Java + entrypoint script, mounts the seeded volume     |

On first start, `docker compose up` runs the init container once to copy the
pre-built server files into the persistent volume, then starts the server container.
Subsequent starts skip the copy and go straight to launching the server.

## Quick start

```bash
# 1. Build images for the current default version
make

# 2. Start the server (seeds the volume on first run)
EULA=true docker compose up
```

The server will be reachable on port `25565`.

## Running with Docker Compose

Copy `docker-compose.yml` and set at minimum `EULA: "true"`:

```yaml
services:
  init:
    image: evilegg/all-the-mods-data:10.6.1
    user: "99:100"
    volumes:
      - data:/data
    command:
      ["sh", "-c", "[ -d /data/libraries ] || cp -r /opt/server/. /data/"]

  server:
    image: evilegg/all-the-mods:10.6.1
    depends_on:
      init:
        condition: service_completed_successfully
    volumes:
      - data:/data
    ports:
      - "25565:25565"
    environment:
      EULA: "true"
    restart: unless-stopped

volumes:
  data:
```

## Environment variables

| Variable           | Default               | Description                         |
| ------------------ | --------------------- | ----------------------------------- |
| `EULA`             | _(required)_          | Must be `true` to start the server  |
| `JVM_OPTS`         | `-Xms2048m -Xmx4096m` | Java heap flags                     |
| `MOTD`             | _(server default)_    | Message of the day                  |
| `MAX_PLAYERS`      | `5`                   | Maximum concurrent players          |
| `ONLINE_MODE`      | `true`                | Verify players against Mojang       |
| `ALLOW_FLIGHT`     | `true`                | Allow flight in survival mode       |
| `ENABLE_WHITELIST` | `false`               | Restrict logins to the whitelist    |
| `WHITELIST_USERS`  | _(empty)_             | Comma-separated Minecraft usernames |
| `OP_USERS`         | _(empty)_             | Comma-separated operator usernames  |

## Build targets

```
make             # build data + runtime images for the default version (local arch)
make dist        # build + push for linux/amd64 and linux/arm64
make 10-6.1      # build a specific version for local arch
make dist-10-6.1 # build + push a specific version for all arches
make help        # list all available targets
```

## Adding a new modpack version

All version metadata lives in `versions.conf` — the `Makefile` never needs to change.

**1. Find the new release on CurseForge.**
Go to the [ATM10 files page](https://www.curseforge.com/minecraft/modpacks/all-the-mods-10/files)
and open the new release.
Note the file ID from the URL and the direct download link for `Server-Files-X.Y.zip`.

**2. Append a line to `versions.conf`.**

```
# make-target  server-version  curseforge-file-id  neoforge-version  download-url
10-6.2  6.2  7800000  21.1.219  https://curseforge.com/.../Server-Files-6.2.zip
```

The last non-comment line is automatically the new default for `make` / `make dist`.

**3. Build and push.**

```bash
make 10-6.2       # local test build
make dist-10-6.2  # push to registry for all architectures
```

That's it — no other files need editing.

## Resetting the server

To wipe world data and re-seed from the image, remove the named volume:

```bash
docker compose down -v
docker compose up
```

To keep world data but force a fresh server install, delete `libraries/` inside
the volume — the init container will re-copy everything on next start.

## Volumes and ports

| Mount   | Purpose                                                |
| ------- | ------------------------------------------------------ |
| `/data` | All persistent state: world saves, configs, mods, logs |

| Port    | Protocol | Purpose                |
| ------- | -------- | ---------------------- |
| `25565` | TCP      | Minecraft game traffic |

## Notes

- The server runs as uid 99 / gid 100 (`minecraft` user) inside the container.
  On non-Unraid systems, ensure the `/data` mount is writable by that uid.
- `EULA=true` is required.
  By accepting it you agree to [Mojang's EULA](https://www.minecraft.net/en-us/eula).
