#!/usr/bin/env bash
# Build the dev image chain and (re)create the distroboxes.
# Usage: ./build.sh        # incremental builds, create containers if missing
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

podman build -t localhost/dev-common:latest "$DIR/common"
podman build -t localhost/dev:latest      "$DIR/dev"
podman build -t localhost/devj:latest     "$DIR/devj"

distrobox assemble create --file "$DIR/distrobox.ini"
