# Chezmoi Dotfiles Repository

This is a **chezmoi** source directory. All edits to dotfiles MUST happen here — never edit destination files (`~/.config/...`, `~/.gitconfig`, etc.) directly.

## Critical Rule

**Edit source files in THIS repo. Run `chezmoi apply` to push changes to the live system.**

Never run an **unscoped** `chezmoi re-add`. A scoped re-add is allowed only after reviewing and intentionally accepting target drift; templates must be merged or edited in source instead. Never edit files under `~/` directly. The flow is always: source → apply → destination.

Exception: `~/.config/chezmoi/chezmoi.toml` is machine-local and deliberately NOT managed (see `.chezmoiignore`). Edit it directly, or let the migration script fill in the values it owns.

## Cross-Machine Sync

`cz` is defined in `dot_config/fish/config.fish.tmpl`; it is the supported workflow on every machine.

```bash
cz sync              # the whole handshake: send, then receive
cz capture <target>  # import intentional drift from ~ into the source (guarded; refuses templates)
cz push ["msg"]      # commit + push source changes
cz diff <target>     # source → destination diff
cz edit <target>     # edit the source of a target; applies on save
cz status            # passthrough to chezmoi
```

`cz sync` runs, in order:

1. **send** — commits and pushes any uncommitted source changes (so local work is never stranded),
2. **drift gate** — refuses to continue if `~` holds edits that exist only in `~`. chezmoi would prompt for each one (or clobber it), so instead it prints the exact keep-local / keep-source command per file,
3. **receive** — `chezmoi git pull -- --autostash --rebase`, then `chezmoi apply`.

Composition, not magic: `chezmoi update` is exactly step 3, and `chezmoi push` (2.73+) is `git add` + `commit` + `push`.

## Two Traps That Cost Real Debugging Time

1. **Never call a password manager from a template.** `{{ onepasswordRead ... }}` is evaluated by *every* command that computes target state — `status`, `diff`, `apply` — so each of them fires a Touch ID prompt, and the session-start protocol alone fired several. Keep secrets in the machine-local config `[data]` and read them as `{{ .the_key }}`. Guard new keys with `{{ if hasKey . "the_key" }}`: chezmoi evaluates templates with `missingkey=error`, so a bare `{{ .the_key }}` turns into a hard failure on every machine that has not been migrated yet. `atuin_sync_key` uses this pattern and keeps an `onepasswordRead` fallback for unmigrated machines.
2. **Pin `umask` in `chezmoi.toml`.** chezmoi derives target file modes from the invoking shell's umask, so from a `umask 000` shell every managed file reports as modified (`old mode 100644 / new mode 100666`) — 160 phantom entries, no real drift. `umask = 0o22` in `~/.config/chezmoi/chezmoi.toml` (and in `.chezmoi.toml.tmpl`) makes `status` and `apply` shell-independent.

## Pushing Changes To Other Machines

Classify every change before pushing:

- **Additive** — new tracked files, new ignore rules, new commands. Safe: worst case another machine already has its own copy, and chezmoi prompts instead of clobbering.
- **Requires new machine-local data** — BREAKS machines that lack it, as a hard template error. `chezmoi apply` is all-or-nothing (the full target state is computed before anything is written), so the machine keeps working but cannot apply. Ship the fallback in the same commit (`hasKey`), and let `run_onchange_after_40-migrate-machine-config.sh` self-migrate each machine on its next apply.
- **Destructive** — deletions, `.chezmoiremove`, `exact_` directories, scripts that uninstall or move files. The only category that can lose data on another machine, so never ride along with a normal push. Stage it: push the addition, let every machine apply and settle, then push the removal. For anything larger, push to a `next` branch, have each machine `chezmoi git checkout next` and apply, then merge to `main` once every machine is migrated.
- **Needs a newer chezmoi** — add `.chezmoiversion` so an old machine fails loudly instead of misbehaving.

Default posture: prefer additive changes with fallbacks; never require a machine-local value and consume it in the same commit. Machine-local switches currently in use, both `hasKey`-guarded so an unset value falls back to the portable behaviour:

- `atuin_sync_key` — the atuin sync key (a secret; falls back to 1Password)
- `pi_hunk_dev_path` — only set on a machine that points pi at a local pi-hunk checkout; absent means the published `npm:pi-hunk`

## Session Start

```bash
cz sync              # send local work, gate on drift, pull + apply
```

If `cz sync` stops at the drift gate, resolve each reported file first:

