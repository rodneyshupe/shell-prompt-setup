#!/bin/bash
# Runs inside the Debian test container as root (see docker-test.sh). Exercises the installer for bash and zsh
# users, and runs the same prompt checks against both shells.
# Env: REPO (the mounted repo, /repo), HTTP_BASE (a web server serving the repo, for the curl-style test).
export DEBIAN_FRONTEND=noninteractive
REPO=${REPO:-/repo}
fail() { echo "FAIL: $*"; exit 1; }
step() { echo "--- $*"; }
INSTALL="bash $REPO/install.sh"

apt-get update -qq >/dev/null && apt-get install -y -qq curl ca-certificates sudo iproute2 git openssh-server original-awk >/dev/null || fail "cannot install test tools"
command -v zsh >/dev/null && fail "the base image already has zsh; the bash-only checks need it absent"

useradd -m -s /bin/bash bob      # bash user (Debian skeleton .bashrc / .profile)
useradd -m -s /bin/bash pat      # will be a zsh user with an existing .zshrc
useradd -m -s /bin/bash zed      # will be a zsh user
useradd -m -s /bin/bash lou      # will be a zsh user with the old whole-file layout
useradd -m -s /bin/sh   shi      # unsupported login shell

# ----------------------------------------------------------------------------------------------
step "1. dry run changes nothing"
$INSTALL --users bob --dry-run >/tmp/dry.out 2>&1 || fail "dry run failed: $(tail -3 /tmp/dry.out)"
[ ! -e /home/bob/.config/shell-prompt-setup ] || fail "dry run created files"
grep -q "dry-run" /tmp/dry.out || fail "no dry-run output"
command -v starship >/dev/null && fail "dry run installed starship"

step "2. bash user, default: prompt only, in .bashrc, zsh not installed"
$INSTALL --users bob --vip 10.0.0.10 --square-from 10.9.9.9 --ssh-agent --round-block || fail "install for bob failed"
command -v starship >/dev/null || fail "starship not installed"
command -v zsh >/dev/null && fail "zsh was installed for a bash-only user"
D=/home/bob/.config/shell-prompt-setup
for f in prompt.sh starship.toml starship-ssh.toml settings.sh; do [ -s $D/$f ] || fail "bob missing $f"; done
[ ! -e $D/zsh-setup.zsh ] || fail "zsh setup installed for a bash user"
grep -q 'shell-prompt-setup: prompt >>>' /home/bob/.bashrc || fail "no prompt block in .bashrc"
grep -q 'shell-prompt-setup: agent >>>' /home/bob/.bashrc || fail "no agent block in .bashrc"
[ ! -e /home/bob/.zshrc ] || fail ".zshrc created for a bash user"
grep -q "PROMPT_VIP=10.0.0.10" $D/settings.sh && grep -q 'PROMPT_SQUARE_FROM="10.9.9.9"' $D/settings.sh || fail "settings.sh content"
grep -q "PROMPT_ROUND_BLOCK=1" $D/settings.sh || fail "--round-block not written to settings.sh"
[ "$(stat -c %U $D/prompt.sh)" = bob ] || fail "owner of installed files"
head -5 /home/bob/.bashrc | grep -q '^# ~/.bashrc' || fail "the original .bashrc content was not kept"
ls /home/bob/.bashrc.bak.* >/dev/null 2>&1 || fail "no backup of .bashrc"

step "3. --shells both on the bash user: zsh added, login shell unchanged"
$INSTALL --users bob --shells both --vip 10.0.0.10 --square-from 10.9.9.9 --ssh-agent || fail "install both for bob failed"
command -v zsh >/dev/null || fail "zsh not installed by --shells both"
grep -q 'shell-prompt-setup: zsh-setup >>>' /home/bob/.zshrc || fail "no zsh-setup block"
[ "$(grep -n 'shell-prompt-setup: prompt >>>' /home/bob/.zshrc | cut -d: -f1)" -lt "$(grep -n 'shell-prompt-setup: zsh-setup >>>' /home/bob/.zshrc | cut -d: -f1)" ] || fail "prompt block must come before the zsh-setup block"
grep -q 'shell-prompt-setup: zprofile >>>' /home/bob/.zprofile || fail "no zprofile block"
[ -s $D/zsh-setup.zsh ] || fail "zsh-setup.zsh missing"
[ "$(getent passwd bob | cut -d: -f7)" = /bin/bash ] || fail "login shell changed without --shell"
su bob -c "zsh -i -c 'echo \$ZSH_AUTOSUGGEST_STRATEGY'" 2>&1 | grep -q 'history completion' || fail "zsh setup not active for bob's zsh"

