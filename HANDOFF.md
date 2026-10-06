# Handoff — the *other* machine

Written on **MacBook-Air**, 2026-10-06, for the agent working on the second machine.
`AGENTS.md` in this repo is the standing operating manual; **this file is a one-time
migration checklist**. Work top to bottom and verify every "expect". Delete this file
and its `.chezmoiignore` line when step 7 is done.

## Context: what changed on MacBook-Air

Three commits (unpushed when this was written; on origin by the time you read it):

1. `feat: cz sync handshake, omp tracking, machine-local config migration` — new `cz`
   subcommands, the atuin key moved out of the template into machine-local config data
   (it used to fire a Touch ID prompt on every chezmoi command), `umask = 0o22` pinned,
   new self-migration script, omp config tracked, this machine's zed/hunk/tmux/nvim drift captured.
2. `feat: track tern settings, capture tailscale + press-and-hold, make pi-hunk path machine-local`
3. `fix(nix): pin nix-darwin to the release branch that matches nixpkgs`

Nothing was deleted, no `.chezmoiremove`, no `exact_` directories. `chezmoi apply` is
all-or-nothing (verified), so a failure here cannot leave a half-applied machine.

## 0. Bootstrap — the `cz` deployed here is the OLD one

The `cz` in this machine's `~/.config/fish/config.fish` predates the change: `cz sync`
with no arguments only refuses and prints status. So use the built-in first:

```bash
chezmoi update -v
```

Expect two kinds of input requests:

- **Touch ID once**, from `.chezmoiscripts/run_onchange_after_40-migrate-machine-config.sh`,
  which adds `umask = 0o22` and `atuin_sync_key` to `~/.config/chezmoi/chezmoi.toml`.
  It is wrapped in a 60s timeout: if 1Password is unreachable it prints the manual
  command and continues. Nothing breaks in that case — the atuin template falls back
  to `onepasswordRead`, which just means prompts until this machine is migrated.
- **One prompt per file this machine has edited locally** ("has changed since chezmoi
  last wrote it?"). Answer per file. If unsure, answer **no** and resolve it in step 2.

Then open a new terminal (or `exec fish`) so the new `cz` is loaded.

## 1. Verify the bootstrap landed

```bash
cz sync extra-argument          # expect: "cz sync takes no arguments." + the capture/push hints
chezmoi --version               # expect >= 2.73.0 (if not: brew upgrade chezmoi)
```

## 2. Send this machine's work, then receive

```bash
cz sync
```

Expect, in this order:

- `→ Source changes to send` + commit + push — **this is why you run nothing else first**:
  this machine's own work must not sit unpushed.
- a drift report and a **non-zero exit**, if `~` holds edits that exist only in `~`. It
  prints one command per file:
  - `cz capture <target>` — keep the local version (plain files)
  - `chezmoi merge <target>` — keep the local version of a template
  - `chezmoi apply --force <target>` — discard the local version
  Choose per file. **Ask the human before `--force` on anything that looks like their work.**
- `→ Pulling from origin` → `→ Applying to ~` → `✓ In sync.`

If the pull fails with a conflict, both machines touched the same file: nothing was
applied. Resolve in `chezmoi cd`, `git rebase --continue`, re-run `cz sync`. Never
force-push.

## 3. Machine-local switches — only if this machine qualifies

- **pi-hunk dev checkout**: if `~/prod/pi-hunk` exists here and is a git checkout, add
  under `[data]` in `~/.config/chezmoi/chezmoi.toml`:
  `pi_hunk_dev_path = "../../prod/pi-hunk"` then
  `chezmoi apply ~/.pi/agent/settings.json`. Otherwise do nothing — the template already
  falls back to `npm:pi-hunk`.
- **Do not copy `atuin_sync_key` from anywhere.** The migration script sourced it from
  1Password on this machine. Verify:
  `chezmoi execute-template '{{ if hasKey . "atuin_sync_key" }}present{{ else }}MISSING{{ end }}'`

## 4. Nix — verify before rebuilding

The repo pins `nix-darwin-26.05` because nix-darwin refuses a branch that does not match
nixpkgs' release. Take the hostname from `~/nix-config/flake.nix`
(`darwinConfigurations."<name>"`) and:

```bash
cd ~/nix-config
nix eval "$HOME/nix-config#darwinConfigurations.\"<name>\".config.system.stateVersion"
```

Expect an integer. If it errors with *"nix-darwin now uses release branches … must match"*,
nixpkgs has moved ahead of the pin: update both together (`nix flake update nixpkgs nix-darwin`),
re-verify, then `chezmoi re-add ~/nix-config/flake.lock`.

Then, only with the human present (needs sudo, rebuilds the system): `drs`

## 5. Behaviour changes to expect on this machine

- Default model becomes `xai-auth` / `grok-4.6` (from `dot_pi/agent/settings.json.tmpl`).
- Moshi and its `services.openssh` block are gone from the nix config, so the next `drs`
  **disables Remote Login (SSH)** here too. Before running `drs`, check
  `~/.ssh/authorized_keys`: on MacBook-Air the only key was Moshi's own (`moshi-pair:…`).
  If this machine has other keys, stop and ask the human for a machine-gated `openssh`
  block instead of silently losing remote access.
- Tern settings are tracked now (`~/Library/Application Support/Tern/settings.json`); if
  this machine's copy differs, `apply` prompts rather than clobbering. Its
  `ssh_private_key`/`ssh_public_key` fields are machine-local — never let `--force` blank them.

## 6. Verify

```bash
chezmoi status                  # expect: no output (every managed file in sync)
cz sync                         # expect: "✓ Source tree clean", then "✓ In sync."
```

## 7. Clean up and report

```bash
cd ~/.local/share/chezmoi
# remove the HANDOFF.md line from .chezmoiignore, then:
rm HANDOFF.md && cz push
```

Report back to the human: chezmoi version, whether `cz sync` completed, which drift you
captured vs discarded vs left, whether `nix eval` passed, whether you touched SSH, and
anything you refused to do.

### Do not

- run `cz sync <target>` expecting the old capture behaviour (it errors on purpose)
- `chezmoi apply --force` over un-reviewed local edits
- force-push, or push removals/`.chezmoiremove`/`exact_` changes as part of this migration
- run `drs` without the human present
