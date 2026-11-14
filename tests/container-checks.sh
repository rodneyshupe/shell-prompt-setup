#!/bin/bash
# Prompt-behaviour checks, run inside the test container by docker-test.sh after the installs.
# Needs: user alice installed with --square-from 10.9.9.9, git, starship.
fail() { echo "FAIL: $*"; exit 1; }
strip() { sed 's/%{[^}]*}//g;s/\x1b\[[0-9;]*m//g'; }
# prompt <env assignments> : first 2 prompt lines as alice, in the directory $DIR
prompt() { su alice -c "cd $DIR && env $1 zsh -i -c 'starship prompt'" 2>&1 | strip | grep -a -v '^$'; }

DIR=/home/alice
echo "--- 2d. corners: rounded by default, square for a listed client, rounded for others"
p=$(prompt "-u SSH_CONNECTION")                       ; echo "$p" | grep -q '^╭─' && echo "$p" | grep -q '^╰─' || fail "default corners not rounded: $p"
p=$(prompt "SSH_CONNECTION='10.9.9.9 51000 10.0.0.1 22'") ; echo "$p" | grep -q '^┌─' && echo "$p" | grep -q '^└─' || fail "listed client not square: $p"
p=$(prompt "SSH_CONNECTION='10.1.1.1 51000 10.0.0.1 22'") ; echo "$p" | grep -q '^╭─' || fail "unlisted client not rounded: $p"
p=$(prompt "-u SSH_CONNECTION PROMPT_CORNERS=square")      ; echo "$p" | grep -q '^┌─' || fail "PROMPT_CORNERS=square ignored: $p"

echo "--- 2e. ssh marker only in an ssh session"
p=$(prompt "-u SSH_CONNECTION")                       ; echo "$p" | grep -q ' ssh ' && fail "ssh tag shown locally: $p"
p=$(prompt "SSH_CONNECTION='10.1.1.1 51000 10.0.0.1 22'") ; echo "$p" | head -1 | grep -q ' ssh ' || fail "ssh tag missing in ssh session: $p"

echo "--- 2e2. orange frame and ssh block in an ssh session, blue frame locally"
raw() { su alice -c "cd $DIR && env $1 zsh -i -c 'starship prompt; true'" 2>&1; }
r=$(raw "SSH_CONNECTION='10.1.1.1 51000 10.0.0.1 22'")
echo "$r" | grep -a -q '38;5;208' || fail "no orange in an ssh session"
echo "$r" | grep -a -q '48;5;208' || fail "ssh block has no orange background"
echo "$r" | grep -a -q '1;34m' && fail "blue frame in an ssh session"
r=$(raw "-u SSH_CONNECTION")
echo "$r" | grep -a -q '1;34m' || fail "no blue frame locally"
echo "$r" | grep -a -q '208' && fail "orange locally"
[ -s /home/alice/.config/starship-ssh.toml ] || fail "starship-ssh.toml not installed"
[ "$(sed 's/bold blue/bold 208/g' /home/alice/.config/starship.toml)" = "$(cat /home/alice/.config/starship-ssh.toml)" ] || fail "ssh variant is not derived from starship.toml"

echo "--- 2g. ssh hop counter through a real sshd (default AcceptEnv LC_*): ssh, ssh2, and a hop without the counter"
apt-get install -y -qq openssh-server >/dev/null 2>&1 || fail "cannot install openssh-server"
mkdir -p /run/sshd; /usr/sbin/sshd || fail "sshd did not start"
su alice -c 'ssh-keygen -q -t ed25519 -N "" -f ~/.ssh/id_ed25519 && cat ~/.ssh/id_ed25519.pub >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys'
O="-o StrictHostKeyChecking=no -o BatchMode=yes -o LogLevel=ERROR"
cat > /tmp/h1.zsh <<'EOS'
print "LABEL=$PROMPT_SSH_LABEL HOPS=$PROMPT_HOPS"
EOS
cat > /tmp/h2.zsh <<EOS
ssh $O localhost 'zsh -i /tmp/h1.zsh'
EOS
cat > /tmp/top1.zsh <<EOS
ssh $O localhost 'zsh -i /tmp/h1.zsh'
EOS
cat > /tmp/top2.zsh <<EOS
ssh $O localhost 'zsh -i /tmp/h2.zsh'
EOS
cat > /tmp/top3.zsh <<EOS
command ssh $O localhost 'zsh -i /tmp/h1.zsh'
EOS
chmod 644 /tmp/h1.zsh /tmp/h2.zsh /tmp/top?.zsh
l1=$(su alice -c "zsh -i /tmp/top1.zsh" 2>&1 | grep -a -o 'LABEL=[a-z0-9]* HOPS=[0-9]*')
l2=$(su alice -c "zsh -i /tmp/top2.zsh" 2>&1 | grep -a -o 'LABEL=[a-z0-9]* HOPS=[0-9]*')
l3=$(su alice -c "zsh -i /tmp/top3.zsh" 2>&1 | grep -a -o 'LABEL=[a-z0-9]* HOPS=[0-9]*')
[ "$l1" = "LABEL=ssh HOPS=1" ]  || fail "one hop: expected 'LABEL=ssh HOPS=1', got [$l1]"
[ "$l2" = "LABEL=ssh2 HOPS=2" ] || fail "two hops: expected 'LABEL=ssh2 HOPS=2', got [$l2]"
[ "$l3" = "LABEL=ssh HOPS=1" ]  || fail "no counter sent: expected 'LABEL=ssh HOPS=1', got [$l3]"
pkill sshd; rm -f /tmp/h?.zsh /tmp/top?.zsh

