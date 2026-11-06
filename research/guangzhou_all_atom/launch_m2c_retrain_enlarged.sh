#!/bin/bash
# =====================================================================================================
# launch_m2c_retrain_enlarged.sh — M2c cyclic-peptide generator retrain on the ENLARGED bound-complex
# corpus, on the PRE-BAKED AMI (activate-only, no cold install).
#
# This is run_m2c_ldm_finetune.sh (the proven 235-complex D2 retrain: stage -> process.py mmap ->
# leakage-aware split -> warm-started LDM fine-tune -> official DockQ panel on the held-out test) with
# exactly three deltas, nothing else reinvented:
#   (1) AMI  = the baked cyclic-peptide image (ami-06e366a5b89d12344). The M2c stack lives in
#       /opt/pepglad-venv (torch 2.5.1 cu121 + torch-scatter + rdkit + biopython + scipy + PyYAML +
#       tqdm + networkx + sympy + tensorboard + boto3 — verified in bake_cyclic_image.sh:54-63). The
#       driver therefore `source`s that venv instead of building one. Only two small, fast top-ups
#       remain (NOT the heavy torch cold-install the AMI saves): `gemmi` (optional cif staging accel,
#       biopython MMCIFParser is the fallback) and the DockQ v1.0 build toolchain (git/build-essential/
#       gfortran — evaluation.dockq git-clones+makes DockQ on first import; the bake did not prebuild it).
#   (2) CORPUS = existing D2 bound_cyclic_v1 (235) U newest d2-mine output (MINE_S3) U the suitable
#       approved-drug co-crystals (data/approved_cocrystals.json). Merged + deduped on the instance into
#       ONE d2-dir, then fed to the SAME m2c_process_complexes.py. GPCR Galpha/Gbeta/Ggamma/Nb/scFv
#       fusion chains are dropped for free: the index names only [receptor, peptide] and process.py ->
#       stage_one extracts exactly those two chains.
#   (3) SPOT-FIRST, ON-DEMAND FALLBACK (user-authorized). The spot ladder runs first; if every spot
#       combo is out of capacity, the SAME type/subnet ladder is retried on-demand so the retrain still
#       launches. Self-terminate + dead-man's-switch + 60s S3 checkpoint streaming are unchanged.
#
# Baseline to beat: the 235-corpus M2c run scored DockQ 0.437 (0.4354) on its 24-complex held-out test
# (SOTA PepGLAD 0.592). This run asks whether ~3.6x more real bound complexes closes that gap.
#
# It launches ONE GPU instance and nothing else.
# Poll:   aws s3 cp $S3RUN/status/status.json -
# Ckpts:  aws s3 ls $S3RUN/ckpts/ --recursive
# Result: aws s3 cp $S3RUN/m2c_eval_result.json -
# Data:   aws s3 cp $S3RUN/dataset_manifest.json -
# =====================================================================================================
set -Eeuo pipefail
REGION=${REGION:-us-west-2}
export AWS_DEFAULT_REGION=$REGION
BUCKET=knowledge-datasets-1759951976
AMI=${AMI:-ami-06e366a5b89d12344}      # PRE-BAKED cyclic-peptide AMI (us-west-2); /opt/pepglad-venv ready
SG=${SG:-sg-011121fdf81073ec8}         # security group (region-specific) => OVERRIDE per region
KEY=${KEY:-biomate-trial-resume-20260912}  # optional SSH key; set KEY="" to omit

