#!/usr/bin/env bash
#
# shell-prompt-setup, Powerline prompt: the Powerline look for zsh or bash, instead of the Starship prompt
# that install.sh sets up. Same shell handling, same optional zsh setup, same marked blocks.
#
#   curl -fsSL https://raw.githubusercontent.com/rodneyshupe/shell-prompt-setup/main/install-powerline.sh | bash
#   curl -fsSL .../install-powerline.sh | sudo bash -s -- --users alice,bob --plain-from 192.0.2.10
#
# Which Powerline depends on the OS (override with --backend):
#   Linux  the `powerline` package (apt) with a small overlay: clock first, left-only theme.
#   macOS  powerline-shell (pip, in a private virtualenv) with the old config: time, user, host, ssh, cwd, git, ...
# Powerline draws its separators with Powerline glyphs: the terminal you look at needs a patched font. Ssh
# clients listed with --plain-from get a glyph-free theme instead (a browser terminal, for instance).
# Installing this replaces the Starship prompt block in ~/.zshrc / ~/.bashrc; install.sh switches back.
#
# Run `install-powerline.sh --help` for all options. Works from a clone or piped from curl.

# --- debug (uncomment to trace) ---
# set -x
set -u

BASE_URL=${BASE_URL:-https://raw.githubusercontent.com/rodneyshupe/shell-prompt-setup/main}
_prev=""
for _a in "$@"; do
  case "$_a" in --base-url=*) BASE_URL=${_a#*=} ;; esac
  [ "$_prev" = --base-url ] && BASE_URL=$_a
  _prev=$_a
done

# Find the library: next to this script in a clone, otherwise download it.
ROOT=""; ROOT_IS_TEMP=0
_self="${BASH_SOURCE[0]:-}"
if [ -n "$_self" ] && [ -f "$_self" ]; then
  _d=$(cd "$(dirname "$_self")" && pwd)
  [ -f "$_d/lib/common.sh" ] && ROOT=$_d
fi
if [ -z "$ROOT" ]; then
  ROOT=$(mktemp -d "${TMPDIR:-/tmp}/shell-prompt-setup.XXXXXX") || { echo "ERROR: cannot create a temp dir" >&2; exit 1; }
  ROOT_IS_TEMP=1
  mkdir -p "$ROOT/lib"
  if command -v curl >/dev/null 2>&1; then curl -fsSL "$BASE_URL/lib/common.sh" -o "$ROOT/lib/common.sh"
  elif command -v wget >/dev/null 2>&1; then wget -q -O "$ROOT/lib/common.sh" "$BASE_URL/lib/common.sh"
  else echo "ERROR: need curl or wget" >&2; exit 1; fi || { echo "ERROR: cannot download $BASE_URL/lib/common.sh" >&2; rm -rf "$ROOT"; exit 1; }
fi
# shellcheck source=lib/common.sh
. "$ROOT/lib/common.sh"

# ---- what is specific to the Powerline prompt -----------------------------------------------------
PROMPT_NAME=powerline
PROMPT_CONFIG_FILES=""
BACKEND=auto
PLAIN_FROM=""
PLAIN_LIST=""
FONTS=0

installer_usage() {
  cat <<'USAGE'
Usage: install-powerline.sh [options]        (Powerline prompt; install.sh is the Starship one)

Powerline settings
  --backend WHICH  auto (default): Linux uses the `powerline` package, macOS uses powerline-shell.
                   powerline-shell: that one on Linux too (pip, private virtualenv). powerline is Linux only.
  --plain-from IP[,IP...]
                   ssh clients whose address is in the list get a glyph-free theme (Powerline's `unicode`
                   theme, powerline-shell's `compatible` mode), for a terminal without a patched font.
  --fonts          macOS: install a Powerline-patched font (Homebrew cask font-meslo-for-powerline). Select it
                   in your terminal's profile yourself. On Linux fonts belong on the machine you look from.
USAGE
}

installer_option() {
  case "$1" in
    --backend)       BACKEND=${2:?--backend needs a value}; OPT_SHIFT=2 ;;
    --backend=*)     BACKEND=${1#*=}; OPT_SHIFT=1 ;;
    --plain-from)    PLAIN_FROM=${2:?--plain-from needs addresses}; OPT_SHIFT=2 ;;
    --plain-from=*)  PLAIN_FROM=${1#*=}; OPT_SHIFT=1 ;;
    --fonts)         FONTS=1; OPT_SHIFT=1 ;;
    *) OPT_SHIFT=0 ;;
  esac
}

installer_check() {
  if [ "$BACKEND" = auto ]; then
    if [ "$OS" = mac ]; then BACKEND=powerline-shell; else BACKEND=powerline; fi
  fi
  case "$BACKEND" in
    powerline)
      [ "$OS" = mac ] && die "--backend powerline is Linux only (the Debian/Ubuntu package); macOS uses powerline-shell"
      PROMPT_CONFIG_FILES="powerline/powerline.sh powerline/powerline/config.json powerline/powerline/themes/shell/default_leftonly.json"
      PROMPT_PKGS_APT="powerline"
      ;;
    powerline-shell)
      PROMPT_CONFIG_FILES="powerline/powerline-shell.sh powerline/powerline-shell-patched/powerline-shell/config.json powerline/powerline-shell-plain/powerline-shell/config.json"
      PROMPT_PKGS_APT="python3 python3-venv procps"
      if [ "$OS" = mac ] && ! command -v python3 >/dev/null 2>&1; then
        warn "python3 not found: powerline-shell needs it (xcode-select --install, or brew install python)"
      fi
      ;;
    *) die "--backend must be auto, powerline or powerline-shell, got '$BACKEND'" ;;
  esac
  if [ -n "$PLAIN_FROM" ]; then
    case "$PLAIN_FROM" in *[!0-9.:,a-fA-F]*|"") die "--plain-from must be a comma-separated list of IP addresses, got '$PLAIN_FROM'" ;; esac
    PLAIN_LIST=$(printf '%s' "$PLAIN_FROM" | tr ',' ' ')
  fi
  if [ "$FONTS" = 1 ] && [ "$OS" != mac ]; then
    warn "--fonts only installs on macOS; on Linux install a Powerline font on the machine you view from"
    FONTS=0
  fi
}

