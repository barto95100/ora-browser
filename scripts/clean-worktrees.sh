#!/bin/bash
# clean-worktrees.sh — Remove the worktrees of branches already merged.
#
# Usage: scripts/clean-worktrees.sh   (from the main checkout or a worktree)
#
# A worktree in .worktrees/ goes once its branch was merged into origin/main
# by a merge commit (pull requests are merged that way): its last commit is
# in origin/main but not on main's own line, so a branch just created from
# main, with no commit yet, stays. A worktree with changes not committed
# stays too. Its build copies are unregistered first (unregister-copies.sh),
# then the worktree and its local branch are removed.
set -uo pipefail

# The main checkout, even when run from a worktree (which may be removed).
root=$(dirname "$(git -C "$(dirname "$0")" rev-parse --path-format=absolute --git-common-dir)")
cd "$root" || exit 1
unregister="$root/scripts/unregister-copies.sh"

git fetch --quiet --prune origin || true
mainline=$(git rev-list --first-parent origin/main)

git worktree list --porcelain | awk '/^worktree /{ sub(/^worktree /, ""); print }' | while IFS= read -r tree; do
    [[ "$tree" == "$root/.worktrees/"* ]] || continue
    head=$(git -C "$tree" rev-parse HEAD 2>/dev/null) || continue
    git merge-base --is-ancestor "$head" origin/main || continue
    grep -qx "$head" <<<"$mainline" && continue
    if [[ -n "$(git -C "$tree" status --porcelain)" ]]; then
        echo "kept (changes not committed): $tree"
        continue
    fi
    branch=$(git -C "$tree" symbolic-ref --quiet --short HEAD || true)
    [[ -x "$unregister" ]] && "$unregister" "$tree"
    if git worktree remove "$tree"; then
        echo "removed: $tree"
        [[ -n "$branch" ]] && git branch --quiet -D "$branch"
    fi
done
git worktree prune
exit 0
