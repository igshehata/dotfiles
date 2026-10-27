#!/usr/bin/env bash
# Installs mise with its official installer (to ~/.local/bin) on machines that
# lack it. mise is deliberately not a Homebrew formula: the mise docs recommend
# the release binary, which also gets new releases sooner. Update it with
# `mise self-update`. Never fails an apply: worst case it prints what to run.

set -uo pipefail

if command -v mise >/dev/null 2>&1 || [[ -x "${HOME}/.local/bin/mise" ]]; then
    exit 0
fi

if ! curl -fsSL https://mise.run | sh; then
    echo "chezmoi: mise install failed - run: curl -fsSL https://mise.run | sh" >&2
fi

exit 0
