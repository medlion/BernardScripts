#!/bin/bash
# Builds and starts a project, then points the local HAProxy at its new containers.
# Usage: deploy.sh PROJECT_FOLDER [--live]   (e.g. deploy.sh <PROJECT_FOLDER> --live)
# Run it from inside the project folder: the .env (with APP_URL) is read from the current directory.
# The build files (docker-bake.hcl, compose.yaml) are in DEPLOY_BASE_DIR/PROJECT_FOLDER.
# --live starts the stack with PROJECT_FOLDER/live/compose.override.yaml, routes HAProxy to
# Vite on port 5173, served by the node service in live/compose.override.yaml.

# --- Settings (DEPLOY_BASE_DIR and HAPROXY_USER/HAPROXY_PASS come from deploy.conf) ---
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
source "$SCRIPT_DIR/deploy.conf" || { echo "ERROR: could not read $SCRIPT_DIR/deploy.conf" >&2; exit 1; }

LIVE=0
BUILD=0
PROJECT=
for arg in "$@"; do
  case $arg in
    --live) LIVE=1 ;;
    --build) BUILD=1 ;;
    *) PROJECT=${arg%/} ;;
  esac
done
if [ -z "$PROJECT" ]; then
  echo "Usage: $0 PROJECT_FOLDER [--live]" >&2
  exit 1
fi
PROJECT_DIR=$DEPLOY_BASE_DIR/$PROJECT
if [ ! -d "$PROJECT_DIR" ]; then
  echo "ERROR: project folder not found: $PROJECT_DIR" >&2
  exit 1
fi

BAKE_FILE=$PROJECT_DIR/docker-bake.hcl
COMPOSE_FILE=$PROJECT_DIR/compose.yaml
COMPOSE_ARGS=(-f "$COMPOSE_FILE")
if [ "$LIVE" -eq 1 ]; then
  COMPOSE_ARGS+=(-f "$PROJECT_DIR/live/compose.override.yaml")
fi
ENV_FILE=./.env
BACKEND_NAME=${PROJECT}_web_80

HAPROXY_API=http://localhost:5555/v3/services/haproxy
# Docker network shared by HAProxy and the app frontend (docker network create proxy)
PROXY_NETWORK=proxy

# --- APP_URL from .env, e.g. https://app.example.com -> app.example.com ---
# Checked before building so a missing value can't produce a broken HAProxy rule.
if [ ! -f "$ENV_FILE" ]; then
  echo "ERROR: $ENV_FILE not found (it must define APP_URL)" >&2
  exit 1
