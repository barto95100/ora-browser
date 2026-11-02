#!/bin/bash
# commit-msg hook: commits carry no AI attribution (see CLAUDE.md).
# $1 is the file holding the commit message; comment lines are ignored.
set -euo pipefail

pattern='co-authored-by:.*(claude|anthropic)|generated with[^a-z]*claude|noreply@anthropic\.com'

if grep -v '^#' "$1" | grep -qiE "$pattern"; then
  echo "commit-msg: AI attribution is not allowed in commit messages (see CLAUDE.md)." >&2
  grep -v '^#' "$1" | grep -iE "$pattern" | sed 's/^/  > /' >&2
  exit 1
fi
