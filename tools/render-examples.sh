#!/usr/bin/env bash
# Regenerates docs/images/*.svg (color, terminal style) and *.txt (plain text) from the REAL prompts, and refreshes
# the plain-text example blocks between the <!-- examples:NAME --> markers in README.md.
# The prompts are captured in a Debian container with the real installers, so the images show what the code draws.
# Usage: tools/render-examples.sh      Needs Docker and python3.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=$(mktemp -d "${TMPDIR:-/tmp}/render-examples.XXXXXX")
docker run --rm --cap-add NET_ADMIN -v "$ROOT":/repo:ro -v "$OUT":/out debian:trixie bash /repo/tools/render-in-container.sh
mkdir -p "$ROOT/docs/images"
python3 "$ROOT/tools/build-examples.py" "$ROOT" "$OUT"
