#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Doc consistency checks (Manager file 2026-11-15-d, part 2). Python standard library only.

  1. every relative link in a tracked *.md resolves to a file or directory (fragments ignored;
     links inside code spans and fenced code blocks are not links)
  2. every R/K/Q/H id that heads a row of docs/master-task-list.md is unique, and every id cited in
     docs/research-sync.md appears somewhere in the master list
  3. every handoff-*.md named in README.md or docs/master-task-list.md exists in docs/
  4. Q10: the FEL kit (docs/r2-fel-test-kit.md) expects u-boot's `DRAM:  2 GiB` on Dale's 2 GB unit, not 1 GiB
     (the u-boot side, no DRAM size cap below 2 GiB, is `scripts/build-uboot.sh --config-only`)

usage: scripts/check-docs.py [REPO]   exit 0 = clean, 1 = problems (listed), 2 = usage
"""
import os
import re
import subprocess
import sys

ID = r"[RKQH]\d{1,2}"           # R1, K23, Q9, H7 (not H616/H700: three digits)
LINK = re.compile(r"!?\[[^\]]*\]\(([^)\s]+)(?:\s+\"[^\"]*\")?\)")


def md_files(repo):
    try:
        out = subprocess.run(["git", "-C", repo, "ls-files", "*.md"], capture_output=True, text=True, check=True).stdout
        return [f for f in out.splitlines() if f]
    except (OSError, subprocess.CalledProcessError):
        return sorted(os.path.relpath(os.path.join(d, f), repo) for d, _, fs in os.walk(repo)
                      if "/.git" not in d and "/.work" not in d for f in fs if f.endswith(".md"))


def strip_code(text):
    """Blank fenced blocks and inline code spans, keeping line numbers."""
    text = re.sub(r"^(```|~~~).*?^\1[^\n]*$", lambda m: "\n" * m.group(0).count("\n"), text, flags=re.M | re.S)
    return re.sub(r"`[^`\n]*`", "``", text)


def check_links(repo, files, problems):
    n = 0
    for f in files:
        text = strip_code(open(os.path.join(repo, f), encoding="utf-8", errors="replace").read())
        for lineno, line in enumerate(text.splitlines(), 1):
            for m in LINK.finditer(line):
                target = m.group(1).strip("<>")
                if re.match(r"^[a-z][a-z0-9+.-]*:", target, re.I) or target.startswith("#"):
                    continue          # http(s), mailto, computer://, in-page anchors
                path = target.split("#", 1)[0].split("?", 1)[0]
                if not path:
                    continue
                n += 1
                base = repo if path.startswith("/") else os.path.dirname(os.path.join(repo, f))
                if not os.path.exists(os.path.normpath(os.path.join(base, path.lstrip("/")))):
                    problems.append("%s:%d: broken link %s" % (f, lineno, target))
    return n


def check_ids(repo, problems):
    ml = os.path.join(repo, "docs", "master-task-list.md")
    sync = os.path.join(repo, "docs", "research-sync.md")
    text = open(ml, encoding="utf-8").read()
    rows = {}
    for lineno, line in enumerate(text.splitlines(), 1):
        m = re.match(r"^\|\s*(%s)\b" % ID, line)
        if m:
            rows.setdefault(m.group(1), []).append(lineno)
    for i, lines in sorted(rows.items()):
        if len(lines) > 1:
            problems.append("docs/master-task-list.md: id %s heads %d rows (lines %s)" % (i, len(lines), ", ".join(map(str, lines))))
    known = set(re.findall(r"\b(%s)\b" % ID, text))
    cited = {}
    for lineno, line in enumerate(open(sync, encoding="utf-8").read().splitlines(), 1):
        for i in re.findall(r"\b(%s)\b" % ID, line):
            cited.setdefault(i, lineno)
    for i, lineno in sorted(cited.items()):
        if i not in known:
            problems.append("docs/research-sync.md:%d: %s is not in docs/master-task-list.md" % (lineno, i))
    return len(rows), len(cited)


def check_handoffs(repo, problems):
    n = 0
    for f in ("README.md", "docs/master-task-list.md"):
        for lineno, line in enumerate(open(os.path.join(repo, f), encoding="utf-8").read().splitlines(), 1):
            for name in re.findall(r"(handoff-[A-Za-z0-9._-]+?\.md)", line):
                n += 1
                if not os.path.exists(os.path.join(repo, "docs", name)):
                    problems.append("%s:%d: handoff docs/%s does not exist" % (f, lineno, name))
    return n


def check_dram_size(repo, problems):
    f = "docs/r2-fel-test-kit.md"
    text = open(os.path.join(repo, f), encoding="utf-8").read()
    if not re.search(r"^DRAM:  2 GiB\b", text, re.M):
        problems.append("%s: expected u-boot line `DRAM:  2 GiB` (Q10) is missing" % f)
    for lineno, line in enumerate(text.splitlines(), 1):
        if re.match(r"^DRAM:  ?(1 GiB|1024 MiB)\b", line):
            problems.append("%s:%d: expects 1 GiB; Q10 says 2 GiB on Dale's unit" % (f, lineno))


def main():
    if len(sys.argv) > 2:
        print(__doc__)
        return 2
    repo = os.path.abspath(sys.argv[1] if len(sys.argv) == 2 else os.path.join(os.path.dirname(__file__), ".."))
    problems = []
    files = md_files(repo)
    links = check_links(repo, files, problems)
    rows, cited = check_ids(repo, problems)
    handoffs = check_handoffs(repo, problems)
    check_dram_size(repo, problems)
    for p in problems:
        print("FAIL " + p)
    print("check-docs: %d .md files, %d relative links, %d master-list ids, %d ids cited in research-sync, "
          "%d handoff refs, r2 DRAM size: %s" % (len(files), links, rows, cited, handoffs,
                                   "OK" if not problems else "%d problem(s)" % len(problems)))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
