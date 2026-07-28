# Chezmoi Dotfiles Repository

This is a **chezmoi** source directory. All edits to dotfiles MUST happen here — never edit destination files (`~/.config/...`, `~/.gitconfig`, etc.) directly.

## Critical Rule

**Edit source files in THIS repo. Run `chezmoi apply` to push changes to the live system.**

Never run an **unscoped** `chezmoi re-add`. A scoped `chezmoi re-add <target>` is allowed only after reviewing and intentionally accepting target drift; templates must be merged or edited in source instead. Never edit files under `~/` directly. The flow is always: source → apply → destination.

## Session Start — Consolidation Protocol

**Before making any edits, ALWAYS run these steps first:**

```bash
git status              # inspect existing source changes
git pull --rebase --autostash  # bring in changes from other machines safely
chezmoi status          # identify source changes vs target drift
chezmoi diff            # review what apply would change
```

If target files have drifted, review each file before continuing. Never bulk-import drift. Use `chezmoi merge <target>` for templates or conflicts, and use `chezmoi re-add <target>` only for specific non-template files whose target changes are intentional.

If `git pull` produces conflicts, resolve them with the user before continuing. If secret-backed templates prevent a global status/diff, inspect the affected targets with scoped commands.

Only after consolidation is complete should you proceed with the user's requested edits.

## After Editing

```bash
chezmoi diff            # review source → target changes
chezmoi apply -v        # push source → live system; preserve overwrite prompts
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
