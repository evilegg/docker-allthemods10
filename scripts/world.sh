#!/usr/bin/env bash
# world.sh — manage /data/world inside the Docker data volume
#
# Usage:
#   ./scripts/world.sh push <dir>              Copy a local world directory into the volume
#   ./scripts/world.sh reset                   Delete all world/DIM directories from the volume
#   ./scripts/world.sh pull [file.tar.gz]      Archive the world directories from the volume
#   ./scripts/world.sh restore <file.tar.gz>   Restore a pull archive back into the volume
#
# Options:
#   --volume <name>         Override the Docker volume name (default: auto-detected)
#   --restart               Restart the server container after push, reset, or restore
#   --project <name>        Override the Compose project name for volume detection
#   -h, --help, --usage     Show this help and exit

set -euo pipefail

# ── helpers ────────────────────────────────────────────────────────────────────

usage() {
    cat >&2 <<'EOF'
Usage:
  ./scripts/world.sh push <dir>              Copy a local world dir into the data volume
  ./scripts/world.sh reset                   Delete all world/DIM dirs from the data volume
  ./scripts/world.sh pull [file.tar.gz]      Archive the world dirs from the data volume to a local file
  ./scripts/world.sh restore <file.tar.gz>   Restore a pull archive into the data volume

Options:
  --volume <name>         Override the detected Docker volume name
  --project <name>        Override the Compose project name used for volume detection
  --restart               Restart the server container after push, reset, or restore
  -h, --help, --usage     Show this help and exit
EOF
    exit 0
}

die() { echo "ERROR: $*" >&2; exit 1; }

# Detect the Docker volume name from docker compose config.
# Falls back to <project>_data if compose config is unavailable.
# Warns when the compose-detected name differs from the naive directory-based name
# (e.g. Compose strips dots from project names: v6.2.1 → v621).
detect_volume() {
    local project="${COMPOSE_PROJECT:-}"

    if docker compose config --format json >/dev/null 2>&1; then
        local vol
        vol=$(docker compose config --format json 2>/dev/null \
            | python3 -c "import sys,json; cfg=json.load(sys.stdin); print(cfg.get('volumes',{}).get('data',{}).get('name',''))" 2>/dev/null || true)
        if [[ -n "$vol" ]]; then
            # Compare against what a naive basename-based name would be.
            local naive_project naive_vol
            naive_project="${project:-$(basename "$(pwd)")}"
            naive_vol="${naive_project}_data"
            if [[ "$vol" != "$naive_vol" ]]; then
                echo "Warning: Compose volume name '${vol}' differs from directory-based name '${naive_vol}'. Use --volume if you need to override." >&2
            fi
            echo "$vol"
            return
        fi
    fi

    # Fallback: <project>_data
    if [[ -z "$project" ]]; then
        project=$(basename "$(pwd)")
    fi
    echo "${project}_data"
}

# Stop the server container if it is running; return 0 if it was running.
stop_server() {
    local running
    running=$(docker compose ps --status running --quiet server 2>/dev/null || true)
    if [[ -n "$running" ]]; then
        echo "Stopping server container..."
        docker compose stop server
        return 0
    fi
    return 1
}

# Restart the server container.
start_server() {
    echo "Starting server container..."
    docker compose start server
}

# Run a command in a throwaway Alpine container with the data volume mounted.
with_volume() {
    local volume="$1"; shift
    docker run --rm --user 99:100 -v "${volume}:/data" alpine "$@"
}

# ── argument parsing ────────────────────────────────────────────────────────────

VOLUME=""
RESTART=false
COMPOSE_PROJECT=""
SUBCOMMAND=""
SUBARGS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --volume)   VOLUME="$2";           shift 2 ;;
        --project)  COMPOSE_PROJECT="$2";  shift 2 ;;
        --restart)  RESTART=true;          shift   ;;
        push|reset|pull|restore)
            SUBCOMMAND="$1"; shift
            SUBARGS=("$@")
            break
            ;;
        -h | --help | --usage) usage ;;
        *) die "Unknown argument: $1" ;;
    esac
done

[[ -z "$SUBCOMMAND" ]] && usage

if [[ -z "$VOLUME" ]]; then
    VOLUME=$(detect_volume)
    echo "Using volume: ${VOLUME}"
fi

# Verify the volume exists
docker volume inspect "$VOLUME" >/dev/null 2>&1 \
    || die "Volume '${VOLUME}' not found. Run the init container first."

# ── subcommands ────────────────────────────────────────────────────────────────

cmd_push() {
    local src="${1:-}"
    [[ -z "$src" ]] && die "push requires a directory argument: ./world.sh push <dir>"
    [[ -d "$src" ]] || die "Not a directory: $src"
    src=$(cd "$src" && pwd)

    local was_running=false
    stop_server && was_running=true

    echo "Pushing '${src}' → /data/world ..."
    docker run --rm \
        --user 99:100 \
        -v "${src}:/src:ro" \
        -v "${VOLUME}:/data" \
        alpine sh -c "rm -rf /data/world && cp -r /src /data/world && echo 'Done.'"

    if $RESTART && $was_running; then
        start_server
    elif $was_running; then
        echo "Server was stopped. Use --restart to bring it back up, or: docker compose start server"
    fi
}

cmd_reset() {
    local was_running=false
    stop_server && was_running=true

    echo "Resetting world directories in volume '${VOLUME}'..."
    with_volume "$VOLUME" sh -c '
        set -e
        count=0
        for target in \
            /data/world \
            /data/world_nether \
            /data/world_the_end \
            /data/DIM-1 \
            /data/DIM1
        do
            if [ -d "$target" ]; then
                rm -rf "$target"
                echo "  Removed: $target"
                count=$((count + 1))
            fi
        done
        # Remove any remaining DIM* directories at the data root
        for d in /data/DIM*; do
            [ -d "$d" ] || continue
            rm -rf "$d"
            echo "  Removed: $d"
            count=$((count + 1))
        done
        echo "Reset complete: $count directories removed."
    '

    if $RESTART && $was_running; then
        start_server
    elif $was_running; then
        echo "Server was stopped. Use --restart to bring it back up, or: docker compose start server"
    fi
}