installer_global() {
  [ "$FONTS" = 1 ] || return 0
  if ! command -v brew >/dev/null 2>&1; then warn "Homebrew not found; install a Powerline font yourself (cask font-meslo-for-powerline)"; return 0; fi
  if [ "$IS_ROOT" = 1 ]; then warn "brew refuses to run as root; fonts skipped"; return 0; fi
  run brew install --cask font-meslo-for-powerline || RC=1
  say "Fonts: select \"Meslo LG ... for Powerline\" in your terminal's profile."
}

# make_venv <user> <dir>: powerline-shell in a private virtualenv, created as that user.
make_venv() {
  local u=$1 dir=$2
  if [ -x "$dir/venv/bin/powerline-shell" ] && [ "$FORCE" != 1 ]; then say "  $dir/venv: already installed"; return 0; fi
  if [ "$DRY" = 1 ]; then say "[dry-run] create $dir/venv and pip install powerline-shell"; return 0; fi
  if as_user "$u" "python3 -m venv '$dir/venv' && '$dir/venv/bin/pip' install --quiet --disable-pip-version-check --upgrade powerline-shell"; then
    say "  $dir/venv: powerline-shell installed"
  else
    warn "could not install powerline-shell into $dir/venv (python3 with venv, and network access to PyPI, are needed)"
    RC=1
  fi
}

installer_user() {
  local u=$1 dir=$3
  case "$BACKEND" in
    powerline)
      place "$SRC/powerline/powerline.sh" "$dir/powerline.sh" "$u"
      place_tree "$SRC/powerline/powerline" "$dir/powerline" "$u"
      ;;
    powerline-shell)
      place "$SRC/powerline/powerline-shell.sh" "$dir/powerline-shell.sh" "$u"
      place_tree "$SRC/powerline/powerline-shell-patched" "$dir/powerline-shell-patched" "$u"
      place_tree "$SRC/powerline/powerline-shell-plain"   "$dir/powerline-shell-plain"   "$u"
      make_venv "$u" "$dir"
      ;;
  esac
  [ -n "$PLAIN_LIST" ] && settings_put "$dir/settings.sh" "$u" "PROMPT_PLAIN_FROM=\"$PLAIN_LIST\""
  return 0
}

installer_body() {
  if [ "$BACKEND" = powerline ]; then
    cat <<'EOF'
# The prompt (Powerline, `powerline` package): ~/.config/shell-prompt-setup/powerline.sh. Works in zsh and bash.
[ -r "$HOME/.config/shell-prompt-setup/powerline.sh" ] && . "$HOME/.config/shell-prompt-setup/powerline.sh"
EOF
  else
    cat <<'EOF'
# The prompt (Powerline, powerline-shell): ~/.config/shell-prompt-setup/powerline-shell.sh. Works in zsh and bash.
[ -r "$HOME/.config/shell-prompt-setup/powerline-shell.sh" ] && . "$HOME/.config/shell-prompt-setup/powerline-shell.sh"
EOF
  fi
}

installer_smoke() {
  if [ "$BACKEND" = powerline ]; then
    echo 'test "$SPS_PROMPT" = powerline && powerline-render shell left >/dev/null'
  else
    echo 'test "$SPS_PROMPT" = powerline-shell && "$SPS_PS" 0 >/dev/null'
  fi
}

# A rc file that already loads Powerline by hand would draw two prompts. Say so and skip it, or with
# --force remove the standard Debian "# Powerline configuration" block (the file is backed up first).
installer_before_rc() {
  local rc=$1 mine tmp
  [ -f "$rc" ] || return 0
  mine='bindings/(bash|zsh)/powerline|powerline-daemon|_update_ps1|powerline-shell'
  others() { awk '/^# >>> shell-prompt-setup: /{skip=1} !skip{print} /^# <<< shell-prompt-setup: /{skip=0}' "$rc" | grep -n -E "$mine" | head -3; }
  [ -n "$(others)" ] || return 0
  if [ "$FORCE" = 1 ] && grep -qx '# Powerline configuration' "$rc"; then
    tmp=$(mktemp "${TMPDIR:-/tmp}/sps-file.XXXXXX")
    awk '/^# Powerline configuration$/{skip=1} !skip{print} skip && /^fi$/{skip=0}' "$rc" > "$tmp"
    run cp -p "$rc" "$rc.bak.$(ts)"
    overwrite_file "$tmp" "$rc"
    rm -f "$tmp"
    say "  $rc: old \"Powerline configuration\" block removed (backup kept)"
    [ -n "$(others)" ] || return 0
  fi
  warn "$rc already loads Powerline itself ($(others | head -1 | cut -c1-70)); not adding a second prompt. Remove those lines, or re-run with --force to remove the standard \"# Powerline configuration\" block."
  RC=1
  return 1
}

installer_done() {
  say "Powerline needs a Powerline-patched font in the terminal you look at; with --plain-from, listed ssh clients get a glyph-free theme."
}

sps_main "$@"
