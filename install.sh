#!/usr/bin/env bash
#
# shell-prompt-setup: zsh + Starship prompt (plain-text symbols, no special font needed),
# autosuggestions, syntax highlighting and better path completion.
#
#   curl -fsSL https://raw.githubusercontent.com/rodneyshupe/shell-prompt-setup/main/install.sh | bash
#   curl -fsSL .../install.sh | sudo bash -s -- --users alice,bob --shell
#
# Run `install.sh --help` for all options. Works from a clone (uses ./config) or piped from
# curl (downloads ./config files from --base-url). No user names are built in: pass them with
# --users. Existing dotfiles that differ are never overwritten unless you pass --force
# (they are then saved as <file>.bak.<timestamp>).

# --- debug (uncomment to trace) ---
# set -x
set -u

REPO_RAW="https://raw.githubusercontent.com/rodneyshupe/shell-prompt-setup/main"
BASE_URL=$REPO_RAW
USERS_ARG=""
SET_SHELL=0
SSH_AGENT=0
VIP=""
SQUARE_FROM=""
DO_PACKAGES=1
FORCE=0
DRY=0
RC=0

usage() {
  cat <<'USAGE'
Usage: install.sh [options]

  --users u1,u2    Users to set up (default: the user running the script). Setting up other
                   users than yourself needs root.
  --shell          Make zsh the login shell of those users (chsh), only after a zsh login
                   test passed for that user. Roll back with: chsh -s /bin/bash <user>
  --ssh-agent      Add an ssh-agent block to ~/.zshrc.local (loads ~/.ssh/github*.key unless
                   an agent is already available, e.g. forwarded; stops only its own agent).
  --vip ADDRESS    Show a [VIP] marker in the prompt while this host holds ADDRESS
                   (keepalived etc.); written as PROMPT_VIP to ~/.zshrc.local.
  --square-from IP[,IP...]
                   Use square corners (┌─ └─) instead of rounded for ssh sessions whose client
                   address is in the list (a browser SSH terminal whose font draws the rounded
                   ones unevenly, for instance); written as PROMPT_SQUARE_FROM to ~/.zshrc.local.
  --no-packages    Do not install packages (zsh starship zsh-autosuggestions
                   zsh-syntax-highlighting); only place the config files.
  --force          Overwrite differing files (backup kept as <file>.bak.<timestamp>).
  --dry-run        Show what would be done, change nothing.
  --base-url URL   Where to download config/ from when not run from a clone
                   (default: the main branch on GitHub).
  -h, --help       This text.

Files placed per user: ~/.zshrc, ~/.config/starship.toml, ~/.config/starship-ssh.toml, ~/.zprofile (Linux only), and
~/.zshrc.local when --ssh-agent, --vip or --square-from is given (managed block only; rest of the file kept).
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --users)       USERS_ARG=${2:?--users needs a value}; shift 2 ;;
    --users=*)     USERS_ARG=${1#*=}; shift ;;
    --shell)       SET_SHELL=1; shift ;;
    --ssh-agent)   SSH_AGENT=1; shift ;;
    --vip)         VIP=${2:?--vip needs an address}; shift 2 ;;
    --vip=*)       VIP=${1#*=}; shift ;;
    --square-from) SQUARE_FROM=${2:?--square-from needs addresses}; shift 2 ;;
    --square-from=*) SQUARE_FROM=${1#*=}; shift ;;
    --no-packages) DO_PACKAGES=0; shift ;;
    --force)       FORCE=1; shift ;;
    --dry-run)     DRY=1; shift ;;
    --base-url)    BASE_URL=${2:?--base-url needs a value}; shift 2 ;;
    --base-url=*)  BASE_URL=${1#*=}; shift ;;
    -h|--help)     usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

say()  { printf '%s\n' "$*"; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
# Run a command, or only print it with --dry-run.
run()  { if [ "$DRY" = 1 ]; then say "[dry-run] $*"; else "$@"; fi; }

case "$(uname -s)" in
  Darwin) OS=mac ;;
  Linux)  OS=linux ;;
  *) die "unsupported OS: $(uname -s)" ;;
esac
ME=$(id -un)
IS_ROOT=0; [ "$(id -u)" = 0 ] && IS_ROOT=1

if [ -n "$VIP" ]; then
  case "$VIP" in *[!0-9.]*|"") die "--vip must be an IPv4 address, got '$VIP'" ;; esac
fi

SQUARE_LIST=""
if [ -n "$SQUARE_FROM" ]; then
  case "$SQUARE_FROM" in *[!0-9.:,a-fA-F]*|"") die "--square-from must be a comma-separated list of IP addresses, got '$SQUARE_FROM'" ;; esac
  SQUARE_LIST=$(printf '%s' "$SQUARE_FROM" | tr ',' ' ')
fi