fi
APP_URL=$(grep '^APP_URL=' "$ENV_FILE" | tail -n1 | cut -d= -f2- | tr -d '"'"'"'\r ')
APP_HOST=${APP_URL#*//}
APP_HOST=${APP_HOST%%/*}
if [ -z "$APP_HOST" ]; then
  echo "ERROR: APP_URL is missing or empty in $ENV_FILE" >&2
  exit 1
fi
echo "App host: $APP_HOST"

# Image tags of the bake default group (cacheonly targets produce no image, so they are left out)
BAKE_TAGS=$(docker buildx bake -f "$BAKE_FILE" --print \
  | jq -r '.group.default.targets[] as $t | .target[$t] | select(.output == null) | .tags[]') || exit 1

# Images used by the compose file (includes the bake tags, plus any others)
COMPOSE_IMAGES=$(docker compose "${COMPOSE_ARGS[@]}" config --images) || exit 1
IMAGES_TO_CHECK=$(printf '%s\n' "$BAKE_TAGS" "$COMPOSE_IMAGES" | sort -u)

# Images that are not in the local image store
MISSING_TAGS=()
while read -r TAG; do
  docker image inspect "$TAG" > /dev/null 2>&1 || MISSING_TAGS+=("$TAG")
done <<< "$IMAGES_TO_CHECK"

if [ "${#MISSING_TAGS[@]}" -eq 0 ]; then
  echo "Images: all found locally"
else
  echo "Images missing locally:"
  printf '  %s\n' "${MISSING_TAGS[@]}"
fi

# --- Build and start ---
# Bake is skipped when every bake image is already local, unless --build is given
BAKE_MISSING=0
for TAG in "${MISSING_TAGS[@]}"; do
  grep -qxF "$TAG" <<< "$BAKE_TAGS" && BAKE_MISSING=1
done
if [ "$BUILD" -eq 1 ]; then
  echo "Building bake images (--build)"
  docker buildx bake -f "$BAKE_FILE"
elif [ "$BAKE_MISSING" -eq 1 ]; then
  echo "Building bake images (missing locally)"
  docker buildx bake -f "$BAKE_FILE"
else
  echo "Skipping build: bake images found locally (use --build to rebuild)"
fi
docker compose "${COMPOSE_ARGS[@]}" up -d

# --- Container IPs ---
get_ip() {
  local id ip i
  for i in $(seq 1 30); do
    id=$(docker compose "${COMPOSE_ARGS[@]}" ps -q "$1")
    [ -n "$id" ] && ip=$(docker inspect -f "{{with index .NetworkSettings.Networks \"$PROXY_NETWORK\"}}{{.IPAddress}}{{end}}" "$id")
    if [ -n "$ip" ]; then echo "$ip"; return 0; fi
    sleep 1
  done
  echo "ERROR: no IP address for service '$1' after 30s" >&2
  return 1
}

# Service names are unique per project, so find the frontend as the service attached to the proxy network.
PROXY_SERVICES=$(docker compose "${COMPOSE_ARGS[@]}" config --format json \
  | jq -r --arg net "$PROXY_NETWORK" '.services | to_entries[] | select(.value.networks // {} | has($net)) | .key') || exit 1
if [ -z "$PROXY_SERVICES" ]; then
  echo "ERROR: no service in $COMPOSE_FILE is attached to the '$PROXY_NETWORK' network" >&2
  exit 1
fi
if [ "$(echo "$PROXY_SERVICES" | wc -l)" -gt 1 ]; then
  echo "ERROR: more than one service is attached to the '$PROXY_NETWORK' network:" >&2
  echo "$PROXY_SERVICES" | sed 's/^/  /' >&2
  exit 1
fi
FRONTEND_SERVICE=$PROXY_SERVICES
echo "Frontend service: $FRONTEND_SERVICE"
FRONTEND_IP=$(get_ip "$FRONTEND_SERVICE") || exit 1
# The backend (FPM) is not exposed through HAProxy: it shares the frontend's
# network namespace (network_mode: service:frontend) and is reached by the frontend only.
echo "Frontend: $FRONTEND_IP"
# --live: Vite binds to the frontend's proxy-network IP (the address HAProxy routes to).
# Started again so the node service picks it up; the first start above has no address yet.
if [ "$LIVE" -eq 1 ]; then
  VITE_HOST=$FRONTEND_IP docker compose "${COMPOSE_ARGS[@]}" up -d
fi


# --- HAProxy dataplane API helper: api METHOD PATH [JSON] ---
api() {
  local out code
  out=$(mktemp)
  code=$(curl -s -o "$out" -w '%{http_code}' -u "$HAPROXY_USER:$HAPROXY_PASS" \
    -X "$1" -H 'Content-Type: application/json' -d "${3:-}" "$HAPROXY_API$2")
  if [ "$code" -ge 400 ]; then
    echo "  API $1 ${2%%\?*} -> $code: $(cat "$out")" >&2
  fi
  rm -f "$out"
  echo "$code"
}

# Adds a haproxy backend with one server (replaces the server if it already exists)
# usage: add_backend NAME IP PORT
add_backend() {
  local name=$1 ip=$2 port=$3
  CREATED=$(api POST "/configuration/backends?transaction_id=$TX" "{\"name\":\"$name\",\"mode\":\"http\"}")
  api DELETE "/configuration/backends/$name/servers/server1?transaction_id=$TX" > /dev/null
  api POST "/configuration/backends/$name/servers?transaction_id=$TX" "{\"name\":\"server1\",\"address\":\"$ip\",\"port\":$port}" > /dev/null
}

# Sends the app host to a backend, from a haproxy frontend.
# Any existing rule for that backend is removed first so a re-deploy repairs a stale/wrong rule.
# usage: add_rule FRONTEND BACKEND [COND_TEST]
add_rule() {
  local idx cond=${3:-"{ hdr(host) -i $APP_HOST }"}
  while idx=$(curl -s -u "$HAPROXY_USER:$HAPROXY_PASS" "$HAPROXY_API/configuration/frontends/$1/backend_switching_rules?transaction_id=$TX" \
      | jq -r --arg n "$2" 'map(.name) | index($n) // empty') && [ -n "$idx" ]; do
    api DELETE "/configuration/frontends/$1/backend_switching_rules/$idx?transaction_id=$TX" > /dev/null
  done
  api POST "/configuration/frontends/$1/backend_switching_rules/0?transaction_id=$TX" \
    "{\"name\":\"$2\",\"cond\":\"if\",\"cond_test\":\"$cond\"}" > /dev/null
}

# --- Update HAProxy inside one transaction ---
VERSION=$(curl -s -u "$HAPROXY_USER:$HAPROXY_PASS" "$HAPROXY_API/configuration/version")
TX=$(curl -s -u "$HAPROXY_USER:$HAPROXY_PASS" -X POST "$HAPROXY_API/transactions?version=$VERSION" | grep -o '"id": *"[^"]*"' | cut -d'"' -f4)
if [ -z "$TX" ]; then
  echo "ERROR: could not open a HAProxy transaction (version='$VERSION')" >&2
  exit 1
fi
echo "Transaction: $TX (config version $VERSION)"

add_backend "$BACKEND_NAME" "$FRONTEND_IP" 80

# Port 80 is redirected to HTTPS by HAProxy itself (see haproxy.cfg), so only the https
# frontend routes to the app. TLS ends at HAProxy, so it uses the plain-HTTP backend.
add_rule https "$BACKEND_NAME"

# --live: host:5173 goes to Vite in the frontend, on its own haproxy frontend so the 80/443 rules are untouched
if [ "$LIVE" -eq 1 ]; then
  VITE_BACKEND=${PROJECT}_vite_5173
  if [ "$(curl -s -o /dev/null -w '%{http_code}' -u "$HAPROXY_USER:$HAPROXY_PASS" "$HAPROXY_API/configuration/frontends/live?transaction_id=$TX")" != "200" ]; then
    api POST "/configuration/frontends?transaction_id=$TX" '{"name":"live","mode":"http"}' > /dev/null
    api POST "/configuration/frontends/live/binds?transaction_id=$TX" '{"name":"live_5173","address":"*","port":5173}' > /dev/null
  fi
  add_backend "$VITE_BACKEND" "$FRONTEND_IP" 5173
  # Matches the host without its port, so http://APP_HOST:5173 (which sends "APP_HOST:5173" as Host) routes too
  add_rule live "$VITE_BACKEND" "{ hdr(host),field(1,:) -i $APP_HOST }"
fi

COMMIT=$(api PUT "/transactions/$TX")
if [ "$COMMIT" != "200" ] && [ "$COMMIT" != "202" ]; then
  echo "ERROR: HAProxy transaction commit failed (HTTP $COMMIT)" >&2
  exit 1
fi
echo "HAProxy updated: $APP_HOST -> frontend $FRONTEND_IP:80 (https only, http redirects to https)"
