#!/bin/bash
# CHEAP CPU smoke test of the FRAGILE step only: build a head-to-tail cyclic peptide + protein-peptide
# complex topology in AMBER tleap (ff19SB, peptide as PROTEIN), from a real BoltzGen design. No MD, no
# GPU. Purpose: validate the cyclic-tleap recipe (strip OXT/terminal-H + explicit bond) and report
# whether the topology builds cleanly + the head-to-tail bond is present, BEFORE committing to a full
# GPU MD + gmx_MMPBSA workflow. Iterate on the recipe here (minutes, ~$0.05) not on GPU MD.
set -Eeuo pipefail
export AWS_DEFAULT_REGION=us-west-2 DEBIAN_FRONTEND=noninteractive PYTHONUNBUFFERED=1 HOME=/root
ROOT=/opt/smoke; OUT_S3=${OUT_S3:?}; DESIGNS_S3=${DESIGNS_S3:?}
mkdir -p "$ROOT/status" "$ROOT/w"; cd "$ROOT/w"
exec > >(tee -a "$ROOT/status/smoke.log") 2>&1
stage(){ printf '{"stage":"%s","time":"%s"}\n' "$1" "$(date -u +%FT%TZ)" > "$ROOT/status/status.json"; aws s3 sync "$ROOT/status" "$OUT_S3/status/" --only-show-errors || true; }
trap 'rc=$?; [ $rc -ne 0 ] && stage failed; sync; sleep 6; aws s3 sync "$ROOT/status" "$OUT_S3/status/" --only-show-errors || true; sleep 4; shutdown -h now; exit $rc' EXIT
systemd-run --unit=smoke-deadline --on-active=40m /sbin/shutdown -h now || true

stage installing
command -v aws >/dev/null 2>&1 || { apt-get update -qq && apt-get install -y -qq unzip curl && curl -fsSL https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o /tmp/a.zip && (cd /tmp && unzip -q -o a.zip && ./aws/install --update); }
curl -fsSL https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -o /tmp/mc.sh
bash /tmp/mc.sh -b -p /opt/miniconda; source /opt/miniconda/etc/profile.d/conda.sh
conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main || true
conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r || true
conda create -y -n at -c conda-forge ambertools gemmi numpy >/dev/null 2>&1
conda activate at
python -c "import gemmi; print('gemmi ok')"; which tleap pdb4amber parmed

stage fetch_design
# grab the 1yf4 top ranked design complex (small 7-mer peptide GSGLLKS + kallikrein) from v5 output
aws s3 sync "$DESIGNS_S3/1yf4/" "$ROOT/w/1yf4/" --only-show-errors --exclude "*" --include "*.cif"
CIF=$(find "$ROOT/w/1yf4" -name "*rank0*_1yf4_*.cif" ! -path "*before_refolding*" | head -1)
[ -z "$CIF" ] && CIF=$(find "$ROOT/w/1yf4" -name "*.cif" ! -path "*before_refolding*" | head -1)
echo "using design: $CIF"

stage split_chains
python - "$CIF" <<'PY'
import sys, gemmi
st=gemmi.read_structure(sys.argv[1]); st.setup_entities(); m=st[0]
def is_aa(r):
    i=gemmi.find_tabulated_residue(r.name); return bool(i) and i.is_amino_acid()
chains=[(c.name, sum(is_aa(r) for r in c)) for c in m]
chains=[c for c in chains if c[1]>0]
chains.sort(key=lambda x:x[1])
pep_name=chains[0][0]; rec_name=chains[-1][0]           # shortest AA chain = peptide, longest = receptor
print("chains(len):", chains, "-> peptide=", pep_name, "receptor=", rec_name)
def write_chain(name, path):
    s=gemmi.Structure(); md=gemmi.Model('1'); ch=gemmi.Chain('A')
    for c in m:
        if c.name!=name: continue
        for r in c:
            if is_aa(r): ch.add_residue(r)
    md.add_chain(ch); s.add_model(md); s.setup_entities()
    s.write_pdb(path)
    return sum(1 for r in ch)
