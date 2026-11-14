# shell-prompt-setup: the prompt. Sourced from ~/.zshrc or ~/.bashrc (a managed block that install.sh
# adds), so it must stay POSIX sh syntax that both zsh and bash (3.2 on macOS included) understand.
#
# What it does: shows the Starship prompt, and
#   - picks rounded corners, or square ones where the font draws rounded ones unevenly
#     (PROMPT_CORNERS=square, or an ssh client whose address is in PROMPT_SQUARE_FROM),
#   - in an ssh session switches to the orange variant of the config and labels the session
#     ssh, ssh2, ssh3, ... by hop count (an ssh() function below sends the count as LC_PROMPT_HOPS),
#   - reads per-machine settings (PROMPT_VIP, PROMPT_SQUARE_FROM, ...) from settings.sh.
# Files live in ~/.config/shell-prompt-setup/ (override with SHELL_PROMPT_SETUP_DIR).

# Interactive shells only (bash reads ~/.bashrc for `ssh host command` on some systems).
case $- in *i*) ;; *) return 0 ;; esac

_sps_dir=${SHELL_PROMPT_SETUP_DIR:-$HOME/.config/shell-prompt-setup}

# Per-machine settings written by install.sh (--vip, --square-from): plain `export NAME=value` lines.
[ -r "$_sps_dir/settings.sh" ] && . "$_sps_dir/settings.sh"

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
  [ -r "$_sps_dir/starship-ssh.toml" ] && _sps_config=$_sps_dir/starship-ssh.toml
else
  unset PROMPT_HOPS PROMPT_SSH_LABEL
fi
[ -r "$_sps_config" ] && export STARSHIP_CONFIG="$_sps_config"

# Sends the next hop count to the host being logged in to. Only ssh typed in this shell carries it.
ssh() { LC_PROMPT_HOPS=$(( ${PROMPT_HOPS:-0} + 1 )) command ssh -o SendEnv=LC_PROMPT_HOPS "$@"; }

# Start Starship for the shell that is running this file.
if command -v starship >/dev/null 2>&1; then
  if [ -n "${ZSH_VERSION:-}" ]; then
    eval "$(starship init zsh)"
  elif [ -n "${BASH_VERSION:-}" ]; then
    eval "$(starship init bash)"
  fi
fi

unset _sps_dir _sps_square _sps_config
