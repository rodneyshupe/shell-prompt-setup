#!/usr/bin/env bash
#
# shell-prompt-setup, Starship prompt: a two-line prompt with plain-text symbols (no special font needed)
# for zsh or bash, plus an optional zsh setup (autosuggestions, syntax highlighting, completion, history).
# For the Powerline prompt use install-powerline.sh instead.
#
#   curl -fsSL https://raw.githubusercontent.com/rodneyshupe/shell-prompt-setup/main/install.sh | bash
#   curl -fsSL .../install.sh | sudo bash -s -- --users alice,bob --shell
#
# Two components, installed into each user's existing shell (zsh or bash, from the login shell):
#   prompt     Starship + prompt.sh (corners, ssh depth, orange ssh variant). zsh or bash.
#   zsh setup  history, completion, colors, key bindings, plugins. zsh only; skip with --prompt-only.
# Nothing replaces your ~/.zshrc or ~/.bashrc: the installer adds marked blocks to them (and removes
# them again with --uninstall). Its own files live in ~/.config/shell-prompt-setup/.
#
# Run `install.sh --help` for all options. Works from a clone (uses ./lib and ./config) or piped from curl
# (downloads them from --base-url). No user names are built in: pass them with --users.

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

# ---- what is specific to the Starship prompt -----------------------------------------------------
PROMPT_NAME=starship
PROMPT_CONFIG_FILES="starship/prompt.sh starship/starship.toml"
PROMPT_PKGS_APT="starship"
PROMPT_PKGS_BREW="starship"
VIP=""
SQUARE_FROM=""
SQUARE_LIST=""
ROUND_BLOCK=""
FRAME_COLOR=""
MAIN_TOML=""
SSH_VARIANT=""

installer_usage() {
  cat <<'USAGE'
Usage: install.sh [options]        (Starship prompt; install-powerline.sh is the Powerline one)

Starship settings
  --vip ADDRESS    Show a [VIP] marker in the prompt while this host holds ADDRESS (keepalived etc.).
  --square-from IP[,IP...]
                   Square corners (┌─ └─) instead of rounded for ssh sessions whose client address is
                   in the list (a browser SSH terminal whose font draws rounded ones unevenly).
  --round-block [halfcircle|powerline]
                   Rounded ends on the ssh block instead of a square one. halfcircle (the default) is plain
                   Unicode, no patched font, but only about cap height. powerline is full height, a real
                   rounded rectangle, but needs a Powerline-patched font (or a terminal that draws Powerline
                   glyphs itself). Not used for clients listed with --square-from. --no-round-block turns it off.
  --frame-color N  Color of the frame, separators, host name and prompt character, an xterm-256 number
                   (default 34, green; 4 or 12 = the old blue). The ssh variant stays orange.
USAGE
}

installer_option() {
  case "$1" in
    --vip)           VIP=${2:?--vip needs an address}; OPT_SHIFT=2 ;;
    --vip=*)         VIP=${1#*=}; OPT_SHIFT=1 ;;
    --square-from)   SQUARE_FROM=${2:?--square-from needs addresses}; OPT_SHIFT=2 ;;
    --square-from=*) SQUARE_FROM=${1#*=}; OPT_SHIFT=1 ;;
    --round-block)
      case "${2:-}" in
        powerline|halfcircle) ROUND_BLOCK=$2; OPT_SHIFT=2 ;;
        *) ROUND_BLOCK=1; OPT_SHIFT=1 ;;
      esac ;;
    --round-block=*)
      ROUND_BLOCK=${1#*=}; OPT_SHIFT=1
      case "$ROUND_BLOCK" in powerline|halfcircle) ;; *) die "--round-block style must be halfcircle or powerline, got '$ROUND_BLOCK'" ;; esac ;;
    --no-round-block) ROUND_BLOCK=0; OPT_SHIFT=1 ;;
    --frame-color)   FRAME_COLOR=${2:?--frame-color needs a color number}; OPT_SHIFT=2 ;;
    --frame-color=*) FRAME_COLOR=${1#*=}; OPT_SHIFT=1 ;;
    *) OPT_SHIFT=0 ;;
  esac
}

installer_check() {
  if [ -n "$VIP" ]; then
    case "$VIP" in *[!0-9.]*|"") die "--vip must be an IPv4 address, got '$VIP'" ;; esac
  fi
  if [ -n "$FRAME_COLOR" ]; then
    case "$FRAME_COLOR" in *[!0-9]*|"") die "--frame-color must be a color number 0-255, got '$FRAME_COLOR'" ;; esac
    [ "$FRAME_COLOR" -le 255 ] || die "--frame-color must be a color number 0-255, got '$FRAME_COLOR'"
  fi
  if [ -n "$SQUARE_FROM" ]; then
    case "$SQUARE_FROM" in *[!0-9.:,a-fA-F]*|"") die "--square-from must be a comma-separated list of IP addresses, got '$SQUARE_FROM'" ;; esac
    SQUARE_LIST=$(printf '%s' "$SQUARE_FROM" | tr ',' ' ')
  fi
}

# The source starship.toml uses `bold 34` (green) for the frame, separators, host name and prompt
# character. Generated into temp files so the source tree is never written to: the local file with
# --frame-color applied (the same as the source by default) and the orange variant for ssh sessions.
installer_global() {
  MAIN_TOML=$(mktemp "${TMPDIR:-/tmp}/starship.XXXXXX") || die "cannot create a temp file"
  SSH_VARIANT=$(mktemp "${TMPDIR:-/tmp}/starship-ssh.XXXXXX") || die "cannot create a temp file"
  sed "s/bold 34/bold ${FRAME_COLOR:-34}/g" "$SRC/starship/starship.toml" > "$MAIN_TOML"
  sed 's/bold 34/bold 208/g' "$SRC/starship/starship.toml" > "$SSH_VARIANT"
}

installer_user() {
  local u=$1 dir=$3 vip sq
  place "$SRC/starship/prompt.sh"      "$dir/prompt.sh"          "$u"
  place "$MAIN_TOML"                  "$dir/starship.toml"      "$u"
  place "$SSH_VARIANT"                 "$dir/starship-ssh.toml"  "$u"
  vip=${VIP:-$M_VIP}; sq=${SQUARE_LIST:-$M_SQUARE}
  set --
  [ -n "$vip" ] && set -- "$@" "PROMPT_VIP=$vip"
  [ -n "$sq" ] && set -- "$@" "PROMPT_SQUARE_FROM=\"$sq\""
  [ -n "$ROUND_BLOCK" ] && set -- "$@" "PROMPT_ROUND_BLOCK=$ROUND_BLOCK"
  [ $# -gt 0 ] && settings_put "$dir/settings.sh" "$u" "$@"
  return 0
}

installer_body() {
  cat <<'EOF'
# The prompt (Starship): ~/.config/shell-prompt-setup/prompt.sh. Works in zsh and bash.
[ -r "$HOME/.config/shell-prompt-setup/prompt.sh" ] && . "$HOME/.config/shell-prompt-setup/prompt.sh"
EOF
}

installer_smoke() { echo 'test -n "$STARSHIP_SHELL" && starship prompt >/dev/null'; }

installer_cleanup() { rm -f "$MAIN_TOML" "$SSH_VARIANT"; return 0; }

sps_main "$@"
