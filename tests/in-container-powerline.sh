#!/bin/bash
# Runs inside a fresh Debian test container as root (see docker-test.sh): install-powerline.sh with both
# backends (the `powerline` package on Linux, powerline-shell in a private virtualenv), for bash and zsh users.
# Env: REPO (the mounted repo, /repo), HTTP_BASE (a web server serving the repo, for the curl-style test).
export DEBIAN_FRONTEND=noninteractive
REPO=${REPO:-/repo}
fail() { echo "FAIL: $*"; exit 1; }
step() { echo "--- $*"; }
PL="bash $REPO/install-powerline.sh"
SL="bash $REPO/install.sh"

apt-get update -qq >/dev/null && apt-get install -y -qq curl ca-certificates sudo zsh >/dev/null || fail "cannot install test tools"
useradd -m -s /bin/bash bob      # bash user, `powerline` package backend
useradd -m -s /usr/bin/zsh zed   # zsh user, `powerline` package backend
useradd -m -s /bin/bash ann      # bash user, powerline-shell backend
useradd -m -s /usr/bin/zsh zoe   # zsh user, powerline-shell backend
useradd -m -s /bin/bash pat      # bash user whose .bashrc already loads Powerline by hand

GLYPH=$(printf '\xee\x82\xb0')   # U+E0B0, the Powerline arrow
norm()  { sed 's/\xc2\xa0/ /g;s/\x1b\[[0-9;]*m//g;s/\\\[//g;s/\\\]//g;s/%{[^}]*}//g'; }   # no NBSP, escapes, prompt wrappers
quiet() { grep -a -v -e 'job control' -e 'process group'; }
TIME_RE='[0-9]{1,2}:[0-9]{2} +(AM|PM)'

# ----------------------------------------------------------------------------------------------
step "1. dry run changes nothing"
$PL --users bob --dry-run >/tmp/dry.out 2>&1 || fail "dry run failed: $(tail -3 /tmp/dry.out)"
[ ! -e /home/bob/.config/shell-prompt-setup ] || fail "dry run created files"
dpkg -s powerline >/dev/null 2>&1 && fail "dry run installed powerline"

step "2. powerline package, bash and zsh users (auto backend on Linux)"
$PL --users bob,zed --plain-from 10.9.9.9 || fail "install for bob,zed failed"
command -v starship >/dev/null && fail "the Powerline installer installed starship"
D=/home/bob/.config/shell-prompt-setup
for f in powerline.sh powerline/config.json powerline/themes/shell/default_leftonly.json settings.sh; do [ -s $D/$f ] || fail "bob missing $f"; done
[ ! -e $D/prompt.sh ] && [ ! -e $D/starship.toml ] || fail "starship files installed by the Powerline installer"
grep -q 'powerline.sh' /home/bob/.bashrc && grep -q 'shell-prompt-setup: prompt >>>' /home/bob/.bashrc || fail "no prompt block in bob's .bashrc"
grep -q 'PROMPT_PLAIN_FROM="10.9.9.9"' $D/settings.sh || fail "settings.sh"
[ ! -e /home/bob/.zshrc ] || fail ".zshrc created for a bash user"
Z=/home/zed/.config/shell-prompt-setup
grep -q 'shell-prompt-setup: zsh-setup >>>' /home/zed/.zshrc && [ -s $Z/zsh-setup.zsh ] || fail "zed's zsh setup"

step "3. bash: the binding builds the prompt (clock, user, glyphs); layered config; plain themes"
r=$(su bob -c "bash -i -c 'echo SPS=\$SPS_PROMPT; echo PATHS=\$POWERLINE_CONFIG_PATHS'" 2>&1 | quiet)
echo "$r" | grep -q 'SPS=powerline' || fail "bash: loader not active: $r"
echo "$r" | grep -q "PATHS=/usr/share/powerline/config_files:/home/bob/.config/shell-prompt-setup/powerline" || fail "bash: config paths: $r"
p=$(su bob -c "bash -i -c 'eval \"\$PROMPT_COMMAND\"; printf %s \"\$PS1\"'" 2>&1 | quiet | norm)
echo "$p" | grep -a -q -E "$TIME_RE" && echo "$p" | grep -a -q 'bob' || fail "bash: PS1 from the binding lacks clock/user: $p"
r=$(su bob -c "bash -i -c 'powerline-render shell left'" 2>&1 | quiet)
echo "$r" | grep -a -q "$GLYPH" || fail "bash: no Powerline glyph in the default theme"
echo "$r" | norm | grep -a -q -E "$TIME_RE" || fail "bash: clock segment missing"
r=$(su bob -c "env SSH_CONNECTION='10.9.9.9 5 10.0.0.1 22' bash -i -c 'powerline-render shell left'" 2>&1 | quiet)
echo "$r" | grep -a -q "$GLYPH" && fail "bash: listed client still got glyphs"
echo "$r" | norm | grep -a -q -E "$TIME_RE" || fail "bash: plain theme lost the clock"
r=$(su bob -c "env SSH_CONNECTION='10.1.1.1 5 10.0.0.1 22' bash -i -c 'powerline-render shell left'" 2>&1 | quiet)
echo "$r" | grep -a -q "$GLYPH" || fail "bash: unlisted client lost the glyphs"
r=$(su bob -c "env PROMPT_PLAIN=1 bash -i -c 'powerline-render shell left'" 2>&1 | quiet)
echo "$r" | grep -a -q "$GLYPH" && fail "bash: PROMPT_PLAIN=1 ignored"
su bob -c "mkdir -p ~/.config/powerline"
r=$(su bob -c "bash -i -c 'echo \$POWERLINE_CONFIG_PATHS'" 2>&1 | quiet)
echo "$r" | grep -q ':/home/bob/.config/powerline$' || fail "the user's own ~/.config/powerline is not layered last: $r"

