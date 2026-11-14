# shell-prompt-setup

One script that sets up **zsh** with a two-line **[Starship](https://starship.rs)** prompt, history/path
**autosuggestions**, **syntax highlighting** and friendlier **Tab completion**, on Debian/Ubuntu and macOS.

The prompt uses only plain characters (box-drawing lines, `│`, text labels such as `git`, `py`, `exit`). It needs
**no Powerline or Nerd Font**, so it renders the same in a browser-based SSH terminal, over a plain SSH session
or in a local terminal app.

```
┌─ 3:30 PM │ alice@webserver │ …/project/src │ git main !? │ took 12s │ exit 1 ERROR via py v3.13.2
└─>
```

## Quick start

For yourself, on this machine:

```bash
curl -fsSL https://raw.githubusercontent.com/rodneyshupe/shell-prompt-setup/main/install.sh | bash
```

For several users on a Linux server (root needed), and make zsh their login shell:

```bash
curl -fsSL https://raw.githubusercontent.com/rodneyshupe/shell-prompt-setup/main/install.sh \
  | sudo bash -s -- --users root,alice,bob --shell
```

Or from a clone: `git clone https://github.com/rodneyshupe/shell-prompt-setup && cd shell-prompt-setup && ./install.sh --help`.

> Piping a script from the internet into a shell runs whatever is there. Read `install.sh` first, or clone and run
> it, or use `--dry-run` to see exactly what it would do. The installer downloads only three files from `config/`.

No user names are built in: pass them with `--users`. Run it as your normal user on a Mac (Homebrew refuses root).

## Options

| Option | What it does |
|---|---|
| `--users u1,u2` | Users to set up. Default: whoever runs the script. Other users than yourself need root. |
| `--shell` | Make zsh the login shell (`chsh`), only for a user whose zsh login test passed. |
| `--ssh-agent` | Add an ssh-agent block to `~/.zshrc.local`: starts an agent loading `~/.ssh/github*.key` unless one exists (e.g. forwarded) and stops only an agent it started. |
| `--vip ADDRESS` | Show a bold yellow `[VIP]` after the host name while this host holds `ADDRESS` (keepalived, HA pairs). |
| `--no-packages` | Only place the config files, install nothing. |
| `--force` | Replace files that differ from this repo (the old one is kept as `<file>.bak.<timestamp>`). |
| `--dry-run` | Print what would happen, change nothing. |
| `--base-url URL` | Where to download `config/` from when not run from a clone (for forks or a mirror). |

Without `--force`, a differing `~/.zshrc`, `~/.config/starship.toml` or `~/.zprofile` is **left alone** and the script
exits non-zero, so an existing setup is never silently replaced. Re-running with nothing changed reports
"already up to date" for each file.

## What gets installed

| Where | What |
|---|---|
| Packages | `zsh`, `starship`, `zsh-autosuggestions`, `zsh-syntax-highlighting` (apt on Debian/Ubuntu, Homebrew on macOS; only the missing ones). On a Debian/Ubuntu release that lacks the `starship` package the script warns and points to the Starship installer. |
| `~/.zshrc` | [`config/zshrc`](config/zshrc): history, completion, colors, key bindings, prompt, plugins. One file for Linux and macOS (it checks what exists). |
| `~/.config/starship.toml` | [`config/starship.toml`](config/starship.toml): the prompt. |
| `~/.zprofile` (Linux) | [`config/zprofile`](config/zprofile): sources `/etc/profile` so login shells get the same `PATH` and `/etc/profile.d/*` as bash does. |
| `~/.zshrc.local` | Only with `--ssh-agent` / `--vip`: a managed block. Anything else you put in that file is kept and the main `.zshrc` sources it, so it is the place for per-machine additions. |

## What you get

**Prompt** (line 1, left to right): clock · user (red for root, cyan otherwise) · `@host` (host name bold green) ·
`[VIP]` if applicable · directory (up to 6 levels, `…/` when truncated) · git branch and status · `took <time>` for
commands over 2 s · `exit <code> <meaning>` after a failure · language/tool versions. Line 2 is `>`, green or red
after a failure.

Git symbols: `!` modified, `+` staged, `?` untracked, `x` deleted, `r` renamed, `=` conflicts, `$` stash,
`>` ahead, `<` behind, `<>` diverged. Language modules (Python, Node, Go, Rust, ...) show only for real project
markers (`pyproject.toml`, `package.json`, `go.mod`, `Cargo.toml`, ...), not for a stray source file in a folder
such as `~/Downloads`. A few languages that have no marker file besides their extension (C, C++, Kotlin, Zig, ...) never
show; delete their `detect_extensions = []` line to bring one back.

**Completion**: Tab opens an arrow-key menu; matching is case-insensitive and also finds fragments of a name
(`docker-comp<Tab>` → `docker-compose.yaml`; `/u/l/b<Tab>` → `/usr/local/bin`). The grey ghost text comes from
history first, then from real files and folders. `*` and `!!` are drawn in bold cyan because the plugin's default
blue is unreadable on dark backgrounds.

**Other**: 50 000-line history shared between sessions without duplicates (a command starting with a space is not
saved); Up/Down search history for what you've typed; `ls`/`ll`/`l` with colors (GNU `ls`/`dircolors` if present,
otherwise BSD `ls -G`); `~/.local/bin` on `PATH`.

## Safety notes

- The login shell is changed only with `--shell`, and only after `zsh -l -i` ran and rendered the prompt for that user.
  Non-interactive `ssh host command`, cron and `#!/bin/bash` scripts are unaffected by a login-shell change.
  Roll back with `chsh -s /bin/bash <user>`.
- Customise by editing the two files in `config/` and re-running with `--force`, or edit `~/.config/starship.toml`
  directly. Preview prompt changes with `starship prompt`. To get rounded corners change `┌─`/`└─` to `╭─`/`╰─`
  in `format` (these look uneven in some fonts).
- Remove: `chsh -s /bin/bash <user>`, delete `~/.zshrc ~/.zprofile ~/.config/starship.toml ~/.zshrc.local`.

## Tests

`tests/docker-test.sh [image]` runs the installer in a clean Debian container (default `debian:trixie`): dry run,
multi-user install, `--shell`, `--vip` (the marker really appears when the address is held), `--ssh-agent`,
idempotence, no-clobber/`--force`, the `curl | bash` path against a local web server, and error handling.
Needs Docker and `python3`.

## License

MIT, see [LICENSE](LICENSE).
