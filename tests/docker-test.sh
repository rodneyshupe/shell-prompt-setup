#!/usr/bin/env bash
# Clean-room test in a Debian container: installs for two users, checks the results,
# checks idempotence and the no-clobber rule, and checks the curl-style path
# (script piped to bash, config downloaded from a local web server).
# Usage: tests/docker-test.sh [image]     (default: debian:trixie)
set -eu
IMAGE=${1:-debian:trixie}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
PORT=8765
python3 -m http.server $PORT --directory "$ROOT" >/dev/null 2>&1 &
HTTP=$!
trap 'kill $HTTP 2>/dev/null' EXIT
sleep 1
docker run --rm --cap-add NET_ADMIN -v "$ROOT":/repo:ro --add-host=host.docker.internal:host-gateway "$IMAGE" bash -c '
set -eu
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq >/dev/null && apt-get install -y -qq curl ca-certificates sudo iproute2 >/dev/null
useradd -m -s /bin/bash alice; useradd -m -s /bin/bash bob
fail() { echo "FAIL: $*"; exit 1; }

echo "--- 1. dry run changes nothing"
bash /repo/install.sh --users root,alice --dry-run --shell >/tmp/dry.out
[ ! -e /home/alice/.zshrc ] || fail "dry run wrote a file"
grep -q "dry-run" /tmp/dry.out || fail "no dry-run output"

echo "--- 2. real install from the clone (root, alice with --shell --vip; bob with --ssh-agent)"
bash /repo/install.sh --users root,alice --shell --vip 10.0.0.10
bash /repo/install.sh --users bob --ssh-agent
for u in root alice bob; do
  h=$(getent passwd $u | cut -d: -f6)
  for f in .zshrc .zprofile .config/starship.toml; do [ -s $h/$f ] || fail "$u missing $f"; done
  [ "$(stat -c %U $h/.zshrc)" = $u ] || fail "$u .zshrc owner"
done
grep -q "PROMPT_VIP=10.0.0.10" /home/alice/.zshrc.local || fail "vip not written"
grep -q "ssh-agent -s" /home/bob/.zshrc.local || fail "ssh-agent block missing"
[ "$(getent passwd alice | cut -d: -f7)" = /usr/bin/zsh ] || fail "alice shell not zsh"
[ "$(getent passwd bob | cut -d: -f7)" = /bin/bash ] || fail "bob shell changed without --shell"

echo "--- 2b. existing directories keep their mode and owner"
[ "$(stat -c %a /root)" = 700 ] || fail "/root mode changed to $(stat -c %a /root)"
chmod 750 /home/alice; bash /repo/install.sh --users alice --force >/dev/null; [ "$(stat -c %a /home/alice)" = 750 ] || fail "home mode changed"
[ "$(stat -c %U /home/alice/.config)" = alice ] || fail ".config owner"

echo "--- 2c. starship prints no config warnings with the packaged version ($(starship --version | head -1))"
w=$(su alice -c "zsh -i -c \"starship prompt\"" 2>&1 >/dev/null | sed "s/\x1b\[[0-9;]*m//g" | grep -a WARN || true)
[ -z "$w" ] || fail "starship warnings: $w"

echo "--- 3. idempotent re-run, and non-interactive commands still work"
bash /repo/install.sh --users root,alice --shell --vip 10.0.0.10 | grep -c "already up to date" | grep -qv "^0$" || fail "re-run not idempotent"
su alice -c "true" && su alice -c "echo \$0 | grep -q zsh"
su -l alice -c "command -v starship" >/dev/null || fail "starship not on PATH for alice"

echo "--- 4. VIP marker follows the address"
mk() { su alice -c "zsh -i -c \"starship prompt\"" 2>&1 | sed "s/%{[^}]*}//g;s/\x1b\[[0-9;]*m//g" | grep -c "\[VIP\]" || true; }
[ "$(mk)" = 0 ] || fail "VIP shown without the address"
ip addr add 10.0.0.10/32 dev lo 2>/dev/null && { [ "$(mk)" = 1 ] || fail "VIP not shown while held"; } || echo "(skipped: cannot add an address in this container)"

echo "--- 5. no clobber without --force"
echo "# mine" >> /home/bob/.zshrc
bash /repo/install.sh --users bob >/tmp/noclob.out 2>&1 && fail "expected non-zero exit when a file differs" || true
grep -q "# mine" /home/bob/.zshrc || fail "differing file was overwritten"
bash /repo/install.sh --users bob --force >/dev/null
ls /home/bob/.zshrc.bak.* >/dev/null || fail "no backup made by --force"
grep -q "# mine" /home/bob/.zshrc && fail "--force did not replace"

echo "--- 6. curl-style: piped to bash, config downloaded"
useradd -m carol
curl -fsSL http://host.docker.internal:'"$PORT"'/install.sh | bash -s -- --users carol --base-url http://host.docker.internal:'"$PORT"' --shell
[ -s /home/carol/.zshrc ] && [ "$(getent passwd carol | cut -d: -f7)" = /usr/bin/zsh ] || fail "curl-style install"

echo "--- 7. unknown user is reported, not fatal to the others"
bash /repo/install.sh --users nosuchuser,carol --no-packages >/dev/null 2>&1 && fail "expected non-zero for unknown user" || true

echo "ALL TESTS PASSED"
'