# zsh users
usermod -s /usr/bin/zsh zed; usermod -s /usr/bin/zsh pat; usermod -s /usr/bin/zsh lou

step "4. zsh user, default: prompt + zsh setup"
$INSTALL --users zed --vip 10.0.0.10 --square-from 10.9.9.9 --round-block || fail "install for zed failed"
Z=/home/zed/.config/shell-prompt-setup
[ -s $Z/zsh-setup.zsh ] && [ -s $Z/prompt.sh ] || fail "zed files"
grep -q 'shell-prompt-setup: zsh-setup >>>' /home/zed/.zshrc || fail "zed zsh-setup block"
[ ! -e /home/zed/.bashrc.bak.* ] 2>/dev/null; grep -q 'shell-prompt-setup' /home/zed/.bashrc && fail "bash rc touched for a zsh-only user"
su zed -c "zsh -i -c 'echo \$ZSH_AUTOSUGGEST_STRATEGY \$STARSHIP_SHELL'" 2>&1 | grep -q 'history completion zsh' || fail "zed: plugins or starship not loaded"

step "5. --prompt-only on an existing zsh setup: your content kept, no zsh setup"
printf '# pat own zshrc\nalias hello=world\nexport PAT_VAR=kept\n' > /home/pat/.zshrc; chown pat /home/pat/.zshrc
$INSTALL --users pat --prompt-only || fail "prompt-only for pat failed"
grep -q 'alias hello=world' /home/pat/.zshrc && grep -q 'PAT_VAR=kept' /home/pat/.zshrc || fail "pat's own .zshrc content lost"
grep -q 'shell-prompt-setup: prompt >>>' /home/pat/.zshrc || fail "no prompt block for pat"
grep -q 'zsh-setup' /home/pat/.zshrc && fail "zsh-setup block added with --prompt-only"
[ ! -e /home/pat/.config/shell-prompt-setup/zsh-setup.zsh ] || fail "zsh-setup.zsh installed with --prompt-only"
[ ! -e /home/pat/.zprofile ] || fail ".zprofile created with --prompt-only"
ls /home/pat/.zshrc.bak.* >/dev/null 2>&1 || fail "no backup of pat's .zshrc"
o=$(su pat -c "zsh -i -c 'echo S=\${STARSHIP_SHELL},P=\${ZSH_AUTOSUGGEST_STRATEGY},V=\${PAT_VAR}; whence -w hello'" 2>&1 | tr '\n' ' ')
echo "$o" | grep -q 'S=zsh,P=,V=kept' || fail "pat: expected starship on, plugins off, own settings kept: $o"
echo "$o" | grep -q 'hello: alias' || fail "pat's alias not active"
o=$(su pat -c "env SSH_CONNECTION='10.1.1.1 5 10.0.0.1 22' zsh -i -c 'starship prompt'" 2>&1 | sed 's/%{[^}]*}//g;s/\x1b\[[0-9;]*m//g')
echo "$o" | grep -q ' ssh ' && ! echo "$o" | grep -q '◖' || fail "without --round-block the ssh block must stay square: $o"

step "6. old whole-file layout is migrated (zshrc, zprofile, starship tomls, .zshrc.local block)"
L=/home/lou; mkdir -p $L/.config
cp $REPO/tests/fixtures/legacy/zshrc $L/.zshrc; cp $REPO/tests/fixtures/legacy/zprofile $L/.zprofile
cp $REPO/tests/fixtures/legacy/starship.toml $L/.config/starship.toml; cp $REPO/tests/fixtures/legacy/starship-ssh.toml $L/.config/starship-ssh.toml
cat > $L/.zshrc.local <<'EOS'
alias mine=1
# >>> shell-prompt-setup (managed block; re-run install.sh to refresh) >>>
# Show [VIP] in the prompt while this host holds this address.
export PROMPT_VIP=10.0.0.10
# Square corners for ssh sessions coming from these client addresses (font workaround).
PROMPT_SQUARE_FROM="10.9.9.9 10.9.9.8"
# ssh-agent with the GitHub keys, unless one is already available (e.g. forwarded).
# Only an agent started here is stopped when the shell exits.
if [[ -z $SSH_AUTH_SOCK ]]; then
  eval "$(ssh-agent -s)" >/dev/null
  ssh-add -k ~/.ssh/github*.key(N) >/dev/null 2>&1
  _zshrc_started_agent=1
