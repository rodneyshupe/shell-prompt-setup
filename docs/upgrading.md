# Upgrading from the first layout

The first version of this project installed a whole-file `~/.zshrc`, `~/.config/starship.toml`, `~/.config/starship-ssh.toml` and a
managed block in `~/.zshrc.local`. The installers migrate that automatically; you only have to re-run one of them:

```bash
curl -fsSL https://raw.githubusercontent.com/rodneyshupe/shell-prompt-setup/main/install.sh | bash
# same options as before: --users, --shell, --vip, --square-from, --ssh-agent, ...
```

What happens, per user:

- the old whole-file `~/.zshrc` (recognised by its header) and `~/.zprofile` are replaced by marked blocks, and the zsh setup is kept;
- the old `~/.config/starship*.toml` copies are moved aside (the config now lives in `~/.config/shell-prompt-setup/`);
- the `PROMPT_VIP` / `PROMPT_SQUARE_FROM` values and the ssh-agent block from the old `~/.zshrc.local` move to `settings.sh` and the
  `agent` block, so a re-run without those flags does not lose them;
- everything that was replaced is kept as `*.bak.<timestamp>`; the rest of your `~/.zshrc.local` stays (the zsh setup still sources it).

Files in `~/.config/shell-prompt-setup/` that differ from the repo's are left alone unless you pass `--force`, so a host that was
installed by an older version needs `--force` once to pick up the new `starship.toml`.

A `~/.bashrc` that loads another prompt by hand (the standard Debian `# Powerline configuration` block, or the powerline-shell `_update_ps1` snippet) is refused by both
installers rather than getting a second prompt; `--force` removes those two standard snippets (after a backup). See [design.md](design.md#powerline-as-a-separate-installer).
