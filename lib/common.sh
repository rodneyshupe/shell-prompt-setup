# shell-prompt-setup: the installer library, sourced by install.sh (Starship) and install-powerline.sh.
# Not run on its own. bash 3.2 compatible (macOS /bin/bash).
#
# What the two installers share: users and login shells, packages, files, marked blocks in ~/.zshrc and
# ~/.bashrc, the optional zsh setup, ssh-agent blocks, migration of the first layout, the smoke test and
# --uninstall. A prompt installer supplies only what is specific to its prompt, as these hooks:
#
#   PROMPT_NAME                 starship | powerline (shown in messages)
#   PROMPT_CONFIG_FILES         files under config/ to download when run through curl
#   PROMPT_PKGS_APT / _BREW     packages the prompt needs
#   installer_usage             extra option help (stdout)
#   installer_option <args...>  handle one extra option: set OPT_SHIFT to the number of args consumed (0 = unknown)
#   installer_check             validate options after parsing
#   installer_global            once, before the users (generated files, ...)
#   installer_user u home dir   place the prompt's files for one user (dir exists)
#   installer_body              block body for the shell rc files (stdout)
#   installer_smoke             command run inside an interactive shell to prove the prompt loaded
#   installer_before_rc rc u    before a prompt block is written to rc: return non-zero to skip that file.
#                               Default: prompt_conflict_guard (another prompt already loaded by hand).
#   installer_cleanup           remove temp files (end of the run)
#   installer_done              extra final message
#
# The installer sets ROOT (a directory with config/) and ROOT_IS_TEMP (1 if config/ still has to be downloaded).

set -u

USERS_ARG=""
SHELLS=auto
PROMPT_ONLY=0
SET_SHELL=0
SSH_AGENT=0
DO_PACKAGES=1
FORCE=0
DRY=0
UNINSTALL=0
RC=0
BASE_URL=${BASE_URL:-https://raw.githubusercontent.com/rodneyshupe/shell-prompt-setup/main}
PROMPT_PKGS_APT=""
PROMPT_PKGS_BREW=""

# Default (no-op) hooks; an installer overrides what it needs after sourcing this file.
OPT_SHIFT=0
installer_usage()      { :; }
installer_option()     { OPT_SHIFT=0; }
installer_check()      { :; }
installer_global()     { :; }
installer_user()       { :; }
installer_body()       { :; }
installer_smoke()      { echo 'true'; }
installer_before_rc()  { prompt_conflict_guard "$1"; }
installer_cleanup()    { :; }
installer_done()       { :; }

say()  { printf '%s\n' "$*"; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
# Run a command, or only print it with --dry-run.
run()  { if [ "$DRY" = 1 ]; then say "[dry-run] $*"; else "$@"; fi; }

common_usage() {
  cat <<'USAGE'
Which shells and components
  --users u1,u2    Users to set up (default: the user running the script). Other users than
                   yourself need root.
  --shells WHICH   auto (default): each user's login shell, zsh or bash. zsh | bash: that one.
                   both: zsh and bash (the existing shell plus the other one).
  --prompt-only    Only the prompt. No zsh setup (plugins, completion, history, key bindings), so
                   an existing zsh configuration is left alone apart from one added block.
  --shell          Make zsh the login shell of those users (chsh) and set zsh up for them, only after
                   a zsh login test passed. Roll back with: chsh -s /bin/bash <user>
  --uninstall      Remove what the installers added (the marked blocks and ~/.config/shell-prompt-setup).
                   Packages and login shells are left as they are.
  --ssh-agent      Start an ssh-agent with ~/.ssh/github*.key unless one is already available (e.g.
                   forwarded); stops only an agent it started.

Other
  --no-packages    Do not install packages; only place the files.
  --force          Replace files in ~/.config/shell-prompt-setup that differ (backup kept as
                   <file>.bak.<timestamp>). Marked blocks in .zshrc/.bashrc are always refreshed.
  --dry-run        Show what would be done, change nothing.
  --base-url URL   Where to download config/ from when not run from a clone (default: main on GitHub).
  -h, --help       This text.
USAGE
}

parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --users)       USERS_ARG=${2:?--users needs a value}; shift 2 ;;
      --users=*)     USERS_ARG=${1#*=}; shift ;;
      --shells)      SHELLS=${2:?--shells needs a value}; shift 2 ;;
      --shells=*)    SHELLS=${1#*=}; shift ;;
      --prompt-only) PROMPT_ONLY=1; shift ;;
      --shell)       SET_SHELL=1; shift ;;
      --uninstall)   UNINSTALL=1; shift ;;
      --ssh-agent)   SSH_AGENT=1; shift ;;
      --no-packages) DO_PACKAGES=0; shift ;;
      --force)       FORCE=1; shift ;;
      --dry-run)     DRY=1; shift ;;
      --base-url)    BASE_URL=${2:?--base-url needs a value}; shift 2 ;;
      --base-url=*)  BASE_URL=${1#*=}; shift ;;
      -h|--help)     installer_usage; echo; common_usage; exit 0 ;;
      *)
        OPT_SHIFT=0
        installer_option "$@"
        if [ "$OPT_SHIFT" -gt 0 ]; then shift "$OPT_SHIFT"
        else echo "Unknown option: $1" >&2; installer_usage >&2; echo >&2; common_usage >&2; exit 2; fi ;;
    esac
  done
  case "$SHELLS" in auto|zsh|bash|both) ;; *) die "--shells must be auto, zsh, bash or both, got '$SHELLS'" ;; esac
}

