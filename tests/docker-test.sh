#!/usr/bin/env bash
# Clean-room test in a Debian container: the installer for bash and zsh users (default, both shells,
# prompt-only on an existing .zshrc, migration of the old layout, idempotence, no-clobber/--force,
# --shell, --uninstall, curl | bash), and the same prompt checks in bash and zsh (corners, ssh depth
# through a real sshd, colors, ahead/behind counts, VIP marker).
# Usage: tests/docker-test.sh [image]     (default: debian:trixie)  Needs Docker and python3.
set -eu
IMAGE=${1:-debian:trixie}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
PORT=8765
python3 -m http.server $PORT --directory "$ROOT" >/dev/null 2>&1 &
HTTP=$!
trap 'kill $HTTP 2>/dev/null' EXIT
sleep 1
docker run --rm --cap-add NET_ADMIN -v "$ROOT":/repo:ro --add-host=host.docker.internal:host-gateway \
  -e REPO=/repo -e HTTP_BASE="http://host.docker.internal:$PORT" "$IMAGE" bash /repo/tests/in-container.sh