# ---- where the config files come from ---------------------------------------------------
SRC=""
SELF="${BASH_SOURCE[0]:-}"
if [ -n "$SELF" ] && [ -f "$SELF" ]; then
  d=$(cd "$(dirname "$SELF")" && pwd)
  [ -f "$d/config/zshrc" ] && SRC="$d/config"
fi
if [ -z "$SRC" ]; then
  SRC=$(mktemp -d "${TMPDIR:-/tmp}/shell-prompt-setup.XXXXXX") || die "cannot create a temp dir"
  trap 'rm -rf "$SRC"' EXIT
  for f in zshrc zprofile starship.toml; do
    if command -v curl >/dev/null 2>&1; then
      curl -fsSL "$BASE_URL/config/$f" -o "$SRC/$f" || die "download failed: $BASE_URL/config/$f"
    elif command -v wget >/dev/null 2>&1; then
      wget -q -O "$SRC/$f" "$BASE_URL/config/$f" || die "download failed: $BASE_URL/config/$f"
    else
      die "need curl or wget to download the config files"
    fi
  done
fi

# ---- packages ----------------------------------------------------------------------------
install_packages() {
  local missing="" p
  if [ "$OS" = mac ]; then
    command -v brew >/dev/null 2>&1 || { warn "Homebrew not found; install packages yourself: starship zsh-autosuggestions zsh-syntax-highlighting"; return; }
    [ "$IS_ROOT" = 1 ] && { warn "brew refuses to run as root; run this script as your normal user"; return; }
    for p in starship zsh-autosuggestions zsh-syntax-highlighting; do
      brew list --formula "$p" >/dev/null 2>&1 || missing="$missing $p"
    done
    [ -z "$missing" ] && { say "Packages already installed."; return; }
    run brew install $missing
  else
    command -v apt-get >/dev/null 2>&1 || { warn "apt-get not found; install zsh starship zsh-autosuggestions zsh-syntax-highlighting yourself"; return; }
    for p in zsh starship zsh-autosuggestions zsh-syntax-highlighting; do
      dpkg -s "$p" >/dev/null 2>&1 || missing="$missing $p"
    done
    [ -z "$missing" ] && { say "Packages already installed."; return; }
    [ "$IS_ROOT" = 1 ] || { warn "packages missing ($missing ) and not running as root; re-run with sudo or install them first"; RC=1; return; }
    for p in $missing; do
      if ! apt-cache policy "$p" 2>/dev/null | grep -q 'Candidate: [^(]'; then
        warn "package '$p' is not available from this system's apt repositories"
        [ "$p" = starship ] && warn "starship: see https://starship.rs/guide/#%F0%9F%9A%80-installation"
        RC=1
      fi
    done
    run env DEBIAN_FRONTEND=noninteractive apt-get install -y $missing || RC=1
  fi
}

# ---- per-user helpers ----------------------------------------------------------------------
home_of() {
  if [ "$OS" = mac ]; then
    dscl . -read "/Users/$1" NFSHomeDirectory 2>/dev/null | awk '{print $2}'
  else
    getent passwd "$1" | cut -d: -f6
  fi
}
group_of() { id -gn "$1" 2>/dev/null; }

# place <source> <destination> <user>: never clobbers a differing file without --force.
place() {
  local src=$1 dst=$2 u=$3 g
  g=$(group_of "$u")
  if [ -e "$dst" ]; then
    if cmp -s "$src" "$dst"; then say "  $dst: already up to date"; return; fi
    if [ "$FORCE" = 1 ]; then
      run cp -p "$dst" "$dst.bak.$(date +%Y%m%d%H%M%S)"
    else
      warn "$dst exists and differs; skipped (use --force to replace, a backup is kept)"
      RC=1; return
    fi
  fi
  # Create the parent directory only if it is missing (e.g. ~/.config); never change the
  # mode or owner of one that exists (/root is 700, homes may be 750).
  if [ ! -d "$(dirname "$dst")" ]; then
    run install -d -m 755 "$(dirname "$dst")"
    [ "$IS_ROOT" = 1 ] && run chown "$u:$g" "$(dirname "$dst")"
  fi
  run install -m 644 "$src" "$dst"
  [ "$IS_ROOT" = 1 ] && run chown "$u:$g" "$dst"
  say "  $dst: installed"
}

