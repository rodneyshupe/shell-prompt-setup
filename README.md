# shell-prompt-setup

A prompt for **zsh and bash**: a two-line **[Starship](https://starship.rs)** prompt (the default), or the
**Powerline** look as a separate installer; plus an optional **zsh setup** (autosuggestions, syntax highlighting, friendlier Tab
completion, history). Debian/Ubuntu and macOS. The parts are separate, so take only what you want:

| | Installer | What it sets up |
|---|---|---|
| **Starship prompt** | [`install.sh`](install.sh) | Plain-text two-line prompt, ssh depth, orange frame over ssh, ahead/behind counts. zsh and bash. |
| **Powerline prompt** | [`install-powerline.sh`](install-powerline.sh) | The Powerline look: the `powerline` package on Linux, `powerline-shell` on macOS. zsh and bash. |
| **zsh setup** | either installer (zsh users; skip with `--prompt-only`) | History, completion, plugins, key bindings. zsh only. |

The prompt uses only plain characters (box-drawing lines, `│`, text labels such as `git`, `py`, `exit`). It needs
**no Powerline or Nerd Font**, so it renders the same in a browser-based SSH terminal, over a plain SSH session
or in a local terminal app.

```
╭─ 3:30 PM │ alice@webserver │ …/project/src │ git main !? >2 │ took 12s │ exit 1 ERROR via py v3.13.2
╰─>

╭─ ssh  3:30 PM │ alice@webserver │ ~
╰─>
```

In an ssh session the frame is **orange** and a black-on-orange block opens line 1: `ssh` for one hop, `ssh2` when you ssh again from that session, `ssh3` for a third, and so on. On your own machine the frame is blue and there is no block, so you can tell a remote host from the local machine, and how deep you are, at a glance.

## Quick start

For yourself, on this machine. The installer looks at your login shell (zsh or bash) and sets that one up, adding the
prompt and, for zsh, the zsh setup:

```bash
curl -fsSL https://raw.githubusercontent.com/rodneyshupe/shell-prompt-setup/main/install.sh | bash
```

Variations:

```bash
# only the prompt: nothing else in your zsh is touched (plugins, completion, history, key bindings are skipped)
curl -fsSL https://raw.githubusercontent.com/rodneyshupe/shell-prompt-setup/main/install.sh | bash -s -- --prompt-only

# the other shell too: your login shell plus the other one (zsh and bash)
curl -fsSL https://raw.githubusercontent.com/rodneyshupe/shell-prompt-setup/main/install.sh | bash -s -- --shells both

# several users on a Linux server (root needed), and make zsh their login shell
curl -fsSL https://raw.githubusercontent.com/rodneyshupe/shell-prompt-setup/main/install.sh \
  | sudo bash -s -- --users root,alice,bob --shell

# see what would happen first (changes nothing)
curl -fsSL https://raw.githubusercontent.com/rodneyshupe/shell-prompt-setup/main/install.sh | bash -s -- --dry-run
```

Or from a clone: `git clone https://github.com/rodneyshupe/shell-prompt-setup && cd shell-prompt-setup && ./install.sh --help`.

> Piping a script from the internet into a shell runs whatever is there. Read `install.sh` first, or clone and run
> it, or use `--dry-run`. The installer downloads four small files from `config/`.

Run it as your normal user on a Mac (Homebrew refuses root, and macOS needs Homebrew for the packages). No user names
are built in: other users than yourself are passed with `--users` (root needed).

### If you already have a zsh or bash setup

**Nothing of yours is replaced.** The installer never overwrites `~/.zshrc` or `~/.bashrc`: it appends a short marked block
(`# >>> shell-prompt-setup: prompt >>>` … `# <<< … <<<`) that sources its own files, and the first time it touches a file it keeps a
backup as `<file>.bak.<timestamp>`. Your aliases, `PATH` changes, nvm/pyenv lines and so on stay where they are.

- **Use `--prompt-only` if you already have a zsh setup** (history, completion, plugins). Without it the zsh setup is added too,
  and a second `compinit`, plugin or key-binding block can fight with yours.
- If your zsh config sets its own prompt (Oh My Zsh `ZSH_THEME`, Powerlevel10k, `PS1=` / `PROMPT=`, another `starship init`), remove
  that: two prompts fight. The new block is appended at the end of the file, so the Starship prompt normally wins.
- Your own `~/.config/starship.toml` is not touched: this prompt keeps its config in `~/.config/shell-prompt-setup/`.
- macOS: terminals start login shells, so the bash block goes into `~/.bash_profile` (or the first of `~/.bash_login`, `~/.profile`
  that exists). Linux: `~/.bashrc`.
- Remove it all again with `--uninstall` (see below).

### Prefer the Powerline look? Use `install-powerline.sh`

Same shell handling, same options, a different prompt: it replaces the Starship prompt block (and `install.sh` switches back, the one
`prompt` block is rewritten in place). Starship is not installed by it.

```bash
curl -fsSL https://raw.githubusercontent.com/rodneyshupe/shell-prompt-setup/main/install-powerline.sh | bash

# glyph-free theme for ssh clients whose terminal has no Powerline font (a browser SSH terminal, say)
curl -fsSL https://raw.githubusercontent.com/rodneyshupe/shell-prompt-setup/main/install-powerline.sh \
  | bash -s -- --plain-from 192.168.1.20,192.168.1.21
```

Which Powerline depends on the OS (`--backend` overrides): **Linux** uses the `powerline` package (apt) with a small overlay (clock first,
left-only theme); **macOS** uses [powerline-shell](https://github.com/b-ryan/powerline-shell) with the config from the old Mac setup (time, user,
host, ssh, cwd, git, jobs, exit code), installed with pip into a private virtualenv, so nothing is installed system-wide. Powerline draws its
separators with Powerline glyphs, so **the terminal you look at needs a Powerline-patched font** (`--fonts` installs one on macOS). That is why
`--plain-from` exists: the listed ssh clients get Powerline's glyph-free `unicode` theme (powerline-shell: `compatible` mode) and everyone else gets
the full look. Details and the glyph caveat: [docs/design.md](docs/design.md).

## Options

Shared by `install.sh` and `install-powerline.sh`:

| Option | What it does |
|---|---|
| `--users u1,u2` | Users to set up. Default: whoever runs the script. Other users than yourself need root. |
| `--shells WHICH` | `auto` (default): each user's login shell, zsh or bash. `zsh` or `bash`: that one. `both`: zsh and bash. A login shell that is neither (fish, sh, ...) is reported and skipped unless you pass this. |
| `--prompt-only` | Only the prompt. No zsh setup, no plugins. |
| `--shell` | Make zsh the login shell (`chsh`) and set zsh up for the user, only after a zsh login test passed. |
| `--uninstall` | Remove the marked blocks and `~/.config/shell-prompt-setup`. Packages and login shells are left as they are. |
| `--ssh-agent` | Add a block that starts an ssh-agent with `~/.ssh/github*.key` unless one is already available (e.g. forwarded) and stops only an agent it started. zsh and bash. |
| `--no-packages` | Only place the files, install nothing. |
| `--force` | Replace files in `~/.config/shell-prompt-setup` that differ from this repo's (the old one is kept as `<file>.bak.<timestamp>`). |
| `--dry-run` | Print what would happen, change nothing. |
| `--base-url URL` | Where to download `config/` from when not run from a clone (for forks or a mirror). |


Only `install.sh` (Starship):

| Option | What it does |
|---|---|
| `--vip ADDRESS` | Show a bold yellow `[VIP]` after the host name while this host holds `ADDRESS` (keepalived, HA pairs). Written to `settings.sh`. |
| `--square-from IP[,IP...]` | Use square corners (`┌─ └─`) instead of rounded for ssh sessions whose client address is in the list, for a terminal whose font draws rounded corners unevenly (a browser SSH terminal, say). Written to `settings.sh`. |

Only `install-powerline.sh`:

| Option | What it does |
|---|---|
| `--backend WHICH` | `auto` (default): Linux uses the `powerline` package, macOS uses powerline-shell. `powerline-shell`: that one on Linux too (pip, private virtualenv). `powerline` is Linux only. |
| `--plain-from IP[,IP...]` | ssh clients whose address is in the list get a glyph-free theme (`unicode` theme / `compatible` mode). Written to `settings.sh` as `PROMPT_PLAIN_FROM`; `PROMPT_PLAIN=1` forces it everywhere. |
| `--fonts` | macOS: install a Powerline-patched font (Homebrew cask `font-meslo-for-powerline`); select it in your terminal's profile yourself. |

The marked blocks in `~/.zshrc` / `~/.bashrc` are always refreshed in place. Files in `~/.config/shell-prompt-setup` that differ
from this repo's (you edited `starship.toml`, or an older version) are **left alone** with a warning and a non-zero exit, unless
you pass `--force`. Re-running with nothing changed reports "already up to date" for each file.

## The parts

### Starship prompt: zsh and bash ([`config/starship/`](config/starship/))

| File | What it is |
|---|---|
| [`prompt.sh`](config/starship/prompt.sh) | One POSIX-sh file that zsh and bash (3.2 on macOS included) both source. Picks the corners, the ssh depth label and the orange ssh variant, defines the `ssh()` hop counter, then starts Starship for whichever shell is running it. |
| [`starship.toml`](config/starship/starship.toml) | The prompt layout and colors, plain-text symbols. Shell-independent. |

**Line 1, left to right:** corner · a black-on-orange `ssh` / `ssh2` / ... block in an ssh session · clock · user (azure for root, cyan
otherwise) · `@host` (host name in the frame color: blue locally, orange over ssh) · `[VIP]` if applicable · directory (up to 6 levels,
`…/` when truncated) · git branch, status and ahead/behind · `took <time>` for commands over 2 s · `exit <code> <meaning>` after a
failure · language/tool versions. Line 2 is `>`, green or red after a failure.

**Git symbols:** `!` modified, `+` staged, `?` untracked, `x` deleted, `r` renamed, `=` conflicts, `$` stash. Ahead/behind the upstream
branch: `>` one commit ahead, `>3` three ahead, `<` one behind, `<2` two behind, `> <2` both; a count shows only above 1, and only as
fresh as the last `git fetch`. Language modules (Python, Node, Go, Rust, ...) show only for real project markers (`pyproject.toml`,
`package.json`, `go.mod`, `Cargo.toml`, ...), not for a stray source file in a folder such as `~/Downloads`. A few languages that have no
marker file besides their extension (C, C++, Kotlin, Zig, ...) never show; delete their `detect_extensions = []` line to bring one back.

**ssh depth.** `prompt.sh` defines an `ssh` function that adds one to a hop counter and sends it as `LC_PROMPT_HOPS` (`-o SendEnv`); sshd
accepts `LC_*` by default (Debian: `AcceptEnv LANG LC_*`), so the next shell shows the depth. It only counts hops started by typing
`ssh` in zsh or bash: a session that arrives without the counter (a browser terminal, `scp`, a script, a server whose sshd does not
accept `LC_*`) is shown as one hop, and an `ssh` from it then counts as 2.

**Corners** are rounded (`╭─ ╰─`). Where a font draws them unevenly, use `--square-from` (or `PROMPT_CORNERS=square` in `settings.sh`)
to get `┌─ └─` for those sessions.

**Settings.** `~/.config/shell-prompt-setup/settings.sh` holds plain `export` lines that `prompt.sh` reads: `PROMPT_VIP`,
`PROMPT_SQUARE_FROM` (space-separated client addresses), `PROMPT_CORNERS=square`. `--vip` and `--square-from` update only the
settings they are given; edit the file by hand for anything else.

### Powerline prompt: zsh and bash ([`config/powerline/`](config/powerline/))

| File | What it is |
|---|---|
| [`powerline.sh`](config/powerline/powerline.sh) | Loader for the `powerline` package (Linux): layers the overlay on the package's own config through `POWERLINE_CONFIG_PATHS` (system config first, then the overlay, then a `~/.config/powerline` of yours), starts the daemon and sources the package's bash or zsh binding. Switches to the `unicode` theme for `--plain-from` clients. |
| [`powerline/`](config/powerline/powerline/) | The overlay: `config.json` (left-only shell theme, no truecolor) and `themes/shell/default_leftonly.json` (the clock first, then host, user, virtualenv, git branch, cwd, jobs, pipe status). Your old config differed from the package defaults in nothing else that mattered. |
| [`powerline-shell.sh`](config/powerline/powerline-shell.sh) | Loader for powerline-shell (macOS, or `--backend powerline-shell`): a prompt function for bash (`PROMPT_COMMAND`) and zsh (`precmd`). `XDG_CONFIG_HOME` is set for that one command only, to pick the patched or plain config. |
| [`powerline-shell-patched/`](config/powerline/powerline-shell-patched/), [`powerline-shell-plain/`](config/powerline/powerline-shell-plain/) | The two powerline-shell configs (segments: time, virtualenv, user, host, ssh, cwd with max depth 4, git, hg, jobs, root, exit code); `mode` is `patched` or `compatible`. |

Nothing is written to `~/.config/powerline` or `~/.config/powerline-shell`: the project keeps everything in `~/.config/shell-prompt-setup/`,
including the powerline-shell virtualenv (`venv/`).

### zsh setup: zsh only ([`config/zsh/`](config/zsh/), skipped with `--prompt-only`)

| File | What it is |
|---|---|
| [`zsh-setup.zsh`](config/zsh/zsh-setup.zsh) | History, completion, colors, key bindings, `PATH`, the two plugins. Sourced from `~/.zshrc` by a block. |
| [`zprofile`](config/zsh/zprofile) | Linux only: a block in `~/.zprofile` that sources `/etc/profile`, so zsh login shells get the same `PATH` and `/etc/profile.d/*` as bash. |

**Completion:** Tab opens an arrow-key menu; matching is case-insensitive and also finds fragments of a name
(`docker-comp<Tab>` → `docker-compose.yaml`; `/u/l/b<Tab>` → `/usr/local/bin`). The grey ghost text comes from
history first, then from real files and folders. `*` and `!!` are drawn in bold cyan because the highlighter's default
blue is unreadable on dark backgrounds.

**Other:** 50 000-line history shared between sessions without duplicates (a command starting with a space is not
saved); Up/Down search history for what you've typed; `ls`/`ll`/`l` with colors (GNU `ls`/`dircolors` if present,
otherwise BSD `ls -G`); `~/.local/bin` on `PATH`; Homebrew's environment on macOS. Put your own additions in `~/.zshrc.local`, which
the zsh setup sources and the installer never touches. More: [docs/zsh-setup.md](docs/zsh-setup.md).

