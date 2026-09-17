#!/bin/bash
# CHEAP CPU smoke test #2: build the head-to-tail cyclic peptide + protein-peptide complex with the
# CHARMM/psfgen mechanism (the automatable equivalent of CHARMM-GUI). Key: build the peptide segment
# with `first none last none` (NO charged terminal patches -> internal N/C types, avoiding the tleap
# N3-C trap) then apply a custom head-to-tail LINK patch. Reports whether the PSF builds, the C-N
# head-to-tail bond is present, and the peptide net charge is integer/neutral. No MD, no GPU.
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
# vmd provides the psfgen plugin (text mode); parmed/gemmi for split + verify
conda create -y -n psf -c conda-forge vmd gemmi numpy parmed >/dev/null 2>&1 || conda create -y -n psf -c conda-forge gemmi numpy parmed >/dev/null 2>&1
conda activate psf
echo "psfgen check:"; (echo 'package require psfgen; puts PSFGEN_OK; exit' | vmd -dispdev text 2>&1 | grep -E "PSFGEN_OK|can't find" | head -3) || echo "vmd/psfgen not available"

stage fetch_toppar
# CHARMM36m protein topology + params. Try the MacKerell tarball (several real release dates), then
# direct-file GitHub mirrors. Keep going until we have top_all36_prot.rtf.
mkdir -p toppar
for V in jul22 jul21 aug21 jul20 jul24; do
  if curl -fsSL "http://mackerell.umaryland.edu/download.php?filename=CHARMM_ff_params_files/toppar_c36_${V}.tgz" -o toppar.tgz 2>/dev/null && tar tzf toppar.tgz >/dev/null 2>&1; then
    tar xzf toppar.tgz; echo "got toppar_c36_${V}.tgz"; break
  fi
done
if [ -z "$(find . -name 'top_all36_prot.rtf' | head -1)" ]; then
  for BASE in \
    "https://raw.githubusercontent.com/wmwv/charmm36-toppar/master" \
    "https://raw.githubusercontent.com/intbio/charmm36/master" \
    "https://raw.githubusercontent.com/gph82/charmm36-toppar/master"; do
    curl -fsSL "$BASE/top_all36_prot.rtf" -o toppar/top_all36_prot.rtf 2>/dev/null || continue
    curl -fsSL "$BASE/par_all36m_prot.prm" -o toppar/par_all36m_prot.prm 2>/dev/null || true
    [ -s toppar/top_all36_prot.rtf ] && { echo "got toppar from $BASE"; break; }
  done
fi
RTF=$(find . -name "top_all36_prot.rtf" | head -1)
echo "topology rtf: ${RTF:-NOT FOUND}"
[ -z "$RTF" ] && { echo "FATAL: could not fetch CHARMM36 protein topology from any source"; stage failed; exit 1; }

stage split_chains
aws s3 sync "$DESIGNS_S3/1yf4/" "$ROOT/w/1yf4/" --only-show-errors --exclude "*" --include "*.cif"
CIF=$(find "$ROOT/w/1yf4" -name "*rank0*_1yf4_*.cif" ! -path "*before_refolding*" | head -1)
[ -z "$CIF" ] && CIF=$(find "$ROOT/w/1yf4" -name "*.cif" ! -path "*before_refolding*" | head -1)
python - "$CIF" <<'PY'
import sys, gemmi
st=gemmi.read_structure(sys.argv[1]); st.setup_entities(); m=st[0]
def is_aa(r):
    i=gemmi.find_tabulated_residue(r.name); return bool(i) and i.is_amino_acid()
ch=[(c.name,sum(is_aa(r) for r in c)) for c in m]; ch=[c for c in ch if c[1]>0]; ch.sort(key=lambda x:x[1])
pep,rec=ch[0][0],ch[-1][0]
def w(name,path):
    s=gemmi.Structure(); md=gemmi.Model('1'); c2=gemmi.Chain('P' if name==pep else 'R')
    for c in m:
        if c.name!=name: continue
        for r in c:
            if is_aa(r): c2.add_residue(r)
    md.add_chain(c2); s.add_model(md); s.setup_entities(); s.write_pdb(path); return sum(1 for _ in c2)
np_=w(pep,'peptide.pdb'); nr=w(rec,'receptor.pdb'); open('counts.env','w').write(f"NPEP={np_}\nNREC={nr}\n")
print("peptide res:",np_,"receptor res:",nr)
PY
. ./counts.env

stage psfgen_build
# custom head-to-tail patch: bond C(res1 in patch) to N(res2 in patch); regenerate handles angles/dih
cat > headtail.top <<'TOP'
* head-to-tail cyclization patch
*
   36  1
PRES LINK         0.00
BOND 1C 2N
TOP

cat > build.tcl <<TCL
package require psfgen
topology ${RTF}
topology headtail.top
# standard name aliases so PDB residue/atom names match CHARMM rtf
pdbalias residue HIS HSD
pdbalias residue HID HSD
pdbalias residue HIE HSE
pdbalias residue HIP HSP
pdbalias atom ILE CD1 CD
pdbalias atom SER HG HG1
pdbalias atom CYS HG HG1
pdbalias residue HOH TIP3

# receptor as normal protein chain
segment REC { pdb receptor.pdb }
coordpdb receptor.pdb REC

# peptide: NO terminal patches -> internal N/C types (avoids the tleap N3-C trap)
segment PEP {
  pdb peptide.pdb
  first none
  last none
}
coordpdb peptide.pdb PEP

# head-to-tail: bond peptide last-residue C to first-residue N
patch LINK PEP:${NPEP} PEP:1
regenerate angles dihedrals
guesscoord

writepsf complex.psf
writepdb complex.pdb

# peptide-only for charge/bond check
resetpsf
topology ${RTF}
topology headtail.top
segment PEP { pdb peptide.pdb; first none; last none }
coordpdb peptide.pdb PEP
patch LINK PEP:${NPEP} PEP:1
regenerate angles dihedrals
guesscoord
writepsf peptide.psf
writepdb peptide_cyc.pdb
exit
TCL
vmd -dispdev text -e build.tcl 2>&1 | tee psfgen.out || true

stage verify
python - <<'PY'
import json, os
rep={}
rep['complex_psf_built']=os.path.exists('complex.psf') and os.path.getsize('complex.psf')>0
rep['peptide_psf_built']=os.path.exists('peptide.psf') and os.path.getsize('peptide.psf')>0
out=open('psfgen.out').read() if os.path.exists('psfgen.out') else ''
rep['psfgen_errors']=[l for l in out.splitlines() if ('ERROR' in l or "couldn't" in l.lower() or 'failed' in l.lower() or 'unknown' in l.lower())][:15]
try:
    import parmed as pmd
    p=pmd.load_file('peptide.psf')
    rep['peptide_nres']=len(p.residues); rep['peptide_natoms']=len(p.atoms)
    rep['peptide_net_charge']=round(sum(a.charge for a in p.atoms),3)
    def idx(res,nm):
        for a in res.atoms:
            if a.name==nm: return a.idx
        return None
    ni=idx(p.residues[0],'N'); ci=idx(p.residues[-1],'C')
    rep['head_to_tail_bond_present']=any({b.atom1.idx,b.atom2.idx}=={ni,ci} for b in p.bonds) if (ni is not None and ci is not None) else False
except Exception as e:
    rep['parmed_error']=str(e)[:200]
json.dump(rep, open('/opt/psf/status/psfgen_smoke.json','w'), indent=2)
print(json.dumps(rep, indent=2))
PY
cp psfgen.out peptide_cyc.pdb /opt/psf/status/ 2>/dev/null || true
stage psfgen_complete
