#!/bin/sh
# Exit 1: an instruction file names a missing path, a missing @import or a deleted name.
# Exit 2: the check itself could not run.
# Plain sh; tested on macOS and Ubuntu.
set -f
export LC_ALL=C
for t in grep sed tr sort awk; do
  command -v "$t" >/dev/null || { echo "need $t"; exit 2; }
done
nl='
'
G=; git rev-parse --git-dir >/dev/null 2>&1 && G=1

# in git: present means in the index; outside git: present on disk
present() {
  if [ -n "$G" ]; then git --literal-pathspecs ls-files --error-unmatch -- "$1" >/dev/null 2>&1
  else [ -e "$1" ]; fi
}
# a/./b/../c -> a/c ; keeps leading ../ so paths outside the repo stay visible
norm() {
  printf '%s\n' "$1" | awk -F/ '{ n = 0
    for (i = 1; i <= NF; i++) {
      if ($i == "" || $i == ".") continue
      if ($i == ".." && n > 0 && s[n] != "..") { n--; continue }
      s[++n] = $i }
    o = "."; for (i = 1; i <= n; i++) o = (i == 1 ? s[i] : o "/" s[i]); print o }'
}
# @imports the way Claude Code reads them: not in code spans or code blocks,
# @ after space, tab or NBSP, first character [A-Za-z0-9._-] or ~/ or /, "\ " is a space, #anchor dropped
imports() {
  awk 'BEGIN { blank = 1 }
  function nocode(s,   out, n, rest, tmp, pos, j) {
    out = ""
    while (match(s, /`+/)) {
      out = out substr(s, 1, RSTART - 1); n = RLENGTH; rest = substr(s, RSTART + n)
      tmp = rest; pos = 0; j = 0
      while (match(tmp, /`+/)) {
        if (RLENGTH == n) { j = pos + RSTART; break }
        pos += RSTART + RLENGTH - 1; tmp = substr(tmp, RSTART + RLENGTH) }
      if (j) { out = out " "; s = substr(rest, j + n) } else { out = out substr(s, RSTART, n); s = rest }
    }
    return out s
  }
  { sub(/\r$/, ""); q = $0
    while (q ~ /^ ? ? ?>/) sub(/^ ? ? ?> ?/, "", q)
    if (fc != "") {
      if (match(q, /^ ? ? ?(`+|~+)[ \t]*$/)) { r = substr(q, RSTART, RLENGTH); gsub(/[ \t]/, "", r)
        if (substr(r, 1, 1) == fc && length(r) >= fl) fc = "" }
      next }
    if (match(q, /^ ? ? ?(```+|~~~+)/)) { r = substr(q, RSTART, RLENGTH); gsub(/ /, "", r)
      if (!(substr(r, 1, 1) == "`" && index(substr(q, RSTART + RLENGTH), "`"))) {
        fc = substr(r, 1, 1); fl = length(r); ic = 0; next } }
    if (q ~ /^[ \t]*$/) { blank = 1; next }
    ind = (q ~ /^(    |\t)/)
    if (ind && !inlist && (blank || ic || !para)) { ic = 1; blank = 0; next }
    if (q ~ /^ ? ? ?([-+*]|[0-9]+[.)])([ \t]|$)/) inlist = 1
    else if (!ind && blank) inlist = 0
    ic = 0; blank = 0; para = (q !~ /^ ? ? ?#/)
    s = " " nocode(q); gsub(/\302\240/, " ", s)
    while (match(s, /[ \t]@([^ \t\\]|\\ )+/)) {
      t = substr(s, RSTART + 2, RLENGTH - 2); s = substr(s, RSTART + RLENGTH)
      if (t !~ /^([A-Za-z0-9._-]|~\/|\/)/) continue
      sub(/#.*/, "", t); gsub(/\\ /, " ", t); if (t != "") print t }
  }' "$1"
}

# 1. instruction files: root, .claude/, and nested ones
roots=$({
  for f in CLAUDE.md .claude/CLAUDE.md CLAUDE.local.md AGENTS.md .claude/AGENTS.md; do echo "$f"; done
  if [ -n "$G" ]; then git -c core.quotepath=off ls-files -co --exclude-standard
  else find . \( -name .git -o -name node_modules \) -prune -o \( -type f -o -type l \) -print | sed 's#^\./##'
  fi | grep -E '(^|/)(CLAUDE\.md|CLAUDE\.local\.md|AGENTS\.md)$'
} | awk '!seen[$0]++')
files=; queue=; bad=; targets=
IFS=$nl
for f in $roots; do [ -f "$f" ] && queue="$queue$f 0$nl"; done

# 2. follow @imports breadth-first, at most four hops, each file once
seen="$nl"
while [ -n "$queue" ]; do
  item=${queue%%"$nl"*}; queue=${queue#*"$nl"}
  f=${item% *}; depth=${item##* }
  case $seen in *"$nl$f$nl"*) continue ;; esac
  seen="$seen$f$nl"; files="$files$f$nl"
  [ "$depth" -lt 4 ] || continue
  imps=$(imports "$f") || exit 2
  d=${f%/*}; [ "$d" = "$f" ] && d=.
  for t in $imps; do
    case $t in /*|'~'*) continue ;; esac      # absolute and home imports: machine-specific, not checked
    r=$(norm "$d/$t")
    case $r in ..|../*) continue ;; esac      # outside the repo: not checked
    { [ -f "$r" ] || { [ ! -e "$r" ] && present "$r"; }; } && targets="$targets$r$nl"
    if present "$r" && [ -f "$r" ]; then queue="$queue$r $((depth + 1))$nl"
    else bad="$bad$f: @$t not found$nl"; fi
  done
done
unset IFS

# in a git repo, require instruction-file edits (and deletions) to be staged before checking
if [ -n "$G" ]; then
  set --; IFS=$nl; for f in $roots$nl$files$targets; do [ -n "$f" ] && set -- "$@" "$f"; done; unset IFS
  unstaged=$(git --literal-pathspecs diff --name-only -- "$@" deleted-names.txt) || exit 2
  [ -z "$unstaged" ] || { echo "stage your instruction file edits first:"; printf '%s\n' "$unstaged"; exit 2; }
fi
[ -n "$files" ] || { echo "no CLAUDE.md or AGENTS.md here"; exit 0; }

# 3. every backticked word with a slash must exist as a path (in git: in the index)
wordsof() {
  spans=$(grep -ohE '`[^`]+`' "$1"); [ $? -le 1 ] || exit 2
  printf '%s\n' "$spans" | tr -d '`' | tr ' \t' '\n\n' |
    grep '/' | grep -v -e '://' -e '[*:#<>$]' -e '^[~-]' | sort -u
}
top=
IFS=$nl
for f in $files; do
  d=${f%/*}; [ "$d" = "$f" ] && d=.
  words=$(wordsof "$f") || exit 2
  if [ "$d" = . ]; then top="$top$words$nl"; continue; fi
  for p in $words; do present "$p" || present "$(norm "$d/$p")" || bad="$bad$f: $p not found$nl"; done
done
topmiss=$(for p in $(printf '%s' "$top" | sort -u); do present "$p" || printf '%s not found\n' "$p"; done)
unset IFS
missing=$(printf '%s\n%s' "$topmiss" "$bad" | sed '/^$/d')
[ -z "$missing" ] || { printf '%s\n' "$missing"; exit 1; }

# 4. no name from deleted-names.txt (optional, one per line) may appear
if [ -e deleted-names.txt ]; then
  [ -f deleted-names.txt ] || { echo "deleted-names.txt: not a file"; exit 2; }
  names=$(sed 's/^[[:space:]]*//;s/[[:space:]]*$//;/^$/d' < deleted-names.txt) || exit 2
  if [ -n "$names" ]; then
    set --; IFS=$nl; for f in $files; do set -- "$@" "$f"; done; unset IFS
    hits=$(printf '%s\n' "$names" | grep -nwFf - "$@")
    [ $? -le 1 ] || exit 2
    [ -z "$hits" ] || { printf '%s\n' "$hits"; echo "Deleted name found"; exit 1; }
  fi
fi
echo "docs ok"