echo "--- 2h. host name: frame blue locally, orange in an ssh session; root user name azure, other users cyan"
H=$(hostname)
r=$(raw "SSH_CONNECTION='10.1.1.1 51000 10.0.0.1 22'")
echo "$r" | grep -a -q "38;5;208m%}$H" || fail "host name not orange in an ssh session"
echo "$r" | grep -a -q '1;32m' && fail "green left in an ssh session"
r=$(raw "-u SSH_CONNECTION")
echo "$r" | grep -a -q "1;34m%}$H" || fail "host name not the frame blue locally"
echo "$r" | grep -a -q '1;32m' && fail "host name green locally"
echo "$r" | grep -a -q "38;5;208" && fail "orange locally"
echo "$r" | grep -a -q "36m%}alice" || fail "non-root user name not cyan"
rr=$(cd /root && env -u SSH_CONNECTION zsh -i -c 'starship prompt; true' 2>&1)
echo "$rr" | grep -a -q "38;5;39m%}root" || fail "root user name not azure: $(echo "$rr" | strip | head -2)"
echo "$rr" | grep -a -q '1;31m' && fail "red left in the root prompt"
rr=$(cd /root && env SSH_CONNECTION='10.1.1.1 51000 10.0.0.1 22' zsh -i -c 'starship prompt; true' 2>&1)
echo "$rr" | grep -a -q "38;5;39m%}root" || fail "root user name not azure over ssh"

echo "--- 2f. ahead/behind counts only above 1; nothing outside a repo or without an upstream"
W=/tmp/abtest; rm -rf $W; mkdir -p $W; chown alice $W
su alice -c "set -e; cd $W; git init -q --bare o.git; git clone -q o.git a 2>/dev/null
  git -C a config user.email t@t; git -C a config user.name t
  cd a; git checkout -q -b main; echo 0 > f; git add f; git commit -q -m c0; git push -q -u origin main
  cd ..; git clone -q -b main o.git b; git -C b config user.email t@t; git -C b config user.name t"
sync() { DIR=$W/a; prompt "-u SSH_CONNECTION" | head -1 | grep -a -o 'git [a-z-]*.*' | sed 's/ *$//'; }
[ "$(sync)" = "git main" ] || fail "in sync should show nothing, got [$(sync)]"
su alice -c "cd $W/a && echo 1 >> f && git commit -qam c1"
[ "$(sync)" = "git main >" ]  || fail "1 ahead should be '>', got [$(sync)]"
su alice -c "cd $W/a && for i in 2 3; do echo \$i >> f; git commit -qam c\$i; done"
[ "$(sync)" = "git main >3" ] || fail "3 ahead should be '>3', got [$(sync)]"
su alice -c "cd $W/a && git push -q origin main && cd ../b && git pull -q && echo x > g && git add g && git commit -qm d1 && git push -q origin main && cd ../a && git fetch -q"
[ "$(sync)" = "git main <" ]  || fail "1 behind should be '<', got [$(sync)]"
su alice -c "cd $W/b && echo y >> g && git commit -qam d2 && git push -q origin main && cd ../a && git fetch -q"
[ "$(sync)" = "git main <2" ] || fail "2 behind should be '<2', got [$(sync)]"
su alice -c "cd $W/a && echo z > h && git add h && git commit -qm e1"
[ "$(sync)" = "git main > <2" ] || fail "diverged should be '> <2', got [$(sync)]"
su alice -c "cd $W/a && git checkout -q -b local-only"
[ "$(sync)" = "git local-only" ] || fail "no upstream should show nothing, got [$(sync)]"
DIR=/tmp; p=$(prompt "-u SSH_CONNECTION" | head -1); echo "$p" | grep -q '│ *$' && fail "stray separator outside a repo: [$p]"
rm -rf $W
echo "prompt checks ok"
