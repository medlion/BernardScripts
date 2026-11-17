#!/bin/bash
# Deploys the project named after the current directory (just the last path part).
# Usage: deployproject.sh [--live] [--build]   (run from inside the project folder)
# Errors out if DEPLOY_BASE_DIR has no folder with that name.

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
source "$SCRIPT_DIR/deploy.conf" || { echo "ERROR: could not read $SCRIPT_DIR/deploy.conf" >&2; exit 1; }

PROJECT=$(basename "$PWD")
if [ ! -d "$DEPLOY_BASE_DIR/$PROJECT" ]; then
  echo "ERROR: no folder named '$PROJECT' in $DEPLOY_BASE_DIR" >&2
  exit 1
fi

exec bash "$SCRIPT_DIR/deploy.sh" "$PROJECT" "$@"