There is no bash counterpart of the zsh setup: bash gets the prompt only. (Autosuggestions and highlighting are zsh plugins.)

## What gets installed

Per user, in `~/.config/shell-prompt-setup/` (all of it removed by `--uninstall`):

| File | |
|---|---|
| `prompt.sh`, `starship.toml` | The Starship prompt (`install.sh`). |
| `starship-ssh.toml` | Generated by `install.sh` from `starship.toml` (every blue, i.e. frame and host name, replaced by orange, 256-colour 208). `prompt.sh` switches to it when `$SSH_CONNECTION` is set. Don't edit it: edit `starship.toml` and re-run with `--force`. |
| `settings.sh` | Only with `--vip` / `--square-from` (see above). |
| `zsh-setup.zsh` | The zsh setup (not with `--prompt-only`). |
| `powerline.sh`, `powerline/` | Powerline prompt, `powerline` package backend (`install-powerline.sh`). |
| `powerline-shell.sh`, `powerline-shell-patched/`, `powerline-shell-plain/`, `venv/` | Powerline prompt, powerline-shell backend. `settings.sh` then holds `PROMPT_PLAIN_FROM`. |

And marked blocks (a block per component, replaced in place on re-runs) in: `~/.zshrc` (`prompt`, `zsh-setup`, `agent`), `~/.zprofile` (Linux
zsh setup), `~/.bashrc` or on macOS `~/.bash_profile` (`prompt`, `agent`). The `prompt` block always comes before the `zsh-setup` block,
so the syntax-highlighting plugin is still loaded last.

