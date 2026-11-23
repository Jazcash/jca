#!/usr/bin/env bash
# Deploy the JCA gametype from a git commit to the live server.
#
#   scripts/deploy.sh [--dry-run] [--force] [<commit>]
#
# Deploys <commit> (default HEAD) using its committed files, not the working
# tree, so what goes live is always something git can give back. Rolling back
# is just deploying an older commit: scripts/deploy.sh <previous-commit>.
#
# The `deployed` git tag marks what's live, and every deploy is appended to
# ~/warfork/jca-deploys.log. Before copying, the live files are compared with
# the `deployed` tag: if they differ (someone edited the server copy directly)
# it stops, so nothing untracked is lost. --force skips that check.
#
# It does NOT restart the server. The server recompiles the gametype on every
# map load, so the deploy takes effect at the next map change and the current
# game carries on undisturbed.

set -euo pipefail

DEST="${JCA_DEPLOY_DEST:-$HOME/warfork/server/basewf/progs/gametypes}"
LOG="${JCA_DEPLOY_LOG:-$HOME/warfork/jca-deploys.log}"
TAG=deployed
PATHS=(gametypes/jca gametypes/jca.gt gametypes/jca.gtd)

dry_run=0
force=0
rev=HEAD
for arg in "$@"; do
    case "$arg" in
        --dry-run) dry_run=1 ;;
        --force) force=1 ;;
        -h|--help) sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*) echo "unknown option: $arg" >&2; exit 2 ;;
        *) rev="$arg" ;;
    esac
done

cd "$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
commit=$(git rev-parse --verify "$rev^{commit}")
short=$(git rev-parse --short "$commit")

if [ "$rev" = HEAD ] && [ -n "$(git status --porcelain -- "${PATHS[@]}")" ]; then
    echo "warning: uncommitted changes in gametypes/ are NOT deployed (only commit $short is):" >&2
    git status --short -- "${PATHS[@]}" >&2
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# extract a commit's gametype files into a directory
extract() {
    mkdir -p "$2"
    git archive "$1" "${PATHS[@]}" | tar -x -C "$2"
}

# succeeds if a directory holding gametypes/{jca,jca.gt,jca.gtd} matches the live copy
matches_live() {
    local base="$1/gametypes" rc=0
    diff -r "$base/jca" "$DEST/jca" || rc=1
    diff "$base/jca.gt" "$DEST/jca.gt" || rc=1
    diff "$base/jca.gtd" "$DEST/jca.gtd" || rc=1
    return $rc
}

if [ $force -eq 0 ]; then
    if ! git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
        echo "error: no '$TAG' tag, so the live copy can't be checked. Use --force for the first deploy." >&2
        exit 1
    fi
    extract "refs/tags/$TAG" "$tmp/live"
    if ! matches_live "$tmp/live" >"$tmp/live.diff" 2>&1; then
        echo "error: the live copy in $DEST differs from the '$TAG' tag ($(git rev-parse --short "refs/tags/$TAG")):" >&2
        cat "$tmp/live.diff" >&2
        echo "Commit those changes (or decide to drop them), then rerun with --force." >&2
        exit 1
    fi
fi

extract "$commit" "$tmp/new"

if matches_live "$tmp/new" >/dev/null 2>&1; then
    echo "Live copy already matches $short, nothing to copy."
else
    echo "Changes going live ($short):"
    new="$tmp/new/gametypes"
    { diff -rq "$new/jca" "$DEST/jca"; diff -q "$new/jca.gt" "$DEST/jca.gt"; diff -q "$new/jca.gtd" "$DEST/jca.gtd"; } 2>&1 \
        | sed -E "s|^Files $new/([^ ]+) and .*|  changed  \\1|; s|^Only in $new/?([^:]*): (.*)|  added    \\1/\\2|; s|^Only in $DEST/?([^:]*): (.*)|  removed  \\1/\\2|" || true
fi

if [ $dry_run -eq 1 ]; then
    echo "(dry run: nothing copied, tag not moved)"
    exit 0
fi

rsync -a --delete "$tmp/new/gametypes/jca/" "$DEST/jca/"
cp "$tmp/new/gametypes/jca.gt" "$tmp/new/gametypes/jca.gtd" "$DEST/"
matches_live "$tmp/new" >/dev/null

git tag -f "$TAG" "$commit" >/dev/null
echo "$(date '+%Y-%m-%d %H:%M:%S') $short $(git log -1 --format=%s "$commit")" >>"$LOG"
echo "Deployed $short. It takes effect at the next map change (no restart needed)."