step "4. zsh: the binding is active, same glyph / plain behaviour"
r=$(su zed -c "zsh -i -c 'echo SPS=\$SPS_PROMPT; powerline-render shell left'" 2>&1)
echo "$r" | grep -q 'SPS=powerline' || fail "zsh: loader not active"
echo "$r" | grep -a -q "$GLYPH" || fail "zsh: no glyph"
r=$(su zed -c "env SSH_CONNECTION='10.9.9.9 5 10.0.0.1 22' zsh -i -c 'powerline-render shell left'" 2>&1)
echo "$r" | grep -a -q "$GLYPH" && fail "zsh: listed client still got glyphs"

step "5. idempotent re-run"
before=$(cd /home && sha256sum bob/.bashrc zed/.zshrc bob/.config/shell-prompt-setup/*.sh bob/.config/shell-prompt-setup/powerline/config.json | sha256sum)
$PL --users bob,zed --plain-from 10.9.9.9 >/tmp/re.out || fail "re-run failed"
after=$(cd /home && sha256sum bob/.bashrc zed/.zshrc bob/.config/shell-prompt-setup/*.sh bob/.config/shell-prompt-setup/powerline/config.json | sha256sum)
[ "$before" = "$after" ] || fail "a re-run changed files"
grep -q "already up to date" /tmp/re.out || fail "re-run not reported as up to date"

step "6. switching between the two prompts replaces the one block (no double prompt)"
$SL --users bob >/dev/null || fail "starship install over powerline failed"
[ "$(grep -c 'shell-prompt-setup: prompt >>>' /home/bob/.bashrc)" = 1 ] || fail "more than one prompt block after switching to starship"
grep -q 'prompt.sh' /home/bob/.bashrc && ! grep -q 'powerline.sh' /home/bob/.bashrc || fail "block not switched to starship"
command -v starship >/dev/null || fail "starship not installed by install.sh"
$PL --users bob --plain-from 10.9.9.9 >/dev/null || fail "powerline install over starship failed"
[ "$(grep -c 'shell-prompt-setup: prompt >>>' /home/bob/.bashrc)" = 1 ] || fail "more than one prompt block after switching back"
grep -q 'powerline.sh' /home/bob/.bashrc && ! grep -q 'prompt.sh' /home/bob/.bashrc || fail "block not switched back"

step "7. an rc that already loads Powerline by hand: refused, or the standard block removed with --force"
cat >> /home/pat/.bashrc <<'EOS'

# Powerline configuration
if [ -f /usr/share/powerline/bindings/bash/powerline.sh ]; then
  powerline-daemon -q
  POWERLINE_BASH_CONTINUATION=1
  POWERLINE_BASH_SELECT=1
  source /usr/share/powerline/bindings/bash/powerline.sh
fi
EOS
chown pat /home/pat/.bashrc; cp /home/pat/.bashrc /tmp/pat.bashrc
$PL --users pat >/tmp/pat.out 2>&1 && fail "expected a non-zero exit when .bashrc already loads Powerline"
grep -q "already loads Powerline" /tmp/pat.out || fail "no explanation: $(tail -3 /tmp/pat.out)"
cmp -s /tmp/pat.bashrc /home/pat/.bashrc || fail ".bashrc changed although the installer refused"
$PL --users pat --force >/dev/null 2>&1 || fail "--force failed"
grep -q '^# Powerline configuration' /home/pat/.bashrc && fail "the old Powerline block was not removed"
[ "$(grep -c 'shell-prompt-setup: prompt >>>' /home/pat/.bashrc)" = 1 ] || fail "our block missing after --force"
ls /home/pat/.bashrc.bak.* >/dev/null 2>&1 || fail "no backup before removing the old block"

step "8. powerline-shell backend: private virtualenv, patched and plain configs, bash and zsh"
$PL --users ann,zoe --backend powerline-shell --plain-from 10.9.9.9 || fail "powerline-shell install failed"
A=/home/ann/.config/shell-prompt-setup
[ -x $A/venv/bin/powerline-shell ] || fail "no venv"
[ "$(stat -c %U $A/venv/bin/powerline-shell)" = ann ] || fail "venv not owned by the user"
grep -q '"mode": "patched"' $A/powerline-shell-patched/powerline-shell/config.json && grep -q '"mode": "compatible"' $A/powerline-shell-plain/powerline-shell/config.json || fail "configs"
grep -q 'powerline-shell.sh' /home/ann/.bashrc || fail "ann's block"
p=$(su ann -c "bash -i -c 'eval \"\$PROMPT_COMMAND\"; printf %s \"\$PS1\"'" 2>&1 | quiet)
echo "$p" | grep -a -q "$GLYPH" || fail "powerline-shell bash: no glyph in patched mode"
echo "$p" | norm | grep -a -q -E '[0-9]{2}:[0-9]{2} (AM|PM)' || fail "powerline-shell bash: no clock: $(echo "$p" | norm)"
p=$(su ann -c "env SSH_CONNECTION='10.9.9.9 5 10.0.0.1 22' bash -i -c 'eval \"\$PROMPT_COMMAND\"; printf %s \"\$PS1\"'" 2>&1 | quiet)
echo "$p" | grep -a -q "$GLYPH" && fail "powerline-shell bash: listed client got glyphs"
echo "$p" | norm | grep -a -q -E '[0-9]{2}:[0-9]{2} (AM|PM)' || fail "powerline-shell bash: plain mode lost the clock"
p=$(su ann -c "env SSH_CONNECTION='10.1.1.1 5 10.0.0.1 22' bash -i -c 'eval \"\$PROMPT_COMMAND\"; printf %s \"\$PS1\"'" 2>&1 | quiet)
echo "$p" | grep -a -q "$GLYPH" || fail "powerline-shell bash: unlisted client lost glyphs"
p=$(su zoe -c "zsh -i -c '_sps_update_ps1; print -r -- \$PS1'" 2>&1)
echo "$p" | grep -a -q "$GLYPH" && echo "$p" | norm | grep -a -q -E '[0-9]{2}:[0-9]{2} (AM|PM)' || fail "powerline-shell zsh: $(echo "$p" | norm)"
r=$(su zoe -c "zsh -i -c 'print \${precmd_functions}'" 2>&1)
echo "$r" | grep -q '_sps_update_ps1' || fail "zsh: prompt function not registered: $r"
case "$(su ann -c "bash -i -c 'echo \$PROMPT_COMMAND'" 2>&1 | quiet)" in *_sps_update_ps1*) ;; *) fail "bash: PROMPT_COMMAND not set" ;; esac

step "9. option checks: a bad backend, --fonts on Linux, a missing address list"
$PL --users bob --backend nonsense --no-packages >/dev/null 2>&1 && fail "expected an error for a bad --backend"
$PL --users bob --plain-from 'not an ip' --no-packages >/dev/null 2>&1 && fail "expected an error for a bad --plain-from"
$PL --users bob --fonts --no-packages >/tmp/fonts.out 2>&1 || fail "--fonts on Linux should only warn"
grep -q "only installs on macOS" /tmp/fonts.out || fail "no --fonts warning"

step "10. curl-style: piped to bash, library and files downloaded"
useradd -m -s /bin/bash carol
curl -fsSL "$HTTP_BASE/install-powerline.sh" | bash -s -- --users carol --base-url "$HTTP_BASE" || fail "curl-style install failed"
grep -q 'powerline.sh' /home/carol/.bashrc && [ -s /home/carol/.config/shell-prompt-setup/powerline/themes/shell/default_leftonly.json ] || fail "curl-style result"

step "11. --uninstall removes the blocks, the files and the virtualenv; your own content stays"
$PL --users ann,bob --uninstall >/dev/null || fail "uninstall failed"
[ ! -e /home/ann/.config/shell-prompt-setup ] && [ ! -e /home/bob/.config/shell-prompt-setup ] || fail "config dirs left behind"
grep -q 'shell-prompt-setup' /home/ann/.bashrc /home/bob/.bashrc && fail "blocks left behind"
head -3 /home/bob/.bashrc | grep -q '^# ~/.bashrc' || fail "bob's original .bashrc content damaged"

echo "ALL POWERLINE TESTS PASSED"
