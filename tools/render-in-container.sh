#!/bin/bash
# Runs inside a Debian container (see render-examples.sh): installs both prompts with the real installers, stages
# a few situations and captures what each prompt really prints, as ANSI text, into /out/ansi plus /out/manifest.tsv
# (family | name | caption | host name to show | user name to show). Times, hosts and users are normalised afterwards.
export DEBIAN_FRONTEND=noninteractive
set -e
apt-get update -qq >/dev/null
apt-get install -y -qq curl ca-certificates zsh git python3 python3-venv procps iproute2 >/dev/null 2>&1
useradd -m -s /usr/bin/zsh alice; useradd -m -s /bin/bash pia; useradd -m -s /bin/bash pam
bash /repo/install.sh --users alice,root --shells zsh --vip 10.0.0.10 >/dev/null 2>&1
bash /repo/install-powerline.sh --users pia --plain-from 192.168.1.20 >/dev/null 2>&1
bash /repo/install-powerline.sh --users pam --backend powerline-shell --plain-from 192.168.1.20 >/dev/null 2>&1
set +e

# a git repo with changes, two commits ahead of its upstream, and a python project folder
for u in alice pia pam; do
  su $u -c 'set -e; cd ~; git init -q --bare origin.git; git clone -q origin.git project 2>/dev/null; cd project
    git config user.email a@b; git config user.name alice; git checkout -q -b main; mkdir -p src api
    echo x > src/app.py; echo "[project]" > api/pyproject.toml; git add -A; git commit -q -m init; git push -q -u origin main
    echo 1 >> src/app.py; git commit -qam c1; echo 2 >> src/app.py; git commit -qam c2; echo 3 >> src/app.py; echo new > src/notes.txt'
done
mkdir -p /opt/stacks /home/alice/pyapp && echo '[project]' > /home/alice/pyapp/pyproject.toml && chown -R alice /home/alice/pyapp
HOST=$(hostname)
mkdir -p /out/ansi; : > /out/manifest.tsv
SSH_CLIENT_ENV="SSH_CONNECTION='192.168.1.20 52311 192.168.1.30 22'"
LISTED_CLIENT="192.168.1.20 52311 192.168.1.30 22"

# rec FAMILY NAME CAPTION HOST USER  (the ANSI text comes on stdin)
rec() {
  cat > "/out/ansi/$1-$2.ans"
  printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5" >> /out/manifest.tsv
}
star() { su alice -c "cd $1 && env $2 zsh -i -c 'starship prompt $3'" 2>/dev/null; }

# ---- Starship (real zsh, the real prompt.sh)
star /home/alice/project/src "-u SSH_CONNECTION" "" | rec starship local "Your own machine: a git repo with changes, two commits ahead of its upstream" laptop alice
star /home/alice "$SSH_CLIENT_ENV" "" | rec starship ssh "Over ssh: orange frame and a square ssh block (the default)" webserver alice
star /home/alice "$SSH_CLIENT_ENV PROMPT_ROUND_BLOCK=powerline" "" | rec starship roundfull "Over ssh with --round-block powerline: a full-height rounded block (needs a font or terminal with the Powerline rounded caps U+E0B6/E0B4)" webserver alice
star /home/alice "$SSH_CLIENT_ENV PROMPT_ROUND_BLOCK=1" "" | rec starship round "Over ssh with --round-block: rounded ends from plain Unicode half circles, no patched font (drawn as shapes here; your terminal draws them with its own font)" webserver alice
ip addr add 10.0.0.10/32 dev lo
( cd /opt/stacks && env SSH_CONNECTION="$LISTED_CLIENT" LC_PROMPT_HOPS=2 PROMPT_ROUND_BLOCK=powerline zsh -i -c 'starship prompt --status 1 --cmd-duration 12000' 2>/dev/null ) | rec starship root "root, second ssh hop, on the host that holds the VIP, after a slow command that failed (rounded block)" docker-network-1 root
ip addr del 10.0.0.10/32 dev lo
star /home/alice/pyapp "-u SSH_CONNECTION" "--status 127" | rec starship python "A python project, command not found" laptop alice
star /home/alice "-u SSH_CONNECTION PROMPT_CORNERS=square" "" | rec starship square "Square corners (for fonts that draw the rounded ones unevenly)" laptop alice

# ---- Powerline, the powerline package (real bash, the real powerline.sh)
pl() { su pia -c "cd $1 && env $2 bash -i -c 'powerline-render shell left $3'" 2>/dev/null; }
pl /home/pia/project/src "-u SSH_CONNECTION" "" | rec powerline local "Powerline look (needs a Powerline-patched font); this package shows the host name only over ssh" laptop alice
pl /home/pia/project/src "-u SSH_CONNECTION" "--last-exit-code=1 --last-pipe-status=1" | rec powerline error "After a failed command" laptop alice
pl /home/pia/project/src "SSH_CONNECTION='$LISTED_CLIENT' SSH_CLIENT='192.168.1.20 52311 22'" "" | rec powerline plain "Over ssh from a client listed with --plain-from: glyph-free theme, and the host name shows" webserver alice

# ---- Powerline, powerline-shell (real bash, the real powerline-shell.sh)
# ps CWD SSH-ENV-ASSIGNMENT EXIT-CODE
ps() {
  xdg=$(su pam -c "env $2 bash -i -c 'echo \$SPS_PS_XDG'" 2>/dev/null | tail -1)
  su pam -c "cd $1 && XDG_CONFIG_HOME=$xdg /home/pam/.config/shell-prompt-setup/venv/bin/powerline-shell --shell bare $3" 2>/dev/null
}
ps /home/pam/project/src "-u SSH_CONNECTION" 0 | rec powerline-shell local "Powerline look (needs a Powerline-patched font)" laptop alice
ps /home/pam/project/src "-u SSH_CONNECTION" 1 | rec powerline-shell error "After a failed command (exit code segment)" laptop alice
ps /home/pam/project/src "SSH_CONNECTION='$LISTED_CLIENT'" 0 | rec powerline-shell plain "Plain mode, for an ssh client listed with --plain-from" webserver alice

# ---- normalise: fixed clock, readable host and user names
python3 - "$HOST" <<'PY'
import re, sys
host = sys.argv[1]
rows = [l.rstrip("\n").split("\t") for l in open("/out/manifest.tsv")]
for fam, name, cap, shown_host, shown_user in rows:
    p = "/out/ansi/%s-%s.ans" % (fam, name)
    t = open(p, encoding="utf-8").read()
    t = t.replace(host, shown_host)
    t = re.sub(r"(?<=[m\u00a0 ])(pia|pam)(?=[\u00a0 \x1b\n])", shown_user, t)
    # a fixed clock; only powerline-shell zero-pads its hour (%I), the others print 3:30
    hour = "03" if fam == "powerline-shell" else "3"
    t = re.sub(r"\b(\d{1,2}):(\d{2})([\u00a0 ])([AP]M)", lambda m: "%s:30%sPM" % (hour, m.group(3)), t)
    open(p, "w", encoding="utf-8").write(t)
PY
echo "captured: $(wc -l < /out/manifest.tsv) prompts"