fi
zshexit() { [[ -n $_zshrc_started_agent ]] && eval "$(ssh-agent -k)" >/dev/null 2>&1 }
# <<< shell-prompt-setup <<<
EOS
chown -R lou $L
$INSTALL --users lou || fail "migration for lou failed"
grep -q 'Managed by shell-prompt-setup' $L/.zshrc && fail "old whole-file .zshrc still there"
grep -q 'shell-prompt-setup: zsh-setup >>>' $L/.zshrc && grep -q 'shell-prompt-setup: agent >>>' $L/.zshrc || fail "lou: blocks after migration"
grep -q 'shell-prompt-setup: zprofile >>>' $L/.zprofile || fail "lou: zprofile block"
grep -q '^# ~/.zprofile: login shells' $L/.zprofile && fail "old zprofile text kept"
[ ! -e $L/.config/starship.toml ] && [ ! -e $L/.config/starship-ssh.toml ] || fail "old starship tomls not moved aside"
ls $L/.config/starship.toml.bak.* >/dev/null 2>&1 || fail "no backup of the old starship.toml"
grep -q 'PROMPT_VIP=10.0.0.10' $L/.config/shell-prompt-setup/settings.sh && grep -q 'PROMPT_SQUARE_FROM="10.9.9.9 10.9.9.8"' $L/.config/shell-prompt-setup/settings.sh || fail "old VIP / square settings not carried over"
grep -q 'shell-prompt-setup (managed block' $L/.zshrc.local && fail "old .zshrc.local block not removed"
grep -q '^alias mine=1' $L/.zshrc.local || fail "user's own .zshrc.local content lost"
su lou -c "zsh -i -c 'echo \$PROMPT_VIP \$ZSH_AUTOSUGGEST_STRATEGY'" 2>&1 | grep -q '10.0.0.10 history completion' || fail "lou: migrated setup not working"