cmd_pull() {
    local outfile="${1:-}"
    if [[ -z "$outfile" ]]; then
        outfile="world-$(date +%Y%m%d-%H%M%S).tar.gz"
    fi
    # Resolve to absolute path so docker bind-mount works
    local outdir
    outdir=$(cd "$(dirname "$outfile")" && pwd)
    outfile="${outdir}/$(basename "$outfile")"

    # Check for backup mod archives first (see: https://github.com/evilegg/docker-allthemods10/issues/<n>)
    local has_backups
    has_backups=$(with_volume "$VOLUME" sh -c \
        '[ -d /data/backups ] && ls /data/backups/*.zip 2>/dev/null | head -1 || true')
    if [[ -n "$has_backups" ]]; then
        echo "Backup archives found in /data/backups — pulling latest backup zip instead of live world dirs."
        local latest
        latest=$(with_volume "$VOLUME" sh -c \
            'ls -t /data/backups/*.zip 2>/dev/null | head -1')
        echo "Latest backup: ${latest}"
        docker run --rm \
            -v "${VOLUME}:/data:ro" \
            -v "${outdir}:/out" \
            alpine cp "/data/${latest#/data/}" "/out/$(basename "$latest")"
        echo "Pulled: ${outdir}/$(basename "$latest")"
        return
    fi

    echo "Archiving world directories from volume '${VOLUME}' → ${outfile} ..."

    # Stop the server to get a consistent snapshot of the live world dirs
    local was_running=false
    stop_server && was_running=true

    docker run --rm \
        -v "${VOLUME}:/data:ro" \
        -v "${outdir}:/out" \
        alpine sh -c '
            set -e
            dirs=""
            for d in world world_nether world_the_end; do
                [ -d "/data/$d" ] && dirs="$dirs $d"
            done
            for d in /data/DIM*; do
                [ -d "$d" ] && dirs="$dirs $(basename $d)"
            done
            [ -z "$dirs" ] && echo "No world directories found." && exit 1
            echo "Archiving:$dirs"
            tar czf /out/'"$(basename "$outfile")"' -C /data $dirs
            echo "Done."
        '

    echo "Pulled: ${outfile}"

    if $was_running; then
        if $RESTART; then
            start_server
        else
            echo "Server was stopped for a consistent snapshot. Use --restart or: docker compose start server"
        fi
    fi
}

cmd_restore() {
    local tarball="${1:-}"
    [[ -z "$tarball" ]] && die "restore requires a tarball argument: ./world.sh restore <file.tar.gz>"
    [[ -f "$tarball" ]] || die "File not found: $tarball"
    tarball=$(cd "$(dirname "$tarball")" && pwd)/$(basename "$tarball")

    local was_running=false
    stop_server && was_running=true

    echo "Deleting existing world directories from volume '${VOLUME}'..."
    with_volume "$VOLUME" sh -c '
        set -e
        for target in \
            /data/world \
            /data/world_nether \
            /data/world_the_end \
            /data/DIM-1 \
            /data/DIM1
        do
            if [ -d "$target" ]; then
                rm -rf "$target"
                echo "  Removed: $target"
            fi
        done
        for d in /data/DIM*; do
            [ -d "$d" ] || continue
            rm -rf "$d"
            echo "  Removed: $d"
        done
    '

    echo "Restoring '${tarball}' → /data ..."
    local tardir
    tardir=$(dirname "$tarball")
    local tarbase
    tarbase=$(basename "$tarball")

    # Detect whether the archive has a top-level wrapper directory.
    # World archives from `pull` have no wrapper (top-level entries are world dirs).
    # If all top-level entries live inside a single directory, strip that level.
    local strip_flag=""
    local top_entries
    top_entries=$(docker run --rm \
        -v "${tardir}:/src:ro" \
        alpine sh -c "tar tzf /src/${tarbase} | cut -d/ -f1 | sort -u")
    local world_dirs="world world_nether world_the_end"
    local is_wrapped=true
    local entry
    while IFS= read -r entry; do
        [[ -z "$entry" ]] && continue
        # If any top-level entry matches a known world dir name, archive is not wrapped
        case "$entry" in
            world|world_nether|world_the_end|DIM*) is_wrapped=false; break ;;
        esac
    done <<< "$top_entries"

    if $is_wrapped; then
        echo "  Detected top-level wrapper directory — stripping one level."
        strip_flag="--strip-components=1"
    fi

    docker run --rm \
        --user 99:100 \
        -v "${tardir}:/src:ro" \
        -v "${VOLUME}:/data" \
        alpine sh -c "tar xzf /src/${tarbase} ${strip_flag} -C /data && echo 'Done.'"

    if $RESTART && $was_running; then
        start_server
    elif $was_running; then
        echo "Server was stopped. Use --restart to bring it back up, or: docker compose start server"
    fi
}

# ── dispatch ────────────────────────────────────────────────────────────────────

case "$SUBCOMMAND" in
    push)    cmd_push    "${SUBARGS[@]+"${SUBARGS[@]}"}" ;;
    reset)   cmd_reset ;;
    pull)    cmd_pull    "${SUBARGS[@]+"${SUBARGS[@]}"}" ;;
    restore) cmd_restore "${SUBARGS[@]+"${SUBARGS[@]}"}" ;;
    *)       usage ;;
esac
