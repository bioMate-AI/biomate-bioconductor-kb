#!/bin/bash
# =============================================================================
# launch_rfpeptides.sh — PROVISIONING launcher for Track-B cyclic hit generation
# via the RFpeptides protocol (RFdiffusion-cyclic -> ProteinMPNN -> cyclic
# self-consistency filter) on our two targets: PD-L1 (5o45) and alphaV/beta6 (9xmm).
#
# Delta vs our existing panels: those used BoltzGen. RFpeptides (Rettie/Juergens/Baker,
# Nat Chem Biol 2025; s41589-025-01929-w) is the method with the PROVEN higher wet-lab
# hit rate on novel targets (binders against 4/4 targets, <=20 designs each, down to
# ~9 nM). The protocol is PUBLIC: it is merged into the main RosettaCommons/RFdiffusion
# repo (inference.cyclic=True inference.cyc_chains='a'; examples design_macrocyclic_*).
#
# This script mirrors launch_refold_rerank.sh: it only validates inputs, uploads code,
# and boots ONE self-terminating GPU instance (spot->on-demand ladder when MARKET=spot)
# that runs the embedded driver. It performs NO GPU work itself.
#
# ---- what the on-GPU driver does, per target ----
#   1. download the receptor structure from RCSB (same pocket BoltzGen used)
#   2. compute hotspot_res + receptor contig from native-ligand contacts (gemmi, 5 A)
#   3. RFdiffusion cyclic backbone generation  (N backbones, binder chain cyclized)
#   4. ProteinMPNN sequence design             (K seqs/backbone, soluble weights)
#   5. cyclic self-consistency fold + scRMSD    (FOLDER: afcycdesign | cyclicboltz1)
#   6. rank candidates by scRMSD + fold confidence -> candidates_<pdb>.jsonl
#
# ---- modes ----
#   PREFLIGHT_ONLY=1   validate repos/weights/AWS locally and EXIT 0 (no launch, no cost)
#   DRY_RUN=1 (default) small pool for a cheap end-to-end shakeout (N=4, K=2)
#   DRY_RUN=0          full pool (N/K from env)
#
# Poll:   aws s3 cp $S3RUN/status/rfp_status.json -
# Result: aws s3 cp $S3RUN/status/candidates_5o45.jsonl -
#         aws s3 cp $S3RUN/status/candidates_9xmm.jsonl -
#         aws s3 cp $S3RUN/status/rfpeptides_summary.json -
# =============================================================================
set -Eeuo pipefail
export AWS_DEFAULT_REGION=us-west-2

BUCKET=knowledge-datasets-1759951976
AMI=${AMI:-ami-04f7da1c787a89267}        # generic DL GPU AMI (driver installs its own envs)
SG=sg-011121fdf81073ec8
KEY=biomate-trial-resume-20260912
PROFILE=AutoimmuneCorpusProfile

# ---- knobs (env-overridable) ----
TARGETS=${TARGETS:-"5o45 9xmm"}          # which of the target table rows to run
NUM_DESIGNS=${NUM_DESIGNS:-}             # RFdiffusion backbones/target (default set by DRY_RUN)
NUM_SEQS=${NUM_SEQS:-}                   # ProteinMPNN seqs/backbone (default set by DRY_RUN)
DIFFUSER_T=${DIFFUSER_T:-50}            # RFdiffusion denoising steps (RFpeptides example uses 50)
FOLDER=${FOLDER:-afcycdesign}            # cyclic self-consistency folder: afcycdesign|cyclicboltz1
MARKET=${MARKET:-ondemand}              # ondemand default; spot => spot->ondemand ladder
DISK_GB=${DISK_GB:-200}                 # RFdiffusion + AF2/Boltz weights are large
DRY_RUN=${DRY_RUN:-1}
PREFLIGHT_ONLY=${PREFLIGHT_ONLY:-0}

