#!/usr/bin/env bash
# Idempotent: keep only GitHub on origin — no second remote, no dual pushurls.
#
#   ./tools/setup-git-github-only.sh
#
# Optional: BINDCAPTAIN_GITHUB_URL=git@github.com:user/repo.git
#
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "error: not inside a git repository" >&2
  exit 1
}
cd "$ROOT"

DEFAULT_GITHUB="git@github.com:randyoyarzabal/bindcaptain.git"
GITHUB_URL="${BINDCAPTAIN_GITHUB_URL:-}"

if git config --get remote.origin.url &>/dev/null; then
  curr="$(git config --get remote.origin.url)"
  if echo "$curr" | grep -q github.com || [[ -n "$GITHUB_URL" ]]; then
    GITHUB_URL="${GITHUB_URL:-$curr}"
  else
    echo "warn: remote.origin.fetch is not github.com (${curr}); use BINDCAPTAIN_GITHUB_URL or fix origin fetch first" >&2
    GITHUB_URL="${GITHUB_URL:-$DEFAULT_GITHUB}"
  fi
else
  GITHUB_URL="${GITHUB_URL:-$DEFAULT_GITHUB}"
  git remote add origin "$GITHUB_URL"
fi

# Drop every secondary push URL on origin until none remain (then git uses fetch URL for push).
while pu="$(git config --get remote.origin.pushurl 2>/dev/null)"; do
  git remote set-url --push --delete origin "$pu"
done || true

git remote set-url origin "$GITHUB_URL"

for name in gitea mirror; do
  if git config --get "remote.${name}.url" &>/dev/null; then
    git remote remove "$name"
    echo "Removed remote: $name"
  fi
done

echo "Remotes now (GitHub only):"
git remote -v
