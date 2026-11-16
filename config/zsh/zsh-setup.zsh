# shell-prompt-setup: the zsh setup (history, completion, colors, key bindings, plugins). Sourced from
# ~/.zshrc by a managed block that install.sh adds (skipped with --prompt-only). The prompt is separate:
# see prompt.sh. Your own additions go in ~/.zshrc.local (sourced below, never touched by the installer).

# History: large, shared between sessions, no duplicates.
# Commands starting with a space are not saved.
HISTFILE=~/.zsh_history
HISTSIZE=50000
SAVEHIST=50000
setopt share_history extended_history hist_ignore_all_dups hist_ignore_space hist_reduce_blanks

setopt interactive_comments   # allow "# comments" on the command line
setopt no_beep

# Homebrew (macOS): puts brew and its tools on PATH.
for _brew in /opt/homebrew/bin/brew /usr/local/bin/brew /home/linuxbrew/.linuxbrew/bin/brew; do
  if [[ -x $_brew ]]; then eval "$($_brew shellenv)"; break; fi
done
unset _brew

# Completion: menu you can arrow through; case-insensitive, then fragments of a name
# (docker-comp<Tab> -> docker-compose.yaml).
autoload -Uz compinit && compinit
zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}' 'r:|[._-]=* r:|=*' 'l:|=* r:|=*'

# Colors for ls and completion. GNU dircolors/ls (Linux, or coreutils on macOS) if present,
# then any ls that takes --color=auto (BusyBox on Alpine), otherwise BSD ls colors (macOS).
if (( $+commands[dircolors] )); then _dircolors=dircolors; _gnuls=ls
elif (( $+commands[gdircolors] )); then _dircolors=gdircolors; _gnuls=gls
fi
if [[ -n $_dircolors ]]; then
  eval "$($_dircolors)"
  zstyle ':completion:*' list-colors ${(s.:.)LS_COLORS}
  alias ls="$_gnuls --color=auto"
  alias ll="$_gnuls --color=auto -l"
  alias l="$_gnuls --color=auto -lA"
elif ls --color=auto -d . >/dev/null 2>&1; then
  alias ls='ls --color=auto'
  alias ll='ls --color=auto -l'
  alias l='ls --color=auto -lA'
else
  export CLICOLOR=1
  alias ls='ls -G'
  alias ll='ls -G -l'
  alias l='ls -G -lA'
fi
unset _dircolors _gnuls

# Emacs-style keys (like bash); Up/Down search history for what's already typed
bindkey -e
autoload -Uz up-line-or-beginning-search down-line-or-beginning-search
zle -N up-line-or-beginning-search
zle -N down-line-or-beginning-search
bindkey '^[[A' up-line-or-beginning-search
bindkey '^[OA' up-line-or-beginning-search
bindkey '^[[B' down-line-or-beginning-search
bindkey '^[OB' down-line-or-beginning-search

# User scripts
export PATH="$HOME/.local/bin:$PATH"

# Your own additions (aliases, PATH, ...)
[[ -r ~/.zshrc.local ]] && source ~/.zshrc.local

# Plugins (Debian/Ubuntu: /usr/share, Homebrew: $(brew --prefix)/share). Syntax highlighting last.
# Ghost-text suggestions: from history first, then from real files/folders (completion).
ZSH_AUTOSUGGEST_STRATEGY=(history completion)
for _d in /usr/share /opt/homebrew/share /usr/local/share /home/linuxbrew/.linuxbrew/share; do
  [[ -r $_d/zsh-autosuggestions/zsh-autosuggestions.zsh ]] && { source $_d/zsh-autosuggestions/zsh-autosuggestions.zsh; break; }
done
for _d in /usr/share /opt/homebrew/share /usr/local/share /home/linuxbrew/.linuxbrew/share; do
  [[ -r $_d/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]] && { source $_d/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh; break; }
done
unset _d

# The default blue for globs (*, ?) and history expansion (!!) is unreadable on dark backgrounds.
(( ${+ZSH_HIGHLIGHT_STYLES} )) && {
  ZSH_HIGHLIGHT_STYLES[globbing]='fg=cyan,bold'
  ZSH_HIGHLIGHT_STYLES[history-expansion]='fg=cyan,bold'
}