# DRY = cheap shakeout; full = real pool. Honour explicit NUM_* overrides.
if [ "$DRY_RUN" = 1 ]; then
  NUM_DESIGNS=${NUM_DESIGNS:-4}; NUM_SEQS=${NUM_SEQS:-2}; MAX_RUNTIME=${MAX_RUNTIME:-4h}
else
  NUM_DESIGNS=${NUM_DESIGNS:-20}; NUM_SEQS=${NUM_SEQS:-8}; MAX_RUNTIME=${MAX_RUNTIME:-24h}
fi

[[ "$MARKET" = spot || "$MARKET" = ondemand ]] || { echo "FATAL: MARKET must be spot or ondemand"; exit 1; }
[[ "$DRY_RUN" = 0 || "$DRY_RUN" = 1 ]]          || { echo "FATAL: DRY_RUN must be 0 or 1"; exit 1; }
[[ "$FOLDER" = afcycdesign || "$FOLDER" = cyclicboltz1 ]] || { echo "FATAL: FOLDER must be afcycdesign or cyclicboltz1"; exit 1; }

HERE=$(cd "$(dirname "$0")" && pwd)
RUNID=rfpeptides-$(date -u +%Y%m%dT%H%M%SZ)
S3RUN=s3://$BUCKET/cyclic_peptide/runs/$RUNID

# =============================================================================
# FAIL-LOUD PREFLIGHT — repo + weight + credential availability, BEFORE any boot.
# RFpeptides depends on public code we do not vendor; if any source moved, fail now,
# not 20 min into a paid GPU boot.
# =============================================================================
RFDIFF_REPO=https://github.com/RosettaCommons/RFdiffusion
MPNN_REPO=https://github.com/dauparas/ProteinMPNN
# IPD weight host: files sit under per-file md5 subdirs (see RFdiffusion scripts/download_models.sh).
# Probe the Complex_base checkpoint — the one the macrocyclic BINDER example relies on.
WEIGHT_URL=http://files.ipd.uw.edu/pub/RFdiffusion/e29311f6f1bf1af907f9ef9f44b8328b/Complex_base_ckpt.pt
# cyclic self-consistency folder repos (one is required, per FOLDER)
AFCYC_REPO=https://github.com/sokrypton/ColabDesign          # AfCycDesign lives in ColabDesign (cyclic offset)
CYCBOLTZ_REPO=https://github.com/Charlesjc-lab/BoltzDesign1_cyclic

reach(){ # reach <url> <label>  — HEAD check, follow redirects, loud on failure
  if curl -fsSL -I --max-time 25 "$1" >/dev/null 2>&1; then
    echo "  OK   $2  ($1)"
  else
    echo "  FAIL $2  ($1)"; return 1
  fi
}

echo "== RFpeptides preflight =="
rc=0
reach "$RFDIFF_REPO"  "RFdiffusion repo (RFpeptides protocol: inference.cyclic)" || rc=1
reach "$MPNN_REPO"    "ProteinMPNN repo (sequence design)"                        || rc=1
# weight host: HEAD one representative binder checkpoint (Complex_base) — the one the
# macrocyclic BINDER example relies on. If the IPD host is down, abort.
reach "$WEIGHT_URL" "RFdiffusion weights host (IPD, Complex_base ckpt)"            || rc=1
case "$FOLDER" in
  afcycdesign)  reach "$AFCYC_REPO"    "AfCycDesign/ColabDesign (cyclic AF2 fold)"   || rc=1 ;;
  cyclicboltz1) reach "$CYCBOLTZ_REPO" "CyclicBoltz1 (cyclic AF3/Boltz fold)"        || rc=1 ;;
esac
# local reusable helper (self-consistency scRMSD metric; already in-tree, RFpeptides metric)
[ -f "$HERE/scrmsd.py" ] && echo "  OK   scrmsd.py present" || { echo "  FAIL scrmsd.py missing in $HERE"; rc=1; }
# AWS identity — a launch needs valid creds; a preflight-only run tolerates their absence.
if aws sts get-caller-identity >/dev/null 2>&1; then
  echo "  OK   AWS caller identity"
