#!/usr/bin/env python3
"""Independent test harness for check-docs.sh.

usage: run-cases.py <script> [PATH]

Builds every case in a fresh temp directory (backticks written literally,
never through a shell), runs the given script with /bin/sh and the given
PATH, and prints expected vs actual (exit, stdout, stderr).
"""
import os, sys, stat, subprocess, tempfile, shutil

SCRIPT = os.path.abspath(sys.argv[1])
PATH = sys.argv[2] if len(sys.argv) > 2 else "/usr/bin:/bin"
SH = os.environ.get("SH", "/bin/sh")
B = "`"

# name -> (files, expected_exit, expected_stdout_contains, note)
# files: {relpath: content}; special keys handled below
CASES = []
def case(name, files, exp_exit, exp_out, note=""):
    CASES.append((name, files, exp_exit, exp_out, note))

# ordinary reader use
case("claude-only-valid", {"scripts/e2e.sh": "", "docs/setup.md": "",
      "CLAUDE.md": f"Run {B}sh scripts/e2e.sh{B} and read {B}docs/setup.md{B}.\n"}, 0, "docs ok")
case("claude-only-missing", {"CLAUDE.md": f"Run {B}scripts/e2e.sh{B}.\n"}, 1, "scripts/e2e.sh not found")
case("agents-only-valid", {"docs/setup.md": "", "AGENTS.md": f"See {B}docs/setup.md{B}.\n"}, 0, "docs ok")
case("agents-only-missing", {"AGENTS.md": f"Run {B}scripts/e2e.sh{B}.\n"}, 1, "scripts/e2e.sh not found")
case("both-missing-in-agents", {"CLAUDE.md": "fine\n", "AGENTS.md": f"Run {B}scripts/e2e.sh{B}.\n"}, 1, "scripts/e2e.sh not found")
case("both-valid", {"a/b": "", "CLAUDE.md": f"{B}a/b{B}\n", "AGENTS.md": f"{B}a/b{B}\n"}, 0, "docs ok")
case("neither", {}, 0, "no CLAUDE.md or AGENTS.md here")
case("path-in-command-valid", {"scripts/e2e.sh": "", "CLAUDE.md": f"Run {B}sh scripts/e2e.sh{B}.\n"}, 0, "docs ok")
case("path-in-command-missing", {"CLAUDE.md": f"Run {B}sh scripts/e2e.sh{B}.\n"}, 1, "scripts/e2e.sh not found")
case("dir-named-CLAUDE.md", {"CLAUDE.md/inner": "x\n"}, 0, "no CLAUDE.md or AGENTS.md here", "directory is not a doc")
case("deleted-name-hit", {"CLAUDE.md": "UI in OldPanel.\n", "deleted-names.txt": "OldPanel\n"}, 1, "Deleted name found")
case("similar-name-OldPanels", {"CLAUDE.md": "UI in OldPanels.\n", "deleted-names.txt": "OldPanel\n"}, 0, "docs ok")
case("similar-name-OldPanelHelper", {"CLAUDE.md": "See OldPanelHelper.\n", "deleted-names.txt": "OldPanel\n"}, 0, "docs ok")
case("deleted-list-empty", {"CLAUDE.md": "ok\n", "deleted-names.txt": ""}, 0, "docs ok")
case("deleted-list-blank-lines", {"CLAUDE.md": "ok\n", "deleted-names.txt": "\n  \n\t\n"}, 0, "docs ok")
case("deleted-list-absent", {"CLAUDE.md": "ok\n"}, 0, "docs ok")
case("crlf-list-hit", {"CLAUDE.md": "UI in OldPanel.\n", "deleted-names.txt": "OldPanel\r\nLegacy\r\n"}, 1, "Deleted name found")
case("crlf-list-clean", {"CLAUDE.md": "UI fine.\n", "deleted-names.txt": "OldPanel\r\nLegacy\r\n"}, 0, "docs ok")
case("name-trailing-spaces", {"CLAUDE.md": "OldPanel here\n", "deleted-names.txt": "OldPanel   \n"}, 1, "Deleted name found")
case("name-in-path-in-doc", {"src/OldPanel.tsx": "", "CLAUDE.md": f"{B}src/OldPanel.tsx{B}\n", "deleted-names.txt": "OldPanel\n"}, 1, "Deleted name found")
case("url-skipped", {"CLAUDE.md": f"See {B}https://example.com/a/b{B}.\n"}, 0, "docs ok")
case("glob-skipped", {"CLAUDE.md": f"Files {B}src/**/*.ts{B}.\n"}, 0, "docs ok")
case("tilde-skipped", {"CLAUDE.md": f"Config {B}~/.claude/x.md{B}.\n"}, 0, "docs ok")
case("flag-with-slash-skipped", {"CLAUDE.md": f"Run {B}git log --since=2020/01/01{B}.\n"}, 0, "docs ok")
case("file-line-skipped", {"CLAUDE.md": f"See {B}src/a.ts:12{B}.\n"}, 0, "docs ok")
case("anchor-skipped", {"CLAUDE.md": f"See {B}docs/x.md#setup{B}.\n"}, 0, "docs ok")
case("existing-directory", {"src/x/.keep": "", "CLAUDE.md": f"Code in {B}src/x/{B}.\n"}, 0, "docs ok")
case("dot-slash", {"a.md": "", "CLAUDE.md": f"See {B}./a.md{B}.\n"}, 0, "docs ok")
case("non-ascii-valid", {"докс/файл.md": "", "CLAUDE.md": f"См. {B}докс/файл.md{B}.\n"}, 0, "docs ok")
case("non-ascii-missing", {"CLAUDE.md": f"См. {B}докс/нет.md{B}.\n"}, 1, "докс/нет.md not found")
case("two-missing-listed-once", {"CLAUDE.md": f"{B}a/1{B} {B}b/2{B} {B}a/1{B}\n"}, 1, "a/1 not found\nb/2 not found")
case("fence-plain-line-not-scanned", {"CLAUDE.md": "```sh\nsh scripts/gone.sh\n```\n"}, 0, "docs ok", "no backticks on the line")
case("fence-inline-backticks-scanned", {"CLAUDE.md": f"```\n{B}scripts/gone.sh{B}\n```\n"}, 1, "scripts/gone.sh not found", "documented: any inline span is scanned")
case("prose-slash-no-backticks", {"CLAUDE.md": "yes/no answers\n"}, 0, "docs ok")
# documented-unsupported input (expected = what the documented format implies)
case("UNSUPPORTED-prose-slash-in-backticks", {"CLAUDE.md": f"{B}yes/no{B} answers\n"}, 1, "yes/no not found", "false positive by design: backticked slash-word = path")
case("UNSUPPORTED-path-with-space", {"my dir/a.md": "", "CLAUDE.md": f"See {B}my dir/a.md{B}.\n"}, 1, "dir/a.md not found", "false positive: spaces unsupported")
case("UNSUPPORTED-trailing-punct", {"a/b": "", "CLAUDE.md": f"See {B}a/b.{B}\n"}, 1, "a/b. not found", "false positive: punctuation inside backticks")
# checker failures (must NOT print docs ok / exit 0)
case("FAIL-unreadable-CLAUDE.md", {"CLAUDE.md": f"Run {B}scripts/e2e.sh{B}.\n", "__chmod000__": "CLAUDE.md"}, "nonzero", "!docs ok")
case("FAIL-unreadable-AGENTS.md-with-good-CLAUDE", {"CLAUDE.md": "fine\n", "AGENTS.md": "x\n", "__chmod000__": "AGENTS.md"}, "nonzero", "!docs ok")
case("FAIL-deleted-names-is-directory", {"CLAUDE.md": "UI in OldPanel.\n", "deleted-names.txt/inner": "OldPanel\n"}, "nonzero", "!docs ok")
case("FAIL-deleted-names-unreadable", {"CLAUDE.md": "UI in OldPanel.\n", "deleted-names.txt": "OldPanel\n", "__chmod000__": "deleted-names.txt"}, "nonzero", "!docs ok")
case("FAIL-grep-missing-from-PATH", {"CLAUDE.md": f"Run {B}scripts/e2e.sh{B}.\n", "__nogrep__": "1"}, "nonzero", "!docs ok")
case("FAIL-grep-exits-2", {"CLAUDE.md": f"Run {B}scripts/e2e.sh{B}.\n", "deleted-names.txt": "OldPanel\n", "__grep2__": "1"}, "nonzero", "!docs ok")
case("FAIL-sed-missing-from-PATH", {"CLAUDE.md": "fine\n", "deleted-names.txt": "OldPanel\n", "__nosed__": "1"}, "nonzero", "!docs ok")
case("FAIL-tr-missing-from-PATH", {"CLAUDE.md": f"Run {B}scripts/e2e.sh{B}.\n", "__notr__": "1"}, "nonzero", "!docs ok")
case("FAIL-sort-missing-from-PATH", {"CLAUDE.md": f"Run {B}scripts/e2e.sh{B}.\n", "__nosort__": "1"}, "nonzero", "!docs ok")
case("deleted-list-symlink", {"CLAUDE.md": "UI in OldPanel.\n", "real.txt": "OldPanel\n", "__symlink__": "real.txt deleted-names.txt"}, 1, "Deleted name found")
case("doc-with-crlf-lines", {"CLAUDE.md": f"Run {B}scripts/e2e.sh{B}.\r\nUI in OldPanel.\r\n", "deleted-names.txt": "OldPanel\n"}, 1, "scripts/e2e.sh not found")
case("doc-with-crlf-lines-clean", {"scripts/e2e.sh": "", "CLAUDE.md": f"Run {B}scripts/e2e.sh{B}.\r\nfine\r\n", "deleted-names.txt": "OldPanel\n"}, 0, "docs ok")
case("nextjs-bracket-path", {"app/[slug]/page.tsx": "", "CLAUDE.md": f"Route in {B}app/[slug]/page.tsx{B}.\n"}, 0, "docs ok")
case("nextjs-bracket-path-missing", {"CLAUDE.md": f"Route in {B}app/[slug]/page.tsx{B}.\n"}, 1, "app/[slug]/page.tsx not found")
case("path-with-question-mark-glob", {"CLAUDE.md": f"See {B}src/file?.ts{B}.\n"}, 1, "src/file?.ts not found", "? is not in the skip list; set -f keeps it literal")
case("repaired-input-passes", {"scripts/e2e.sh": "", "docs/setup.md": "", "CLAUDE.md": f"Before release, run {B}sh scripts/e2e.sh{B}.\nSetup lives in {B}docs/setup.md{B}.\n", "deleted-names.txt": "OldPanel\nLegacyStore\n"}, 0, "docs ok", "the demo CLAUDE.md after the two fixes")
case("tab-inside-span-valid", {"scripts/e2e.sh": "", "CLAUDE.md": f"Run {B}cd\tscripts/e2e.sh{B}.\n"}, 0, "docs ok", "regression: tab used to yield 'cd not found'")
case("name-leading-spaces", {"CLAUDE.md": "UI in OldPanel.\n", "deleted-names.txt": "  OldPanel\n"}, 1, "Deleted name found", "regression: leading spaces silently disabled the name")
case("name-leading-tab", {"CLAUDE.md": "UI in OldPanel.\n", "deleted-names.txt": "\tOldPanel\n"}, 1, "Deleted name found")
case("KNOWN-deleted-names-dangling-symlink", {"CLAUDE.md": "UI in OldPanel.\n", "__symlink__": "nowhere.txt deleted-names.txt"}, 0, "docs ok", "known limit: a dangling link counts as no list")
case("env-names-var-does-not-leak", {"CLAUDE.md": "UI in OldPanel.\n", "__env__": "names=OldPanel"}, 0, "docs ok", "regression: exported names= used to trigger check 2")
case("backslash-in-path-printed-verbatim", {"CLAUDE.md": f"See {B}docs\\new/x.md{B}.\n"}, 1, "docs\\new/x.md not found", "regression: echo mangled backslashes under sh/dash")
case("origin-main-false-positive-documented", {"CLAUDE.md": f"Rebase on {B}origin/main{B}.\n"}, 1, "origin/main not found", "documented false positive")
# symlink
case("symlinked-CLAUDE.md", {"real.md": f"Run {B}scripts/e2e.sh{B}.\n", "__symlink__": "real.md CLAUDE.md"}, 1, "scripts/e2e.sh not found")
# run from a subdirectory
case("run-from-subdir", {"CLAUDE.md": f"Run {B}scripts/e2e.sh{B}.\n", "docs/x.md": "", "__cwd__": "docs"}, 0, "no CLAUDE.md or AGENTS.md here", "wrong dir = nothing checked, says so")

