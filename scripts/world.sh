#!/usr/bin/env bash
# world.sh — manage /data/world inside the Docker data volume
#
# Usage:
#   ./scripts/world.sh push <dir>          Copy a local world directory into the volume
#   ./scripts/world.sh reset               Delete all world/DIM directories from the volume
#   ./scripts/world.sh pull [file.tar.gz]  Archive the world directories from the volume
#
# Options:
#   --volume <name>         Override the Docker volume name (default: auto-detected)
#   --restart               Restart the server container after push or reset
#   --project <name>        Override the Compose project name for volume detection
#   -h, --help, --usage     Show this help and exit

set -euo pipefail

# ── helpers ────────────────────────────────────────────────────────────────────

usage() {
    cat >&2 <<'EOF'
Usage:
  ./scripts/world.sh push <dir>          Copy a local world dir into the data volume
  ./scripts/world.sh reset               Delete all world/DIM dirs from the data volume
  ./scripts/world.sh pull [file.tar.gz]  Archive the world dirs from the data volume to a local file

Options:
  --volume <name>         Override the detected Docker volume name
  --project <name>        Override the Compose project name used for volume detection
  --restart               Restart the server container after push or reset
  -h, --help, --usage     Show this help and exit
EOF
    exit 1
}

die() { echo "ERROR: $*" >&2; exit 1; }

# Detect the Docker volume name from docker compose config.
# Falls back to <project>_data if compose config is unavailable.
detect_volume() {
    local project="${COMPOSE_PROJECT:-}"

    if docker compose config --format json >/dev/null 2>&1; then
        local vol
        vol=$(docker compose config --format json 2>/dev/null \
            | python3 -c "import sys,json; cfg=json.load(sys.stdin); print(cfg.get('volumes',{}).get('data',{}).get('name',''))" 2>/dev/null || true)
        if [[ -n "$vol" ]]; then
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
    docker run --rm -v "${volume}:/data" alpine "$@"
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
        push|reset|pull)
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

# ── dispatch ────────────────────────────────────────────────────────────────────

case "$SUBCOMMAND" in
    push)  cmd_push  "${SUBARGS[@]+"${SUBARGS[@]}"}" ;;
    reset) cmd_reset ;;
    pull)  cmd_pull  "${SUBARGS[@]+"${SUBARGS[@]}"}" ;;
    *)     usage ;;
esac