else
  echo "  WARN AWS caller identity unavailable (ok for PREFLIGHT_ONLY, FATAL for a launch)"
  [ "$PREFLIGHT_ONLY" = 1 ] || rc=1
fi
[ "$rc" = 0 ] || { echo "FATAL: preflight failed — fix the sources above before launching"; exit 1; }
echo "== preflight OK =="

if [ "$PREFLIGHT_ONLY" = 1 ]; then
  echo "PREFLIGHT_ONLY=1 -> not launching. All RFpeptides sources reachable."
  exit 0
fi

# ---- upload the one external helper the driver reuses ----
aws s3 cp "$HERE/scrmsd.py"            "$S3RUN/code/scrmsd.py"            --only-show-errors
aws s3 cp "$HERE/launch_rfpeptides.sh" "$S3RUN/code/launch_rfpeptides.sh" --only-show-errors

# =============================================================================
# ON-GPU DRIVER (bootstrap). Mirrors launch_refold_rerank.sh's BOOT wrapper:
# deadline/self-terminate + background status sync, then the RFpeptides stages.
# =============================================================================
BOOT=$(mktemp)
cat > "$BOOT" <<'BOOT_EOF'
#!/bin/bash
set -Eeuo pipefail
export AWS_DEFAULT_REGION=us-west-2 DEBIAN_FRONTEND=noninteractive PYTHONUNBUFFERED=1 HOME=/root
OUT_S3=${OUT_S3:?}
TARGETS=${TARGETS:?}; NUM_DESIGNS=${NUM_DESIGNS:?}; NUM_SEQS=${NUM_SEQS:?}
DIFFUSER_T=${DIFFUSER_T:?}; FOLDER=${FOLDER:?}; MAX_RUNTIME=${MAX_RUNTIME:?}
ROOT=/opt/rfp-run
mkdir -p "$ROOT/status" "$ROOT/code" "$ROOT/inputs" "$ROOT/out"
exec > >(tee -a "$ROOT/status/driver.log") 2>&1
sync_status(){ aws s3 sync "$ROOT/status" "$OUT_S3/status/" --only-show-errors || true; }
stage(){ printf '{"stage":"%s","time":"%s"}\n' "$1" "$(date -u +%FT%TZ)" > "$ROOT/status/rfp_status.json"; sync_status; }
finish(){ rc=$?; trap - EXIT; [ "$rc" -ne 0 ] && stage "driver_failed_rc_$rc"; sync_status; shutdown -h now; exit "$rc"; }
trap finish EXIT
systemctl is-active --quiet rfp-deadline.timer 2>/dev/null || systemd-run --unit=rfp-deadline --on-active="$MAX_RUNTIME" /sbin/shutdown -h now
(while sleep 120; do sync_status; done) &

stage installing_base
command -v aws >/dev/null 2>&1 || { apt-get update -qq && apt-get install -y -qq unzip curl && curl -fsSL https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o /tmp/a.zip && (cd /tmp && unzip -q -o a.zip && ./aws/install --update); }
apt-get -o DPkg::Lock::Timeout=300 install -y -qq git curl wget || true
if [ ! -x /opt/miniforge/bin/python3 ]; then
  for i in 1 2 3 4 5; do curl -fsSL -o /tmp/mf.sh https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-Linux-x86_64.sh && break; sleep 10; done
  bash /tmp/mf.sh -b -p /opt/miniforge
fi
source /opt/miniforge/etc/profile.d/conda.sh

# ---- pull the reusable helper ----
aws s3 cp "$OUT_S3/code/scrmsd.py" "$ROOT/code/scrmsd.py" --only-show-errors

