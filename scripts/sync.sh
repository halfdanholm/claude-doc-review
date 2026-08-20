#!/bin/bash
# Commit and push everything in the repo this script lives in.
#
# Purpose: carry a document and its .review/ comments between a local machine
# (where the reviewer GUI runs) and a remote Claude Code session (where it
# cannot). Safe to run from a hook, a timer, or by hand; safe to run
# concurrently — a second caller exits quietly.
#
#   scripts/sync.sh [commit message]
#
# Always exits 0, so a hook can never block or wedge a session.

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO" || exit 0

# mkdir is atomic on every platform, including macOS, which has no flock.
LOCK="$REPO/.git/autosync.lock"
mkdir "$LOCK" 2>/dev/null || exit 0
trap 'rmdir "$LOCK" 2>/dev/null' EXIT

log() { printf '[autosync] %s\n' "$1"; }

git rev-parse --git-dir >/dev/null 2>&1 || { log "not a git repo"; exit 0; }

BRANCH="$(git symbolic-ref --short HEAD 2>/dev/null)"
[ -n "$BRANCH" ] || { log "detached HEAD, refusing to sync"; exit 0; }

DIRTY="$(git status --porcelain)"
[ -n "$DIRTY" ] || [ -n "$(git remote)" ] || exit 0

# 1. Commit local work first, so a rebase can never discard it.
if [ -n "$DIRTY" ]; then
  # Commits need an identity. Invent one and it pollutes history under a name
  # nobody recognises, so say what is missing instead.
  if ! git config user.email >/dev/null 2>&1 || ! git config user.name >/dev/null 2>&1; then
    log "no git identity set — nothing committed. Fix with:"
    log "  git config user.name  \"Your Name\""
    log "  git config user.email \"you@example.com\""
    exit 0
  fi
  git add -A
  MSG="${1:-doc sync: $(git diff --cached --name-only | head -3 | paste -sd, -)}"
  git commit -q -m "$MSG" && log "committed: $MSG"
fi

[ -n "$(git remote)" ] || { log "no remote — committed locally only"; exit 0; }

# 2. Integrate whatever the other side pushed.
if ! git pull --rebase --autostash -q 2>/dev/null; then
  log "pull --rebase hit a conflict — stopping so nothing is lost."
  log "resolve in $REPO, then: git rebase --continue && scripts/sync.sh"
  exit 0
fi

# 3. Publish.
if git push -q 2>/dev/null; then
  log "pushed to $BRANCH"
else
  log "push failed (offline, or no upstream) — committed locally, will go next run"
fi
exit 0