# Write/refresh the managed block in ~/.zshrc.local (everything outside the markers is kept).
write_local() {
  local u=$1 home=$2 f="$2/.zshrc.local" tmp block g
  g=$(group_of "$u")
  tmp=$(mktemp "${TMPDIR:-/tmp}/zsh-local.XXXXXX") || return
  block=$(mktemp "${TMPDIR:-/tmp}/zsh-block.XXXXXX") || return
  {
    echo "# >>> shell-prompt-setup (managed block; re-run install.sh to refresh) >>>"
    if [ -n "$VIP" ]; then
      echo "# Show [VIP] in the prompt while this host holds this address."
      echo "export PROMPT_VIP=$VIP"
    fi
    if [ -n "$SQUARE_LIST" ]; then
      echo "# Square corners for ssh sessions coming from these client addresses (font workaround)."
      echo "PROMPT_SQUARE_FROM=\"$SQUARE_LIST\""
    fi
    if [ "$SSH_AGENT" = 1 ]; then
      cat <<'AGENT'
# ssh-agent with the GitHub keys, unless one is already available (e.g. forwarded).
# Only an agent started here is stopped when the shell exits.
if [[ -z $SSH_AUTH_SOCK ]]; then
  eval "$(ssh-agent -s)" >/dev/null
  ssh-add -k ~/.ssh/github*.key(N) >/dev/null 2>&1
  _zshrc_started_agent=1
fi
zshexit() { [[ -n $_zshrc_started_agent ]] && eval "$(ssh-agent -k)" >/dev/null 2>&1 }
AGENT
    fi
    echo "# <<< shell-prompt-setup <<<"
  } > "$block"
  if [ -f "$f" ]; then
    awk '/^# >>> shell-prompt-setup/{skip=1} !skip{print} /^# <<< shell-prompt-setup/{skip=0}' "$f" > "$tmp"
  fi
  cat "$block" >> "$tmp"
  if [ -f "$f" ] && cmp -s "$tmp" "$f"; then
    say "  $f: already up to date"
  else
    run install -m 644 "$tmp" "$f"
    [ "$IS_ROOT" = 1 ] && run chown "$u:$g" "$f"
    say "  $f: written"
  fi
  rm -f "$tmp" "$block"
}

# Log in as the user with zsh and render the prompt; chsh only if that works.
smoke_test() {
  local u=$1 zsh_bin=$2
  if [ "$u" = "$ME" ]; then
    "$zsh_bin" -l -i -c 'starship prompt >/dev/null' >/dev/null 2>&1
  else
    su - "$u" -s "$zsh_bin" -c "$zsh_bin -l -i -c 'starship prompt >/dev/null'" >/dev/null 2>&1
  fi
}

# ---- main --------------------------------------------------------------------------------
[ "$DO_PACKAGES" = 1 ] && install_packages

# Orange variant of starship.toml for ssh sessions (the blue frame and host name -> orange), generated into a temp
# file so the source tree is never written to.
SSH_VARIANT=$(mktemp "${TMPDIR:-/tmp}/starship-ssh.XXXXXX") || die "cannot create a temp file"
sed 's/bold blue/bold 208/g' "$SRC/starship.toml" > "$SSH_VARIANT"

TARGETS=${USERS_ARG:-$ME}
OLDIFS=$IFS; IFS=,; set -- $TARGETS; IFS=$OLDIFS
for u in "$@"; do
  [ -n "$u" ] || continue
  say "== user: $u"
  if ! id "$u" >/dev/null 2>&1; then warn "user '$u' does not exist; skipped"; RC=1; continue; fi
  if [ "$u" != "$ME" ] && [ "$IS_ROOT" != 1 ]; then warn "only root can set up other users; skipped '$u'"; RC=1; continue; fi
  home=$(home_of "$u")
  [ -n "$home" ] && [ -d "$home" ] || { warn "no home directory for '$u'; skipped"; RC=1; continue; }

  place "$SRC/zshrc"         "$home/.zshrc"                 "$u"
  place "$SRC/starship.toml" "$home/.config/starship.toml"  "$u"
  place "$SSH_VARIANT"       "$home/.config/starship-ssh.toml" "$u"
  [ "$OS" = linux ] && place "$SRC/zprofile" "$home/.zprofile" "$u"
  if [ "$SSH_AGENT" = 1 ] || [ -n "$VIP" ] || [ -n "$SQUARE_LIST" ]; then write_local "$u" "$home"; fi

  if [ "$DRY" = 1 ]; then
    [ "$SET_SHELL" = 1 ] && say "  [dry-run] would test a zsh login for $u, then chsh -s zsh $u"
    continue
  fi
  zsh_bin=$(command -v zsh || true)
  if [ -z "$zsh_bin" ]; then warn "zsh not installed; cannot test or change the shell of $u"; RC=1; continue; fi
  if smoke_test "$u" "$zsh_bin"; then
    say "  zsh login test: ok"
    if [ "$SET_SHELL" = 1 ]; then
      grep -qx "$zsh_bin" /etc/shells 2>/dev/null || warn "$zsh_bin is not listed in /etc/shells"
      if [ "$IS_ROOT" = 1 ]; then chsh -s "$zsh_bin" "$u" || RC=1; else chsh -s "$zsh_bin" || RC=1; fi
      say "  login shell: $zsh_bin (roll back: chsh -s /bin/bash $u)"
    fi
  else
    warn "zsh login test failed for $u; login shell NOT changed"
    RC=1
  fi
done

rm -f "$SSH_VARIANT"
[ "$DRY" = 1 ] && say "(dry run: nothing was changed)"
[ "$RC" = 0 ] && say "Done. Open a new terminal (or run: exec zsh)."
exit $RC