- `cz capture <target>` — keep the `~` version (plain files),
- `chezmoi merge <target>` — keep the `~` version of a template,
- `chezmoi apply --force <target>` — discard the `~` version.

Then write/commit source edits from this repo, `chezmoi apply`, and `cz push`.

## Path Mapping

| Source (this repo)                          | Destination (live system)                    |
|---------------------------------------------|----------------------------------------------|
| `dot_config/fish/config.fish.tmpl`          | `~/.config/fish/config.fish`                 |
| `dot_config/ghostty/config`                 | `~/.config/ghostty/config`                   |
| `dot_gitconfig.tmpl`                        | `~/.gitconfig`                               |
| `dot_omp/private_agent/private_config.yml`  | `~/.omp/agent/config.yml` (dir 0700)         |
| `nix-config/private_configuration.nix.tmpl` | `~/nix-config/configuration.nix`             |

### Naming rules

- `dot_` prefix → `.` in destination (e.g. `dot_config` → `.config`)
- `private_` prefix → 0600 file / 0700 directory (strip prefix in destination name)
- `.tmpl` suffix → Go template (strip suffix in destination name)
- `exact_` prefix → directory is exact (chezmoi removes unmanaged files in it) — destructive, see above

### To find the source path for any managed file

```bash
chezmoi source-path ~/.config/fish/config.fish
```

## What Is Tracked

| Tool | Tracked | Deliberately not tracked |
|---|---|---|
| fish / nushell / zsh / tmux / nvim / starship | full config | histories, `fish_variables`, tmux plugins, nvim README/LICENSE |
| **omp** | `~/.omp/agent/{config.yml,mcp.json,pi-hunk.json}` (`private_`) | `~/.omp/`: dbs, `logs/`, `cache/`, `webcache/`, `sessions/`, `run/`, `blobs/`, `managed-skills/`, `natives/`, `plugins/`, `install-id`, `stats.db*`, `autoqa.db*` |
| **zed** | `~/.config/zed/settings.json` | `~/.config/zed/prompts/` (prompt DB) |
| **herdr** | `~/.config/herdr/config.toml` | logs, `session*.json`, `release-notes.json`, `.plugins.lock` |
| atuin | `~/.config/atuin/config.toml` (templated) | `~/.local/share/atuin/` (history, records, key) |
| **tern** | `~/Library/Application Support/Tern/settings.json` (`private_`) | `web-token`, `host_key`, `daemon.state`, `carly/`, `buffers/`, `notes/`, sockets, locks |
| 1Password / gh / copilot / docker / kube / raycast | nothing | auth tokens, machine state |

Tool-rewritten config (omp `config.yml`, zed `settings.json`, hunk `config.toml`) drifts whenever the app writes it. That is expected: `cz sync` reports it, `cz capture <target>` imports it.

Tern (`so.stencil.tern`) has **no Homebrew cask** (closed beta, distributed outside brew), so it cannot be declared in `nix-config` casks until one exists — install it by hand on each machine. Its settings *do* live in a file: `~/Library/Application Support/Tern/settings.json` (71 preferences, no absolute paths) and that file is tracked. The app rewrites it, so expect drift. `ssh_private_key`/`ssh_public_key` in it are empty here and are machine-local: on a machine where they are populated, `apply` prompts before overwriting rather than blanking them.

## Common Tasks

Add a fish function: create `dot_config/fish/functions/<name>.fish`, then `chezmoi apply`.

Edit an existing config: edit the source in this repo, then `chezmoi apply`.

Add a nix package — the `nix` fish wrapper edits the chezmoi source directly:

```bash
nix add <package>        # nix packages
nix add --brew <pkg>     # homebrew brews
nix add --cask <pkg>     # homebrew casks
```

Track a file the app itself rewrites (omp, zed, hunk): `chezmoi add ~/path/to/file` (adds it as source), then `cz push`.

## Template Variables

From `~/.config/chezmoi/chezmoi.toml` (machine-local, not in git):

- `{{ .git_name }}`, `{{ .git_work_email }}`, `{{ .git_personal_email }}`
- `{{ .atuin_sync_key }}` — atuin sync key, sourced from 1Password once per machine
- `{{ .pi_hunk_dev_path }}` — optional; set only on machines that point pi at a local pi-hunk checkout (absent → `npm:pi-hunk`)

Built in by chezmoi: `{{ .chezmoi.hostname }}`, `{{ .chezmoi.os }}`, `{{ .chezmoi.arch }}`.