Packages: `starship` always for `install.sh` (the Powerline installer installs `powerline` on Linux, or `python3 python3-venv procps` for powerline-shell, and no Starship); `zsh` (Linux), `zsh-autosuggestions` and `zsh-syntax-highlighting` for the zsh setup (apt on
Debian/Ubuntu, Homebrew on macOS; only the missing ones). On a Debian/Ubuntu release without a `starship` package the script
warns and points to the Starship installer.

### Upgrading from the first layout

Earlier versions of this repo installed a whole-file `~/.zshrc`, `~/.config/starship.toml`, `~/.config/starship-ssh.toml` and a managed
block in `~/.zshrc.local`. Re-running the installer migrates that automatically: the old whole-file `.zshrc` (recognised by its
header) and `.zprofile` are replaced by the blocks, the old starship files are moved aside, and the `PROMPT_VIP` / `PROMPT_SQUARE_FROM`
values and the ssh-agent block from the old `.zshrc.local` move to `settings.sh` and the `agent` block. Everything replaced is kept as
`*.bak.<timestamp>`; the rest of your `~/.zshrc.local` stays.

## Safety notes

- The login shell is changed only with `--shell`, and only after `zsh -l -i` ran and the prompt loaded for that user.
  Non-interactive `ssh host command`, cron and `#!/bin/bash` scripts are unaffected by a login-shell change.
  Roll back with `chsh -s /bin/bash <user>`.
