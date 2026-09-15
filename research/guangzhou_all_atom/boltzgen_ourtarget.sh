#!/bin/bash
# BoltzGen on OUR cyclic test targets (backbone pivot, step 1 of the post-qualification plan).
# For each real receptor target from our PepBDB cyclic test set: download the RCSB structure,
# compute the binding pocket (receptor residues contacting the native peptide), write a BoltzGen
# peptide-anything spec (HEAD-TO-TAIL cyclic binder, matched length), and design + score.
# NOTE (honest): our PepBDB "cyclic" peptides are mostly DISULFIDE-cyclized; a cyclic:true redesign
# is a DE-NOVO head-to-tail cyclic binder to the same pocket, not a native reconstruction. That is
# exactly the cyclic-peptide-drug design task, and it enables a fair head-to-head vs the PepGLAD
# cyclic model on identical targets/pockets.
set -Eeuo pipefail
export AWS_DEFAULT_REGION=us-west-2 DEBIAN_FRONTEND=noninteractive PYTHONUNBUFFERED=1
ROOT=/opt/boltzgen-run
OUT_S3=${OUT_S3:?}
NUM_DESIGNS=${NUM_DESIGNS:-8}
BUDGET=${BUDGET:-2}
mkdir -p "$ROOT/status" "$ROOT/specs" "$ROOT/cifs"
exec > >(tee -a "$ROOT/status/boltzgen_targets.log") 2>&1
stage(){ printf '{"stage":"%s","time":"%s"}\n' "$1" "$(date -u +%FT%TZ)" > "$ROOT/status/status.json"; aws s3 sync "$ROOT/status" "$OUT_S3/status/" --only-show-errors || true; }
trap 'rc=$?; [ $rc -ne 0 ] && stage failed; aws s3 sync "$ROOT/status" "$OUT_S3/status/" --only-show-errors || true; shutdown -h now; exit $rc' EXIT
systemd-run --unit=bg-deadline --on-active=5h /sbin/shutdown -h now || true

# target: "pdbid receptor_chain peptide_chain native_pep_len"  (real receptor pockets, not insulin homodimers)
TARGETS=(
  "1g9i E I 22"   # bovine trypsin (serine protease) — classic druggable active site
  "1yf4 A B 9"    # kallikrein/chymotrypsin-like serine protease
  "1csb B A 47"   # cathepsin B (cysteine protease)
  "1kat W X 19"   # cytokine/growth-factor-like receptor chain
  "1kc4 A B 19"   # toxin-scaffold receptor
  "1u8p B C 7"    # antibody Fab (paratope target)
)

stage installing
command -v aws >/dev/null 2>&1 || { apt-get update -qq && apt-get install -y -qq unzip curl git && curl -fsSL https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o /tmp/a.zip && (cd /tmp && unzip -q -o a.zip && ./aws/install --update); }
apt-get -o DPkg::Lock::Timeout=300 install -y -qq git curl
curl -fsSL https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -o /tmp/mc.sh
bash /tmp/mc.sh -b -p /opt/miniconda
source /opt/miniconda/etc/profile.d/conda.sh
conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main || true
conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r || true
conda create -y -n bg -c conda-forge python=3.12
conda activate bg
pip install -q boltzgen gemmi numpy
git clone https://github.com/HannesStark/boltzgen "$ROOT/boltzgen" || true
export HF_HOME="$ROOT/hf_cache"
python -c "import boltzgen, torch, gemmi; print('boltzgen import ok; cuda', torch.cuda.is_available())"
cd "$ROOT/boltzgen"