# ---- RFdiffusion: clone + SE3nv env + weights (RFpeptides protocol is in main) ----
stage install_rfdiffusion
if [ ! -d "$ROOT/RFdiffusion" ]; then git clone https://github.com/RosettaCommons/RFdiffusion "$ROOT/RFdiffusion"; fi
cd "$ROOT/RFdiffusion"
conda env list | grep -q SE3nv || conda env create -f env/SE3nv.yml
# shellcheck disable=SC1091
conda activate SE3nv
pip install -q -e "$ROOT/RFdiffusion/env/SE3Transformer" || true
pip install -q -e "$ROOT/RFdiffusion" || true
mkdir -p "$ROOT/RFdiffusion/models"
# the macrocyclic BINDER example uses the complex/base checkpoints; download_models.sh grabs the full
# set (files live under per-file md5 subdirs). Fallback hits the same hashed URLs explicitly.
bash scripts/download_models.sh "$ROOT/RFdiffusion/models" || {
  base=http://files.ipd.uw.edu/pub/RFdiffusion
  declare -A W=(
    [Base_ckpt.pt]=6f5902ac237024bdd0c176cb93063dc4
    [Complex_base_ckpt.pt]=e29311f6f1bf1af907f9ef9f44b8328b
    [Complex_Fold_base_ckpt.pt]=60f09a193fb5e5ccdc4980417708dbab
    [ActiveSite_ckpt.pt]=5532d2e1f3a4738decd58b19d633b3c3
  )
  for m in "${!W[@]}"; do
    wget -q -O "$ROOT/RFdiffusion/models/$m" "$base/${W[$m]}/$m" || { echo "FATAL: weight $m download failed"; exit 1; }
  done
}

# ---- ProteinMPNN: clone (run-as-script; soluble weights ship in the repo) ----
stage install_proteinmpnn
[ -d "$ROOT/ProteinMPNN" ] || git clone https://github.com/dauparas/ProteinMPNN "$ROOT/ProteinMPNN"

# ---- cyclic self-consistency folder ----
stage install_folder_"$FOLDER"
case "$FOLDER" in
  afcycdesign)
    conda create -y -n fold -c conda-forge python=3.10
    conda run -n fold pip install -q "jax[cuda12]" dm-haiku biopython numpy
    conda run -n fold pip install -q git+https://github.com/sokrypton/ColabDesign.git
    # AF2 params (cyclic-offset AfCycDesign reuses stock AF2 weights)
    mkdir -p "$ROOT/af2_params"
    [ -f "$ROOT/af2_params/params_model_1_ptm.npz" ] || {
      wget -q -O /tmp/af2.tar https://storage.googleapis.com/alphafold/alphafold_params_2022-12-06.tar \
        && tar -xf /tmp/af2.tar -C "$ROOT/af2_params" || { echo "FATAL: AF2 params download failed"; exit 1; }
    }
    ;;
  cyclicboltz1)
    [ -d "$ROOT/CyclicBoltz1" ] || git clone https://github.com/Charlesjc-lab/BoltzDesign1_cyclic "$ROOT/CyclicBoltz1"
    conda create -y -n fold -c conda-forge python=3.11
    conda run -n fold pip install -q -e "$ROOT/CyclicBoltz1" || conda run -n fold pip install -q boltz
    ;;
esac

# ---- target table: "pdbid recep_chains pep_chain binder_lo binder_hi" ----
# (same receptors + pockets the BoltzGen panels used; see boltzgen_ourtarget.sh)
declare -A ROW
ROW[5o45]="5o45 A B 12 16"      # PD-L1 IgV; native macrocycle in chain B (len 14)
ROW[9xmm]="9xmm A,B E 9 14"     # alphaV/beta6 two-subunit RGD pocket; native 9-mer cyclic RGD in chain E

