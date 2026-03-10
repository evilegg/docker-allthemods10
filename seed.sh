#!/bin/sh
set -e

# Seed server files into /data if the volume is empty (no libraries/ dir).
if [ ! -d /data/libraries ]; then
    echo "Seeding /data from /opt/server..."
    cp -r /opt/server/. /data/
fi
