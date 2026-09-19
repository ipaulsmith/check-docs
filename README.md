<p align="center">
  <img src="./assets/readme/check-docs-hero.svg" width="100%" alt="check-docs stops the commit: a line in your instructions points to src/OldPanel.tsx, a file that was deleted">
</p>

<h3 align="center">A 39-line shell script that stops a commit<br>when CLAUDE.md or AGENTS.md names a deleted file.</h3>

<p align="center">
  Plain <code>sh</code> · standard Unix tools<br>
  For projects that use CLAUDE.md or AGENTS.md
</p>

<p align="center">
  Made by Pavel Rabtsevich · <a href="https://x.com/p_rabtsevich"><b>@p_rabtsevich</b></a> on X
</p>

<p align="center">
  <a href="https://github.com/ipaulsmith/check-docs/actions/workflows/test.yml"><img src="https://github.com/ipaulsmith/check-docs/actions/workflows/test.yml/badge.svg" alt="Tests on macOS and Ubuntu"></a>
</p>

<p align="center">
  <a href="#install">Install</a> ·
  <a href="#what-happens-when-it-catches-something">Example</a> ·
  <a href="#what-it-checks">What it checks</a> ·
  <a href="#limitations">Limitations</a>
</p>

## Why this exists

CLAUDE.md and AGENTS.md are the files your coding agent reads before it works in your repo. They tell it where things live and how to run them.

When you delete or move a file, the build and the tests catch the code that still uses it. Nothing shows you the line in CLAUDE.md that still points to it. The agent keeps reading that line and does what it says.

`check-docs` covers the mechanical part of that gap. Before every commit it reads those two files, looks for paths and names that no longer exist, and stops the commit until you fix the line.

## Install

Open Claude Code, Codex or Cursor in your repo and paste this whole block into the chat. The agent saves the script, adds it to the pre-commit setup you already have without overwriting anything, and runs it once.