- `prompt.sh` does nothing in a non-interactive shell, so `ssh host command` and scripts are unaffected by the blocks.
- Customise by editing `~/.config/shell-prompt-setup/starship.toml` (re-running the installer then needs `--force` to replace it), or
  fork the repo and use `--base-url`. Preview prompt changes with `starship prompt`.
- `--ssh-agent` in bash sets the shell's `EXIT` trap, which replaces any `EXIT` trap you set earlier in the same file.
- Remove: `install.sh --uninstall` (add `--users` for others). Your original files come back by deleting the blocks, which it does; a
  `*.bak.*` backup from the first install is left in place for you to remove.

## Design notes

Why the prompt looks like this, what was tried and rejected, and the Starship format-string traps: [docs/design.md](docs/design.md).
The zsh setup: [docs/zsh-setup.md](docs/zsh-setup.md).

## Layout and tests

```
install.sh              Starship prompt (+ zsh setup)
install-powerline.sh    Powerline prompt (+ zsh setup)
lib/common.sh           what the two share: users, shells, packages, files, marked blocks, migration, smoke test, --uninstall
config/starship/        prompt.sh, starship.toml
config/powerline/       loaders and configs for the powerline package and powerline-shell
config/zsh/             zsh-setup.zsh, zprofile
tests/                  docker-test.sh runs both suites; fixtures/legacy/ is the first layout, for the migration test
```

`tests/docker-test.sh [image] [starship|powerline]` runs each suite in a fresh Debian container (default `debian:trixie`). **starship** (`tests/in-container.sh`):
a bash-only install that leaves zsh uninstalled, `--shells both`, a zsh install, `--prompt-only` on an existing `.zshrc`, migration from the first
layout, idempotence, no-clobber and `--force`, `--shell`, `--uninstall`, an unsupported login shell, `curl | bash`; and the same prompt checks in bash and
zsh: corners, the ssh block, depth through a real sshd, colors, ahead/behind counts and the VIP marker. **powerline** (`tests/in-container-powerline.sh`):
both backends for bash and zsh users, the clock and glyphs actually rendered by the bindings, glyph-free themes for listed clients, layering of a
user's own `~/.config/powerline`, switching between the two prompts, an rc that already loads Powerline, option errors, `--uninstall`, `curl | bash`.
Needs Docker and `python3`. The macOS paths (bash 3.2, the powerline-shell virtualenv on Python 3.14) were checked by hand on a Mac.

## License

MIT, see [LICENSE](LICENSE).