detect_system() {
  case "$(uname -s)" in
    Darwin) OS=mac ;;
    Linux)  OS=linux ;;
    *) die "unsupported OS: $(uname -s)" ;;
  esac
  ME=$(id -un)
  IS_ROOT=0; [ "$(id -u)" = 0 ] && IS_ROOT=1
}

# download <relative path under the repo> <destination>
download() {
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$BASE_URL/$1" -o "$2" || die "download failed: $BASE_URL/$1"
  elif command -v wget >/dev/null 2>&1; then
    wget -q -O "$2" "$BASE_URL/$1" || die "download failed: $BASE_URL/$1"
  else
    die "need curl or wget to download the config files"
  fi
}

fetch_config() {
  local f files="$PROMPT_CONFIG_FILES zsh/zsh-setup.zsh zsh/zprofile"
  [ "$ROOT_IS_TEMP" = 1 ] || return 0
  for f in $files; do
    mkdir -p "$ROOT/config/$(dirname "$f")"
    download "config/$f" "$ROOT/config/$f"
  done
}

# ---- per-user lookups ------------------------------------------------------------------------
# SHELL_PROMPT_SETUP_HOME installs into that directory instead of the user's home (used by tests).
home_of() {
  if [ -n "${SHELL_PROMPT_SETUP_HOME:-}" ]; then printf '%s\n' "$SHELL_PROMPT_SETUP_HOME"; return; fi
  if [ "$OS" = mac ]; then
    dscl . -read "/Users/$1" NFSHomeDirectory 2>/dev/null | awk '{print $2}'
  else
    getent passwd "$1" | cut -d: -f6
  fi
}
login_shell_of() {
  local s
  if [ "$OS" = mac ]; then
    s=$(dscl . -read "/Users/$1" UserShell 2>/dev/null | awk '{print $2}')
  else
    s=$(getent passwd "$1" | cut -d: -f7)
  fi
  basename "${s:-sh}"
}
group_of() { id -gn "$1" 2>/dev/null; }

# plan_user <user>: sets LSH (login shell) and T_ZSH / T_BASH (which shells to set up).
plan_user() {
  LSH=$(login_shell_of "$1")
  T_ZSH=0; T_BASH=0
  case "$SHELLS" in
    auto) case "$LSH" in zsh) T_ZSH=1 ;; bash) T_BASH=1 ;; esac ;;
    zsh)  T_ZSH=1 ;;
    bash) T_BASH=1 ;;
    both) T_ZSH=1; T_BASH=1 ;;
  esac
  [ "$SET_SHELL" = 1 ] && T_ZSH=1
  return 0
}

# valid_user <user>: exists, and we may set it up.
valid_user() {
  id "$1" >/dev/null 2>&1 || return 1
  [ "$1" = "$ME" ] || [ "$IS_ROOT" = 1 ]
}

