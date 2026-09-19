#!/bin/sh
# Real git repos with check-docs.sh installed as a pre-commit hook.
# Each case asserts the script's exit code, its output, and whether a commit was made.
# usage: sh tests/git-cases.sh /absolute/path/to/check-docs.sh [shell]
# Exits 0 when every case passes, 1 otherwise.
S=$1; SH=${2:-/bin/sh}
[ -f "$S" ] || { echo "usage: sh tests/git-cases.sh /absolute/path/to/check-docs.sh [shell]"; exit 2; }
case $S in /*) ;; *) echo "give an absolute path to check-docs.sh"; exit 2 ;; esac
ROOT=$(mktemp -d); trap 'rm -rf "$ROOT"' EXIT
PASS=0; FAIL=0; N=0

new() {  # fresh repo with the hook; the hook records the script's exit code
  N=$((N + 1)); D="$ROOT/r$N"; git init -q "$D"; cd "$D" || exit 2
  git config user.email test@example.com; git config user.name test
  git config commit.gpgsign false
  cp "$S" check-docs.sh; mkdir scripts; : > scripts/e2e.sh
  printf '#!/bin/sh\n%s check-docs.sh\ncode=$?\necho $code > .git/hook-exit\nexit $code\n' "$SH" > .git/hooks/pre-commit
  chmod +x .git/hooks/pre-commit
  rm -f .git/hook-exit
}
commits() { git rev-list --count HEAD 2>/dev/null || echo 0; }

# check NAME WANT_EXIT WANT_COMMIT(yes|no) WANT_TEXT -- runs "$@" as the commit command
check() {
  name=$1; want_exit=$2; want_commit=$3; want_text=$4; shift 4
  GD=$(git rev-parse --absolute-git-dir)
  before=$(commits); rm -f "$GD/hook-exit"
  out=$("$@" 2>&1)
  after=$(commits)
  got_exit=$(cat "$GD/hook-exit" 2>/dev/null || echo none)
  [ "$after" -gt "$before" ] && made=yes || made=no
  if [ "$got_exit" = "$want_exit" ] && [ "$made" = "$want_commit" ] &&
     printf '%s\n' "$out" | grep -qF -- "$want_text"; then
    PASS=$((PASS + 1)); echo "PASS  $name"
  else
    FAIL=$((FAIL + 1)); echo "FAIL  $name"
    echo "      want exit=$want_exit commit=$want_commit text='$want_text'"
    echo "      got  exit=$got_exit commit=$made"
    printf '%s\n' "$out" | sed 's/^/      | /'
  fi
}

STAGE="stage CLAUDE.md, AGENTS.md and deleted-names.txt first"
MISSING="scripts/missing.sh not found"

new; printf 'Run `scripts/missing.sh`.\n' > CLAUDE.md; git add -A; printf 'Run `scripts/e2e.sh`.\n' > CLAUDE.md
check "staged stale, working copy fixed"   2 no "$STAGE"   git commit -qm x

new; printf 'Run `scripts/e2e.sh`.\n' > CLAUDE.md; git add -A; printf 'Run `scripts/tmp.sh`.\n' > CLAUDE.md
check "staged fine, working copy stale"    2 no "$STAGE"   git commit -qm x

new; printf 'Run `scripts/e2e.sh`.\n' > CLAUDE.md; git add -A
check "all staged, fine"                   0 yes "docs ok" git commit -qm x

new; printf 'Run `scripts/missing.sh`.\n' > CLAUDE.md; git add -A
check "all staged, stale path"             1 no "$MISSING" git commit -qm x

new; printf 'Run `scripts/e2e.sh`.\n' > CLAUDE.md; git add -A; git commit -qm base >/dev/null 2>&1
printf 'Run `scripts/missing.sh`.\n' > CLAUDE.md
check "commit -a, stale path"              1 no "$MISSING" git commit -qam x
printf 'Run `scripts/e2e.sh`.\nok\n' > CLAUDE.md
check "commit -a, fixed"                   0 yes "docs ok" git commit -qam y
printf 'Run `scripts/missing.sh`.\n' > CLAUDE.md
check "git commit CLAUDE.md, stale path"   1 no "$MISSING" git commit -qm z CLAUDE.md

new; printf 'UI in OldPanel.\n' > CLAUDE.md; printf 'Legacy\n' > deleted-names.txt; git add -A; printf 'OldPanel\n' > deleted-names.txt
check "unstaged deleted-names.txt"         2 no "$STAGE"   git commit -qm x

new; printf 'UI in OldPanel.\n' > CLAUDE.md; printf 'OldPanel\n' > deleted-names.txt; git add -A
check "deleted name in CLAUDE.md"          1 no "Deleted name found" git commit -qm x

new; printf 'Run `scripts/e2e.sh`.\n' > CLAUDE.md; : > a; git add a scripts
check "CLAUDE.md untracked, path tracked"  0 yes "docs ok" git commit -qm x

new; printf 'Run `scripts/e2e.sh`.\n' > CLAUDE.md; git add CLAUDE.md
check "path on disk but never git added"   1 no "scripts/e2e.sh not found" git commit -qm x

new; printf 'Run `scripts/e2e.sh`.\n' > CLAUDE.md; git add -A; git commit -qm base >/dev/null 2>&1; git rm -q --cached scripts/e2e.sh
check "git rm --cached, file kept on disk" 1 no "scripts/e2e.sh not found" git commit -qm x

new; printf 'Code in `scripts/`.\n' > CLAUDE.md; git add -A
check "folder with a tracked file"         0 yes "docs ok" git commit -qm x

new; printf 'Code in `scripts/`.\n' > CLAUDE.md; git add CLAUDE.md
check "folder with only untracked files"   1 no "scripts/ not found" git commit -qm x

new; mkdir -p 'app/[slug]'; : > 'app/[slug]/page.tsx'; printf 'Route `app/[slug]/page.tsx`.\n' > CLAUDE.md; git add -A
check "bracket path, no glob expansion"    0 yes "docs ok" git commit -qm x

new; printf 'Run `scripts/missing.sh`.\n' > CLAUDE.md; mkdir sub; : > sub/f; git add -A; cd sub || exit 2
check "commit from a subfolder, stale"     1 no "$MISSING" git commit -qm x
cd ..

# outside git: run the script by hand
D="$ROOT/plain"; mkdir "$D"; cd "$D" || exit 2; cp "$S" check-docs.sh
printf 'Run `scripts/missing.sh`.\n' > CLAUDE.md
out=$(env -i PATH=/usr/bin:/bin "$SH" check-docs.sh 2>&1); code=$?
if [ "$code" = 1 ] && printf '%s\n' "$out" | grep -qF "$MISSING"; then
  PASS=$((PASS + 1)); echo "PASS  outside git, stale path"
else
  FAIL=$((FAIL + 1)); echo "FAIL  outside git, stale path (exit=$code)"; printf '%s\n' "$out" | sed 's/^/      | /'
fi

echo; echo "$((PASS + FAIL)) cases, $FAIL FAIL"
[ "$FAIL" -eq 0 ]
