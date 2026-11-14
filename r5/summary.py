#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Summarise r5-measure console logs into a Markdown table. usage: summary.py boot-*.log"""
import re,sys
def parse(f):
    t=open(f,errors="replace").read()
    t=re.sub(r"\[ *[0-9.]+\] r5-measure\[\d+\]: ","",t)
    g=lambda p: (re.search(p,t,re.M) or [None,None])[1]
    return dict(
        total=g(r"^MemTotal:\s+(\d+)"), avail=g(r"^MemAvailable:\s+(\d+)"), anon=g(r"^AnonPages:\s+(\d+)"),
        slab=g(r"^Slab:\s+(\d+)"), cached=g(r"^Cached:\s+(\d+)"), rss=g(r"rss_sum_kB (\d+)"), pss=g(r"pss_sum_kB (\d+)"),
        zram=g(r"^/dev/zram0 zstd\s+(\S+)"), boot=g(r"Startup finished in (.*)"), procs=g(r"== procs (\d+)"),
        svcs=len(re.findall(r"^\S+\.service$", t.split("== services")[1].split("==")[0], re.M)) if "== services" in t else None)
mb=lambda k: f"{int(k)/1024:.0f}" if k else "–"
print("| run | MemTotal | MemAvailable | used (total−avail) | AnonPages | Slab | Cached | RSS sum | PSS sum | zram | running services | boot (TCG) |")
print("|---|---|---|---|---|---|---|---|---|---|---|---|")
for f in sys.argv[1:]:
    d=parse(f); u=(int(d['total'])-int(d['avail']))/1024 if d['total'] else 0
    print(f"| {f.replace('boot-','').replace('.log','')} | {mb(d['total'])} | {mb(d['avail'])} | {u:.0f} | {mb(d['anon'])} | {mb(d['slab'])} | {mb(d['cached'])} | {mb(d['rss'])} | {mb(d['pss'])} | {d['zram']} | {d['svcs']} | {d['boot']} |")