# as_user <user> <command string>: run a shell command as that user.
as_user() {
  local u=$1; shift
  if [ "$u" = "$ME" ]; then sh -c "$*"; else su - "$u" -s /bin/sh -c "$*"; fi
}

# ---- packages ----------------------------------------------------------------------------
# install_packages <need_zsh 0|1> <need_plugins 0|1> <need_prompt 0|1>
install_packages() {
  local need_zsh=$1 need_plugins=$2 need_prompt=$3 missing="" p want=""
  if [ "$OS" = mac ]; then
    [ "$need_prompt" = 1 ] && want="$PROMPT_PKGS_BREW"
    [ "$need_plugins" = 1 ] && want="$want zsh-autosuggestions zsh-syntax-highlighting"
    [ -n "${want# }" ] || return 0
    command -v brew >/dev/null 2>&1 || { warn "Homebrew not found; install these yourself: $want"; return; }
    [ "$IS_ROOT" = 1 ] && { warn "brew refuses to run as root; run this script as your normal user"; return; }
    for p in $want; do brew list --formula "$p" >/dev/null 2>&1 || missing="$missing $p"; done
    [ -z "$missing" ] && { say "Packages already installed."; return; }
    run brew install $missing
  else
    [ "$need_zsh" = 1 ] && want="zsh"
    [ "$need_prompt" = 1 ] && want="$want $PROMPT_PKGS_APT"
    [ "$need_plugins" = 1 ] && want="$want zsh-autosuggestions zsh-syntax-highlighting"
    [ -n "${want# }" ] || return 0
    command -v apt-get >/dev/null 2>&1 || { warn "apt-get not found; install these yourself: $want"; return; }
    for p in $want; do dpkg -s "$p" >/dev/null 2>&1 || missing="$missing $p"; done
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

# ---- files ---------------------------------------------------------------------------------
ts() { date +%Y%m%d%H%M%S; }

# ensure_dir <dir> <user>: create a missing directory (never touches the mode/owner of an existing one).
ensure_dir() {
  local d=$1 u=$2 g
  [ -d "$d" ] && return 0
  g=$(group_of "$u")
  run install -d -m 755 "$d"
  [ "$IS_ROOT" = 1 ] && run chown "$u:$g" "$d"
  return 0
}

# place <source> <destination> <user> [always]: never clobbers a differing file without --force
# (or 'always'); a replaced file is kept as <file>.bak.<timestamp>. Missing parent directories are created.
place() {
  local src=$1 dst=$2 u=$3 always=${4:-} g
  g=$(group_of "$u")
  if [ -e "$dst" ]; then
    if cmp -s "$src" "$dst"; then say "  $dst: already up to date"; return 0; fi
    if [ "$FORCE" = 1 ] || [ -n "$always" ]; then
      [ -n "$always" ] || run cp -p "$dst" "$dst.bak.$(ts)"
    else
      warn "$dst exists and differs; skipped (use --force to replace, a backup is kept)"
      RC=1; return 0
    fi
  fi
  ensure_dir "$(dirname "$dst")" "$u"
  run install -m 644 "$src" "$dst"
  [ "$IS_ROOT" = 1 ] && run chown "$u:$g" "$dst"
  say "  $dst: installed"
}

# place_tree <source dir> <destination dir> <user>: place every file under a directory (keeps the layout).
place_tree() {
  local s=$1 d=$2 u=$3 f
  # shellcheck disable=SC2044
  for f in $(cd "$s" && find . -type f | sort | sed 's|^\./||'); do
    ensure_dir "$(dirname "$d/$f")" "$u"
    place "$s/$f" "$d/$f" "$u"
  done
}

# ---- marked blocks in .zshrc / .bashrc ------------------------------------------------------
block_start() { printf '# >>> shell-prompt-setup: %s >>>' "$1"; }
block_end()   { printf '# <<< shell-prompt-setup: %s <<<' "$1"; }

# overwrite_file <new content file> <destination>: keeps the destination's owner, mode and inode.
overwrite_file() {
  if [ "$DRY" = 1 ]; then say "[dry-run] update $2"; else cat "$1" > "$2"; fi
}

# block_put <file> <name> <user>  (block body on stdin). Replaces the block in place if present;
# otherwise appends it (the prompt block goes before the zsh-setup block, which must stay last so the
# syntax-highlighting plugin is loaded last). A new block in an existing file first backs the file up.
block_put() {
  local f=$1 name=$2 u=$3 g s e blk tmp
  g=$(group_of "$u"); s=$(block_start "$name"); e=$(block_end "$name")
  blk=$(mktemp "${TMPDIR:-/tmp}/sps-block.XXXXXX"); tmp=$(mktemp "${TMPDIR:-/tmp}/sps-file.XXXXXX")
  { printf '%s\n' "$s"; cat; printf '%s\n' "$e"; } > "$blk"
  if [ ! -e "$f" ]; then
    ensure_dir "$(dirname "$f")" "$u"
    run install -m 644 "$blk" "$f"
    [ "$IS_ROOT" = 1 ] && run chown "$u:$g" "$f"
    say "  $f: created with the $name block"
  else
    if grep -qxF "$s" "$f"; then
      awk -v s="$s" -v e="$e" -v nf="$blk" '$0==s{while((getline l < nf)>0) print l; skip=1; next} $0==e{skip=0; next} !skip{print}' "$f" > "$tmp"
    elif [ "$name" = prompt ] && grep -qxF "$(block_start zsh-setup)" "$f"; then
      awk -v s="$(block_start zsh-setup)" -v nf="$blk" '$0==s && !done{while((getline l < nf)>0) print l; print ""; done=1} {print}' "$f" > "$tmp"
    else
      { cat "$f"; [ -n "$(tail -c1 "$f")" ] && echo; echo; cat "$blk"; } > "$tmp"
    fi
    if cmp -s "$tmp" "$f"; then
      say "  $f: $name block already up to date"
    else
      grep -qxF "$s" "$f" || run cp -p "$f" "$f.bak.$(ts)"
      overwrite_file "$tmp" "$f"
      say "  $f: $name block written"
    fi
  fi
  rm -f "$blk" "$tmp"
}

# block_remove <file> <name>
block_remove() {
  local f=$1 name=$2 s e tmp
  [ -f "$f" ] || return 0
  s=$(block_start "$name"); e=$(block_end "$name")
  grep -qxF "$s" "$f" || return 0
  tmp=$(mktemp "${TMPDIR:-/tmp}/sps-file.XXXXXX")
  awk -v s="$s" -v e="$e" '$0==s{skip=1; next} $0==e{skip=0; next} !skip{print}' "$f" > "$tmp"
  overwrite_file "$tmp" "$f"
  say "  $f: $name block removed"
  rm -f "$tmp"
}

# The rc file bash reads: ~/.bashrc on Linux; on macOS terminals start login shells, which read the
# first of .bash_profile, .bash_login, .profile (created as .bash_profile if none exists).
bash_rc_for() {
  local home=$1 f
  if [ "$OS" = linux ]; then printf '%s\n' "$home/.bashrc"; return; fi
  for f in .bash_profile .bash_login .profile; do
    [ -e "$home/$f" ] && { printf '%s\n' "$home/$f"; return; }
  done
  printf '%s\n' "$home/.bash_profile"
}

# ---- another prompt already loaded by hand ---------------------------------------------------------
# A prompt that the user's own rc file already loads (Powerline, powerline-shell, a hand-written starship init)
# would fight with ours for PS1 on every prompt. prompt_conflict_guard <rc file> says so and returns non-zero
# (the caller then skips that file), or, with --force, first removes the standard snippets it recognises,
# after a backup: the Debian "# Powerline configuration" block and the powerline-shell _update_ps1 snippet.
# Anything else (a hand-written `starship init`, oh-my-posh, ...) is never removed: the user has to.
FOREIGN_PROMPT='bindings/(bash|zsh)/powerline|powerline-daemon|_update_ps1|powerline-shell|starship init|oh-my-posh init'

foreign_prompt_lines() {   # lines of the rc file that load another prompt, outside our own blocks
  # commented-out lines cannot conflict, so they are ignored
  awk '/^# >>> shell-prompt-setup: /{skip=1} !skip{print} /^# <<< shell-prompt-setup: /{skip=0}' "$1" | grep -n -E "$FOREIGN_PROMPT" | grep -v -E '^[0-9]+:[[:space:]]*#' | head -3
}

prompt_conflict_guard() {
  local rc=$1 tmp changed=0
  [ -f "$rc" ] || return 0
  [ -n "$(foreign_prompt_lines "$rc")" ] || return 0
  if [ "$FORCE" = 1 ]; then
    tmp=$(mktemp "${TMPDIR:-/tmp}/sps-file.XXXXXX")
    if grep -qx '# Powerline configuration' "$rc"; then
      awk '/^# Powerline configuration$/{skip=1} !skip{print} skip && /^fi$/{skip=0}' "$rc" > "$tmp"
      cat "$tmp" > "$tmp.2" && mv "$tmp.2" "$tmp"
      changed=1
    else
      cat "$rc" > "$tmp"
    fi
    if grep -q '_update_ps1' "$tmp"; then
      awk '
        function flush() { if (have) print held; have = 0 }
        skipf { if ($0 ~ /^}/) skipf = 0; next }
        skipi { if ($0 ~ /^fi[ \t]*$/) skipi = 0; next }
        $0 ~ /^(function )?_update_ps1[ \t]*\(\)/ {
          if (have && held ~ /^#!\/usr\/bin\/env bash/) have = 0
          flush(); if ($0 !~ /}[ \t]*$/) skipf = 1; next }
        $0 ~ /^if .*_update_ps1/ { flush(); if ($0 !~ /fi[ \t]*$/) skipi = 1; next }
        { flush(); held = $0; have = 1 }
        END { flush() }' "$tmp" > "$tmp.2" && mv "$tmp.2" "$tmp"
      changed=1
    fi
    if [ "$changed" = 1 ]; then
      run cp -p "$rc" "$rc.bak.$(ts)"
      overwrite_file "$tmp" "$rc"
      say "  $rc: the standard Powerline / powerline-shell prompt snippets removed (backup kept)"
    fi
    rm -f "$tmp" "$tmp.2"
    [ "$DRY" = 1 ] && [ "$changed" = 1 ] && return 0
    [ -n "$(foreign_prompt_lines "$rc")" ] || return 0
  fi
  warn "$rc already loads another prompt by hand ($(foreign_prompt_lines "$rc" | head -1 | cut -c1-70)); not adding a second one. Remove those lines yourself, or re-run with --force to remove the standard Powerline / powerline-shell snippets (a backup is kept)."
  RC=1
  return 1
}

