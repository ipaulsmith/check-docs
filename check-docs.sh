#!/bin/sh
# Exit 1: CLAUDE.md or AGENTS.md names a missing path or a deleted name.
# Exit 2: the check itself could not run.
# Plain sh; tested on macOS and Ubuntu.
set -f
export LC_ALL=C
for t in grep sed tr sort; do
  command -v "$t" >/dev/null || { echo "need $t"; exit 2; }
done

set --
[ -f CLAUDE.md ] && set -- "$@" CLAUDE.md
[ -f AGENTS.md ] && set -- "$@" AGENTS.md
[ $# -gt 0 ] || { echo "no CLAUDE.md or AGENTS.md here"; exit 0; }
# in a git repo, require instruction-file edits to be staged before checking
if git rev-parse --git-dir >/dev/null 2>&1; then
  git diff --quiet -- "$@" deleted-names.txt ||
    { echo "stage CLAUDE.md, AGENTS.md and deleted-names.txt first"; exit 2; }
fi

# 1. every backticked word with a slash must exist as a path
spans=$(grep -ohE '`[^`]+`' "$@")
[ $? -le 1 ] || exit 2   # grep: 0 found, 1 found nothing, 2 error
paths=$(printf '%s\n' "$spans" | tr -d '`' | tr ' \t' '\n\n' |
  grep '/' | grep -v -e '://' -e '[*:#<>$]' -e '^[~-]' | sort -u)
missing=$(for p in $paths; do [ -e "$p" ] || printf '%s not found\n' "$p"; done)
[ -z "$missing" ] || { printf '%s\n' "$missing"; exit 1; }

# 2. no name from deleted-names.txt (optional, one per line) may appear
if [ -e deleted-names.txt ]; then
  [ -f deleted-names.txt ] || { echo "deleted-names.txt: not a file"; exit 2; }
  names=$(sed 's/^[[:space:]]*//;s/[[:space:]]*$//;/^$/d' < deleted-names.txt) || exit 2
  if [ -n "$names" ]; then
    hits=$(printf '%s\n' "$names" | grep -nwFf - "$@")
    [ $? -le 1 ] || exit 2
    [ -z "$hits" ] || { printf '%s\n' "$hits"; echo "Deleted name found"; exit 1; }
  fi
fi
echo "docs ok"
