#!/bin/bash
# CPU smoke #3: build the head-to-tail cyclic peptide with a MODERN standalone psfgen (Eigenstate,
# conda-forge `psfgen` Python API) instead of the ancient VMD-1.9.3 psfgen that failed the LINK patch.
# `first none last none` -> internal N/C types (no N3 trap) + custom LINK patch for the head-to-tail
# amide. Peptide-only (isolates the fragile cyclization; no receptor HIS-aliasing noise). Reports PSF
# build, head-to-tail C-N bond present, net charge. No MD, no GPU.
set -Eeuo pipefail
export AWS_DEFAULT_REGION=us-west-2 DEBIAN_FRONTEND=noninteractive PYTHONUNBUFFERED=1 HOME=/root
ROOT=/opt/psf; OUT_S3=${OUT_S3:?}; DESIGNS_S3=${DESIGNS_S3:?}
mkdir -p "$ROOT/status" "$ROOT/w"; cd "$ROOT/w"
exec > >(tee -a "$ROOT/status/psf.log") 2>&1
stage(){ printf '{"stage":"%s","time":"%s"}\n' "$1" "$(date -u +%FT%TZ)" > "$ROOT/status/status.json"; aws s3 sync "$ROOT/status" "$OUT_S3/status/" --only-show-errors || true; }
trap 'rc=$?; [ $rc -ne 0 ] && stage failed; sync; sleep 6; aws s3 sync "$ROOT/status" "$OUT_S3/status/" --only-show-errors || true; sleep 4; shutdown -h now; exit $rc' EXIT
systemd-run --unit=psf-deadline --on-active=40m /sbin/shutdown -h now || true

stage installing
command -v aws >/dev/null 2>&1 || { apt-get update -qq && apt-get install -y -qq unzip curl && curl -fsSL https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o /tmp/a.zip && (cd /tmp && unzip -q -o a.zip && ./aws/install --update); }
curl -fsSL https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -o /tmp/mc.sh
bash /tmp/mc.sh -b -p /opt/miniconda; source /opt/miniconda/etc/profile.d/conda.sh
conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main || true
conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r || true
# modern standalone psfgen (Eigenstate) with Python API — NOT the VMD 1.9.3 plugin
conda create -y -n psf -c conda-forge python=3.11 psfgen gemmi numpy parmed >/dev/null 2>&1 || \
  { conda create -y -n psf -c conda-forge python=3.11 gemmi numpy parmed >/dev/null 2>&1; conda activate psf; pip install psfgen 2>&1 | tail -3; }
conda activate psf
python -c "import psfgen, inspect; from psfgen import PsfGen; print('psfgen OK ver', getattr(psfgen,'__version__','?')); print([m for m in dir(PsfGen) if not m.startswith('_')])"

stage fetch_toppar
mkdir -p toppar
for V in jul22 jul21 aug21 jul20 jul24; do
  if curl -fsSL "http://mackerell.umaryland.edu/download.php?filename=CHARMM_ff_params_files/toppar_c36_${V}.tgz" -o toppar.tgz 2>/dev/null && tar tzf toppar.tgz >/dev/null 2>&1; then tar xzf toppar.tgz; echo "got toppar_c36_${V}"; break; fi
done
if [ -z "$(find . -name 'top_all36_prot.rtf' | head -1)" ]; then
  for BASE in "https://raw.githubusercontent.com/wmwv/charmm36-toppar/master" "https://raw.githubusercontent.com/intbio/charmm36/master"; do
    curl -fsSL "$BASE/top_all36_prot.rtf" -o toppar/top_all36_prot.rtf 2>/dev/null && [ -s toppar/top_all36_prot.rtf ] && { echo "got rtf from $BASE"; break; }
  done
fi
RTF=$(find . -name "top_all36_prot.rtf" | head -1)
echo "rtf: ${RTF:-NOTFOUND}"; [ -z "$RTF" ] && { echo "FATAL: no CHARMM36 rtf"; exit 1; }