# ---- block bodies --------------------------------------------------------------------------
body_zsh_setup() {
  cat <<'EOF'
# The zsh setup (history, completion, colors, key bindings, plugins): zsh-setup.zsh.
[[ -r "$HOME/.config/shell-prompt-setup/zsh-setup.zsh" ]] && source "$HOME/.config/shell-prompt-setup/zsh-setup.zsh"
EOF
}
body_agent_zsh() {
  cat <<'EOF'
# ssh-agent with the GitHub keys, unless one is already available (e.g. forwarded).
# Only an agent started here is stopped when the shell exits.
if [[ -z $SSH_AUTH_SOCK ]]; then
  eval "$(ssh-agent -s)" >/dev/null
  ssh-add -k ~/.ssh/github*.key(N) >/dev/null 2>&1
  _sps_started_agent=1
fi
zshexit() { [[ -n $_sps_started_agent ]] && eval "$(ssh-agent -k)" >/dev/null 2>&1 }
EOF
}
body_agent_bash() {
  cat <<'EOF'
# ssh-agent with the GitHub keys, unless one is already available (e.g. forwarded).
# Only an agent started here is stopped when the shell exits (note: this sets the shell's EXIT trap).
if [ -z "${SSH_AUTH_SOCK:-}" ]; then
  eval "$(ssh-agent -s)" >/dev/null
  for _sps_key in "$HOME"/.ssh/github*.key; do [ -f "$_sps_key" ] && ssh-add -k "$_sps_key" >/dev/null 2>&1; done
  unset _sps_key
  _sps_started_agent=1
fi
_sps_agent_stop() { [ -n "${_sps_started_agent:-}" ] && eval "$(ssh-agent -k)" >/dev/null 2>&1; }
trap _sps_agent_stop EXIT
EOF
}

