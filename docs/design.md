# Design notes

Why the prompt looks and works the way it does, what was tried, and the traps hit on the way.

## Structure: a prompt that works in zsh and bash, and a separate zsh setup

The repo has separate parts so any can be used without the others:

- **Starship prompt** (`config/starship/`, installed by `install.sh`): `starship.toml` and `prompt.sh`. Starship already supports zsh and
  bash, and the TOML is shell-independent, so everything that is not Starship's own config lives in **one POSIX-sh file**, `prompt.sh`, that
  both shells source: the corner choice, the ssh hop counter and label, the switch to the orange config, the `ssh()` function, and finally
  `starship init zsh` or `starship init bash`, chosen with `$ZSH_VERSION` / `$BASH_VERSION`. One file means the two shells cannot drift
  apart. It has to stay POSIX: no arrays, no `[[ ]]`, no zsh glob qualifiers, nothing newer than bash 3.2 (macOS `/bin/bash`).
  Tested on bash 3.2, bash 5 and zsh 5.9; Starship's bash integration needs nothing else.
- **Powerline prompt** (`config/powerline/`, installed by `install-powerline.sh`): see [Powerline](#powerline-as-a-separate-installer) below.
- **zsh setup** (`config/zsh/`): history, completion, colors, key bindings, plugins. Zsh-only by nature (the plugins are zsh plugins),
  and optional (`--prompt-only`). See [zsh-setup.md](zsh-setup.md).
- **`lib/common.sh`**: what the two installers share (users and login shells, packages, files, marked blocks, migration, smoke test,
  `--uninstall`). Each installer is a short script that sources it and defines only its prompt-specific hooks (which files to place, the
  block body, which packages, how to prove the prompt loaded). Both download the library and their config files through `curl | bash`, so
  each stays a single command.

### Why marked blocks instead of replacing `~/.zshrc`

The first version installed a whole-file `~/.zshrc`. That cannot work for bash, where `~/.bashrc` always exists and always has the
distribution's content, and it is rude to a zsh user who has their own setup. So the installer only **appends a marked block**
(`# >>> shell-prompt-setup: <name> >>>` … `# <<< … <<<`) that sources a file in `~/.config/shell-prompt-setup/`, replaces that block in
place on re-runs, backs the file up the first time, and removes the blocks again with `--uninstall`. Consequences worth knowing:

- The project's own files (`prompt.sh`, `starship.toml`, ...) live in their own directory, so a user's own `~/.config/starship.toml` is
  never touched, and `STARSHIP_CONFIG` is pointed at the project's file explicitly. Removing the project is one directory and the blocks.
- Order matters in `~/.zshrc`: the `prompt` block goes before the `zsh-setup` block, because the syntax-highlighting plugin has to be
  loaded last. `block_put` inserts a new prompt block before an existing zsh-setup block.
- On macOS terminals start **login** shells, which read `~/.bash_profile` (or the first of `.bash_login`, `.profile`), not `~/.bashrc`;
  on Linux the block goes into `~/.bashrc`. `prompt.sh` returns at once in a non-interactive shell, because bash also reads `~/.bashrc`
  for `ssh host command` on some systems.
- Per-machine settings (`PROMPT_VIP`, `PROMPT_SQUARE_FROM`, `PROMPT_CORNERS`) are plain `export` lines in `settings.sh`, read by
  `prompt.sh`, so they work the same in both shells. `--vip` and `--square-from` change only the lines they are given.
- `--ssh-agent` has a zsh and a bash version of its block (the bash one sets the `EXIT` trap).
- The installer detects the shell from the user's **login shell** (passwd, or `dscl` on macOS), not from `$SHELL` of the process that runs
  it, because it often runs as root for other users. `--shells both` adds the other one; a login shell that is neither is reported and
  skipped rather than guessed.
- The earlier whole-file layout is migrated automatically (recognised by its header), so re-running the installer on an old machine is safe.

## Powerline as a separate installer

The first prompt of this setup was Powerline (the Debian `powerline` package on the guests, `powerline-shell` on the Mac). It is available
again as `install-powerline.sh`, on purpose as **its own installer rather than a flag of `install.sh`**: it has a different dependency stack
(an apt package, or a Python virtualenv), different configuration and different caveats, so it is updated and tested on its own, and the
Starship installer does not grow options that only apply to the other prompt. The shared mechanics are in `lib/common.sh`, so the two cannot
drift on shell detection, blocks, migration or uninstall. Choices:

- **One `prompt` block.** Both installers write the same marked block, with a different body (`prompt.sh` or `powerline.sh` /
  `powerline-shell.sh`). Switching prompts rewrites that block in place: never two prompts, `--uninstall` needs no special case. The other
  prompt's files stay in `~/.config/shell-prompt-setup/`, unused.
- **Backend by OS.** Linux: the `powerline` package (what the guests ran); macOS: `powerline-shell` (what the Mac ran). `--backend
  powerline-shell` also works on Linux, and is what the tests use to cover it. The `powerline` package is Linux-only here.
- **What of your old Powerline config is kept.** Compared with the package's defaults, your 46-file `~/.config/powerline` changed
  nothing that matters except two things: `config.json` selects the `default_leftonly` shell theme (no truecolor), and that theme gained
  the clock segment (`%l:%M %p`, priority 5). The other differences (weather and mail segments in the `wm` theme, a missing `workspace`
  colour) are leftovers of copying another version's defaults. So the overlay is just those two files.
- **The overlay is layered, not copied to `~/.config/powerline`.** `POWERLINE_CONFIG_PATHS=<package config>:<overlay>[:~/.config/powerline]`:
  later paths win, and the **system directory has to be listed first**, otherwise the base themes are not found (verified: the overlay
  is silently ignored in the other order, and the theme fails to load without the system path). A user's own `~/.config/powerline`, if any,
  goes last and wins, so someone who customised Powerline for tmux or vim keeps that.
- **powerline-shell in a private virtualenv** (`~/.config/shell-prompt-setup/venv`, created as the user): no pip into the system Python (blocked
  by PEP 668 on current Debian and Homebrew), no sudo, no dependency on pipx, removed with the directory. It reads
  `$XDG_CONFIG_HOME/powerline-shell/config.json`, so the prompt function sets `XDG_CONFIG_HOME` for **that one command only** (exporting it would
  redirect every other tool's config): one directory per variant, `powerline-shell-patched/` and `powerline-shell-plain/`.
- **Glyphs.** Powerline separators are Private Use Area glyphs (U+E0B0 ...) that only render with a patched font in the terminal you look
  at, which is exactly what failed in a browser SSH terminal. The server cannot tell, so `--plain-from IP[,IP]` lists the ssh clients that
  get the glyph-free theme (`ext.shell.top_theme=unicode` for `powerline`, `"mode": "compatible"` for powerline-shell); everyone else gets the
  full look. The earlier approach (a client-side `LC_NERDFONT=1` marker sent by every glyph-capable machine) was dropped: it needs setup on
  every client. `PROMPT_PLAIN=1` forces the plain theme. On macOS `--fonts` installs a patched font (Homebrew cask
  `font-meslo-for-powerline`); choosing it in the terminal profile stays manual.
- **An rc that already loads another prompt by hand** (the guests' `~/.bashrc` has the standard `# Powerline configuration` block, the Proxmox nodes'
  has the powerline-shell `_update_ps1` snippet) would draw two prompts: both assign `PS1` on every prompt and the winner depends on the order of
  `PROMPT_COMMAND`. This is a property of any prompt installer, not just the Powerline one, so the guard lives in `lib/common.sh`
  (`prompt_conflict_guard`) and both installers use it. It refuses to add a block and says which lines it found; with `--force` it removes the two
  standard snippets it recognises (after a backup) and nothing else. A hand-written `starship init`, oh-my-posh and the like are never removed: the
  installer cannot know what else those lines do.
- **Not ported on purpose:** the Starship prompt's own features (ssh depth label, orange frame over ssh, ahead/behind counts, VIP marker,
  rounded/square corners). Powerline has its own segments and themes; a lookalike would be a different project.

## Why plain-text symbols (the Starship prompt)

A Powerline prompt draws its separators, git branch and lock with Private Use Area glyphs (U+E0A0-E0B3). Those only
render when the **viewing** side has a Powerline/Nerd Font:

- A local terminal app with such a font: fine.
- A browser-rendered SSH terminal (Cloudflare's, for example): the glyphs are missing and the terminal's web font can't be
  changed.

The server side is identical in both cases (same locale, same sshd settings), and the two connection paths can't always
be told apart by source address. So the fix is a prompt that only uses characters every font has, rather than a prompt
that switches look per connection.

## Decisions

- **Shell:** zsh (the macOS default), so a Mac and the servers match.
- **Prompt:** Starship. Works in bash and zsh; one TOML config shared by Linux and macOS.
- **Symbols:** Starship's `plain-text-symbols` preset. It was the only one that rendered correctly in a browser SSH terminal
  (`nerd-font-symbols`, `no-nerd-font` and the powerline-style presets `pastel-powerline`, `tokyo-night`, `gruvbox-rainbow`
  all showed missing glyphs).
- **Layout:** two lines, box-drawing frame, `│` separators, clock first (12-hour).
- **Corners:** rounded `╭─` / `╰─`, with square `┌─` / `└─` where a font draws the rounded ones unevenly (a browser SSH
  terminal). The corners are Starship `env_var` modules (`PROMPT_CORNER_TOP` / `PROMPT_CORNER_BOTTOM`, defaulting to rounded), so
  switching needs no second config file and no extra process: `prompt.sh` exports the square ones when `PROMPT_CORNERS=square` or when
  the ssh client address is in `PROMPT_SQUARE_FROM`. Detection is by client address because the browser terminal can't send a marker;
  its sessions arrive from the tunnel host, so a normal session coming through that same host gets square corners too.
- **Remote marker:** in an ssh session the whole frame (corners and `│` separators) is **orange** and a bold black-on-orange `ssh` block
  opens line 1; locally the frame is blue and there is no block. Starship styles are static, so the orange frame is a second config,
  `starship-ssh.toml`, generated by `install.sh` from `starship.toml` (every `bold blue` -> `bold 208`: frame, separators and host name) and selected by `prompt.sh` via
  `STARSHIP_CONFIG` when `$SSH_CONNECTION` is set. The block itself is an `env_var.SSH_CONNECTION` module, so it needs no fork. 208 is
  the 256-colour orange, which works where truecolor does not (Terminal.app).
  The block's text is `fg:16` (true black), not `black`: with bold, many terminals draw the 8-colour black as dark grey, which is hard to read on orange.
- **ssh depth:** the block's text is the number of ssh hops: `ssh`, `ssh2`, `ssh3`. `SSH_CONNECTION` only describes the current
  connection, so the depth can't be read from it. The first hop is detectable but a second one is not, unless the client says so:
  `prompt.sh` defines `ssh()` to send `LC_PROMPT_HOPS=<own depth + 1>` (`-o SendEnv`), and sshd's default `AcceptEnv LC_*` delivers it.
  The block is an `env_var.PROMPT_SSH_LABEL` module whose text `prompt.sh` computes (non-numeric values are ignored). Limits: only ssh typed in
  zsh carries the counter, and a server whose sshd doesn't accept `LC_*` shows one hop. Rejected: guessing from the client address (needs a
  list of your own machines) and a custom module that walks the process tree (a fork per prompt).
- **Ahead/behind:** Starship's `git_status` can only show a count always or never, so the counts come from a `custom.gitsync` module
  (`git rev-list --left-right --count @{upstream}...HEAD`): `>` for one ahead, `>3` for three, `<`/`<2` behind, `> <2` both. Counts show
  only above 1. It prints nothing outside a repo or without an upstream. Custom modules are off unless `when` is set (`when = true`),
  and the format must wrap `$output` in a `( ... )` group or an empty result leaves a stray separator.
- **Path:** up to 6 folders, `…/` when truncated. Inside a repo the path starts at the repo root, so the repo name stays visible.
- **Colors:** frame and separators bold blue locally (orange in an ssh session, see Remote marker), time white, user name bold azure
  for root (256-colour 39, the complement of the orange frame; red was too close to it) and bold cyan for anyone else, `@` white and the
  host name the **same blue as the frame** locally and **bold orange** in an ssh session (the generated variant turns every `bold blue` orange), path bold white, git bold magenta, git status and exit
  code bold red, final `>` bold green or red after a failure. The host is a separate Starship module, so its color can't depend on the
  user. For a bolder look give `hostname.style` a background, e.g.
  `bold black bg:green`.
- **Errors and timing:** extra segments on line 1, only when relevant: `exit <code> <meaning> <signal>`, `took <duration>`
  for commands over 2 s.
- **No Oh My Zsh:** Starship plus the two packaged plugins covers it, with a faster start.
- **Language modules need a project marker.** Starship shows a module such as `via py v3.14` for any `*.py` file in the
  current folder, so a stray `test.py` in `~` or `~/Downloads` puts it on every prompt. Every module that has extension
  triggers gets `detect_extensions = []`, so it only shows for real markers (`pyproject.toml`, `package.json`, `go.mod`,
  `Cargo.toml`, ...). The languages that have no marker besides their extension never show (C, C++, Kotlin, Zig, ...);
  delete a module's line to bring it back. `cpp` and `fortran` are not listed at all: Starship 1.22 (Debian 13) has no
  such tables and warns about unknown keys on every prompt.
- **Completion:** case-insensitive, then fragments of a name (`docker-comp<Tab>`); ghost text from history first, then
  from real files and folders (`ZSH_AUTOSUGGEST_STRATEGY=(history completion)`). Glob characters (`*`) and history
  expansion (`!!`) are bold cyan because the highlighter's default blue is unreadable on dark backgrounds.
- **VIP marker:** a `custom` module shows a bold yellow `[VIP]` while the host has the address in `$PROMPT_VIP`
  (keepalived etc.). The check is `ip -4 -o addr show | grep` on every prompt and costs about 1-2 ms of a roughly 15 ms
  render. It is read when the prompt draws, so it lags a failover until the next Enter.

### Rejected alternatives

| Option | Why not |
|---|---|
| Keep Powerline, switch theme per connection | Needed a client-side marker (an env var sent by ssh `SetEnv`); still two looks to maintain. |
| Pure | Nice and font-safe, but zsh-only and minimal; no clock without extra work. |
| Oh My Posh | Same idea as Starship, wordier config. |
| Powerlevel10k | zsh-only and in limited-maintenance mode. |
| Kali/Parrot-style bracket prompts | Previewed; preferred `│` separators without brackets. |

## What it looks like

```
╭─ 3:30 PM │ root@webserver │ …/project │ git main !? >2
╰─> _

╭─ ssh  3:30 PM │ root@webserver │ ~   (orange frame, orange `ssh` block; `ssh2` after a second hop)
╰─> _

╭─ 3:30 PM │ root@webserver │ …/project/config/nginx │ git main !? │ exit 1 ERROR
╰─> _

┌─ 3:30 PM │ root@webserver │ /opt/stacks │ took 12s │ exit 127 NOTFOUND
╰─> _
```

Git symbols (plain-text preset, bold red, after the branch name, e.g. `git main +!?>`):

| Symbol | Meaning |
|---|---|
| `!` | modified, not staged |
| `+` | staged |
| `?` | untracked |
| `x` | deleted |
| `r` | renamed |
| `=` | merge conflicts |
| `$` | stash present |
| `>` `>3` / `<` `<2` / `> <2` | ahead of / behind / both, from the upstream; a count only above 1; only as fresh as the last `git fetch` |

During a git operation `git_state` adds e.g. `(REBASING 2/5)`, `(MERGING)`, `(CHERRY-PICKING)`, `(BISECTING)`.

## Format-string gotchas (hit while building `starship.toml`)

- `(`, `)`, `[`, `]` are special in Starship format strings; escape them as `\\(` etc. in TOML basic strings.
- A module's `format` can't reference another module (`$git_status` inside `git_branch.format` renders nothing). Put both in
  the top-level `format` and wrap them in a `( ... )` conditional group so the separator disappears outside a repo.
- `$all` includes `$line_break`, so end line 1 with `$all\` rather than a literal newline, or you get a blank line.
- Modules that start with text (`via py ...`) expect a space before them, but `cmd_duration` and `git_status` end without
  one; that is why the format has a space before `$all`.
- TOML rejects duplicate tables, so the hand-written section and the appended `starship preset plain-text-symbols` tables
  must not define the same module twice.
- Preview a change without opening a new shell: `starship prompt`.

## Ideas not done

- `fzf` (Ctrl-T/Ctrl-R/Alt-C) and `fzf-tab`, for fuzzy file and history picking.
- pyenv/other version-manager init in the zsh setup for people who use one.
- A bash counterpart of the zsh setup (readline settings for case-insensitive completion, shared history); `ble.sh` for ghost text.
