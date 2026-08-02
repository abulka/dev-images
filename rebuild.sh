#!/usr/bin/env bash
# Force a full rebuild of the dev image chain and replace the distroboxes.
# Usage: ./rebuild.sh      # --no-cache image builds, --replace containers
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

podman build --no-cache -t localhost/dev-common:latest "$DIR/common"
podman build --no-cache -t localhost/dev:latest      "$DIR/dev"
podman build --no-cache -t localhost/devj:latest     "$DIR/devj"

distrobox assemble create --replace --file "$DIR/distrobox.ini"
