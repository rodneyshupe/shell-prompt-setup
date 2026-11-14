# shell-prompt-setup: the Powerline prompt, using powerline-shell (https://github.com/b-ryan/powerline-shell),
# installed into a private virtualenv in ~/.config/shell-prompt-setup/venv. Sourced from ~/.zshrc or
# ~/.bashrc (a managed block that install-powerline.sh adds). Works in zsh and bash (3.2 on macOS included).
#
# Two configs live next to it: powerline-shell-patched (the Powerline look, needs a patched font in the
# terminal) and powerline-shell-plain (mode "compatible", no special font). powerline-shell reads
# $XDG_CONFIG_HOME/powerline-shell/config.json, so XDG_CONFIG_HOME is set for that one command only.
# The plain one is used for ssh clients listed in PROMPT_PLAIN_FROM (settings.sh), or with PROMPT_PLAIN=1.

# Interactive shells only.
case $- in *i*) ;; *) return 0 ;; esac

_sps_dir=${SHELL_PROMPT_SETUP_DIR:-$HOME/.config/shell-prompt-setup}
[ -r "$_sps_dir/settings.sh" ] && . "$_sps_dir/settings.sh"

_sps_plain=
if [ "${PROMPT_PLAIN:-}" = 1 ]; then
  _sps_plain=1
elif [ -n "${SSH_CONNECTION:-}" ] && [ -n "${PROMPT_PLAIN_FROM:-}" ]; then
  case " $PROMPT_PLAIN_FROM " in *" ${SSH_CONNECTION%% *} "*) _sps_plain=1 ;; esac
fi

# These two stay set: the prompt function below runs on every prompt.
SPS_PS=$_sps_dir/venv/bin/powerline-shell
if [ -n "$_sps_plain" ]; then SPS_PS_XDG=$_sps_dir/powerline-shell-plain; else SPS_PS_XDG=$_sps_dir/powerline-shell-patched; fi

if [ -x "$SPS_PS" ]; then
  export SPS_PROMPT=powerline-shell
  if [ -n "${BASH_VERSION:-}" ]; then
    _sps_update_ps1() { local e=$?; PS1=$(XDG_CONFIG_HOME=$SPS_PS_XDG "$SPS_PS" "$e"); }
    case ";${PROMPT_COMMAND:-};" in
      *";_sps_update_ps1;"*) ;;
      *) PROMPT_COMMAND="_sps_update_ps1${PROMPT_COMMAND:+;$PROMPT_COMMAND}" ;;
    esac
  elif [ -n "${ZSH_VERSION:-}" ]; then
    _sps_update_ps1() { local e=$?; PS1="$(XDG_CONFIG_HOME=$SPS_PS_XDG "$SPS_PS" --shell zsh "$e")"; }
    case " $precmd_functions " in
      *" _sps_update_ps1 "*) ;;
      *) precmd_functions+=(_sps_update_ps1) ;;
    esac
  fi
fi

unset _sps_dir _sps_plain
