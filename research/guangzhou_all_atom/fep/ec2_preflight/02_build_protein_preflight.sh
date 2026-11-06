#!/bin/bash
exec > /tmp/build_a.log 2>&1
set -x
export PATH=/opt/conda/bin:$PATH
export GMXLIB=/root
cd /root && rm -rf buildA && mkdir buildA && cd buildA
echo "=== download inputs ==="
curl -sSL "$URL_TRI" -o tri.cif
curl -sSL "$URL_ITP" -o cada_mn.itp
curl -sSL "$URL_EM"  -o em.mdp
ls -l tri.cif cada_mn.itp em.mdp; head -1 tri.cif
echo "=== cif -> complex.pdb (protein chains A,B,P; drop Mn/water/het) ==="
/opt/conda/bin/python - <<'PY'
import gemmi
AA=set("ALA ARG ASN ASP CYS GLN GLU GLY HIS ILE LEU LYS MET PHE PRO SER THR TRP TYR VAL".split())
st=gemmi.read_structure("tri.cif"); st.setup_entities()
m=st[0]; out=gemmi.Structure(); out.add_model(gemmi.Model("1"))
for ch in m:
    keep=[r for r in ch if r.name in AA]
    if keep:
        nc=gemmi.Chain(ch.name)
        for r in keep: nc.add_residue(r)
        out[0].add_chain(nc)
out.setup_entities()
doc=out.make_pdb_string()
open("complex.pdb","w").write(doc)
print("chains:", [ (c.name, len(c)) for c in out[0] ])
PY
grep -c "^ATOM" complex.pdb
echo "=== pdb2gmx (CHARMM36m, tip3p) — vacuum topology parse test ==="
# auto-answer: default termini; SS bonds auto. Use -ignh to rebuild H; -merge all to one system.
printf '\n' | gmx pdb2gmx -f complex.pdb -ff charmm36-jul2022 -water tip3p -ignh -merge all \
  -o conf.gro -p topol.top -i posre.itp 2>&1 | tail -25
echo "PDB2GMX_EXIT=${PIPESTATUS[0]}"
echo "=== grompp PREFLIGHT (vacuum box; does the topology parse?) ==="
if [ -f conf.gro ]; then
  gmx editconf -f conf.gro -o box.gro -bt dodecahedron -d 1.0 2>&1 | tail -3
  gmx grompp -f em.mdp -c box.gro -p topol.top -o em.tpr -maxwarn 50 2>&1 | tail -20
  echo "GROMPP_EXIT=$?"
  [ -f em.tpr ] && echo "PREFLIGHT_PASS: em.tpr built ($(stat -c%s em.tpr) bytes)" || echo "PREFLIGHT_FAIL: no em.tpr"
else
  echo "PREFLIGHT_SKIP: pdb2gmx produced no conf.gro"
fi
echo "DONE $(date)"