# --- spec builder: RCSB structure -> pocket (receptor residues within 5A of native peptide) -> yaml ---
build_spec(){
  local pdb="$1" recep="$2" pep="$3" L="$4"
  local cif="$ROOT/cifs/${pdb}.cif" spec="$ROOT/specs/${pdb}.yaml"
  curl -fsSL "https://files.rcsb.org/download/${pdb^^}.cif" -o "$cif" || { echo "download failed $pdb"; return 1; }
  PDB="$pdb" CIF="$cif" RECEP="$recep" PEP="$pep" NLEN="$L" SPEC="$spec" python - <<'PY'
import os, gemmi, numpy as np
cif=os.environ['CIF']; recep=os.environ['RECEP']; pep=os.environ['PEP']; L=int(os.environ['NLEN']); spec=os.environ['SPEC']
st=gemmi.read_structure(cif); st.setup_entities(); model=st[0]
def is_aa(res):
    info=gemmi.find_tabulated_residue(res.name)
    return bool(info) and info.is_amino_acid()
def get_chain(name):
    for ch in model:
        if ch.name==name: return ch
    return None
rc=get_chain(recep); pc=get_chain(pep)
# fallback: two longest polymer chains if named chains missing
if rc is None or pc is None:
    polys=sorted(model, key=lambda c: sum(is_aa(r) for r in c), reverse=True)
    rc = rc or polys[0]; pc = pc or (polys[1] if len(polys)>1 else polys[0])
# receptor & peptide amino-acid residues, in file order
rres=[r for r in rc if is_aa(r)]
pres=[r for r in pc if is_aa(r)]
def hcoords(res):
    return np.array([[a.pos.x,a.pos.y,a.pos.z] for a in res if a.element.name!='H'], dtype=float)
P=np.vstack([hcoords(r) for r in pres]) if pres else np.zeros((0,3))
assert len(rres) and len(P), "empty chain coords"
# BoltzGen indexes binding residues by 1-based SEQUENTIAL position within the parsed chain (bounded
# by chain length), NOT by PDB author number. So we write a CLEAN single-chain receptor CIF
# (standard AAs only, chain 'A', renumbered 1..N contiguous) and emit binding as sequential
# positions in that same ordered list — removing all auth/label ambiguity and chain-id mismatches.
new=gemmi.Structure(); nm=gemmi.Model('1'); ch=gemmi.Chain('A')
pocket=[]
for i,res in enumerate(rres):
    c=hcoords(res)
    if len(c) and np.sqrt(((c[:,None,:]-P[None,:,:])**2).sum(-1)).min() < 5.0:
        pocket.append(i+1)              # 1-based sequential index
    res.seqid=gemmi.SeqId(i+1,' ')      # renumber contiguously
    ch.add_residue(res)
assert pocket, "empty pocket"
nm.add_chain(ch); new.add_model(nm); new.setup_entities()
recep_cif=cif.replace('.cif','_recep.cif')
new.make_mmcif_document().write_file(recep_cif)
lo=max(7, L-2); hi=min(18, L+2); hi=max(hi, lo+1)
binding=",".join(str(x) for x in pocket)
yaml=f"""entities:
  - protein:
      id: X
      sequence: {lo}..{hi}
      cyclic: true
  - file:
      path: {recep_cif}
      include:
        - chain:
            id: A
      binding_types:
        - chain:
            id: A
            binding: {binding}
"""
open(spec,'w').write(yaml)
print(f"{os.environ['PDB']}: recep_chain={rc.name}->A ({len(rres)} res) pep_chain={pc.name} pocket_seq_positions={len(pocket)} max_idx={max(pocket)} design_len={lo}..{hi}")
PY
}

declare -A RESULT
for t in "${TARGETS[@]}"; do
  set -- $t; pdb="$1"; recep="$2"; pep="$3"; L="$4"
  stage "prep_${pdb}"
  if ! build_spec "$pdb" "$recep" "$pep" "$L"; then RESULT[$pdb]="spec_failed"; continue; fi
  boltzgen check "$ROOT/specs/${pdb}.yaml" 2>&1 | tail -5 || { RESULT[$pdb]="check_failed"; continue; }
  stage "design_${pdb}"
  if boltzgen run "$ROOT/specs/${pdb}.yaml" --protocol peptide-anything \
       --num_designs "$NUM_DESIGNS" --budget "$BUDGET" \
       --output "$ROOT/out/${pdb}" --cache "$ROOT/hf_cache" 2>&1 | tail -25; then
    RESULT[$pdb]="ok"
  else
    RESULT[$pdb]="run_failed"
  fi
  # collect this target's ranked metrics (aggregate step reads from out/ directly; sync CSVs to S3)
  aws s3 sync "$ROOT/out/${pdb}" "$OUT_S3/boltzgen_targets/${pdb}/" --only-show-errors \
    --exclude "*" --include "*.csv" --include "*.json" --include "*rank01*.cif" --include "*rank01*.pdb" || true
  stage "done_${pdb}"
done

stage aggregating
python - <<'PY'
import glob, os, json, csv
root='/opt/boltzgen-run/out'
summary={}
for csvf in glob.glob(root+'/**/*metrics*.csv', recursive=True):
    tgt=csvf.split('/out/')[1].split('/')[0]
    try:
        rows=list(csv.DictReader(open(csvf)))
        if not rows: continue
        # rank-1 row (first) — surface the headline metrics BoltzGen reports
        r0=rows[0]
        keys=[k for k in r0 if any(s in k.lower() for s in ('iptm','ptm','rmsd','quality','filter','sequence','pae','plddt'))]
        summary.setdefault(tgt,{})[os.path.basename(csvf)]={'n_designs':len(rows),'sample_design':{k:r0[k] for k in keys}}
    except Exception as e:
        summary.setdefault(tgt,{})['error']=str(e)[:200]
json.dump(summary, open('/opt/boltzgen-run/status/boltzgen_targets_summary.json','w'), indent=2)
print(json.dumps(summary, indent=2)[:4000])
PY
cp /opt/boltzgen-run/status/boltzgen_targets_summary.json "$ROOT/status/" 2>/dev/null || true
stage boltzgen_targets_complete