def build(root, files):
    for rel, content in files.items():
        if rel.startswith("__"):
            continue
        p = os.path.join(root, rel)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, "w") as fh:
            fh.write(content)
    if "__symlink__" in files:
        tgt, ln = files["__symlink__"].split()
        os.symlink(tgt, os.path.join(root, ln))
    if "__chmod000__" in files:
        os.chmod(os.path.join(root, files["__chmod000__"]), 0)

def stub_bin(root, drop=None, grep2=False):
    """A PATH dir with the real tools linked in, minus `drop`, or with a grep that always errors."""
    b = os.path.join(root, "stubbin"); os.makedirs(b)
    for tool in ["grep", "sed", "tr", "sort", "cat", "printf", "echo", "ls"]:
        if tool == drop:
            continue
        real = None
        for d in PATH.split(":"):
            if os.path.exists(os.path.join(d, tool)):
                real = os.path.join(d, tool); break
        if real and not (tool == "grep" and grep2):
            os.symlink(real, os.path.join(b, tool))
    if grep2:
        g = os.path.join(b, "grep")
        with open(g, "w") as fh:
            fh.write("#!/bin/sh\necho 'grep: simulated failure' >&2\nexit 2\n")
        os.chmod(g, 0o755)
    return b

def run():
    print(f"script: {SCRIPT}\nshell: {SH}\nPATH: {PATH}\n")
    rows = []
    fails = 0
    for name, files, exp_exit, exp_out, note in CASES:
        root = tempfile.mkdtemp(prefix="cd-")
        build(root, files)
        env = {"PATH": PATH, "LC_ALL": "en_US.UTF-8", "HOME": root}
        if "__env__" in files:
            k, v = files["__env__"].split("=", 1); env[k] = v
        if "__nogrep__" in files:
            env["PATH"] = stub_bin(root, drop="grep")
        if "__nosed__" in files:
            env["PATH"] = stub_bin(root, drop="sed")
        if "__notr__" in files:
            env["PATH"] = stub_bin(root, drop="tr")
        if "__nosort__" in files:
            env["PATH"] = stub_bin(root, drop="sort")
        if "__grep2__" in files:
            env["PATH"] = stub_bin(root, grep2=True)
        cwd = os.path.join(root, files.get("__cwd__", ""))
        r = subprocess.run([SH, SCRIPT], cwd=cwd, env=env, capture_output=True, text=True, errors="replace")
        out, err = r.stdout.rstrip("\n"), r.stderr.rstrip("\n")
        if exp_exit == "nonzero":
            ok_exit = r.returncode != 0
        else:
            ok_exit = r.returncode == exp_exit
        if exp_out.startswith("!"):
            ok_out = exp_out[1:] not in out
        else:
            ok_out = exp_out in out
        verdict = "PASS" if (ok_exit and ok_out) else "FAIL"
        if verdict == "FAIL":
            fails += 1
        rows.append((verdict, name, exp_exit, r.returncode, out.replace("\n", " | "), err.replace("\n", " | "), note))
        # restore perms so temp cleanup works
        if "__chmod000__" in files:
            os.chmod(os.path.join(root, files["__chmod000__"]), 0o644)
        shutil.rmtree(root, ignore_errors=True)
    for v, n, ee, ae, o, e, note in rows:
        print(f"{v}  {n}\n      expected exit={ee}  actual exit={ae}\n      stdout: {o!r}\n      stderr: {e!r}" + (f"\n      note: {note}" if note else ""))
    print(f"\n{len(rows)} cases, {fails} FAIL")
    return fails

if __name__ == "__main__":
    sys.exit(1 if run() else 0)
