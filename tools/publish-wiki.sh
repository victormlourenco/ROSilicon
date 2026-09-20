#!/usr/bin/env bash
# Publishes wiki/ to this repository's GitHub wiki.
#
# The wiki pages are kept in wiki/ so they are reviewed and versioned with the
# code; this script is what copies them over. It mirrors the folder: a page
# deleted here is deleted there.
#
# GitHub only creates the wiki's git repository once a first page has been saved
# in the web UI — https://github.com/<owner>/<repo>/wiki/_new. Until then the
# remote does not exist and this script says so.
set -euo pipefail

cd "$(dirname "$0")/.."
SOURCE="${WIKI_SOURCE:-wiki}"
REMOTE="${WIKI_REMOTE:-$(git remote get-url origin | sed 's/\.git$//').wiki.git}"
MESSAGE="${1:-Update the wiki from wiki/}"

[ -d "$SOURCE" ] || { echo "No $SOURCE/ to publish." >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

if ! git clone --quiet "$REMOTE" "$WORK/wiki" 2>/dev/null; then
    cat >&2 <<MSG
Could not clone $REMOTE

If the wiki has no pages yet, GitHub has not created its repository. Open
  $(git remote get-url origin | sed -e 's/\.git$//' -e 's|git@github.com:|https://github.com/|')/wiki/_new
save any page once, and run this again — the first push overwrites it.
MSG
    exit 1
fi

rsync --archive --delete --exclude .git --exclude README.md "$SOURCE/" "$WORK/wiki/"

cd "$WORK/wiki"
if git diff --quiet && git diff --quiet --cached && [ -z "$(git status --porcelain)" ]; then
    echo "The wiki already matches $SOURCE/."
    exit 0
fi

git add --all
git commit --quiet --message "$MESSAGE"
git push --quiet origin HEAD
echo "Published $SOURCE/ to the wiki."
