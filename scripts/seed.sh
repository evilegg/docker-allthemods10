#!/bin/sh
# seed.sh — data image entrypoint; seeds /data then overlays overrides/
#
# Usage:
#   /seed.sh
#
# Environment:
#   OVERRIDES_NOCLOBBER=true   Skip files that already exist in /data.
#                              Default behaviour is to overwrite and log a warning.

usage() {
    cat >&2 <<'EOF'
Usage:
  /seed.sh

Seeds /data from /opt/server if not already seeded, then overlays any files
from /opt/overrides/ onto /data.

Environment:
  OVERRIDES_NOCLOBBER=true   Skip files that already exist in /data.
                             Default: overwrite and log a warning.
EOF
    exit 0
}

set -e

case "${1:-}" in
    -h | --help | --usage) usage ;;
esac

# Seed server files into /data if the volume is empty (no libraries/ dir).
if [ ! -d /data/libraries ]; then
    echo "Seeding /data from /opt/server..."
    cp -r /opt/server/. /data/
fi

# Overlay overrides/ onto /data if any files were bundled into the image.
# Set OVERRIDES_NOCLOBBER=true to skip files that already exist in /data.
if [ "$(find /opt/overrides -type f 2>/dev/null | head -1)" ]; then
    echo "Applying overrides..."
    find /opt/overrides -type f | while read -r src; do
        rel="${src#/opt/overrides/}"
        dest="/data/$rel"
        if [ "${OVERRIDES_NOCLOBBER:-false}" = "true" ] && [ -e "$dest" ]; then
            echo "WARNING: skipping existing file: $rel"
        else
            if [ -e "$dest" ]; then
                echo "WARNING: overwriting existing file: $rel"
            fi
            mkdir -p "$(dirname "$dest")"
            cp "$src" "$dest"
        fi
    done
fi
