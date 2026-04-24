#!/usr/bin/env bash
# One-time (idempotent): make `git push origin` push to GitHub and Fluxmire Gitea.
# Run from repo root: ./tools/setup-git-dual-push.sh

set -euo pipefail
ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "error: not inside a git repository" >&2
  exit 1
}
cd "$ROOT"

GITHUB_URL="$(git config remote.origin.url)"
GITEA_URL="ssh://git@git.fluxmire.io:2222/homelab/bindcaptain.git"

if git config --get-all remote.origin.pushurl 2>/dev/null | grep -Fq "$GITEA_URL"; then
  echo "remote.origin already has Gitea pushurl."
  git remote -v
  exit 0
fi

if ! git config --get-all remote.origin.pushurl &>/dev/null; then
  git remote set-url --add --push origin "$GITHUB_URL"
fi
git remote set-url --add --push origin "$GITEA_URL"

echo "Configured: git push origin will update GitHub and Gitea."
git remote -v