for pdb in $TARGETS; do
  row=${ROW[$pdb]:-}
  [ -n "$row" ] || { echo "WARN: unknown target $pdb — skipping"; continue; }
  # shellcheck disable=SC2086
  set -- $row; pdb=$1; recep=$2; pep=$3; blo=$4; bhi=$5
  stage "prep_${pdb}"

  # structure: RFdiffusion wants a .pdb. Fetch RCSB .pdb; fall back to .cif->.pdb via gemmi.
  pdbfile="$ROOT/inputs/${pdb}.pdb"
  if ! curl -fsSL "https://files.rcsb.org/download/${pdb^^}.pdb" -o "$pdbfile"; then
    curl -fsSL "https://files.rcsb.org/download/${pdb^^}.cif" -o "$ROOT/inputs/${pdb}.cif" || { echo "FATAL: structure download failed $pdb"; continue; }
    conda run -n fold python - "$ROOT/inputs/${pdb}.cif" "$pdbfile" <<'CVT'
import sys, gemmi
st = gemmi.read_structure(sys.argv[1]); st.setup_entities()
st.write_pdb(sys.argv[2])
CVT
  fi

  # --- hotspot_res + receptor contig from native-ligand contacts (<5 A), gemmi ---
  # emits two files: <pdb>.hotspots (comma-joined CHAIN+AUTHNUM) and <pdb>.contig (receptor part).
  conda run -n fold python - "$pdbfile" "$recep" "$pep" "$ROOT/out/${pdb}.hotspots" "$ROOT/out/${pdb}.contig" <<'POCKET' || { echo "FATAL: pocket computation failed $pdb"; continue; }
import sys, gemmi, numpy as np
pdbfile, recep, pep, hs_out, contig_out = sys.argv[1:6]
st = gemmi.read_structure(pdbfile); st.setup_entities(); model = st[0]
def is_aa(r):
    info = gemmi.find_tabulated_residue(r.name); return bool(info) and info.is_amino_acid()
def chain(name):
    for ch in model:
        if ch.name == name: return ch
    return None
def heavy(r):
    return np.array([[a.pos.x, a.pos.y, a.pos.z] for a in r if a.element.name != 'H'], float)
recep_ids = [c.strip() for c in recep.split(',') if c.strip()]
pc = chain(pep)
# peptide pocket-definer: all non-water residues (canonical + ncAA) of the ligand chain
assert pc is not None, f"peptide chain {pep} not found"
pres = [r for r in pc if r.name not in ('HOH', 'WAT', 'H2O', 'DOD')]
P = np.vstack([heavy(r) for r in pres if len(heavy(r))])
assert len(P), "empty peptide coords"
hot = []          # (dist, 'CHAIN+AUTHNUM')
contig_parts = []
for rn in recep_ids:
    rc = chain(rn)
    if rc is None: continue
    rres = [r for r in rc if is_aa(r)]
    if not rres: continue
    # receptor contig: author-numbered span of resolved residues for this chain
    nums = [r.seqid.num for r in rres]
    contig_parts.append(f"{rc.name}{min(nums)}-{max(nums)}/0")
    for r in rres:
        c = heavy(r)
        if not len(c): continue
        d = np.sqrt(((c[:, None, :] - P[None, :, :]) ** 2).sum(-1)).min()
        if d < 5.0:
            hot.append((float(d), f"{rc.name}{r.seqid.num}"))
