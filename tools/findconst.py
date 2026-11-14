# Usage: python findconst.py <raw arm64 kernel Image>. Python stdlib only. Read-only.
# Find clusters of AArch64 MOVZ/CMP-immediate loads of given 16-bit constants in a raw Image.
import sys, struct
data=open(sys.argv[1],'rb').read()
want={0x2000,0x2400,0x2c00,0x5000,0x5400,0x5c00,0x5d00,0x6000,0x6c00,0x7400,0x7c00}
hits=[]
for off in range(0,len(data)-4,4):
    ins=struct.unpack_from('<I',data,off)[0]
    if ins & 0x7f800000 == 0x52800000 and ((ins>>21)&3)==0:   # MOVZ W/X, hw=0
        imm=(ins>>5)&0xffff
        if imm in want: hits.append((off,imm))
    elif ins & 0x7f800000 == 0x71000000 or ins & 0x7f800000==0x31000000: # SUBS/ADDS imm (CMP/CMN)
        sh=(ins>>22)&1; imm=((ins>>10)&0xfff)<<(12 if sh else 0)
        if imm in want: hits.append((off,imm))
best=[]
for i,(o,_) in enumerate(hits):
    win={v for (p,v) in hits if o<=p<o+512}
    if len(win)>=4: best.append((len(win),o,sorted(hex(x) for x in win)))
best.sort(reverse=True)
seen=set()
for n,o,w in best:
    k=o//512
    if k in seen: continue
    seen.add(k); print(n,hex(o),w)
    if len(seen)>8: break
