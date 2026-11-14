# Design notes

Why the prompt looks and works the way it does, what was tried, and the traps hit on the way.

## Why

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
- **Corners:** square `┌─` / `└─`. Rounded `╭─` / `╰─` looked uneven in a real terminal (font-dependent glyphs).
- **Path:** up to 6 folders, `…/` when truncated. Inside a repo the path starts at the repo root, so the repo name stays visible.
- **Colors:** frame and separators bold blue, time white, user name bold red for root and bold cyan for anyone else,
  `@` white and the host name **bold green** (the host is the thing you most need to see; green is not used elsewhere
  on line 1), path bold white, git bold magenta, git status and exit code bold red, final `>` bold green or red after a
  failure. The host is a separate Starship module, so its color can't depend on the user. For a bolder look give
  `hostname.style` a background, e.g. `bold black bg:green`.
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
┌─ 3:30 PM │ root@webserver │ …/project │ git main !?
└─> _

┌─ 3:30 PM │ root@webserver │ …/project/config/nginx │ git main !? │ exit 1 ERROR
└─> _

┌─ 3:30 PM │ root@webserver │ /opt/stacks │ took 12s │ exit 127 NOTFOUND
└─> _
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
| `>` / `<` / `<>` | ahead of / behind / diverged from the remote (no counts; only as fresh as the last `git fetch`) |

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

- Rounded corners (`╭─`/`╰─`): font-dependent.
- Ahead/behind counts in the git status (`ahead = ">${count}"`, `behind = "<${count}"`).
- `fzf` (Ctrl-T/Ctrl-R/Alt-C) and `fzf-tab`, for fuzzy file and history picking.
- pyenv/other version-manager init in `zshrc` for people who use one.