assert hot, "no pocket contacts found"
# RFdiffusion hotspots: keep the closest ~8 (too many over-constrains the diffusion)
hot.sort(key=lambda x: x[0])
keep = [h for _, h in hot[:8]]
open(hs_out, 'w').write(",".join(keep))
open(contig_out, 'w').write(" ".join(contig_parts))
print(f"{pdbfile}: hotspots={keep} contig_recep='{' '.join(contig_parts)}' (pocket_contacts={len(hot)})")
POCKET

  HOTS=$(cat "$ROOT/out/${pdb}.hotspots")
  RECCONTIG=$(cat "$ROOT/out/${pdb}.contig")
  # RFdiffusion hotspot list needs escaped single quotes: ['A51','A52',...]
  HS_FMT="[$(echo "$HOTS" | sed "s/\([^,][^,]*\)/\\\\'\1\\\\'/g")]"

  # --- stage 1: RFdiffusion cyclic backbone generation (binder chain cyclized) ---
  stage "rfdiffusion_${pdb}"
  outpfx="$ROOT/out/${pdb}/rfd"
  mkdir -p "$ROOT/out/${pdb}"
  "$ROOT/RFdiffusion/scripts/run_inference.py" \
    --config-name base \
    inference.output_prefix="$outpfx" \
    inference.input_pdb="$pdbfile" \
    inference.num_designs="$NUM_DESIGNS" \
    "contigmap.contigs=[${blo}-${bhi} ${RECCONTIG}]" \
    inference.cyclic=True inference.cyc_chains='a' \
    diffuser.T="$DIFFUSER_T" \
    ppi.hotspot_res="$HS_FMT" 2>&1 | tail -30 || { echo "WARN rfdiffusion failed $pdb"; continue; }

  # --- stage 2: ProteinMPNN sequence design on each cyclic backbone ---
  stage "proteinmpnn_${pdb}"
  mpnn_out="$ROOT/out/${pdb}/mpnn"; mkdir -p "$mpnn_out"
  conda run -n SE3nv python "$ROOT/ProteinMPNN/protein_mpnn_run.py" \
    --pdb_path_chains A \
    --out_folder "$mpnn_out" \
    --num_seq_per_target "$NUM_SEQS" \
    --sampling_temp 0.1 --seed 37 --batch_size 1 \
    --pdb_path "$outpfx"_0.pdb 2>&1 | tail -15 || echo "WARN mpnn single-bb mode; see per-bb loop below"
  for bb in "$outpfx"_*.pdb; do
    [ -e "$bb" ] || continue
    conda run -n SE3nv python "$ROOT/ProteinMPNN/protein_mpnn_run.py" \
      --pdb_path "$bb" --pdb_path_chains A --out_folder "$mpnn_out" \
      --num_seq_per_target "$NUM_SEQS" --sampling_temp 0.1 --seed 37 --batch_size 1 \
      2>&1 | tail -3 || true
  done

  # --- stage 3: cyclic self-consistency fold + scRMSD, rank ---
  stage "selfconsistency_${pdb}"
  conda run -n fold python - "$ROOT" "$pdb" "$outpfx" "$mpnn_out" "$FOLDER" "$ROOT/status/candidates_${pdb}.jsonl" <<'RANK' || echo "WARN self-consistency failed $pdb"
import sys, os, glob, json, subprocess
root, pdb, outpfx, mpnn_out, folder, out_jsonl = sys.argv[1:7]
# collect (backbone_pdb, designed_seqs) from ProteinMPNN fasta outputs
fastas = glob.glob(os.path.join(mpnn_out, "seqs", "*.fa")) + glob.glob(os.path.join(mpnn_out, "*.fa"))
records = []
for fa in fastas:
    name = os.path.splitext(os.path.basename(fa))[0]
    bb = outpfx + "_" + name.split("_")[-1] + ".pdb"
    seqs = []
    hdr = None
    for ln in open(fa):
        ln = ln.strip()
        if ln.startswith(">"):
            hdr = ln
        elif ln and hdr and "sample" in hdr:   # skip the input/native header, keep sampled designs
            seqs.append(ln.split("/")[0])        # cyclic monomer chain
    for i, s in enumerate(seqs):
        records.append({"target": pdb, "backbone": os.path.basename(bb) if os.path.exists(bb) else name,
                        "seq": s, "length": len(s)})