# ---- settings (settings.sh: plain export lines read by the prompt loaders) ---------------------------
# settings_put <settings file> <user> NAME=value...: updates only the given settings, each in the place where it
# already is (so a re-run does not reorder the file), new ones are appended; the value is written as is (quote it
# yourself). The new lines go to awk through a file, not a -v variable: macOS's BSD awk rejects a newline in -v.
settings_put() {
  local f=$1 u=$2 tmp newf kv; shift 2
  [ $# -gt 0 ] || return 0
  tmp=$(mktemp "${TMPDIR:-/tmp}/sps-settings.XXXXXX"); newf=$(mktemp "${TMPDIR:-/tmp}/sps-settings-new.XXXXXX")
  for kv in "$@"; do echo "export $kv"; done > "$newf"
  {
    echo "# shell-prompt-setup settings: plain export lines read by the prompt loader (the installers update them)."
    if [ -f "$f" ]; then
      awk '
        NR == FNR { k = $0; sub(/=.*/, "", k); K[k] = $0; order[++m] = k; next }
        /^# shell-prompt-setup settings/ { next }
        { done = 0; for (k in K) if (index($0, k "=") == 1) { print K[k]; seen[k] = 1; done = 1; break } if (!done) print }
        END { for (i = 1; i <= m; i++) if (!seen[order[i]]) print K[order[i]] }' "$newf" "$f"
    else
      cat "$newf"
    fi
  } > "$tmp"
  place "$tmp" "$f" "$u" always
  rm -f "$tmp" "$newf"
}

# ---- migration from the first layout (whole-file ~/.zshrc, ~/.config/starship*.toml, ~/.zshrc.local) ----
# Sets LEGACY_ZSH=1 when a whole-file ~/.zshrc managed by this project was replaced (it contained the
# zsh setup, so that is kept), and M_VIP / M_SQUARE / M_AGENT from the old ~/.zshrc.local block.
migrate_legacy() {
  local u=$1 home=$2 f blkstart='# >>> shell-prompt-setup (managed block; re-run install.sh to refresh) >>>' tmp
  LEGACY_ZSH=0; M_VIP=""; M_SQUARE=""; M_AGENT=0
  f=$home/.zshrc
  if [ "$T_ZSH" = 1 ] && [ -f "$f" ] && grep -q 'Managed by shell-prompt-setup' "$f" && ! grep -q '>>> shell-prompt-setup:' "$f"; then
    run cp -p "$f" "$f.bak.$(ts)"
    if [ "$DRY" = 1 ]; then say "[dry-run] replace the old whole-file $f"; else : > "$f"; fi
    say "  $f: old whole-file setup replaced (backup kept)"
    LEGACY_ZSH=1
  fi
  f=$home/.zprofile
  if [ "$T_ZSH" = 1 ] && [ -f "$f" ] && head -1 "$f" | grep -q '^# ~/.zprofile: login shells (Linux)'; then
    run cp -p "$f" "$f.bak.$(ts)"
    if [ "$DRY" = 1 ]; then say "[dry-run] replace the old whole-file $f"; else : > "$f"; fi
    say "  $f: old whole-file setup replaced (backup kept)"
  fi
  for f in "$home/.config/starship.toml" "$home/.config/starship-ssh.toml"; do
    if [ -f "$f" ] && head -1 "$f" | grep -q '^# Starship prompt: two-line frame'; then
      run mv "$f" "$f.bak.$(ts)"
      say "  $f: old copy moved aside (the config now lives in ~/.config/shell-prompt-setup)"
    fi
  done
  f=$home/.zshrc.local
  if [ -f "$f" ] && grep -qxF "$blkstart" "$f"; then
    M_VIP=$(sed -n 's/^export PROMPT_VIP=//p' "$f" | head -1)
    M_SQUARE=$(sed -n 's/^PROMPT_SQUARE_FROM="\(.*\)"$/\1/p' "$f" | head -1)
    grep -q 'ssh-agent -s' "$f" && M_AGENT=1
    tmp=$(mktemp "${TMPDIR:-/tmp}/sps-file.XXXXXX")
    awk '/^# >>> shell-prompt-setup \(managed block/{skip=1} !skip{print} /^# <<< shell-prompt-setup <<</{skip=0}' "$f" > "$tmp"
    run cp -p "$f" "$f.bak.$(ts)"
    if grep -q '[^[:space:]]' "$tmp"; then overwrite_file "$tmp" "$f"; else run rm -f "$f"; fi
    say "  $f: old managed block moved to settings.sh / the ssh-agent block (backup kept)"
    rm -f "$tmp"
  fi
}

# smoke_test <user> <zsh|bash> <path to the shell>: an interactive shell of that kind, as that user,
# must load the prompt and render it (installer_smoke gives the command).
smoke_test() {
  local u=$1 kind=$2 bin=$3 flags="-i" cmd
  if [ "$kind" = zsh ] || [ "$OS" = mac ]; then flags="-l -i"; fi
  cmd="$bin $flags -c '$(installer_smoke)'"
  if [ "$u" = "$ME" ]; then
    sh -c "$cmd" >/dev/null 2>&1
  else
    su - "$u" -s "$bin" -c "$cmd" >/dev/null 2>&1
  fi
}

# ---- main --------------------------------------------------------------------------------
sps_main() {
  local u home dir kind bin rc f b h zsh_ok zsh_bin zsh_setup agent need_any need_zsh need_plugins OLDIFS

  detect_system
  parse_args "$@"
  installer_check
  fetch_config
  SRC=$ROOT/config
  [ "$ROOT_IS_TEMP" = 1 ] && trap 'rm -rf "$ROOT"' EXIT

  if [ "$UNINSTALL" != 1 ]; then
    # Packages first, from what the users need.
    need_any=0; need_zsh=0; need_plugins=0
    OLDIFS=$IFS; IFS=,; set -- ${USERS_ARG:-$ME}; IFS=$OLDIFS
    for u in "$@"; do
      [ -n "$u" ] && valid_user "$u" || continue
      plan_user "$u"
      if [ "$T_ZSH" = 1 ] || [ "$T_BASH" = 1 ]; then need_any=1; fi
      if [ "$T_ZSH" = 1 ]; then need_zsh=1; [ "$PROMPT_ONLY" = 1 ] || need_plugins=1; fi
      # an old whole-file zsh setup keeps the zsh setup
      h=$(home_of "$u")
      if [ "$T_ZSH" = 1 ] && [ -f "$h/.zshrc" ] && grep -q 'Managed by shell-prompt-setup' "$h/.zshrc" 2>/dev/null; then need_plugins=1; fi
    done
    if [ "$DO_PACKAGES" = 1 ] && [ "$need_any" = 1 ]; then install_packages "$need_zsh" "$need_plugins" 1; fi
    installer_global
  fi

  OLDIFS=$IFS; IFS=,; set -- ${USERS_ARG:-$ME}; IFS=$OLDIFS
  for u in "$@"; do
    [ -n "$u" ] || continue
    say "== user: $u"
    if ! id "$u" >/dev/null 2>&1; then warn "user '$u' does not exist; skipped"; RC=1; continue; fi
    if ! valid_user "$u"; then warn "only root can set up other users; skipped '$u'"; RC=1; continue; fi
    home=$(home_of "$u")
    [ -n "$home" ] && [ -d "$home" ] || { warn "no home directory for '$u'; skipped"; RC=1; continue; }
    dir=$home/.config/shell-prompt-setup

    if [ "$UNINSTALL" = 1 ]; then
      for f in "$home/.zshrc" "$home/.zprofile" "$home/.bashrc" "$home/.bash_profile" "$home/.bash_login" "$home/.profile"; do
        for b in prompt zsh-setup zprofile agent; do block_remove "$f" "$b"; done
      done
      [ -d "$dir" ] && { run rm -rf "$dir"; say "  $dir: removed"; }
      continue
    fi

    plan_user "$u"
    if [ "$T_ZSH" = 0 ] && [ "$T_BASH" = 0 ]; then
      warn "login shell of '$u' is '$LSH', not zsh or bash; skipped (use --shells zsh|bash|both)"
      RC=1; continue
    fi
    say "  shells: $([ "$T_ZSH" = 1 ] && echo zsh) $([ "$T_BASH" = 1 ] && echo bash)  (login shell: $LSH)$([ "$PROMPT_ONLY" = 1 ] && echo ', prompt only')  prompt: $PROMPT_NAME"

    migrate_legacy "$u" "$home"
    agent=$SSH_AGENT; [ "$M_AGENT" = 1 ] && agent=1
    zsh_setup=0
    if [ "$T_ZSH" = 1 ] && { [ "$PROMPT_ONLY" != 1 ] || [ "$LEGACY_ZSH" = 1 ]; }; then zsh_setup=1; fi

    # Files of this project (never the user's own rc files).
    ensure_dir "$home/.config" "$u"
    ensure_dir "$dir" "$u"
    installer_user "$u" "$home" "$dir"
    [ "$zsh_setup" = 1 ] && place "$SRC/zsh/zsh-setup.zsh" "$dir/zsh-setup.zsh" "$u"

    # Marked blocks in the shell's own rc files.
    if [ "$T_ZSH" = 1 ]; then
      if installer_before_rc "$home/.zshrc" "$u"; then installer_body | block_put "$home/.zshrc" prompt "$u"; fi
      if [ "$zsh_setup" = 1 ]; then
        body_zsh_setup | block_put "$home/.zshrc" zsh-setup "$u"
        [ "$OS" = linux ] && block_put "$home/.zprofile" zprofile "$u" < "$SRC/zsh/zprofile"
      fi
      [ "$agent" = 1 ] && body_agent_zsh | block_put "$home/.zshrc" agent "$u"
    fi
    if [ "$T_BASH" = 1 ]; then
      rc=$(bash_rc_for "$home")
      if installer_before_rc "$rc" "$u"; then installer_body | block_put "$rc" prompt "$u"; fi
      [ "$agent" = 1 ] && body_agent_bash | block_put "$rc" agent "$u"
    fi

    if [ "$DRY" = 1 ]; then
      [ "$SET_SHELL" = 1 ] && say "  [dry-run] would test a zsh login for $u, then chsh -s zsh $u"
      continue
    fi

    # Test each shell that was set up; change the login shell only if zsh passed.
    zsh_ok=0
    for kind in zsh bash; do
      if [ "$kind" = zsh ]; then [ "$T_ZSH" = 1 ] || continue; else [ "$T_BASH" = 1 ] || continue; fi
      bin=$(command -v "$kind" || true)
      if [ -z "$bin" ]; then warn "$kind is not installed; cannot test it for $u"; RC=1; continue; fi
      if smoke_test "$u" "$kind" "$bin"; then
        say "  $kind login test: ok"
        [ "$kind" = zsh ] && zsh_ok=1
      else
        warn "$kind test failed for $u (the prompt did not load)"
        RC=1
      fi
    done
    if [ "$SET_SHELL" = 1 ]; then
      if [ "$zsh_ok" = 1 ]; then
        zsh_bin=$(command -v zsh)
        grep -qx "$zsh_bin" /etc/shells 2>/dev/null || warn "$zsh_bin is not listed in /etc/shells"
        if [ "$IS_ROOT" = 1 ]; then chsh -s "$zsh_bin" "$u" || RC=1; else chsh -s "$zsh_bin" || RC=1; fi
        say "  login shell: $zsh_bin (roll back: chsh -s /bin/bash $u)"
      else
        warn "zsh test did not pass for $u; login shell NOT changed"
      fi
    fi
  done

  installer_cleanup
  [ "$DRY" = 1 ] && say "(dry run: nothing was changed)"
  if [ "$RC" = 0 ]; then
    if [ "$UNINSTALL" = 1 ]; then say "Done. Open a new terminal."; else say "Done. Open a new terminal (or run: exec zsh / exec bash)."; installer_done; fi
  fi
  exit $RC
}
