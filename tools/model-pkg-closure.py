#!/usr/bin/python3
# SPDX-License-Identifier: GPL-2.0-only
# R33: model which packages a slimming change would remove, from an image rootfs dpkg status file.
# usage: tools/model-pkg-closure.py <rootfs>/var/lib/dpkg/status   (run from the repo root; reads image/packages.txt)
# Roots = image/packages.txt + Priority required/important/Essential + the kernel. Desk estimate, not an apt solve.
import re,sys
st=open(sys.argv[1]).read().split('\n\n')
pk={}
for b in st:
    d={}; k=None
    for l in b.split('\n'):
        if l.startswith(' ') and k: d[k]+=l; continue
        if ':' in l: k,v=l.split(':',1); d[k]=v.strip()
    if 'Package' in d and 'install ok installed' in d.get('Status',''):
        pk[d['Package']]=d
prov={}
for n,d in pk.items():
    for p in re.split(r',\s*',d.get('Provides','')):
        if p: prov.setdefault(p.split()[0],[]).append(n)
def deps(n,override):
    s=override.get(n, pk[n].get('Depends','')+','+pk[n].get('Pre-Depends',''))
    out=[]
    for alt in s.split(','):
        alt=alt.strip()
        if not alt: continue
        for a in alt.split('|'):
            nm=a.strip().split()[0].split(':')[0]
            if nm in pk: out.append(nm); break
            if nm in prov: out.append(prov[nm][0]); break
    return out
roots=[l.strip() for l in open('image/packages.txt') if l.strip() and not l.startswith('#')]
roots=[r for r in roots if r in pk]+[n for n,d in pk.items() if d.get('Priority') in ('required','important') or d.get('Essential')=='yes' or n.startswith('linux-image') or n=='reduxos-retroarch-slim']
def closure(roots,override,drop=()):
    seen=set(); st=[r for r in roots if r not in drop]
    while st:
        n=st.pop()
        if n in seen or n in drop: continue
        seen.add(n); st+=deps(n,override)
    return seen
size=lambda S: sum(int(pk[n].get('Installed-Size','0')) for n in S)/1024
base=closure(roots,{})
print(f"installed {len(pk)} pkgs {size(pk):.0f} MB; reachable {len(base)} {size(base):.0f} MB")
ra_min='libasound2t64,libavcodec60,libavformat60,libavutil58,libc6,libdrm2,libegl1,libflac12t64,libfreetype6,libgbm1,libgcc-s1,libgles2,libstdc++6,libswresample4,libswscale7,libudev1,zlib1g,libretro-core-info,fonts-dejavu-core'
for name,ov,drop in [('RA source build (KMS/GLES only)',{'retroarch':ra_min},()),('drop mpv',{},('mpv',)),('both',{'retroarch':ra_min},('mpv',))]:
    c=closure(roots,ov,drop); gone=base-c
    print(f"{name}: -{size(gone):.0f} MB, {len(gone)} pkgs: "+' '.join(sorted(gone, key=lambda n:-int(pk[n].get('Installed-Size','0')))[:14]))