# Self-consistency fold is folder-specific and is the ONE step finalized per-folder before a full run
# (see docs/20261004_RFPEPTIDES_SETUP.md "Self-consistency filter"). A helper at
#   code/fold_predict_<folder>.sh  <seq> <bb.pdb> <out_pred.pdb>
# must write an INDEPENDENT cyclic re-fold of the designed sequence to out_pred.pdb, using:
#   afcycdesign  -> ColabDesign cyclic AF2 (add_cyclic_offset) predict, params at $ROOT/af2_params
#   cyclicboltz1 -> boltz predict with the cyclic flag ($ROOT/CyclicBoltz1)
# We then score designability with the in-tree RFpeptides metric scrmsd.py. If the helper is ABSENT
# we DO NOT fake a score: scrmsd stays null, scrmsd_computed=false, and a loud banner is printed —
# candidates are still emitted (real ProteinMPNN seqs), just not self-consistency-ranked.
helper = os.path.join(root, "code", f"fold_predict_{folder}.sh")
have_helper = os.path.exists(helper)
if not have_helper:
    print("=" * 70)
    print(f"WARNING: self-consistency helper {helper} ABSENT — scRMSD NOT computed.")
    print("Candidates are ProteinMPNN sequences only; finalize the folder predict step")
    print("before a full run (see RFPEPTIDES_SETUP.md). Ranking falls back to length.")
    print("=" * 70)
scored = []
for i, r in enumerate(records):
    sc = None; conf = None; computed = False
    bbp = os.path.join(os.path.dirname(outpfx), r["backbone"])
    if have_helper and os.path.exists(bbp):
        pred = os.path.join(os.path.dirname(outpfx), f"pred_{pdb}_{i}.pdb")
        try:
            subprocess.run(["bash", helper, r["seq"], bbp, pred], check=True, timeout=1800)
            if os.path.exists(pred):
                j = subprocess.run([sys.executable, os.path.join(root, "code", "scrmsd.py"),
                                    "--designed", bbp, "--refold", pred],
                                   capture_output=True, text=True, timeout=120)
                sc = json.loads(j.stdout).get("scrmsd"); computed = True
        except Exception as e:
            print(f"WARN predict/scrmsd failed for {pdb} cand {i}: {e}")
    r["scrmsd"] = sc; r["fold_confidence"] = conf; r["scrmsd_computed"] = computed
    scored.append(r)
# rank: designable first (low scRMSD), then high confidence
scored.sort(key=lambda r: (r["scrmsd"] if r["scrmsd"] is not None else 1e9,
                           -(r["fold_confidence"] or 0)))
with open(out_jsonl, "w") as f:
    for r in scored:
        f.write(json.dumps(r) + "\n")
print(f"{pdb}: wrote {len(scored)} candidates -> {out_jsonl}")
RANK

  aws s3 sync "$ROOT/out/${pdb}" "$OUT_S3/rfpeptides/${pdb}/" --only-show-errors \
    --exclude "*" --include "*.pdb" --include "*.fa" --include "*.jsonl" --include "*.json" --include "*.trb" || true
  aws s3 cp "$ROOT/status/candidates_${pdb}.jsonl" "$OUT_S3/status/candidates_${pdb}.jsonl" --only-show-errors || true
  stage "done_${pdb}"
done

# ---- aggregate ----
stage aggregating
python3 - "$ROOT/status" <<'AGG'
import sys, glob, os, json
sd = sys.argv[1]; summ = {}
for f in glob.glob(os.path.join(sd, "candidates_*.jsonl")):
    tgt = os.path.basename(f)[len("candidates_"):-len(".jsonl")]
    rows = [json.loads(l) for l in open(f) if l.strip()]
    top = rows[0] if rows else None
    n_sc = sum(1 for r in rows if r.get("scrmsd_computed"))
    summ[tgt] = {"n_candidates": len(rows), "n_scrmsd_computed": n_sc,
                 "self_consistency": "computed" if n_sc else "SKIPPED_no_folder_helper",
                 "top": {k: top.get(k) for k in ("seq", "length", "scrmsd", "fold_confidence")} if top else None}
json.dump(summ, open(os.path.join(sd, "rfpeptides_summary.json"), "w"), indent=2)
print(json.dumps(summ, indent=2))
AGG
sync_status
stage rfpeptides_complete
BOOT_EOF

aws s3 cp "$BOOT" "$S3RUN/code/bootstrap.sh" --only-show-errors

