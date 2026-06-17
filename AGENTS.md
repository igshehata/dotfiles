# Chezmoi Dotfiles Repository

This is a **chezmoi** source directory. All edits to dotfiles MUST happen here — never edit destination files (`~/.config/...`, `~/.gitconfig`, etc.) directly.

## Critical Rule

**Edit source files in THIS repo. Run `chezmoi apply` to push changes to the live system.**

Never run `chezmoi re-add`. Never edit files under `~/` directly. The flow is always: source → apply → destination.

## Session Start — Consolidation Protocol

**Before making any edits, ALWAYS run these steps first:**

```bash
chezmoi re-add          # capture any local drift (tools/agents that edited live files)
git pull --rebase       # bring in changes from other machines
```

If `chezmoi re-add` produces changes, stage and review them before proceeding:
```bash
git status              # see what re-add brought in
git diff --cached       # if staged, or git diff for unstaged
```

If `git pull` produces conflicts, resolve them with the user before continuing.

Only after consolidation is complete should you proceed with the user's requested edits.

## After Editing

```bash
chezmoi apply --force   # push source → live system
git add -A && git commit -m "descriptive message"
git push
```

## Path Mapping

Chezmoi uses naming conventions to map source paths → destination paths:

| Source (this repo)                         | Destination (live system)                    |
|--------------------------------------------|----------------------------------------------|
| `dot_config/fish/config.fish.tmpl`         | `~/.config/fish/config.fish`                 |
| `dot_config/fish/functions/myfunc.fish`    | `~/.config/fish/functions/myfunc.fish`       |
| `dot_config/ghostty/config`               | `~/.config/ghostty/config`                   |
| `dot_gitconfig.tmpl`                       | `~/.gitconfig`                               |
| `dot_gitignore_global`                     | `~/.gitignore_global`                        |
| `nix-config/private_configuration.nix.tmpl`| `~/nix-config/configuration.nix`             |
| `dot_config/opencode/opencode.jsonc`       | `~/.config/opencode/opencode.jsonc`          |

### Naming rules

- `dot_` prefix → `.` in destination (e.g., `dot_config` → `.config`)
- `private_` prefix → file gets 0600 permissions (strip prefix in destination name)
- `.tmpl` suffix → file is a Go template (strip suffix in destination name)
- Directories follow the same `dot_` / `private_` rules
- `exact_` prefix → directory is exact (chezmoi removes unmanaged files in it)

### To find the source path for any managed file:

```bash
chezmoi source-path ~/.config/fish/config.fish
# → /Users/islam.shehata/.local/share/chezmoi/dot_config/fish/config.fish.tmpl
```

## Common Tasks

### Add a fish function

Create a new file at `dot_config/fish/functions/<name>.fish` in this repo, then:
```bash
chezmoi apply
```

### Add to an existing config (e.g., fish config)

Edit `dot_config/fish/config.fish.tmpl` in this repo, then:
```bash
chezmoi apply
```

### Add a nix package

The `nix` fish function wrapper already handles this — it edits the chezmoi source directly. Use:
```bash
nix add <package>        # adds to nix packages
nix add --brew <pkg>     # adds to homebrew brews
nix add --cask <pkg>     # adds to homebrew casks
```

### Track a new file

```bash
chezmoi add ~/.config/something/config.toml
```

### Template variables

Available in `.tmpl` files via `{{ .variable }}`:

- `{{ .git_name }}` — full name
- `{{ .git_work_email }}` — work email
- `{{ .git_personal_email }}` — personal email
