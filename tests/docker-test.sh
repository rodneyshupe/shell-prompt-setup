#!/usr/bin/env bash
# Clean-room tests in Debian containers, one fresh container per suite:
#   starship   install.sh for bash and zsh users (default, both shells, prompt-only on an existing .zshrc, migration
#              of the first layout, idempotence, no-clobber/--force, --shell, --uninstall, curl | bash), and the same
#              prompt checks in bash and zsh (corners, ssh depth through a real sshd, colors, ahead/behind, VIP).
#   powerline  install-powerline.sh with both backends (the `powerline` package, powerline-shell in a virtualenv),
#              glyph-free themes for listed clients, switching between the two prompts, an rc that already loads
#              Powerline, --uninstall, curl | bash.
# Usage: tests/docker-test.sh [image] [starship|powerline]     (default: debian:trixie, both suites)
# Needs Docker and python3.
set -eu
IMAGE=${1:-debian:trixie}
SUITE=${2:-all}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
PORT=8765
python3 -m http.server $PORT --directory "$ROOT" >/dev/null 2>&1 &
HTTP=$!
trap 'kill $HTTP 2>/dev/null' EXIT
sleep 1
run_suite() {
  echo "######## suite: $1"
  docker run --rm --cap-add NET_ADMIN -v "$ROOT":/repo:ro --add-host=host.docker.internal:host-gateway \
    -e REPO=/repo -e HTTP_BASE="http://host.docker.internal:$PORT" "$IMAGE" bash "/repo/tests/$2"
}
case "$SUITE" in all|starship)  run_suite starship in-container.sh ;; esac
case "$SUITE" in all|powerline) run_suite powerline in-container-powerline.sh ;; esac