# --- inputs (env-overridable) ------------------------------------------------------------------------
# (a) epoch-221 LDM -> warm-start the DIFFUSION (its .autoencoder is dropped in warm_start_diffusion)
WARM_LDM_S3=${WARM_LDM_S3:-s3://$BUCKET/cyclic_peptide/RELEASED/pepglad_ldm_epoch221/epoch221_step77700.ckpt}
# (b) M1 v1 AE (production AE) -> becomes the FROZEN autoencoder of the LDM (AE_MODE=v1, matches the 0.437 ckpt)
V1_AE_S3=${V1_AE_S3:-s3://$BUCKET/cyclic_peptide/runs/m1-ae-midtrain-20260928T225554Z/ckpts/m1_ae_midtrain/version_0/checkpoint/epoch39_step3520.ckpt}
# (c) EXISTING D2 bound cyclic complexes (235): index.txt + bound_cyclic_manifest.jsonl
D2_EXISTING_S3=${D2_EXISTING_S3:-s3://$BUCKET/cyclic_peptide/datasets/bound_cyclic_v1}
# (d) NEW mine output (REQUIRED): the d2-mine-local-<stamp> dir holding bound_cyclic_manifest.jsonl + index.txt.
#     Both EC2 d2-mine runs on S3 (20260930T204156Z, 20261001T043807Z) FAILED and produced no manifest, so
#     this MUST point at the locally-mined upload. Example upload (from the repo, once the local mine is done):
#       STAMP=$(date -u +%Y%m%dT%H%M%SZ)
#       aws s3 cp research/guangzhou_all_atom/data/bound_cyclic/v2/bound_cyclic_manifest.jsonl \
#         s3://$BUCKET/cyclic_peptide/runs/d2-mine-local-$STAMP/bound_cyclic_manifest.jsonl
#       aws s3 cp research/guangzhou_all_atom/data/bound_cyclic/v2/index.txt \
#         s3://$BUCKET/cyclic_peptide/runs/d2-mine-local-$STAMP/index.txt
#       then: MINE_S3=s3://$BUCKET/cyclic_peptide/runs/d2-mine-local-$STAMP ./launch_m2c_retrain_enlarged.sh
MINE_S3=${MINE_S3:?set MINE_S3 to the d2-mine-local-<stamp> dir (must contain index.txt + bound_cyclic_manifest.jsonl)}

# training / data knobs (same defaults as the 235 launcher; test/val scale with the larger corpus)
POCKET_TH=${POCKET_TH:-10.0}
MIN_TEST=${MIN_TEST:-24}                 # floor for the held-out test set; test_frac dominates at this corpus size
VAL_FRAC=${VAL_FRAC:-0.1}
TEST_FRAC=${TEST_FRAC:-0.1}
ID_TH=${ID_TH:-0.6}                      # peptide-seq identity threshold for the leakage-aware split
MAX_EPOCH=${MAX_EPOCH:-40}
LR=${LR:-1.0e-5}
N_SAMPLES=${N_SAMPLES:-16}               # samples/target at eval (>=2 for diversity/consistency)
STRUCT_PASS=${STRUCT_PASS:-0}            # 1 = also run struct_only pass for DockQ>=/RMSD<= buckets
AE_MODE=${AE_MODE:-v1}                   # v1 = frozen v1 AE (matches the DockQ-0.437 baseline ckpt)
COCRYSTALS_TO_TRAIN=${COCRYSTALS_TO_TRAIN:-1}  # 1 = pin approved-drug co-crystals to TRAIN (see note below)
MAX_RUNTIME=${MAX_RUNTIME:-14h}          # staging ~850 complexes (network) + 40-epoch train on ~3.6x data + eval

RUNID=m2c-retrain-enlarged-$(date -u +%Y%m%dT%H%M%SZ)
S3RUN=s3://$BUCKET/cyclic_peptide/runs/$RUNID
HERE=$(cd "$(dirname "$0")" && pwd)

# --- preflight: fail BEFORE spending an instance if the mine output is not on S3 yet ----------------
echo "preflight: checking MINE_S3 exists ($MINE_S3) ..."
aws s3 ls "$MINE_S3/index.txt" >/dev/null 2>&1 || { echo "FATAL: $MINE_S3/index.txt not found — upload the local mine first (see header)"; exit 1; }
aws s3 ls "$MINE_S3/bound_cyclic_manifest.jsonl" >/dev/null 2>&1 || { echo "FATAL: $MINE_S3/bound_cyclic_manifest.jsonl not found"; exit 1; }
aws s3 ls "$D2_EXISTING_S3/index.txt" >/dev/null 2>&1 || { echo "FATAL: $D2_EXISTING_S3/index.txt not found"; exit 1; }
[ -f "$HERE/data/approved_cocrystals.json" ] || { echo "FATAL: missing data/approved_cocrystals.json"; exit 1; }
echo "preflight OK"

# --- build + upload the code bundle ------------------------------------------------------------------
# Same module set as run_m2c_ldm_finetune.sh (m2c_train_ldm reuses warm_start_diffusion from m2_train_ldm,
# which imports m1_peptide_dataset + m2_peptide_ldm at module level; m1_closure_ae unpickles the v1 AE) PLUS
# approved_cocrystals.json for the co-crystal fold-in.
TMP=$(mktemp -d)
for f in m2c_process_complexes.py m1_closure_ae.py m1_peptide_dataset.py m2_peptide_ldm.py \
         m2_train_ldm.py m2c_train_ldm.py m2c_eval.py \
         m2c_ldm_finetune.yaml m2c_test_codesign.yaml m2c_setup_latent_guidance.yaml; do
  [ -f "$HERE/$f" ] || { echo "FATAL: missing $f"; exit 1; }
  cp "$HERE/$f" "$TMP/"
done
cp "$HERE/data/approved_cocrystals.json" "$TMP/approved_cocrystals.json"
tar czf "$TMP/pepglad_runtime.tar.gz" -C "$HERE/runtime" PepGLAD
tar czf "$TMP/code.tar.gz" -C "$TMP" \
  m2c_process_complexes.py m1_closure_ae.py m1_peptide_dataset.py m2_peptide_ldm.py \
  m2_train_ldm.py m2c_train_ldm.py m2c_eval.py \
  m2c_ldm_finetune.yaml m2c_test_codesign.yaml m2c_setup_latent_guidance.yaml \
  approved_cocrystals.json pepglad_runtime.tar.gz
SHA=$(shasum -a 256 "$TMP/code.tar.gz" | awk '{print $1}')
aws s3 cp "$TMP/code.tar.gz" "$S3RUN/code/code.tar.gz" --only-show-errors
echo "uploaded code.tar.gz ($SHA)"
echo "  WARM_LDM_S3=$WARM_LDM_S3"
echo "  V1_AE_S3=$V1_AE_S3"
echo "  D2_EXISTING_S3=$D2_EXISTING_S3"
echo "  MINE_S3=$MINE_S3"
echo "  AE_MODE=$AE_MODE COCRYSTALS_TO_TRAIN=$COCRYSTALS_TO_TRAIN MIN_TEST=$MIN_TEST MAX_EPOCH=$MAX_EPOCH LR=$LR N_SAMPLES=$N_SAMPLES MAX_RUNTIME=$MAX_RUNTIME"

# --- driver script that runs ON the instance --------------------------------------------------------
cat > "$TMP/driver.sh" <<'DRIVER'
#!/bin/bash
set -Eeuo pipefail
export AWS_DEFAULT_REGION=us-west-2
export DEBIAN_FRONTEND=noninteractive PYTHONUNBUFFERED=1 OMP_NUM_THREADS=4
ROOT=/opt/guangzhou-peptide
mkdir -p "$ROOT/status" "$ROOT/code" "$ROOT/data" "$ROOT/ckpts"
exec > >(tee -a "$ROOT/status/bootstrap.log") 2>&1

stage() {
  printf '{"stage":"%s","time":"%s"}\n' "$1" "$(date -u +%FT%TZ)" > "$ROOT/status/status.json"
  aws s3 sync "$ROOT/status" "$OUT_S3/status/" --only-show-errors || true
}
sync_all() {
  aws s3 sync "$ROOT/status" "$OUT_S3/status/" --only-show-errors || true
  [ -d "$ROOT/ckpts" ] && aws s3 sync "$ROOT/ckpts" "$OUT_S3/ckpts/" --only-show-errors || true
  [ -f "$ROOT/m2c_eval_result.json" ] && aws s3 cp "$ROOT/m2c_eval_result.json" "$OUT_S3/m2c_eval_result.json" --only-show-errors || true
  [ -f "$ROOT/data/bound_cyclic_pepglad/manifest.json" ] && aws s3 cp "$ROOT/data/bound_cyclic_pepglad/manifest.json" "$OUT_S3/dataset_manifest.json" --only-show-errors || true
}
finish() {
  rc=$?
  trap - EXIT
  [ "$rc" -ne 0 ] && stage failed || true
  sync_all
  shutdown -h now
  exit "$rc"
}
trap finish EXIT

# periodic heartbeat + checkpoint stream (every 60s) + best-effort spot-interruption capture
(while sleep 60; do sync_all; done) &
(while sleep 5; do
  token=$(curl -fsS --max-time 2 -X PUT -H 'X-aws-ec2-metadata-token-ttl-seconds: 60' http://169.254.169.254/latest/api/token) || continue
  if curl -fsS --max-time 2 -H "X-aws-ec2-metadata-token: $token" http://169.254.169.254/latest/meta-data/spot/instance-action > "$ROOT/status/spot-interruption.json"; then
    stage spot_interruption; sync_all; break
  fi
done) >/dev/null 2>&1 &

# ---- BAKED AMI: activate the pre-built M2c venv (NO torch/torch-scatter cold install) --------------
stage activating
source /opt/pepglad-venv/bin/activate
# Two small, fast top-ups only (not the heavy install the AMI saves):
#  * gemmi: optional cif->pdb staging accel (biopython MMCIFParser is the built-in fallback). pip is a no-op
#    if the AMI already carries it; failure is non-fatal (processing falls back).
pip install -q --disable-pip-version-check 'gemmi==0.6.7' || echo "WARN: gemmi install failed; MMCIFParser fallback"
#  * DockQ v1.0 build toolchain (evaluation.dockq git-clones+makes DockQ on first import; bake did not
#    prebuild it). The 235 launcher installed these at runtime on the same AMI lineage successfully.
for attempt in 1 2 3 4 5 6; do apt-get -o DPkg::Lock::Timeout=300 update -qq && break; [ "$attempt" = 6 ] && echo "WARN: apt update flaky"; sleep 10; done
apt-get -o DPkg::Lock::Timeout=300 install -y -qq git build-essential gfortran || echo "WARN: DockQ toolchain apt failed; eval may report DockQ unavailable"
pip freeze > "$ROOT/status/environment.txt" || true
python -c 'import torch,torch_scatter,rdkit,networkx,sympy,Bio,scipy,tensorboard; assert torch.cuda.is_available(); print("pepglad venv ok", torch.__version__, torch.cuda.get_device_name(0))'

stage fetching_code
aws s3 cp "$OUT_S3/code/code.tar.gz" "$ROOT/code.tar.gz" --only-show-errors
tar xzf "$ROOT/code.tar.gz" -C "$ROOT/code"
mkdir -p "$ROOT/code/runtime"
tar xzf "$ROOT/code/pepglad_runtime.tar.gz" -C "$ROOT/code/runtime"   # -> $ROOT/code/runtime/PepGLAD

stage fetching_data
aws s3 cp "$WARM_LDM_S3" "$ROOT/data/epoch221.ckpt" --only-show-errors    # (a) diffusion warm-start
aws s3 cp "$V1_AE_S3"    "$ROOT/data/v1_ae.ckpt"    --only-show-errors     # (b) FROZEN autoencoder
# three corpus sources into separate dirs
mkdir -p "$ROOT/data/src_v1" "$ROOT/data/src_mine"
aws s3 cp "$D2_EXISTING_S3/index.txt"                    "$ROOT/data/src_v1/index.txt" --only-show-errors
aws s3 cp "$D2_EXISTING_S3/bound_cyclic_manifest.jsonl"  "$ROOT/data/src_v1/bound_cyclic_manifest.jsonl" --only-show-errors
aws s3 cp "$MINE_S3/index.txt"                           "$ROOT/data/src_mine/index.txt" --only-show-errors
aws s3 cp "$MINE_S3/bound_cyclic_manifest.jsonl"         "$ROOT/data/src_mine/bound_cyclic_manifest.jsonl" --only-show-errors

cd "$ROOT/code"

# ---- AE_MODE=epoch221 : matched-latent diagnostic (swap in epoch-221's OWN .autoencoder). Default v1. ----
if [ "${AE_MODE:-v1}" = "epoch221" ]; then
  python -c "import sys; sys.path.insert(0,'runtime/PepGLAD'); import torch, models; \
    ldm=torch.load('$ROOT/data/epoch221.ckpt', map_location='cpu', weights_only=False); \
    torch.save(ldm.autoencoder, '$ROOT/data/v1_ae.ckpt'); print('[AE_MODE=epoch221] frozen AE = epoch-221 .autoencoder (matched latent)')"
fi

# ---- merge the enlarged corpus: v1 U mine U suitable co-crystals -> ONE d2-dir -------------------------
# Written as a small staged script for readability. Dedup by index pdb_id, priority v1 -> mine -> cocrystals
# (first-seen wins, so a PDB present in the mine keeps its REAL peptide_seq rather than a co-crystal's blank).
cat > "$ROOT/code/merge_corpus.py" <<'PYMERGE'
#!/usr/bin/env python3
"""Merge the enlarged M2c corpus into ONE d2-dir (index.txt + bound_cyclic_manifest.jsonl) that
m2c_process_complexes.read_d2 consumes verbatim. Three sources, in priority order:
  1. existing D2 v1 (index + manifest)         2. newest d2-mine (index + manifest)
  3. suitable:true approved-drug co-crystals (approved_cocrystals.json) -> synthesized index+manifest rows
Dedup key = index pdb_id (e.g. '7T11_P'); first source to carry an id wins. Co-crystal GPCR fusion chains
(Galpha/Gbeta/Ggamma/Nb/scFv) are dropped automatically downstream because the index names only
[receptor, peptide] and process.py -> stage_one extracts exactly those two chains.
"""
import json, sys
from pathlib import Path

out_dir, v1_dir, mine_dir, cocryst_json = (Path(sys.argv[1]), Path(sys.argv[2]),
                                           Path(sys.argv[3]), Path(sys.argv[4]))
out_dir.mkdir(parents=True, exist_ok=True)

# RCSB-verified cleaner-structure overrides (task-specified): eptifibatide -> 8T2U (full-length aIIbb3 +
# eptifibatide, no Fab), not the JSON's primary 2VDN (carries Fab 10E5 H/L chains).
PDB_OVERRIDE = {"Eptifibatide": {"pdb": "8T2U", "rec_chain": "A", "pep_chain": "C"}}

def _first_chain(s):
    """First real chain id from a possibly messy field, e.g. 'A,B'->'A', 'F (L11) + X (23S rRNA)'->'F'."""
    if not s:
        return ""
    tok = s.replace(",", " ").split()
    return tok[0].strip() if tok else ""

def _provenance(method):
    m = (method or "").lower()
    if "x-ray" in m or "xray" in m:
        return "crystal_experimental"
    if "em" in m or "cryo" in m:
        return "cryoEM_experimental"
    if "nmr" in m:
        return "NMR_experimental"
    return "PDB_experimental"

def read_index(p):
    rows = []
    if not p.is_file():
        return rows
    for ln in p.read_text().splitlines():
        if not ln.strip():
            continue
        parts = ln.rstrip("\n").split("\t")
        if len(parts) >= 3:
            rows.append(parts)
    return rows

def read_manifest(p):
    rows = []
    if not p.is_file():
        return rows
    for ln in p.read_text().splitlines():
        if not ln.strip():
            continue
        try:
            rows.append(json.loads(ln))
        except json.JSONDecodeError:
            continue
    return rows

# ---- 1+2: existing + mine index lines (dedup by pdb_id, first wins) ----
index_by_id = {}           # pdb_id -> [pdb_id, rec, pep, flag]
for d in (v1_dir, mine_dir):
    for parts in read_index(d / "index.txt"):
        index_by_id.setdefault(parts[0], parts[:3] + ["0"])

# ---- 1+2: manifest rows (dedup by (pdb4.upper, pep_chain), first wins — read_d2's key) ----
manifest_by_key = {}       # (PDB4, pep_chain) -> dict
for d in (v1_dir, mine_dir):
    for r in read_manifest(d / "bound_cyclic_manifest.jsonl"):
        if r.get("status") != "ok":
            continue
        key = (str(r.get("pdb_id", "")).upper(), r.get("pep_chain", ""))
        manifest_by_key.setdefault(key, r)

# ---- 3: suitable co-crystals -> synthesized index + manifest rows (only if pdb_id not already present) ----
cocryst_ids = []           # index pdb_ids actually ADDED from the co-crystal source
records = json.loads(cocryst_json.read_text()).get("records", [])
for rec in records:
    if not rec.get("suitable"):
        continue
    ov = PDB_OVERRIDE.get(rec.get("drug"))
    pdb = (ov["pdb"] if ov else rec.get("pdb")) or ""
    rec_chain = _first_chain(ov["rec_chain"] if ov else rec.get("rec_chain"))
    pep_chain = _first_chain(ov["pep_chain"] if ov else rec.get("pep_chain"))
    if not (pdb and rec_chain and pep_chain) or rec_chain == pep_chain:
        continue
    pdb4 = pdb.split("_")[0].upper()
    idx_id = f"{pdb4}_{pep_chain}"
    if idx_id in index_by_id:            # already in v1/mine -> keep the seq-bearing version
        continue
    index_by_id[idx_id] = [idx_id, rec_chain, pep_chain, "0"]
    cocryst_ids.append(idx_id)
    key = (pdb4, pep_chain)
    manifest_by_key.setdefault(key, {
        "pdb_id": pdb4, "pep_chain": pep_chain, "rec_chains": [rec_chain],
        "peptide_seq": "",                      # unknown from the curated JSON -> singleton cluster, no leakage
        "cyclization_type": "unknown",
        "conformer_provenance": _provenance(rec.get("method")),
        "receptor_name": rec.get("target", ""),
        "drug": rec.get("drug", ""),
        "resolution": rec.get("resolution"),
        "status": "ok", "source": "approved_cocrystal",
    })

# ---- write merged d2-dir ----
with open(out_dir / "index.txt", "w") as f:
    for pid in index_by_id:
        p = index_by_id[pid]
        f.write(f"{p[0]}\t{p[1]}\t{p[2]}\t0\n")
with open(out_dir / "bound_cyclic_manifest.jsonl", "w") as f:
    for r in manifest_by_key.values():
        f.write(json.dumps(r) + "\n")
(out_dir / "cocrystal_ids.txt").write_text("\n".join(cocryst_ids) + ("\n" if cocryst_ids else ""))

n_v1 = len(read_index(v1_dir / "index.txt"))
n_mine = len(read_index(mine_dir / "index.txt"))
print(json.dumps({
    "n_v1_index": n_v1, "n_mine_index": n_mine,
    "n_cocrystals_added": len(cocryst_ids),
    "n_merged_index": len(index_by_id),
    "n_merged_manifest_ok": len(manifest_by_key),
    "cocrystal_ids": cocryst_ids,
}, indent=2))
PYMERGE

stage merging_corpus
python merge_corpus.py \
  "$ROOT/data/bound_cyclic_merged" \
  "$ROOT/data/src_v1" \
  "$ROOT/data/src_mine" \
  "$ROOT/code/approved_cocrystals.json" | tee "$ROOT/status/merge_report.json"
aws s3 cp "$ROOT/status/merge_report.json" "$OUT_S3/merge_report.json" --only-show-errors || true

# ---- resume-aware complex-mmap build: reuse THIS run's S3 dataset if a spot interruption restarted us ----
stage building_dataset
if aws s3 ls "$OUT_S3/dataset/processed/index.txt" >/dev/null 2>&1; then
  echo "found prebuilt mmap in THIS run's S3 -> reusing (spot-resume)"
  mkdir -p "$ROOT/data/bound_cyclic_pepglad"
  aws s3 sync "$OUT_S3/dataset" "$ROOT/data/bound_cyclic_pepglad" --only-show-errors
else
  python m2c_process_complexes.py \
    --d2-dir  "$ROOT/data/bound_cyclic_merged" \
    --out-dir "$ROOT/data/bound_cyclic_pepglad" \
    --pocket-th "$POCKET_TH" --min-test "$MIN_TEST" \
    --val-frac "$VAL_FRAC" --test-frac "$TEST_FRAC" --id-th "$ID_TH"
  aws s3 sync "$ROOT/data/bound_cyclic_pepglad" "$OUT_S3/dataset" --only-show-errors || true
fi

# ---- optional: pin the precious approved-drug co-crystals to TRAIN -------------------------------------
# Co-crystal rows carry blank peptide_seq (unknown from the curated JSON) -> each is a singleton cluster in
# m2c_process_complexes.cluster_by_sequence. A singleton can land in test/valid, which (a) spends a rare
# real-drug complex on evaluation instead of training, and (b) leaves a residual leakage path if the SAME
# peptide also appears in the mine with a real seq (blank vs real -> identity 0 -> they don't co-cluster).
# Pinning co-crystals to TRAIN removes both. The held-out test then measures generalization on mined
# experimental complexes with proper sequence clustering. Deterministic; default ON; set =0 to disable.
if [ "${COCRYSTALS_TO_TRAIN:-1}" = "1" ] && [ -s "$ROOT/data/bound_cyclic_merged/cocrystal_ids.txt" ]; then
  stage pinning_cocrystals_to_train
  python - "$ROOT/data/bound_cyclic_pepglad/processed" "$ROOT/data/bound_cyclic_merged/cocrystal_ids.txt" <<'PYPIN'
import sys
from pathlib import Path
proc = Path(sys.argv[1]); ids = set(l.strip() for l in Path(sys.argv[2]).read_text().splitlines() if l.strip())
def load(name):
    p = proc / name
    return (p, [l for l in p.read_text().splitlines() if l.strip()] if p.is_file() else [])
(tp, train), (vp, val), (sp, test) = load("train_index.txt"), load("valid_index.txt"), load("test_index.txt")
def pid(line): return line.split("\t")[0]
moved = [l for l in (val + test) if pid(l) in ids]
if moved:
    keep_val  = [l for l in val  if pid(l) not in ids]
    keep_test = [l for l in test if pid(l) not in ids]
    train = train + moved
    tp.write_text("\n".join(train) + "\n")
    vp.write_text("\n".join(keep_val) + ("\n" if keep_val else ""))
    sp.write_text("\n".join(keep_test) + ("\n" if keep_test else ""))
print(f"pinned {len(moved)} co-crystal(s) to train; train={len(train)} valid={len(keep_val) if moved else len(val)} test={len(keep_test) if moved else len(test)}")
PYPIN
  aws s3 sync "$ROOT/data/bound_cyclic_pepglad" "$OUT_S3/dataset" --only-show-errors || true
fi

stage training
python m2c_train_ldm.py --gpus 0 --config m2c_ldm_finetune.yaml \
  --warm_start_ldm_ckpt="$ROOT/data/epoch221.ckpt" \
  --model.autoencoder_ckpt="$ROOT/data/v1_ae.ckpt" \
  --dataset.train.mmap_dir="$ROOT/data/bound_cyclic_pepglad/processed" \
  --dataset.train.specify_index="$ROOT/data/bound_cyclic_pepglad/processed/train_index.txt" \
  --dataset.valid.mmap_dir="$ROOT/data/bound_cyclic_pepglad/processed" \
  --dataset.valid.specify_index="$ROOT/data/bound_cyclic_pepglad/processed/valid_index.txt" \
  --trainer.config.save_dir="$ROOT/ckpts/m2c_ldm_finetune" \
  --trainer.config.max_epoch="$MAX_EPOCH" \
  --trainer.config.optimizer.lr="$LR"
sync_all

stage evaluating
# Make the guidance+test config data paths absolute so they resolve from cwd=runtime/PepGLAD (eval-path fix
# carried over from the 235 launcher).
sed -i "s|\./data/bound_cyclic_pepglad|$ROOT/data/bound_cyclic_pepglad|g" \
  m2c_setup_latent_guidance.yaml m2c_test_codesign.yaml m2c_ldm_finetune.yaml
BEST_CKPT=$(head -1 "$ROOT/ckpts/m2c_ldm_finetune"/version_*/checkpoint/topk_map.txt 2>/dev/null | sed 's/^[^:]*: //' || true)
if [ -z "$BEST_CKPT" ] || [ ! -f "$BEST_CKPT" ]; then
  BEST_CKPT=$(ls -t "$ROOT/ckpts/m2c_ldm_finetune"/version_*/checkpoint/epoch*.ckpt 2>/dev/null | head -1 || true)
fi
echo "eval checkpoint: $BEST_CKPT"
if [ -n "$BEST_CKPT" ]; then
  STRUCT_FLAG=""; [ "$STRUCT_PASS" = "1" ] && STRUCT_FLAG="--struct-pass"
  python m2c_eval.py \
    --m2c-ckpt "$BEST_CKPT" \
    --data-dir "$ROOT/data/bound_cyclic_pepglad" \
    --test-config m2c_test_codesign.yaml \
    --guidance-config m2c_setup_latent_guidance.yaml \
    --n-samples "$N_SAMPLES" --gpu 0 $STRUCT_FLAG --out "$ROOT/m2c_eval_result.json"
  cp "$ROOT/m2c_eval_result.json" "$ROOT/status/m2c_eval_result.json" 2>/dev/null || true
  aws s3 sync "$ROOT/m2c_gen_codesign" "$OUT_S3/gen_codesign" --only-show-errors || true
else
  echo '{"status":"error","error":"no checkpoint produced"}' > "$ROOT/m2c_eval_result.json"
fi
stage complete
sync_all
DRIVER
aws s3 cp "$TMP/driver.sh" "$S3RUN/code/driver.sh" --only-show-errors

# --- user-data: dead-man's-switch preamble FIRST, then fetch+run the driver -------------------------
UD=$(cat <<EOF | base64
#!/bin/bash
systemd-run --unit=m2c-deadline --on-active=${MAX_RUNTIME} /sbin/shutdown -h now || shutdown -h +600 &
exec > /var/log/m2c-boot.log 2>&1
set -Eeuo pipefail
export AWS_DEFAULT_REGION=us-west-2
mkdir -p /opt/guangzhou-peptide/code
for i in 1 2 3 4 5; do aws s3 cp $S3RUN/code/driver.sh /opt/guangzhou-peptide/driver.sh && break; sleep 10; done
chmod +x /opt/guangzhou-peptide/driver.sh
OUT_S3=$S3RUN WARM_LDM_S3=$WARM_LDM_S3 V1_AE_S3=$V1_AE_S3 \
  D2_EXISTING_S3=$D2_EXISTING_S3 MINE_S3=$MINE_S3 \
  POCKET_TH=$POCKET_TH MIN_TEST=$MIN_TEST VAL_FRAC=$VAL_FRAC TEST_FRAC=$TEST_FRAC ID_TH=$ID_TH \
  MAX_EPOCH=$MAX_EPOCH LR=$LR N_SAMPLES=$N_SAMPLES STRUCT_PASS=$STRUCT_PASS AE_MODE=$AE_MODE \
  COCRYSTALS_TO_TRAIN=$COCRYSTALS_TO_TRAIN MAX_RUNTIME=$MAX_RUNTIME \
  bash /opt/guangzhou-peptide/driver.sh
EOF
)

declare -a COMBO=(
  "g5.xlarge subnet-0254e4c3634b41bfc"
  "g5.xlarge subnet-03b277a7a08d388c1"
  "g5.xlarge subnet-09e4dce46682a6c60"
  "g6.xlarge subnet-0b35a6e2c1cf02dc2"
  "g6.xlarge subnet-0254e4c3634b41bfc"
  "g5.2xlarge subnet-0254e4c3634b41bfc"
  "g6.2xlarge subnet-0b35a6e2c1cf02dc2"
  "g4dn.xlarge subnet-0254e4c3634b41bfc"
  "g4dn.xlarge subnet-03b277a7a08d388c1"
  "g4dn.xlarge subnet-09e4dce46682a6c60"
  "g4dn.xlarge subnet-0b35a6e2c1cf02dc2"
  "g4dn.2xlarge subnet-0254e4c3634b41bfc"
  "g5.4xlarge subnet-0254e4c3634b41bfc"
  "g6.4xlarge subnet-0b35a6e2c1cf02dc2"
  "g4dn.2xlarge subnet-09e4dce46682a6c60"
)
if [ -n "${COMBO_OVERRIDE:-}" ]; then
  mapfile -t COMBO <<< "$COMBO_OVERRIDE"
fi

# launch: ONE run-instances attempt for a given market mode ("spot" or "ondemand")
try_launch() {
  local mode=$1 c TYPE SUBNET market_opt
  for c in "${COMBO[@]}"; do
    set -- $c; TYPE=$1; SUBNET=$2
    if [ "$mode" = "spot" ]; then
      market_opt=(--instance-market-options '{"MarketType":"spot","SpotOptions":{"SpotInstanceType":"one-time","InstanceInterruptionBehavior":"terminate"}}')
    else
      market_opt=()   # on-demand
    fi
    echo "[$mode] trying $TYPE in $SUBNET ..."
    IID=$(aws ec2 run-instances \
      --image-id "$AMI" --instance-type "$TYPE" ${KEY:+--key-name $KEY} \
      --subnet-id "$SUBNET" --security-group-ids "$SG" \
      --iam-instance-profile Name=AutoimmuneCorpusProfile \
      "${market_opt[@]}" \
      --instance-initiated-shutdown-behavior terminate \
      --block-device-mappings '[{"DeviceName":"/dev/sda1","Ebs":{"VolumeSize":200,"VolumeType":"gp3"}}]' \
      --user-data "$UD" \
      --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$RUNID},{Key=project,Value=cyclic_peptide},{Key=market,Value=$mode}]" \
      --query 'Instances[0].InstanceId' --output text 2>/dev/null) && [ -n "$IID" ] && { echo "LAUNCHED [$mode] $TYPE $SUBNET -> $IID"; return 0; }
    echo "  no capacity ($TYPE $SUBNET)"
  done
  return 1
}

IID=""
# spot-first; on-demand fallback (user-authorized) if every spot combo is out of capacity
try_launch spot || { echo "all spot combos exhausted -> falling back to ON-DEMAND"; try_launch ondemand; } || true
[ -z "$IID" ] && { echo "FATAL: no GPU capacity across all combos (spot AND on-demand)"; exit 1; }
rm -rf "$TMP"
echo "RUNID=$RUNID"; echo "INSTANCE=$IID"
echo "poll:    aws s3 cp $S3RUN/status/status.json -"
echo "merge:   aws s3 cp $S3RUN/merge_report.json -"
echo "ckpts:   aws s3 ls $S3RUN/ckpts/ --recursive"
echo "result:  aws s3 cp $S3RUN/m2c_eval_result.json -"
echo "data:    aws s3 cp $S3RUN/dataset_manifest.json -"