npep=write_chain(pep_name,'peptide_raw.pdb'); nrec=write_chain(rec_name,'receptor_raw.pdb')
open('counts.env','w').write(f"NPEP={npep}\nNREC={nrec}\n")
print("peptide residues:", npep, " receptor residues:", nrec)
PY
. ./counts.env

stage prep
# pdb4amber: drop H + waters; keep it minimal. For the cyclic peptide we then strip OXT (C-term) so
# the head-to-tail amide is chemically correct.
pdb4amber -i peptide_raw.pdb  -o peptide_clean.pdb  --nohyd --dry 2>&1 | tail -5 || true
pdb4amber -i receptor_raw.pdb -o receptor_clean.pdb --nohyd --dry 2>&1 | tail -5 || true
# remove OXT records from the peptide (tleap will otherwise treat C-term as capped)
grep -v ' OXT ' peptide_clean.pdb > peptide_nooxt.pdb || cp peptide_clean.pdb peptide_nooxt.pdb

stage tleap_peptide_cyclic
# ATTEMPT recipe: load peptide, remove terminal extras, add head-to-tail bond, saveparm. We log
# tleap output verbatim so we can SEE if terminal typing / missing-atom errors occur.
cat > pep.tleap <<TLEAP
source leaprc.protein.ff19SB
pep = loadpdb peptide_nooxt.pdb
remove pep pep.1.H2
remove pep pep.1.H3
remove pep pep.${NPEP}.OXT
bond pep.1.N pep.${NPEP}.C
check pep
savepdb pep pep_cyclic.pdb
saveamberparm pep pep_gas.prmtop pep_gas.inpcrd
quit
TLEAP
tleap -f pep.tleap 2>&1 | tee tleap_pep.log || true

stage tleap_complex
cat > comp.tleap <<TLEAP
source leaprc.protein.ff19SB
PROT = loadpdb receptor_clean.pdb
PEP  = loadpdb peptide_nooxt.pdb
remove PEP PEP.1.H2
remove PEP PEP.1.H3
remove PEP PEP.${NPEP}.OXT
bond PEP.1.N PEP.${NPEP}.C
COMP = combine {PROT PEP}
check COMP
saveamberparm COMP comp_gas.prmtop comp_gas.inpcrd
quit
TLEAP
tleap -f comp.tleap 2>&1 | tee tleap_comp.log || true

stage verify
python - <<'PY'
import json, os
rep={'built':{}, 'tleap_errors':{}}
for tag,log,parm in [('peptide','tleap_pep.log','pep_gas.prmtop'),('complex','tleap_comp.log','comp_gas.prmtop')]:
    txt=open(log).read() if os.path.exists(log) else ''
    errs=[l for l in txt.splitlines() if ('FATAL' in l or 'Error' in l or 'Warning: Close contact' in l or 'could not' in l.lower())]
    rep['tleap_errors'][tag]=errs[:15]
    rep['built'][tag]=os.path.exists(parm) and os.path.getsize(parm)>0
# check the head-to-tail bond is present in the peptide topology via parmed
try:
    import parmed as pmd
    p=pmd.load_file('pep_gas.prmtop')
    nres=len(p.residues); n_atom_first=p.residues[0]; c_atom_last=p.residues[-1]
    # find a bond between N of res0 and C of last res
    def idx(res,nm):
        for a in res.atoms:
            if a.name==nm: return a.idx
        return None
    ni=idx(p.residues[0],'N'); ci=idx(p.residues[-1],'C')
    has_cyc=any({b.atom1.idx,b.atom2.idx}=={ni,ci} for b in p.bonds) if (ni is not None and ci is not None) else False
    rep['peptide_nres']=nres; rep['head_to_tail_bond_present']=has_cyc; rep['peptide_natoms']=len(p.atoms)
except Exception as e:
    rep['parmed_error']=str(e)[:200]
json.dump(rep, open('/opt/smoke/status/build_smoke.json','w'), indent=2)
print(json.dumps(rep, indent=2))
PY
cp pep_cyclic.pdb /opt/smoke/status/ 2>/dev/null || true
cp tleap_pep.log tleap_comp.log /opt/smoke/status/ 2>/dev/null || true
stage smoke_complete
