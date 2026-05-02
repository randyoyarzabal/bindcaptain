#!/usr/bin/env bash
# One-time (idempotent): GitHub (origin) + a private second remote — fetch both, push origin to both.
# Internal mirror host/URL is NOT stored in this repository; set it in your environment or local/git-mirror.url.
#
#   export BINDCAPTAIN_GIT_MIRROR_URL='ssh://...'   # or one line in local/git-mirror.url
#   ./tools/setup-git-dual-push.sh
#
# Deploy host (SSH to GitHub not set up yet):
#   BINDCAPTAIN_PREFER_MIRROR_FOR_PULL=1 ./tools/setup-git-dual-push.sh
#
# See README (Git / mirror section) and local/git-mirror.url.example.

set -euo pipefail
ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "error: not inside a git repository" >&2
  exit 1
}
cd "$ROOT"

LOCAL_MIRROR_FILE="$ROOT/local/git-mirror.url"
DEFAULT_GITHUB="git@github.com:randyoyarzabal/bindcaptain.git"
GITHUB_URL="${DEFAULT_GITHUB}"
if [[ -n "${BINDCAPTAIN_GITHUB_URL:-}" ]]; then
  GITHUB_URL="$BINDCAPTAIN_GITHUB_URL"
fi

# Second-remote URL: env > local file (gitignored) > already-configured remotes in .git/ (not from repo)
MIRROR_URL="${BINDCAPTAIN_GIT_MIRROR_URL:-}"
if [[ -z "$MIRROR_URL" && -f "$LOCAL_MIRROR_FILE" ]]; then
  MIRROR_URL="$(awk '!/^[[:space:]]*#/ && NF { gsub(/^[[:space:]]+|[[:space:]]+$/, ""); print; exit }' "$LOCAL_MIRROR_FILE" | tr -d '\r')"
fi
MIRROR_NAME="${BINDCAPTAIN_GIT_MIRROR_REMOTE_NAME:-}"
if [[ -z "$MIRROR_NAME" ]]; then
  if git config --get remote.mirror.url &>/dev/null; then
    MIRROR_NAME=mirror
  elif git config --get remote.gitea.url &>/dev/null; then
    MIRROR_NAME=gitea
  else
    MIRROR_NAME=mirror
  fi
fi
if [[ -z "$MIRROR_URL" && -n "$MIRROR_NAME" ]]; then
  MIRROR_URL="$(git config --get "remote.$MIRROR_NAME.url" 2>/dev/null || true)"
fi
if [[ -z "$MIRROR_URL" ]]; then
  echo "error: set BINDCAPTAIN_GIT_MIRROR_URL, or create local/git-mirror.url (see local/git-mirror.url.example).
Private mirror addresses are not committed to the public tree." >&2
  exit 1
fi

# origin: fetch from GitHub
if git config --get remote.origin.url &>/dev/null; then
  if ! git config --get remote.origin.url | grep -q 'github.com'; then
    echo "Setting origin fetch to GitHub: $DEFAULT_GITHUB" >&2
    git remote set-url origin "$DEFAULT_GITHUB"
  else
    GITHUB_URL="$(git config --get remote.origin.url)"
  fi
else
  git remote add origin "$GITHUB_URL"
fi

# second remote: mirror / legacy name
if git config --get "remote.$MIRROR_NAME.url" &>/dev/null; then
  git remote set-url "$MIRROR_NAME" "$MIRROR_URL"
else
  git remote add "$MIRROR_NAME" "$MIRROR_URL"
fi

# Two push URLs on origin (idempotent, compare full URLs)
_pushes_all="$(git config --get-all remote.origin.pushurl 2>/dev/null || true)"
if [[ -z "$_pushes_all" ]]; then
  git remote set-url --add --push origin "$GITHUB_URL"
  git remote set-url --add --push origin "$MIRROR_URL"
  echo "Added dual pushurl on origin (GitHub + mirror)."
else
  if ! echo "$_pushes_all" | grep -Fq "$GITHUB_URL"; then
    git remote set-url --add --push origin "$GITHUB_URL"
  fi
  if ! echo "$_pushes_all" | grep -Fq "$MIRROR_URL"; then
    git remote set-url --add --push origin "$MIRROR_URL"
  else
    echo "remote.origin already has this mirror pushurl; OK."
  fi
fi

if [[ "${BINDCAPTAIN_PREFER_MIRROR_FOR_PULL:-0}" == "1" || "${BINDCAPTAIN_PREFER_GITEA_FOR_PULL:-0}" == "1" ]]; then
  b="$(git branch --show-current 2>/dev/null || true)"
  if [[ -n "$b" ]]; then
    git config "branch.$b.remote" "$MIRROR_NAME"
    git config "branch.$b.merge" "refs/heads/$b"
    echo "branch $b → tracks $MIRROR_NAME for merge (use: git pull | git fetch --all)"
  fi
fi

echo "Remotes: origin=GitHub, $MIRROR_NAME=private mirror; push origin → both. See: git remote -v"
git remote -v