stage split_peptide
aws s3 sync "$DESIGNS_S3/1yf4/" "$ROOT/w/1yf4/" --only-show-errors --exclude "*" --include "*.cif"
CIF=$(find "$ROOT/w/1yf4" -name "*rank0*_1yf4_*.cif" ! -path "*before_refolding*" | head -1)
[ -z "$CIF" ] && CIF=$(find "$ROOT/w/1yf4" -name "*.cif" ! -path "*before_refolding*" | head -1)
python - "$CIF" <<'PY'
import sys, gemmi
st=gemmi.read_structure(sys.argv[1]); st.setup_entities(); m=st[0]
def is_aa(r):
    i=gemmi.find_tabulated_residue(r.name); return bool(i) and i.is_amino_acid()
ch=[(c.name,sum(is_aa(r) for r in c)) for c in m]; ch=[c for c in ch if c[1]>0]; ch.sort(key=lambda x:x[1])
pep=ch[0][0]
s=gemmi.Structure(); md=gemmi.Model('1'); c2=gemmi.Chain('P')
for c in m:
    if c.name!=pep: continue
    for r in c:
        if is_aa(r): c2.add_residue(r)
md.add_chain(c2); s.add_model(md); s.setup_entities()
# renumber peptide residues 1..N so the LINK patch resid refs ('1'..'N') are valid
n=0
for r in s[0][0]:
    n+=1; r.seqid=gemmi.SeqId(n,' ')
s.write_pdb('peptide.pdb')
open('counts.env','w').write(f"NPEP={n}\n"); print("peptide residues (renumbered 1..N):", n)
PY
. ./counts.env

stage build_cyclic
cat > headtail.top <<'TOP'
* head-to-tail cyclization patch
*
   36  1
PRES CYCP         0.00
BOND 1C 2N

END
TOP
RTF="$RTF" NPEP="$NPEP" python - <<'PY'
import os, json
from psfgen import PsfGen
NPEP=int(os.environ['NPEP']); rep={}
g=PsfGen()
g.read_topology(os.environ['RTF'])
g.read_topology('headtail.top')
# peptide segment WITHOUT terminal patches -> internal N/C types (avoids the N3 trap)
g.add_segment(segid='PEP', pdbfile='peptide.pdb', first='none', last='none')
g.read_coords(segid='PEP', filename='peptide.pdb')
# head-to-tail: bond last-residue C -> first-residue N
g.patch('CYCP', [('PEP', str(NPEP)), ('PEP', '1')])
g.regenerate_angles(); g.regenerate_dihedrals()
try: g.guess_coords()
except Exception as e: rep['guess_coords_warn']=str(e)[:150]
g.write_psf(filename='peptide.psf'); g.write_pdb(filename='peptide_cyc.pdb')
rep['psf_built']=os.path.exists('peptide.psf') and os.path.getsize('peptide.psf')>0
import parmed as pmd
p=pmd.load_file('peptide.psf')
def idx(res,nm):
    for a in res.atoms:
        if a.name==nm: return a.idx
    return None
ni=idx(p.residues[0],'N'); ci=idx(p.residues[-1],'C')
rep['peptide_nres']=len(p.residues); rep['peptide_natoms']=len(p.atoms)
rep['resids']=[r.number for r in p.residues]; rep['nbonds']=len(p.bonds)
rep['net_charge']=round(sum(a.charge for a in p.atoms),3)
rep['head_to_tail_bond_present']=any({b.atom1.idx,b.atom2.idx}=={ni,ci} for b in p.bonds) if (ni is not None and ci is not None) else False
json.dump(rep, open('/opt/psf/status/psfgen_smoke.json','w'), indent=2)
print(json.dumps(rep, indent=2))
PY
cp peptide_cyc.pdb /opt/psf/status/ 2>/dev/null || true
stage psfgen_complete
