#!/bin/bash
# launch.sh — runtime container entrypoint; applies env overrides then execs the server
#
# Usage:
#   /launch.sh [command]
#
# Options:
#   -h, --help, --usage   Show this help and exit
#
# Environment:
#   EULA=true               Required; server exits with code 99 without it
#   JVM_OPTS                JVM memory flags (e.g. -Xms2048m -Xmx4096m)
#   MOTD                    Server description string
#   ALLOW_FLIGHT            true/false
#   MAX_PLAYERS             Integer
#   ONLINE_MODE             true/false
#   ENABLE_WHITELIST        true/false
#   WHITELIST_USERS         Comma-separated Minecraft usernames to whitelist
#   OP_USERS                Comma-separated Minecraft usernames to op

usage() {
    cat >&2 <<'EOF'
Usage:
  /launch.sh [command]

Applies environment-variable overrides to server config, populates
whitelist.json and ops.json via playerdb.co UUID lookups, then execs
the given command (default: ./run.sh) as PID 1.

Options:
  -h, --help, --usage   Show this help and exit

Environment:
  EULA=true               Required; server exits with code 99 without it
  JVM_OPTS                JVM memory flags (e.g. -Xms2048m -Xmx4096m)
  MOTD                    Server description string
  ALLOW_FLIGHT            true/false
  MAX_PLAYERS             Integer
  ONLINE_MODE             true/false
  ENABLE_WHITELIST        true/false
  WHITELIST_USERS         Comma-separated Minecraft usernames to whitelist
  OP_USERS                Comma-separated Minecraft usernames to op
EOF
    exit 0
}

case "${1:-}" in
    -h | --help | --usage) usage ;;
esac

set -x

cd /data

if [[ "$EULA" = "true" ]]; then
    echo "eula=true" > eula.txt
else
    echo "ERROR: Set EULA=true to accept the Minecraft EULA." >&2
    exit 99
fi

if [[ ! -d "libraries" ]]; then
    echo "ERROR: /data/libraries not found." >&2
    echo "Run the data init container first to seed the volume." >&2
    exit 1
fi

if [[ -n "$JVM_OPTS" ]]; then
    sed -i '/-Xm[s,x]/d' user_jvm_args.txt
    for j in ${JVM_OPTS}; do sed -i '$a\'$j'' user_jvm_args.txt; done
fi

if [[ -f server.properties ]]; then
    [[ -n "$MOTD" ]]             && sed -i "s/^motd=.*/motd=$MOTD/" server.properties
    [[ -n "$ENABLE_WHITELIST" ]] && sed -i "s/white-list=.*/white-list=$ENABLE_WHITELIST/" server.properties
    [[ -n "$ALLOW_FLIGHT" ]]     && sed -i "s/allow-flight=.*/allow-flight=$ALLOW_FLIGHT/" server.properties
    [[ -n "$MAX_PLAYERS" ]]      && sed -i "s/max-players=.*/max-players=$MAX_PLAYERS/" server.properties
    [[ -n "$ONLINE_MODE" ]]      && sed -i "s/online-mode=.*/online-mode=$ONLINE_MODE/" server.properties
    sed -i 's/server-port.*/server-port=25565/g' server.properties
fi

# Initialize whitelist.json if not present
if [[ ! -f whitelist.json ]]; then
    echo "[]" > whitelist.json
fi

IFS=',' read -ra USERS <<< "$WHITELIST_USERS"
for raw_username in "${USERS[@]}"; do
    username=$(echo "$raw_username" | xargs)

    if [[ -z "$username" ]] || ! [[ "$username" =~ ^[a-zA-Z0-9_]{3,16}$ ]]; then
        echo "Whitelist: Invalid or empty username: '$username'. Skipping..."
        continue
    fi

    UUID=$(curl -s "https://playerdb.co/api/player/minecraft/$username" | jq -r '.data.player.id')
    if [[ "$UUID" != "null" ]]; then
        if jq -e ".[] | select(.uuid == \"$UUID\" and .name == \"$username\")" whitelist.json > /dev/null; then
            echo "Whitelist: $username ($UUID) is already whitelisted. Skipping..."
        else
            echo "Whitelist: Adding $username ($UUID) to whitelist."
            jq ". += [{\"uuid\": \"$UUID\", \"name\": \"$username\"}]" whitelist.json > tmp.json && mv tmp.json whitelist.json
        fi
    else
        echo "Whitelist: Failed to fetch UUID for $username."
    fi
done

# Initialize ops.json if not present
if [[ ! -f ops.json ]]; then
    echo "[]" > ops.json
fi

IFS=',' read -ra OPS <<< "$OP_USERS"
for raw_username in "${OPS[@]}"; do
    username=$(echo "$raw_username" | xargs)

    if [[ -z "$username" ]] || ! [[ "$username" =~ ^[a-zA-Z0-9_]{3,16}$ ]]; then
        echo "Ops: Invalid or empty username: '$username'. Skipping..."
        continue
    fi

    UUID=$(curl -s "https://playerdb.co/api/player/minecraft/$username" | jq -r '.data.player.id')
    if [[ "$UUID" != "null" ]]; then
        if jq -e ".[] | select(.uuid == \"$UUID\" and .name == \"$username\")" ops.json > /dev/null; then
            echo "Ops: $username ($UUID) is already an operator. Skipping..."
        else
            echo "Ops: Adding $username ($UUID) as operator."
            jq ". += [{\"uuid\": \"$UUID\", \"name\": \"$username\", \"level\": 4, \"bypassesPlayerLimit\": false}]" ops.json > tmp.json && mv tmp.json ops.json
        fi
    else
        echo "Ops: Failed to fetch UUID for $username."
    fi
done

chmod 755 run.sh
exec "$@"
