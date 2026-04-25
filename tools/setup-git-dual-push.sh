#!/usr/bin/env bash
# One-time (idempotent): track GitHub and Fluxmire Gitea — fetch both, `git push origin` to both.
# Run from repo root: ./tools/setup-git-dual-push.sh
#
# On a host that has SSH only for Gitea (e.g. deploy server) but should still fetch from GitHub when you add a key:
#   BINDCAPTAIN_PREFER_GITEA_FOR_PULL=1 ./tools/setup-git-dual-push.sh
# (Install a GitHub deploy key or add ~/.ssh for git@github.com so `git fetch origin` succeeds.)

set -euo pipefail
ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "error: not inside a git repository" >&2
  exit 1
}
cd "$ROOT"

GITEA_URL="ssh://git@git.fluxmire.io:2222/homelab/bindcaptain.git"
DEFAULT_GITHUB="git@github.com:randyoyarzabal/bindcaptain.git"
GITHUB_URL="${DEFAULT_GITHUB}"
if [[ -n "${BINDCAPTAIN_GITHUB_URL:-}" ]]; then
  GITHUB_URL="$BINDCAPTAIN_GITHUB_URL"
fi

# origin: fetch (and first push) from GitHub — use existing origin if it is already a github.com URL
if git config --get remote.origin.url &>/dev/null; then
  if git config --get remote.origin.url | grep -q 'github.com'; then
    GITHUB_URL="$(git config --get remote.origin.url)"
  else
    echo "Setting origin fetch to GitHub: $DEFAULT_GITHUB" >&2
    git remote set-url origin "$DEFAULT_GITHUB"
  fi
else
  git remote add origin "$GITHUB_URL"
fi

# gitea: explicit second remote
if git config --get remote.gitea.url &>/dev/null; then
  git remote set-url gitea "$GITEA_URL"
else
  git remote add gitea "$GITEA_URL"
fi

# Two push URLs on origin: GitHub + Gitea (idempotent)
_pushes_all="$(git config --get-all remote.origin.pushurl 2>/dev/null || true)"
if [[ -z "$_pushes_all" ]]; then
  git remote set-url --add --push origin "$GITHUB_URL"
  git remote set-url --add --push origin "$GITEA_URL"
  echo "Added dual pushurl (GitHub + Gitea) on origin."
else
  if ! echo "$_pushes_all" | grep -q 'github.com'; then
    git remote set-url --add --push origin "$GITHUB_URL"
  fi
  if ! echo "$_pushes_all" | grep -q 'git.fluxmire.io:2222'; then
    git remote set-url --add --push origin "$GITEA_URL"
  else
    echo "remote.origin already has Gitea pushurl; OK."
  fi
fi

# Optional: current branch fast-forwards from gitea on pull (handy if GitHub fetch has no key yet)
if [[ "${BINDCAPTAIN_PREFER_GITEA_FOR_PULL:-0}" == "1" ]]; then
  b="$(git branch --show-current 2>/dev/null || true)"
  if [[ -n "$b" ]]; then
    git config "branch.$b.remote" gitea
    git config "branch.$b.merge" "refs/heads/$b"
    echo "branch $b → tracks gitea for merge (use: git pull | git fetch --all to update remotes/gitea and remotes/origin)"
  fi
fi

echo "Remotes: fetch origin=GitHub, gitea=Gitea; push origin → both. See: git remote -v"
git remote -v
