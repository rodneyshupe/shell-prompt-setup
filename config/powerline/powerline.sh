# shell-prompt-setup: the Powerline prompt, using the `powerline` package (Debian/Ubuntu). Sourced from
# ~/.zshrc or ~/.bashrc (a managed block that install-powerline.sh adds). Works in zsh and bash.
#
# The package reads its own config from /usr/share/powerline/config_files; the overlay in
# ~/.config/shell-prompt-setup/powerline (clock segment, left-only theme) is layered on top through
# POWERLINE_CONFIG_PATHS, so nothing is written to ~/.config/powerline. A ~/.config/powerline of your own
# is layered last and wins.
#
# Powerline draws its separators with Powerline glyphs, which need a patched font in the terminal you
# look at. For ssh clients listed in PROMPT_PLAIN_FROM (settings.sh), or with PROMPT_PLAIN=1, the
# glyph-free `unicode` theme is used instead.

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

_sps_pl=${POWERLINE_ROOT:-/usr/share/powerline}
if [ -d "$_sps_pl/config_files" ] && command -v powerline-daemon >/dev/null 2>&1; then
  _sps_paths=$_sps_pl/config_files:$_sps_dir/powerline
  [ -d "$HOME/.config/powerline" ] && _sps_paths=$_sps_paths:$HOME/.config/powerline
  export POWERLINE_CONFIG_PATHS=$_sps_paths
  [ -n "$_sps_plain" ] && export POWERLINE_CONFIG_OVERRIDES=ext.shell.top_theme=unicode
  export SPS_PROMPT=powerline
  powerline-daemon -q
  if [ -n "${BASH_VERSION:-}" ] && [ -r "$_sps_pl/bindings/bash/powerline.sh" ]; then
    POWERLINE_BASH_CONTINUATION=1
    POWERLINE_BASH_SELECT=1
    . "$_sps_pl/bindings/bash/powerline.sh"
  elif [ -n "${ZSH_VERSION:-}" ] && [ -r "$_sps_pl/bindings/zsh/powerline.zsh" ]; then
    . "$_sps_pl/bindings/zsh/powerline.zsh"
  fi
fi

unset _sps_dir _sps_plain _sps_pl _sps_paths
