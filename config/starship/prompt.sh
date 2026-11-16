# shell-prompt-setup: the prompt. Sourced from ~/.zshrc or ~/.bashrc (a managed block that install.sh
# adds), so it must stay POSIX sh syntax that both zsh and bash (3.2 on macOS included) understand.
#
# What it does: shows the Starship prompt, and
#   - picks rounded corners, or square ones where the font draws rounded ones unevenly
#     (PROMPT_CORNERS=square, or an ssh client whose address is in PROMPT_SQUARE_FROM),
#   - in an ssh session switches to the orange variant of the config and labels the session
#     ssh, ssh2, ssh3, ... by hop count (an ssh() function below sends the count as LC_PROMPT_HOPS),
#   - colors the user name by access: root magenta, admin-group member gold, others cyan,
#   - reads per-machine settings (PROMPT_VIP, PROMPT_SQUARE_FROM, PROMPT_ROUND_BLOCK, ...) from settings.sh.
# Files live in ~/.config/shell-prompt-setup/ (override with SHELL_PROMPT_SETUP_DIR).

# Interactive shells only (bash reads ~/.bashrc for `ssh host command` on some systems).
case $- in *i*) ;; *) return 0 ;; esac

_sps_dir=${SHELL_PROMPT_SETUP_DIR:-$HOME/.config/shell-prompt-setup}

# Per-machine settings written by install.sh (--vip, --square-from): plain `export NAME=value` lines.
[ -r "$_sps_dir/settings.sh" ] && . "$_sps_dir/settings.sh"

# User name color by access level, worked out once per shell (not per prompt): root (uid 0) magenta, a member of an
# admin group gold, anyone else cyan. The groups are PROMPT_PRIV_GROUPS (settings.sh), default: sudo wheel admin docker
# (docker counts because it is root-equivalent). starship.toml shows whichever of the three variables is set.
unset PROMPT_USER_ROOT PROMPT_USER_PRIV PROMPT_USER_PLAIN
_sps_user=$(id -un 2>/dev/null || echo "${USER:-?}")
if [ "$(id -u 2>/dev/null)" = 0 ]; then
  export PROMPT_USER_ROOT=$_sps_user
else
  _sps_priv=
  for _sps_g in $(id -Gn 2>/dev/null); do
    case " ${PROMPT_PRIV_GROUPS:-sudo wheel admin docker} " in *" $_sps_g "*) _sps_priv=1 ;; esac
  done
  if [ -n "$_sps_priv" ]; then export PROMPT_USER_PRIV=$_sps_user; else export PROMPT_USER_PLAIN=$_sps_user; fi
fi

# Corners: rounded by default (starship.toml's env_var defaults); square when asked for.
_sps_square=
if [ "${PROMPT_CORNERS:-}" = square ]; then
  _sps_square=1
elif [ -n "${SSH_CONNECTION:-}" ] && [ -n "${PROMPT_SQUARE_FROM:-}" ]; then
  case " $PROMPT_SQUARE_FROM " in *" ${SSH_CONNECTION%% *} "*) _sps_square=1 ;; esac
fi
if [ -n "$_sps_square" ]; then
  export PROMPT_CORNER_TOP='┌─' PROMPT_CORNER_BOTTOM='└─'
fi

# ssh sessions: hop count (the ssh function below sends it as LC_PROMPT_HOPS; sshd accepts LC_*), the
# label ssh / ssh2 / ssh3, and the orange variant of the config. A session that arrives without a counter
# (a browser terminal, scp, a script) counts as one hop; a non-numeric value is ignored.
_sps_config=$_sps_dir/starship.toml
if [ -n "${SSH_CONNECTION:-}" ]; then
  case "${LC_PROMPT_HOPS:-}" in
    ''|*[!0-9]*) PROMPT_HOPS=1 ;;
    *) PROMPT_HOPS=$LC_PROMPT_HOPS ;;
  esac
  if [ "$PROMPT_HOPS" -gt 1 ]; then PROMPT_SSH_LABEL=ssh$PROMPT_HOPS; else PROMPT_SSH_LABEL=ssh; fi
  export PROMPT_HOPS PROMPT_SSH_LABEL
  # Rounded ends for the ssh block, opt in with PROMPT_ROUND_BLOCK (settings.sh, install.sh --round-block):
  #   1 or halfcircle  the Unicode half circles, no patched font, but only about cap height
  #   powerline        Powerline's rounded caps, full height, but they need a Powerline-patched font (or a terminal
  #                    that draws Powerline glyphs itself)
  # Not for a client that already gets square corners, because that is a font that draws rounded shapes badly.
  _sps_cap=
  if [ -z "$_sps_square" ]; then
    case "${PROMPT_ROUND_BLOCK:-}" in
      1|halfcircle) PROMPT_BLOCK_CAP_L='◖'; PROMPT_BLOCK_CAP_R='◗'; _sps_cap=1 ;;
      powerline)    PROMPT_BLOCK_CAP_L=$(printf '\356\202\266'); PROMPT_BLOCK_CAP_R=$(printf '\356\202\264'); _sps_cap=1 ;;
    esac
  fi
  if [ -n "$_sps_cap" ]; then export PROMPT_BLOCK_CAP_L PROMPT_BLOCK_CAP_R; else unset PROMPT_BLOCK_CAP_L PROMPT_BLOCK_CAP_R; fi
  [ -r "$_sps_dir/starship-ssh.toml" ] && _sps_config=$_sps_dir/starship-ssh.toml
else
  unset PROMPT_HOPS PROMPT_SSH_LABEL PROMPT_BLOCK_CAP_L PROMPT_BLOCK_CAP_R
fi
[ -r "$_sps_config" ] && export STARSHIP_CONFIG="$_sps_config"

# Sends the next hop count to the host being logged in to. Only ssh typed in this shell carries it.
ssh() { LC_PROMPT_HOPS=$(( ${PROMPT_HOPS:-0} + 1 )) command ssh -o SendEnv=LC_PROMPT_HOPS "$@"; }

# Start Starship for the shell that is running this file.
if ! command -v starship >/dev/null 2>&1; then
  # A fresh macOS login shell has no Homebrew on PATH yet (the zsh setup adds it later in ~/.zshrc).
  for _sps_b in /opt/homebrew/bin /usr/local/bin "$HOME/.local/bin"; do
    [ -x "$_sps_b/starship" ] && { PATH="$PATH:$_sps_b"; export PATH; break; }
  done
  unset _sps_b
fi
if command -v starship >/dev/null 2>&1; then
  if [ -n "${ZSH_VERSION:-}" ]; then
    eval "$(starship init zsh)"
  elif [ -n "${BASH_VERSION:-}" ]; then
    eval "$(starship init bash)"
  fi
fi

unset _sps_dir _sps_square _sps_config _sps_cap _sps_user _sps_priv _sps_g
