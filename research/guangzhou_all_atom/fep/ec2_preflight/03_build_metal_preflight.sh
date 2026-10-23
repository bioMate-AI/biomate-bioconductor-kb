#!/bin/bash
exec > /tmp/build_a2.log 2>&1
set -x
export PATH=/opt/conda/bin:$PATH
export GMXLIB=/root
cd /root/buildA || { echo "NO buildA"; exit 1; }
# buildA already has: tri.cif, cada_mn.itp, em.mdp, conf.gro (protein), topol.top (protein-only)
test -f conf.gro && test -f topol.top || { echo "MISSING protein build"; exit 1; }
echo "=== build 3 CaDA-Mn (center + 6 octahedral dummies @0.9A) + merge into protein .gro ==="
/opt/conda/bin/python - <<'PY'
import gemmi
st=gemmi.read_structure("tri.cif")
mns=[]
for ch in st[0]:
    for r in ch:
        if r.name=="MN":
            a=r[0]; mns.append((a.pos.x,a.pos.y,a.pos.z))
print("Mn centers:", mns)
assert len(mns)==3, f"expected 3 Mn, got {len(mns)}"
# read protein conf.gro
L=open("conf.gro").read().splitlines()
title=L[0]; n=int(L[1]); atoms=L[2:2+n]; box=L[2+n]
d=0.09  # nm, M-D bond
offs=[(d,0,0),(-d,0,0),(0,d,0),(0,-d,0),(0,0,d),(0,0,-d)]
# gro is nm; cif is Angstrom
mn_lines=[]; resnum=9000; anum=n
for i,(x,y,z) in enumerate(mns):
    x,y,z=x/10.0,y/10.0,z/10.0
    resnum+=1
    anum+=1; mn_lines.append(f"{resnum%100000:5d}{'MN2':<5s}{'MN':>5s}{anum%100000:5d}{x:8.3f}{y:8.3f}{z:8.3f}")
    for j,(dx,dy,dz) in enumerate(offs):
        anum+=1; mn_lines.append(f"{resnum%100000:5d}{'MN2':<5s}{('D%d'%(j+1)):>5s}{anum%100000:5d}{x+dx:8.3f}{y+dy:8.3f}{z+dz:8.3f}")
allatoms=atoms+mn_lines
open("confmn.gro","w").write(title+"\n"+f"{len(allatoms)}\n"+"\n".join(allatoms)+"\n"+box+"\n")
print("merged atoms:", len(allatoms), "(protein", n, "+ Mn", len(mn_lines),")")
PY
echo "=== topol.top surgery: include cada_mn.itp (after FF include) + add MN2 3 to [molecules] ==="
/opt/conda/bin/python - <<'PY'
t=open("topol.top").read().splitlines(); out=[]; inc_done=False
for i,l in enumerate(t):
    out.append(l)
    if (not inc_done) and l.strip().startswith('#include') and 'forcefield.itp' in l:
        out.append('#include "cada_mn.itp"'); inc_done=True
# add MN2 3 at end of [ molecules ]
s="\n".join(out).rstrip().splitlines()
# find [ molecules ] block and append after its last non-empty molecule line
res=[]; inmol=False
for l in s:
    res.append(l)
if '[ molecules ]' in "\n".join(s) or '[molecules]' in "\n".join(s):
    res.append("MN2                 3")
open("topol.top","w").write("\n".join(res)+"\n")
print("cada include inserted:", inc_done, "| MN2 3 appended")
PY
grep -nE 'cada_mn|MN2' topol.top | head
echo "=== box + solvate + grompp PREFLIGHT (metal-aware) ==="
gmx editconf -f confmn.gro -o box.gro -bt dodecahedron -d 1.0 2>&1 | tail -3
gmx solvate -cp box.gro -cs spc216.gro -o solv.gro -p topol.top 2>&1 | tail -4
gmx grompp -f em.mdp -c solv.gro -p topol.top -o em_mn.tpr -maxwarn 100 2>&1 | tail -25
echo "GROMPP_MN_EXIT=$?"
[ -f em_mn.tpr ] && echo "METAL_PREFLIGHT_PASS: em_mn.tpr ($(stat -c%s em_mn.tpr) bytes)" || echo "METAL_PREFLIGHT_FAIL"
echo "DONE $(date)"