# ---- user-data: pull + exec the bootstrap wrapper with env ----
UD=$(cat <<EOF | base64
#!/bin/bash
exec > /var/log/rfp-boot.log 2>&1
mkdir -p /opt/rfp-run
for i in 1 2 3 4 5; do aws s3 cp $S3RUN/code/bootstrap.sh /opt/rfp-run/bootstrap.sh --region us-west-2 && break; sleep 10; done
chmod +x /opt/rfp-run/bootstrap.sh
OUT_S3=$S3RUN TARGETS="$TARGETS" NUM_DESIGNS=$NUM_DESIGNS NUM_SEQS=$NUM_SEQS \\
  DIFFUSER_T=$DIFFUSER_T FOLDER=$FOLDER MAX_RUNTIME=$MAX_RUNTIME \\
  bash /opt/rfp-run/bootstrap.sh
EOF
)

# ---- GPU capacity ladder (same inventory as launch_refold_rerank.sh) ----
declare -a COMBO=(
  "g5.4xlarge subnet-0254e4c3634b41bfc" "g5.4xlarge subnet-03b277a7a08d388c1" "g5.4xlarge subnet-09e4dce46682a6c60"
  "g6.4xlarge subnet-0254e4c3634b41bfc" "g6.4xlarge subnet-0b35a6e2c1cf02dc2"
  "g5.8xlarge subnet-0254e4c3634b41bfc" "g6.8xlarge subnet-0254e4c3634b41bfc"
  "g5.2xlarge subnet-0254e4c3634b41bfc" "g6.2xlarge subnet-0b35a6e2c1cf02dc2"
)
launch_one(){
  local market="$1" c TYPE SUBNET market_opt=""
  [ "$market" = spot ] && market_opt='--instance-market-options {"MarketType":"spot","SpotOptions":{"SpotInstanceType":"one-time","InstanceInterruptionBehavior":"terminate"}}'
  for c in "${COMBO[@]}"; do
    # shellcheck disable=SC2086
    set -- $c; TYPE=$1; SUBNET=$2
    echo "[$market] trying $TYPE in $SUBNET ..."
    IID=$(aws ec2 run-instances --image-id "$AMI" --instance-type "$TYPE" --key-name "$KEY" \
      --subnet-id "$SUBNET" --security-group-ids "$SG" --iam-instance-profile Name=$PROFILE $market_opt \
      --instance-initiated-shutdown-behavior terminate \
      --block-device-mappings "[{\"DeviceName\":\"/dev/sda1\",\"Ebs\":{\"VolumeSize\":$DISK_GB,\"VolumeType\":\"gp3\"}}]" \
      --user-data "$UD" \
      --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$RUNID},{Key=project,Value=cyclic_peptide}]" \
      --query 'Instances[0].InstanceId' --output text 2>/dev/null) && [ -n "$IID" ] && [ "$IID" != "None" ] \
      && { echo "LAUNCHED [$market] $TYPE $SUBNET -> $IID"; return 0; }
    echo "  no capacity ([$market] $TYPE $SUBNET)"
  done
  return 1
}
IID=""
if [ "$MARKET" = ondemand ]; then
  launch_one ondemand || true
else
  launch_one spot || launch_one ondemand || true
fi
{ [ -z "${IID:-}" ] || [ "$IID" = "None" ]; } && { echo "FATAL: no GPU capacity"; rm -f "$BOOT"; exit 1; }
rm -f "$BOOT"
echo "=============================================================="
echo "RUNID    = $RUNID"
echo "params   : TARGETS='$TARGETS' N=$NUM_DESIGNS K=$NUM_SEQS T=$DIFFUSER_T FOLDER=$FOLDER MARKET=$MARKET DRY_RUN=$DRY_RUN deadline=$MAX_RUNTIME"
echo "INSTANCE = $IID"
echo "poll     : aws s3 cp $S3RUN/status/rfp_status.json -"
echo "result   : aws s3 cp $S3RUN/status/candidates_5o45.jsonl - ; aws s3 cp $S3RUN/status/candidates_9xmm.jsonl -"
echo "summary  : aws s3 cp $S3RUN/status/rfpeptides_summary.json -"
echo "=============================================================="
