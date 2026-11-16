# zsh setup

The optional, zsh-only half of the repo (`config/zsh/`). The prompt is separate: see [design.md](design.md). Install it with the
default `install.sh` for a zsh user, leave it out with `--prompt-only`, or add it to a bash user with `--shells both`.

`zsh-setup.zsh` is sourced from `~/.zshrc` by a marked block, and its parts are independent of the prompt. It sets, in this order:

1. **History:** 50 000 lines in `~/.zsh_history`, shared between sessions (`share_history`), no duplicates, a command starting with a space is
   not saved, extended timestamps. `interactive_comments` (allow `# comments` on the command line), `no_beep`.
2. **Homebrew** (macOS and Linuxbrew): `brew shellenv`, so brew and its tools are on `PATH` in a fresh `.zshrc`.
3. **Completion:** `compinit`, an arrow-key menu (`menu select`), case-insensitive matching, then fragment matching
   (`docker-comp<Tab>` → `docker-compose.yaml`) through `matcher-list`. Zsh already expands partial path segments (`/u/l/b<Tab>` →
   `/usr/local/bin`) by default.
4. **Colors for `ls` and completion:** GNU `dircolors`/`ls` if present (Linux, or coreutils on macOS as `gdircolors`/`gls`), then any `ls`
   that accepts `--color=auto` (BusyBox on Alpine), otherwise `CLICOLOR` and BSD `ls -G`. Aliases `ls`, `ll`, `l`.
5. **Key bindings:** emacs mode; Up/Down search history for what is already typed (`up-line-or-beginning-search`).
6. **`~/.local/bin` on `PATH`.**
7. **`~/.zshrc.local`**, if it exists: yours, sourced here and never touched by the installer.
8. **Plugins** (from `/usr/share`, `$(brew --prefix)/share` or Linuxbrew): `zsh-autosuggestions` with
   `ZSH_AUTOSUGGEST_STRATEGY=(history completion)` (ghost text from history first, then from the real files and folders), and
   `zsh-syntax-highlighting` **last**, as its README requires. The highlighter's default blue for globs (`*`, `?`) and history expansion
   (`!!`) is unreadable on dark backgrounds, so both are `fg=cyan,bold`.

## Linux: `~/.zprofile`

zsh login shells do not read `/etc/profile`, which is where Debian sets root's `PATH` (including `sbin`) and runs `/etc/profile.d/*`.
A block in `~/.zprofile` does `emulate sh -c '. /etc/profile'` so a zsh login gets what a bash login gets. Not needed on macOS.

## Order in `~/.zshrc`

The installer appends blocks, never reorders your file: `prompt` first, then `zsh-setup`, so the highlighter is loaded after
everything else the project adds. If you add your own lines after the blocks that define widgets, move the `zsh-setup` block to the
very end.

## If you already use Oh My Zsh or another framework

Use `--prompt-only`. Two completion initialisations, two sets of plugins and two history configurations in one file is a recipe for
slow starts and surprises; the prompt block alone is just `source prompt.sh`. Remove the framework's prompt/theme setting so only
Starship draws the prompt.
