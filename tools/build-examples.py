#!/usr/bin/env python3
"""Builds docs/images/<family>.svg and .txt from the captured prompts and refreshes the README example blocks.

Called by render-examples.sh:  build-examples.py <repo root> <capture dir (manifest.tsv + ansi/)>
"""
import os
import re
import subprocess
import sys

root, out = sys.argv[1], sys.argv[2]
titles = {
    "starship": "Starship prompt (install.sh)",
    "powerline": "Powerline prompt, the powerline package (install-powerline.sh, Linux)",
    "powerline-shell": "Powerline prompt, powerline-shell (install-powerline.sh, macOS)",
}
rows = [line.rstrip("\n").split("\t") for line in open(os.path.join(out, "manifest.tsv"), encoding="utf-8")]
readme_path = os.path.join(root, "README.md")
readme = open(readme_path, encoding="utf-8").read()

for fam, title in titles.items():
    pairs = []
    for f, name, cap, _host, _user in rows:
        if f == fam:
            pairs += [os.path.join(out, "ansi", "%s-%s.ans" % (f, name)), cap]
    svg = os.path.join(root, "docs", "images", fam + ".svg")
    txt = os.path.join(root, "docs", "images", fam + ".txt")
    subprocess.check_call([sys.executable, os.path.join(root, "tools", "ansi2svg.py"),
                           "--title", title, "--svg", svg, "--txt", txt] + pairs)
    # README: the plain text, one block per prompt, between the markers
    blocks, cur = [], None
    for line in open(txt, encoding="utf-8").read().split("\n"):
        if line.startswith("# "):
            cur = [line[2:], []]
            blocks.append(cur)
        elif cur is not None and line != "":
            cur[1].append(line)
    # only the first situation is repeated as plain text here; the picture shows them all, the .txt file has them all
    cap, ls = blocks[0]
    md = "**%s**, as plain text:\n\n```text\n%s\n```\n\nAll the situations in the picture, as plain text: [docs/images/%s.txt](docs/images/%s.txt).\n" % (cap, "\n".join(ls), fam, fam)
    pat = re.compile(r"(<!-- examples:%s -->\n).*?(<!-- /examples:%s -->)" % (re.escape(fam), re.escape(fam)), re.S)
    if pat.search(readme):
        readme = pat.sub(lambda m: m.group(1) + "\n" + md + "\n" + m.group(2), readme)

open(readme_path, "w", encoding="utf-8").write(readme)
print("wrote docs/images/*.svg and *.txt; README example blocks refreshed")