step "7. idempotent re-run; our files are not clobbered without --force"
before=$(cd /home && sha256sum bob/.bashrc bob/.zshrc zed/.zshrc zed/.config/shell-prompt-setup/* | sha256sum)
$INSTALL --users bob --shells both --vip 10.0.0.10 --square-from 10.9.9.9 --ssh-agent >/tmp/re1.out || fail "re-run failed"
$INSTALL --users zed --vip 10.0.0.10 --square-from 10.9.9.9 >/tmp/re2.out || fail "re-run failed"
after=$(cd /home && sha256sum bob/.bashrc bob/.zshrc zed/.zshrc zed/.config/shell-prompt-setup/* | sha256sum)
[ "$before" = "$after" ] || fail "a re-run changed files"
grep -c "already up to date" /tmp/re1.out | grep -qv '^0$' || fail "re-run not reported as up to date"
echo "# hand edit" >> $Z/starship.toml
$INSTALL --users zed >/tmp/nc.out 2>&1 && fail "expected a non-zero exit when a file differs"
grep -q '# hand edit' $Z/starship.toml || fail "differing file overwritten without --force"
$INSTALL --users zed --force >/dev/null 2>&1 || fail "--force failed"
grep -q '# hand edit' $Z/starship.toml && fail "--force did not replace"
ls $Z/starship.toml.bak.* >/dev/null 2>&1 || fail "no backup from --force"

step "8. --shell changes the login shell, only after the zsh test"
$INSTALL --users bob --shell --vip 10.0.0.10 --square-from 10.9.9.9 --ssh-agent || fail "--shell failed"
[ "$(getent passwd bob | cut -d: -f7)" = /usr/bin/zsh ] || fail "bob's login shell not zsh"
usermod -s /bin/bash bob   # back to bash for the bash checks below

step "9. unsupported login shell is reported; --shells bash handles it; unknown user is not fatal"
$INSTALL --users shi --no-packages >/tmp/sh.out 2>&1 && fail "expected non-zero for an unsupported login shell"
grep -q "not zsh or bash" /tmp/sh.out || fail "no message for the unsupported login shell"
$INSTALL --users shi --shells bash --no-packages >/dev/null 2>&1 || fail "--shells bash for /bin/sh user failed"
$INSTALL --users nosuchuser,zed --no-packages >/dev/null 2>&1 && fail "expected non-zero for an unknown user"

step "10. curl-style: piped to bash, files downloaded"
useradd -m -s /bin/bash carol
curl -fsSL "$HTTP_BASE/install.sh" | bash -s -- --users carol --base-url "$HTTP_BASE" || fail "curl-style install failed"
[ -s /home/carol/.config/shell-prompt-setup/prompt.sh ] && grep -q 'shell-prompt-setup: prompt >>>' /home/carol/.bashrc || fail "curl-style result"

step "10b. --round-block powerline: full-height Powerline caps; invalid style rejected"
useradd -m -s /bin/bash cap
$INSTALL --users cap --round-block powerline --square-from 10.9.9.9 --no-packages >/dev/null || fail "--round-block powerline failed"
grep -q 'PROMPT_ROUND_BLOCK=powerline' /home/cap/.config/shell-prompt-setup/settings.sh || fail "style not written to settings.sh"
o=$(su cap -c "env SSH_CONNECTION='10.1.1.1 5 10.0.0.1 22' bash -i -c 'starship prompt'" 2>&1)
echo "$o" | grep -a -q "$(printf '\xee\x82\xb6')" && echo "$o" | grep -a -q "$(printf '\xee\x82\xb4')" || fail "Powerline caps missing for an unlisted ssh client"
echo "$o" | grep -a -q "$(printf '\xe2\x97\x96')" && fail "half circles shown together with the Powerline caps"
o=$(su cap -c "env SSH_CONNECTION='10.9.9.9 5 10.0.0.1 22' bash -i -c 'starship prompt'" 2>&1)
echo "$o" | grep -a -q "$(printf '\xee\x82\xb6')" && fail "a listed (square) client got the Powerline caps"
$INSTALL --users cap --round-block=nonsense --no-packages >/dev/null 2>&1 && fail "expected an error for an invalid --round-block style"

step "10c. settings.sh with a BSD-style awk (macOS's awk is not GNU/mawk): create, update in place, keep the other settings"
mkdir -p /tmp/bsdawk && ln -sf "$(command -v original-awk)" /tmp/bsdawk/awk
useradd -m -s /bin/bash bsd
BSD="env PATH=/tmp/bsdawk:$PATH bash $REPO/install.sh"
$BSD --users bsd --vip 10.0.0.10 --square-from 10.9.9.9 --round-block powerline --no-packages >/dev/null || fail "bsd awk: first install failed"
grep -q 'PROMPT_ROUND_BLOCK=powerline' /home/bsd/.config/shell-prompt-setup/settings.sh || fail "bsd awk: settings missing after the first install"
$BSD --users bsd --round-block halfcircle --no-packages >/dev/null || fail "bsd awk: update failed"
S=/home/bsd/.config/shell-prompt-setup/settings.sh
[ "$(grep -c '^export' $S)" = 3 ] || fail "bsd awk: expected 3 settings, got: $(cat $S)"
grep -q 'PROMPT_VIP=10.0.0.10' $S && grep -q 'PROMPT_SQUARE_FROM="10.9.9.9"' $S || fail "bsd awk: the other settings were lost: $(cat $S)"
grep -q 'PROMPT_ROUND_BLOCK=halfcircle' $S && ! grep -q 'PROMPT_ROUND_BLOCK=powerline' $S || fail "bsd awk: the setting was not updated in place"
[ "$(grep -n 'PROMPT_ROUND_BLOCK' $S | cut -d: -f1)" = 4 ] || fail "bsd awk: the update moved the setting: $(cat $S)"

step "12. an rc that already loads another prompt by hand: refused, or (--force) the standard snippets are removed"
useradd -m -s /bin/bash nod; useradd -m -s /bin/bash dby; useradd -m -s /bin/bash hnd
# nod: the powerline-shell snippet exactly as found on the Proxmox nodes
cat >> /home/nod/.bashrc <<'EOS'
# Some more alias to avoid making mistakes:
# alias rm='rm -i'
#!/usr/bin/env bash
function _update_ps1() {
    PS1=$(powerline-shell $?)
}

if [[ $TERM != linux && ! $PROMPT_COMMAND =~ _update_ps1 ]]; then
    PROMPT_COMMAND="_update_ps1; $PROMPT_COMMAND"
fi
EOS
# dby: the standard Debian Powerline block
cat >> /home/dby/.bashrc <<'EOS'

# Powerline configuration
if [ -f /usr/share/powerline/bindings/bash/powerline.sh ]; then
  powerline-daemon -q
  POWERLINE_BASH_CONTINUATION=1
  POWERLINE_BASH_SELECT=1
  source /usr/share/powerline/bindings/bash/powerline.sh
fi
alias keepme=1
EOS
# hnd: a hand-written starship init, which is never removed
printf '\neval "$(starship init bash)"\nalias keepme=1\n' >> /home/hnd/.bashrc
chown nod:nod /home/nod/.bashrc; chown dby:dby /home/dby/.bashrc; chown hnd:hnd /home/hnd/.bashrc
for u in nod dby hnd; do cp /home/$u/.bashrc /tmp/$u.bashrc; done
# cmt: the same snippets, but commented out: nothing to conflict with, so no refusal and nothing removed
useradd -m -s /bin/bash cmt
cat >> /home/cmt/.bashrc <<'EOS'
#function _update_ps1() {
#    PS1=$(powerline-shell $?)
#}
# eval "$(starship init bash)"
EOS
chown cmt:cmt /home/cmt/.bashrc; cp /home/cmt/.bashrc /tmp/cmt.bashrc


$INSTALL --users nod >/tmp/nod.out 2>&1 && fail "expected a non-zero exit when .bashrc already loads another prompt"
grep -q "already loads another prompt" /tmp/nod.out || fail "no explanation: $(tail -3 /tmp/nod.out)"
cmp -s /tmp/nod.bashrc /home/nod/.bashrc || fail "nod's .bashrc changed although the installer refused"
$INSTALL --users nod --force >/dev/null 2>&1 || fail "--force failed for nod"
grep -q -E '_update_ps1|powerline-shell' /home/nod/.bashrc && fail "the powerline-shell snippet was not removed: $(grep -n -E '_update_ps1|powerline-shell' /home/nod/.bashrc)"
grep -q "alias rm='rm -i'" /home/nod/.bashrc || fail "nod's other lines were damaged"
[ "$(grep -c 'shell-prompt-setup: prompt >>>' /home/nod/.bashrc)" = 1 ] || fail "our block missing after --force"
ls /home/nod/.bashrc.bak.* >/dev/null 2>&1 || fail "no backup before removing the snippet"
o=$(su nod -c "bash -i -c 'echo S=\$STARSHIP_SHELL; echo PC=\$PROMPT_COMMAND'" 2>&1)
echo "$o" | grep -q 'S=bash' || fail "nod: starship not active after --force: $o"
echo "$o" | grep -q '_update_ps1' && fail "nod: the old prompt function is still in PROMPT_COMMAND"

$INSTALL --users dby --force >/dev/null 2>&1 || fail "--force failed for dby"
grep -q '^# Powerline configuration' /home/dby/.bashrc && fail "the Debian Powerline block was not removed"
grep -q 'alias keepme=1' /home/dby/.bashrc || fail "dby's own line after the block was removed"
[ "$(grep -c 'shell-prompt-setup: prompt >>>' /home/dby/.bashrc)" = 1 ] || fail "dby: our block missing"

$INSTALL --users cmt >/tmp/cmt.out 2>&1 || fail "commented-out prompt lines must not block the install: $(tail -3 /tmp/cmt.out)"
grep -q '^#function _update_ps1' /home/cmt/.bashrc && grep -q 'shell-prompt-setup: prompt >>>' /home/cmt/.bashrc || fail "cmt: commented lines should stay and our block be added"
$INSTALL --users hnd --force >/tmp/hnd.out 2>&1 && fail "expected a refusal for a hand-written starship init, even with --force"
cmp -s /tmp/hnd.bashrc /home/hnd/.bashrc || fail "a hand-written starship init was touched"
grep -q "already loads another prompt" /tmp/hnd.out || fail "no explanation for the hand-written init"

# ----------------------------------------------------------------------------------------------
# Prompt behaviour, the same checks in bash (bob) and zsh (zed).
H=$(hostname)
strip()  { sed 's/%{[^}]*}//g;s/\\\[//g;s/\\\]//g;s/\x1b\[[0-9;]*m//g'; }
unwrap() { sed 's/%{//g;s/%}//g;s/\\\[//g;s/\\\]//g'; }
# raw <user> <shell> <env assignments> [dir]: the prompt as that shell renders it (escapes kept)
raw()    { su "$1" -c "cd ${4:-/home/$1} && env $3 $2 -i -c 'starship prompt; true'" 2>&1 | unwrap | grep -a -v -e '^bash: ' -e 'no job control'; }
txt()    { raw "$@" | sed 's/\x1b\[[0-9;]*m//g' | grep -a -v '^$'; }
SSHENV="SSH_CONNECTION='10.1.1.1 51000 10.0.0.1 22'"

checks() {
  local u=$1 sh=$2 r p w
  step "$sh: starship is active and the config is the project's"
  [ "$(su $u -c "env -u SSH_CONNECTION $sh -i -c 'echo \$STARSHIP_SHELL'" 2>&1 | tail -1)" = "$sh" ] || fail "$sh: STARSHIP_SHELL not set"
  r=$(su $u -c "env -u SSH_CONNECTION $sh -i -c 'echo \$STARSHIP_CONFIG'" 2>&1 | tail -1)
  [ "$r" = "/home/$u/.config/shell-prompt-setup/starship.toml" ] || fail "$sh: local config is [$r]"
  r=$(su $u -c "env $SSHENV $sh -i -c 'echo \$STARSHIP_CONFIG'" 2>&1 | tail -1)
  [ "$r" = "/home/$u/.config/shell-prompt-setup/starship-ssh.toml" ] || fail "$sh: ssh config is [$r]"
  w=$(su $u -c "env -u SSH_CONNECTION $sh -i -c 'starship prompt; true' 2>&1 >/dev/null | grep -a -c WARN")
  [ "$w" = 0 ] || fail "$sh: starship warnings"

  step "$sh: corners (rounded; square for a listed client; PROMPT_CORNERS=square)"
  p=$(txt $u $sh "-u SSH_CONNECTION");                                   echo "$p" | grep -q '^╭─' && echo "$p" | grep -q '^╰─' || fail "$sh: default corners: $p"
  p=$(txt $u $sh "SSH_CONNECTION='10.9.9.9 5 10.0.0.1 22'");             echo "$p" | grep -q '^┌─' && echo "$p" | grep -q '^└─' || fail "$sh: listed client not square: $p"
  p=$(txt $u $sh "$SSHENV");                                             echo "$p" | grep -q '^╭─' || fail "$sh: unlisted client not rounded: $p"
  p=$(txt $u $sh "-u SSH_CONNECTION PROMPT_CORNERS=square");             echo "$p" | grep -q '^┌─' || fail "$sh: PROMPT_CORNERS=square ignored: $p"

  step "$sh: ssh block, depth label, colors"
  p=$(txt $u $sh "-u SSH_CONNECTION");                                   echo "$p" | grep -q ' ssh' && fail "$sh: ssh block shown locally: $p"
  p=$(txt $u $sh "$SSHENV" | head -1);                                   echo "$p" | grep -q ' ssh ' || fail "$sh: no ssh block over ssh: $p"
  p=$(txt $u $sh "$SSHENV LC_PROMPT_HOPS=3" | head -1);                  echo "$p" | grep -q ' ssh3 ' || fail "$sh: no ssh3 label: $p"
  p=$(txt $u $sh "$SSHENV LC_PROMPT_HOPS=x" | head -1);                  echo "$p" | grep -q ' ssh ' || fail "$sh: junk counter not ignored: $p"
  r=$(raw $u $sh "$SSHENV")
  echo "$r" | grep -a -q '38;5;208' && echo "$r" | grep -a -q '48;5;208;38;5;16' || fail "$sh: ssh block not black on orange"
  echo "$r" | grep -a -q "38;5;208m$H" || fail "$sh: host name not orange over ssh"
  echo "$r" | grep -a -q '38;5;34m' && fail "$sh: green left over ssh"
  r=$(raw $u $sh "-u SSH_CONNECTION")
  echo "$r" | grep -a -q "38;5;34m$H" || fail "$sh: local host name not the frame green"
  echo "$r" | grep -a -q '38;5;208' && fail "$sh: orange locally"
  echo "$r" | grep -a -q "36m$u" || fail "$sh: user name not cyan"

  step "$sh: rounded ssh block (opt-in, installed with --round-block): half circles, but not for a listed client or locally"
  p=$(txt $u $sh "$SSHENV" | head -1);                                    echo "$p" | grep -q '◖ ssh ◗' || fail "$sh: no rounded ends on the ssh block: $p"
  p=$(txt $u $sh "$SSHENV LC_PROMPT_HOPS=3" | head -1);                   echo "$p" | grep -q '◖ ssh3 ◗' || fail "$sh: ssh3 block not rounded: $p"
  r=$(raw $u $sh "$SSHENV");                                              echo "$r" | grep -a -q '38;5;208m◖' && echo "$r" | grep -a -q '38;5;208m◗' || fail "$sh: the caps are not orange"
  p=$(txt $u $sh "SSH_CONNECTION='10.9.9.9 5 10.0.0.1 22'" | head -1);    echo "$p" | grep -q '◖' && fail "$sh: a listed (square) client got rounded ends: $p"
  p=$(txt $u $sh "$SSHENV PROMPT_CORNERS=square" | head -1);              echo "$p" | grep -q '◖' && fail "$sh: PROMPT_CORNERS=square still rounded the block: $p"
  p=$(txt $u $sh "-u SSH_CONNECTION" | head -1);                          echo "$p" | grep -q '◖\|◗' && fail "$sh: caps shown locally: $p"

  step "$sh: hop counter through a real sshd (ssh, ssh2, no counter)"
  local O="-o StrictHostKeyChecking=no -o BatchMode=yes -o LogLevel=ERROR" ext=sh
  [ "$sh" = zsh ] && ext=zsh
  printf 'print_it() { echo "LABEL=$PROMPT_SSH_LABEL HOPS=$PROMPT_HOPS"; }\nprint_it\n' > /tmp/h1.$ext
  printf "ssh $O localhost '$sh -i /tmp/h1.$ext'\n" > /tmp/h2.$ext
  printf "ssh $O localhost '$sh -i /tmp/h2.$ext'\n" > /tmp/top2.$ext
  printf "ssh $O localhost '$sh -i /tmp/h1.$ext'\n" > /tmp/top1.$ext
  printf "command ssh $O localhost '$sh -i /tmp/h1.$ext'\n" > /tmp/top3.$ext
  chmod 644 /tmp/h1.$ext /tmp/h2.$ext /tmp/top?.$ext
  local l1 l2 l3
  l1=$(su $u -c "$sh -i /tmp/top1.$ext" 2>&1 | grep -a -o 'LABEL=[a-z0-9]* HOPS=[0-9]*' | tail -1)
  l2=$(su $u -c "$sh -i /tmp/top2.$ext" 2>&1 | grep -a -o 'LABEL=[a-z0-9]* HOPS=[0-9]*' | tail -1)
  l3=$(su $u -c "$sh -i /tmp/top3.$ext" 2>&1 | grep -a -o 'LABEL=[a-z0-9]* HOPS=[0-9]*' | tail -1)
  [ "$l1" = "LABEL=ssh HOPS=1" ]  || fail "$sh: one hop: [$l1]"
  [ "$l2" = "LABEL=ssh2 HOPS=2" ] || fail "$sh: two hops: [$l2]"
  [ "$l3" = "LABEL=ssh HOPS=1" ]  || fail "$sh: no counter sent: [$l3]"

  step "$sh: ahead/behind counts only above 1; nothing outside a repo or without an upstream"
  local W=/tmp/ab-$sh
  rm -rf $W; mkdir -p $W; chown $u $W
  su $u -c "set -e; cd $W; git init -q --bare o.git; git clone -q o.git a 2>/dev/null; git -C a config user.email t@t; git -C a config user.name t
    cd a; git checkout -q -b main; echo 0 > f; git add f; git commit -q -m c0; git push -q -u origin main
    cd ..; git clone -q -b main o.git b; git -C b config user.email t@t; git -C b config user.name t"
  sync() { txt $u $sh "-u SSH_CONNECTION" $W/a | head -1 | grep -a -o 'git [a-z-]*.*' | sed 's/ *$//'; }
  [ "$(sync)" = "git main" ]  || fail "$sh: in sync should show nothing, got [$(sync)]"
  su $u -c "cd $W/a && echo 1 >> f && git commit -qam c1";  [ "$(sync)" = "git main >" ]   || fail "$sh: 1 ahead: [$(sync)]"
  su $u -c "cd $W/a && for i in 2 3; do echo \$i >> f; git commit -qam c\$i; done"; [ "$(sync)" = "git main >3" ] || fail "$sh: 3 ahead: [$(sync)]"
  su $u -c "cd $W/a && git push -q origin main && cd ../b && git pull -q && echo x > g && git add g && git commit -qm d1 && git push -q origin main && cd ../a && git fetch -q"
  [ "$(sync)" = "git main <" ]  || fail "$sh: 1 behind: [$(sync)]"
  su $u -c "cd $W/b && echo y >> g && git commit -qam d2 && git push -q origin main && cd ../a && git fetch -q"
  [ "$(sync)" = "git main <2" ] || fail "$sh: 2 behind: [$(sync)]"
  su $u -c "cd $W/a && echo z > h && git add h && git commit -qm e1"; [ "$(sync)" = "git main > <2" ] || fail "$sh: diverged: [$(sync)]"
  su $u -c "cd $W/a && git checkout -q -b local-only"; [ "$(sync)" = "git local-only" ] || fail "$sh: no upstream: [$(sync)]"
  p=$(txt $u $sh "-u SSH_CONNECTION" /tmp | head -1); echo "$p" | grep -q '│ *$' && fail "$sh: stray separator outside a repo: [$p]"
  rm -rf $W

  step "$sh: VIP block (black on green) follows the address, rounded like the ssh block over ssh"
  p=$(txt $u $sh "-u SSH_CONNECTION" | head -1); echo "$p" | grep -q ' VIP ' && fail "$sh: VIP shown without the address: $p"
  if ip addr add 10.0.0.10/32 dev lo 2>/dev/null; then
    p=$(txt $u $sh "-u SSH_CONNECTION" | head -1)
    echo "$p" | grep -q ' VIP ' || fail "$sh: VIP not shown while held: $p"
    echo "$p" | grep -q '◖' && fail "$sh: caps on the VIP block in a local shell: $p"
    r=$(raw $u $sh "-u SSH_CONNECTION"); echo "$r" | grep -a -q '48;5;40;38;5;16' || fail "$sh: the VIP block is not black on green"
    echo "$r" | grep -a -q '33m.*VIP' && fail "$sh: the VIP is still yellow"
    p=$(txt $u $sh "$SSHENV" | head -1);                                  echo "$p" | grep -q '◖ VIP ◗' || fail "$sh: the VIP block is not rounded over ssh: $p"
    r=$(raw $u $sh "$SSHENV");                                            echo "$r" | grep -a -q '38;5;40m◖' || fail "$sh: the VIP caps are not green"
    p=$(txt $u $sh "SSH_CONNECTION='10.9.9.9 5 10.0.0.1 22'" | head -1);  echo "$p" | grep -q ' VIP ' && ! echo "$p" | grep -q '◖ VIP' || fail "$sh: a listed (square) client must get the square VIP block: $p"
    ip addr del 10.0.0.10/32 dev lo
  else echo "(skipped: cannot add an address in this container)"; fi
}

# sshd for the hop tests (default Debian AcceptEnv LANG LC_*)
mkdir -p /run/sshd; /usr/sbin/sshd || fail "sshd did not start"
for u in bob zed; do
  su $u -c 'ssh-keygen -q -t ed25519 -N "" -f ~/.ssh/id_ed25519 && cat ~/.ssh/id_ed25519.pub >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys'
done

checks bob bash
checks zed zsh

step "root: magenta user name in both shells (not red)"
$INSTALL --users root --shells both >/dev/null || fail "root install failed"
for sh in bash zsh; do
  r=$(cd /root && env -u SSH_CONNECTION $sh -i -c 'starship prompt; true' 2>&1 | unwrap)
  echo "$r" | grep -a -q "38;5;207mroot" || fail "$sh: root user name not magenta"
  echo "$r" | grep -a -q '1;31m' && fail "$sh: red left in the root prompt: $(echo "$r" | cat -v | head -5)"
done

step "admin-group member: gold user name (docker counts), cyan again outside the groups, PROMPT_PRIV_GROUPS overrides"
groupadd -f docker; usermod -aG docker bob
for sh in bash zsh; do
  r=$(raw bob $sh "-u SSH_CONNECTION")
  echo "$r" | grep -a -q "38;5;178mbob" || fail "$sh: docker member not gold"
  r=$(raw bob $sh "-u SSH_CONNECTION PROMPT_PRIV_GROUPS=wheel")
  echo "$r" | grep -a -q "36mbob" || fail "$sh: PROMPT_PRIV_GROUPS override ignored"
done
r=$(raw zed zsh "-u SSH_CONNECTION")
echo "$r" | grep -a -q "36mzed" || fail "zsh: user outside the groups not cyan"
gpasswd -d bob docker >/dev/null

step "11. --uninstall removes only what the installer added"
$INSTALL --users pat --uninstall >/dev/null || fail "uninstall failed"
grep -q 'shell-prompt-setup' /home/pat/.zshrc && fail "blocks left in pat's .zshrc"
grep -q 'alias hello=world' /home/pat/.zshrc && grep -q 'PAT_VAR=kept' /home/pat/.zshrc || fail "pat's own content damaged by uninstall"
[ ! -e /home/pat/.config/shell-prompt-setup ] || fail "config dir left behind"
[ "$(getent passwd pat | cut -d: -f7)" = /usr/bin/zsh ] || fail "uninstall changed the login shell"
$INSTALL --users bob --uninstall >/dev/null; grep -q 'shell-prompt-setup' /home/bob/.bashrc /home/bob/.zshrc /home/bob/.zprofile && fail "bob: blocks left"
head -3 /home/bob/.bashrc | grep -q '^# ~/.bashrc' || fail "bob's original .bashrc content damaged"

echo "ALL TESTS PASSED"