```text
Save the script at the end of this message as check-docs.sh in the repo root.
Add `sh check-docs.sh` to the repo's existing pre-commit setup.
If the repo already uses Husky, pre-commit, core.hooksPath or another hook setup,
use that instead of creating a competing hook.
Otherwise use .git/hooks/pre-commit and make it executable.
Keep everything that is already there. Do not overwrite or remove anything.
Run sh check-docs.sh once now.
If it fails, show me the stale line before changing anything.

check-docs.sh:
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
if G=$(git rev-parse --git-dir 2>/dev/null); then
  git diff --quiet -- "$@" deleted-names.txt ||
    { echo "stage CLAUDE.md, AGENTS.md and deleted-names.txt first"; exit 2; }
fi

# 1. every backticked word with a slash must exist as a path (in git: in the index)
spans=$(grep -ohE '`[^`]+`' "$@")
[ $? -le 1 ] || exit 2   # grep: 0 found, 1 found nothing, 2 error
paths=$(printf '%s\n' "$spans" | tr -d '`' | tr ' \t' '\n\n' |
  grep '/' | grep -v -e '://' -e '[*:#<>$]' -e '^[~-]' | sort -u)
missing=$(for p in $paths; do if [ -n "$G" ]; then git --literal-pathspecs ls-files --error-unmatch -- "$p"; else [ -e "$p" ]; fi >/dev/null 2>&1 || printf '%s not found\n' "$p"; done)
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
```

Or by hand:

```sh
curl -fsSL https://raw.githubusercontent.com/ipaulsmith/check-docs/main/check-docs.sh -o check-docs.sh
sh check-docs.sh
```

Then add `sh check-docs.sh` to your pre-commit hook. If the repo already uses Husky, the pre-commit framework or `core.hooksPath`, add the line there instead of creating a second hook. A new `.git/hooks/pre-commit` needs `#!/bin/sh` as its first line and `chmod +x`.

The check has to run on every commit, whatever files it touches. With the pre-commit framework set `always_run: true` and `pass_filenames: false` on the hook. Otherwise a commit that only deletes files can skip it.

## What happens when it catches something

<p align="center">
  <img src="./assets/readme/check-docs-stop.svg" width="100%" alt="Stop the commit: CLAUDE.md names src/OldPanel.tsx, the check prints src/OldPanel.tsx not found and the commit is stopped">
</p>

Four commits in a test repo with the script installed as a pre-commit hook. The script output is copied as it printed. The `→` lines are notes.

```text
$ git commit -m "delete panel"          # CLAUDE.md still names src/OldPanel.tsx
src/OldPanel.tsx not found
→ commit stopped

$ git commit -m "fix path"              # OldPanel is in deleted-names.txt
3:Use `OldPanel` for settings.
Deleted name found
→ commit stopped

$ git commit -m "fix name"              # edited CLAUDE.md, forgot git add
stage CLAUDE.md, AGENTS.md and deleted-names.txt first
→ commit stopped

$ git add CLAUDE.md && git commit -m "fix name"
docs ok
→ committed
```

## What it checks

It reads CLAUDE.md and AGENTS.md, whichever of the two exist in the folder it runs from. As a git hook that is the repo root.

- **Paths.** Every word with a slash that you wrote in backticks, like `src/OldPanel.tsx`, must exist. In a git repo it must be in the index, so it is part of what you commit. Outside git it must exist on disk.
- **Deleted names.** If you keep a `deleted-names.txt` with one name per line, none of those names may appear in the two files as a whole word.
- **Unstaged edits.** In a git repo it first makes sure your latest edits to CLAUDE.md, AGENTS.md and `deleted-names.txt` are staged, so it checks the same version of these files that you commit. The files themselves are always read from disk, so an untracked CLAUDE.md or `deleted-names.txt` is checked too, even though it is not in the commit.

| Exit | Prints | Commit |
|:---:|---|---|
| `0` | `docs ok`, or `no CLAUDE.md or AGENTS.md here` | goes through |
| `1` | the missing path, or the line with a deleted name | stopped |
| `2` | why the check could not run, or that your edits to these files are not staged | stopped |

These are the script's exit codes. `git commit` itself exits 1 whenever the hook fails.

## How it works

- It needs `sh`, `grep`, `sed`, `tr` and `sort`. If one is missing it says so and exits 2. Git is optional: outside a git repo the staged-files check is skipped and paths are checked on disk.
- Paths are taken from every backticked span, split on spaces. A word counts as a path when it has a slash. Words are skipped when they contain `://`, `*`, `:`, `#`, `<`, `>` or `$`, or start with `~` or `-`. That leaves out URLs, globs, `file:line` references, anchors and flags.
- In a git repo a path counts as present when `git ls-files` finds it in the index, as a file or as a folder with tracked files. A file that exists on disk but was never added with `git add`, or was removed with `git rm --cached`, counts as missing. Pathspecs are literal, so `app/[slug]/page.tsx` is not a glob.
- Each missing path is printed once as `<path> not found`. If any path is missing, the deleted-names check does not run on that commit.
- `deleted-names.txt` is optional. Leading and trailing spaces are trimmed, blank lines are ignored, and matching is whole-word and case-sensitive. Each hit is printed with its line number, then `Deleted name found`. When both CLAUDE.md and AGENTS.md exist, the file name is printed too. If `deleted-names.txt` exists but is not a regular file, the check exits 2. A `deleted-names.txt` symlink that points nowhere counts as no list. Whole-word matching is byte-based, so word boundaries are not detected inside non-Latin names.
- The staged-files check uses `git diff --quiet`. Any unstaged change to the three files stops the commit with `stage CLAUDE.md, AGENTS.md and deleted-names.txt first`, so you cannot commit one version of these files while the check looked at another.
- To cover other instruction files, add them to the list near the top of the script, next to CLAUDE.md and AGENTS.md. The staging message still names only the original three files.

## Limitations

- It is a text match, not a Markdown parser. It only checks words with a slash inside single backticks on a line. Fenced code blocks are not treated as code: plain lines inside a fence are not checked, but a single-backtick span inside a fence is. Paths in plain prose are not checked.
- Any backticked word with a slash counts as a path. `origin/main`, branch names like `feature/foo`, API routes like `/api/users`, scoped packages like `@tanstack/react-query` and `owner/repo` names all show up as missing. Drop the backticks around them, or skip the check once with `git commit --no-verify`.
- Not checked: Markdown links like `[setup](docs/setup.md)`, `@path` imports, file names without a slash like `Makefile`, and instruction files other than the root CLAUDE.md and AGENTS.md, such as `.claude/CLAUDE.md`, `CLAUDE.local.md`, nested CLAUDE.md or AGENTS.md files, or `.cursor/rules`. See [#2](https://github.com/ipaulsmith/check-docs/issues/2) and [#3](https://github.com/ipaulsmith/check-docs/issues/3).
- Inside a git repo, paths are checked against the git index, not the working tree. Untracked or ignored files such as `dist/` or `.venv/bin/python`, absolute paths like `/usr/bin/env`, paths outside the repo such as `../other/`, and paths inside a submodule or through a symlinked folder are reported as missing. If you reference one of these on purpose, remove the backticks or skip the hook for that commit with `git commit --no-verify`.
- Paths with spaces are not supported.
- It runs on the folder it starts in. Run from a subfolder by hand and it reports that there is nothing to check.
- A stray single backtick shifts the pairing, so a path after it can be missed. Punctuation glued to a path inside the backticks, like `` `src/a.ts,` ``, becomes part of the path and shows up as missing.
- Outside git on macOS, letter case is ignored, so `src/oldpanel.tsx` passes when the file is `OldPanel.tsx`. Inside git the index lookup is case-exact.
- Tested on macOS and Ubuntu on every push, under `dash`, `bash` and each system's own `/bin/sh`. It uses `grep -o`, `-h` and `-w`, which are not in POSIX but are in GNU and BSD grep. Windows is not supported. Git Bash and WSL have not been tested.

## Tests

```sh
python3 tests/run-cases.py check-docs.sh
sh tests/git-cases.sh "$PWD/check-docs.sh"
```

Both exit non-zero if any case fails. CI runs them on macOS and Ubuntu on every push, under `dash`, `bash` and each system's own `/bin/sh`.

- `run-cases.py` builds 62 cases in temp folders, including unreadable files, missing tools, CRLF line endings and non-ASCII paths, and checks exit codes and output. Set `SH=/bin/dash` or `SH=/bin/bash` to use another shell. Run it as a normal user, not root.
- `git-cases.sh` runs 17 scenarios in real git repos with the script installed as a pre-commit hook, including `git commit -a` and a commit from a subfolder. For each one it checks the script's exit code, its output and whether the commit was made. Pass a shell as the second argument to use another one.

## License

MIT. Bug reports go to [issues](https://github.com/ipaulsmith/check-docs/issues) or [@p_rabtsevich](https://x.com/p_rabtsevich) on X.
