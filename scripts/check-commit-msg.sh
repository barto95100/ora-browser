#!/bin/bash
# commit-msg hook: commits carry no AI attribution (see CLAUDE.md).
# $1 is the file holding the commit message. Comment lines are ignored, and so
# is everything below the scissors line (the diff of `git commit -v`).
set -euo pipefail

pattern='co-authored-by:.*(claude|anthropic)|generated with[^a-z]*claude|noreply@anthropic\.com'

message() {
  sed '/^# -\{24\} >8 -\{24\}$/,$d' "$1" | grep -v '^#' || true
}

if message "$1" | grep -qiE "$pattern"; then
  echo "commit-msg: AI attribution is not allowed in commit messages (see CLAUDE.md)." >&2
  message "$1" | grep -iE "$pattern" | sed 's/^/  > /' >&2
  exit 1
fi
