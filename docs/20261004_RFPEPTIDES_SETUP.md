# RFpeptides Cyclic Hit-Generation — Setup & Scoping (Track B)

**Date:** 2026-10-04 · **Status:** BUILT + LOCALLY VERIFIED; **not launched** (parent reviews + launches).
**Branch:** `cursor/tutorial-live-recording-and-report-editing-4ea7`
**Extends:** `docs/20261004_PEPTIDE_PROGRAM_PLAN.md` → Track B (B1).
**Launcher:** `research/guangzhou_all_atom/launch_rfpeptides.sh` · **Metric:** `research/guangzhou_all_atom/scrmsd.py` (reused).

---

## 1. Why this track (the delta)

Our two existing panels (PD-L1 `5o45` → 10-peptide; αvβ6 `9xmm` → 12-peptide) were generated with
**BoltzGen** (`boltzgen_ourtarget.sh`). The genuine delta is a **generation-method swap to RFpeptides**,
the protocol with the *proven* higher wet-lab hit rate on novel targets:

> Rettie, Juergens, … Baker. *Accurate de novo design of high-affinity protein-binding macrocycles
> using deep learning.* **Nat Chem Biol (2025)**, s41589-025-01929-w. Binders obtained against **4/4**
> diverse targets with **≤20 designed macrocycles each**, affinities to **~9 nM**, X-ray Cα-RMSD < 1.5 Å
> to the design models.

This is a **method swap, not a new category** (see §7 honest framing). The defensible contribution of the
program remains the integrated system + proprietary data + prospectively-validated loop, not "we beat SOTA."

---

## 2. The exact pipeline

RFpeptides is a three-stage pipeline. All three stages are **public and runnable** (§6):

| Stage | Tool | What it does | Source |
|---|---|---|---|
| 1. Backbone | **RFdiffusion (cyclic)** | diffuse N macrocyclic binder backbones against the target pocket, binder chain cyclized | `github.com/RosettaCommons/RFdiffusion` (RFpeptides protocol **merged into main**) |
| 2. Sequence | **ProteinMPNN** | design K sequences per backbone | `github.com/dauparas/ProteinMPNN` |
| 3. Self-consistency filter | **AfCycDesign** (default) *or* **CyclicBoltz1** | independently re-fold each designed cyclic sequence; keep designs whose re-fold matches the design model (low scRMSD) | ColabDesign (`github.com/sokrypton/ColabDesign`) / `github.com/Charlesjc-lab/BoltzDesign1_cyclic` |

**Designability metric = scRMSD** (Cα-RMSD between the RFdiffusion backbone and the independent re-fold,
Kabsch-superposed). This is the RFpeptides paper's own filter; we reuse the in-tree
`scrmsd.py` (pure-numpy, has `--selftest`, already used by the UniMoMo refold/rerank stage).

### RFdiffusion cyclic flags (verbatim from the repo's `examples/design_macrocyclic_binder.sh`)
```
scripts/run_inference.py --config-name base \
  inference.output_prefix=... inference.input_pdb=target.pdb \
  inference.num_designs=10 \
  'contigmap.contigs=[12-18 A3-117/0]' \      # [binder_len  receptor_chain_span/chainbreak]
  inference.cyclic=True inference.cyc_chains='a' \  # cyclize the (first) binder chain
  diffuser.T=50 \
  ppi.hotspot_res=[\'A51\',\'A52\',...]        # pocket residues (author numbering)
```
The launcher builds `contigmap.contigs` and `ppi.hotspot_res` **automatically** from the native-ligand
contacts (gemmi, <5 Å), so the pocket matches the one BoltzGen conditioned on.

---

## 3. Inputs we already have

Same receptors + pockets as the BoltzGen panels (`boltzgen_ourtarget.sh`):

| Target | PDB | Receptor chain(s) | Native ligand chain (pocket definer) | Binder length range |
|---|---|---|---|---|
| **PD-L1** | `5o45` | A (IgV) | B — macrocyclic peptide-71 (len 14; ncAAs MEA/SAR/9KK/CCS) | 12–16 |
| **αvβ6** | `9xmm` | A,B (two-subunit RGD site) | E — 9-mer cyclic RGD | 9–14 |

Structures are **downloaded at run time from RCSB** (no local copy needed, mirrors `boltzgen_ourtarget.sh`).
RFdiffusion needs a `.pdb`; the driver fetches `.pdb` and falls back to `.cif → .pdb` via gemmi. The
two-subunit αvβ6 pocket is handled: hotspots and contig span **both** chains A and B (Arg→αV, Asp→β6 MIDAS),
same rationale as the BoltzGen comma-separated receptor handling.

---

## 4. Install recipe (runs on-instance in the driver; no local install)

The launcher boots a generic DL GPU AMI and the driver installs three envs (first run; a bake step can
pre-build these — see §8):

```
# RFdiffusion
git clone github.com/RosettaCommons/RFdiffusion
conda env create -f env/SE3nv.yml ; conda activate SE3nv
pip install -e env/SE3Transformer ; pip install -e .
bash scripts/download_models.sh models/          # weights under per-file md5 subdirs on files.ipd.uw.edu

# ProteinMPNN (run-as-script; soluble weights ship in the repo)
git clone github.com/dauparas/ProteinMPNN

# self-consistency folder (default afcycdesign)
conda create -n fold python=3.10 ; pip install "jax[cuda12]" dm-haiku biopython
pip install git+github.com/sokrypton/ColabDesign.git
# + stock AF2 params (alphafold_params_2022-12-06.tar) — AfCycDesign reuses them with a cyclic offset
#   (alt: FOLDER=cyclicboltz1 → clone Charlesjc-lab/BoltzDesign1_cyclic, pip install boltz)
```

Model-weight hosts verified reachable (preflight, 2026-10-04):
`files.ipd.uw.edu/pub/RFdiffusion/<md5>/Complex_base_ckpt.pt` → **200 OK**.

---

## 5. GPU / instance / runtime / cost

Mirrors our baked-AMI / self-terminate / **spot→on-demand ladder** pattern (same inventory as
`launch_refold_rerank.sh`): g5/g6 `.2–.8xlarge` (A10G/L4, 24 GB), `us-west-2`, IAM
`AutoimmuneCorpusProfile`, deadline-timer + `shutdown -h now` self-terminate, 120 s S3 status sync.

| Item | Estimate |
|---|---|
| Instance | g5.4xlarge (A10G 24 GB) on-demand ≈ **$1.62/h**; spot ≈ $0.55–0.80/h |
| Cold install (first run) | ~20–35 min (RFdiffusion env + SE3 + weights + AF2 params ~5 GB) — **bake to kill this** (§8) |
| RFdiffusion backbones | ~30–90 s/design on A10G → N=20/target ≈ 10–30 min/target |
| ProteinMPNN | seconds per backbone (negligible) |
| Self-consistency fold | ~1–3 min/sequence (AF2 cyclic) → dominates; K=8 × 20 bb × 2 targets ≈ 5–16 h |
| **DRY_RUN (N=4,K=2, both targets)** | ~1.5–3 h wall, **~$2–5** |
| **Full (N=20,K=8, both targets)** | ~8–18 h wall, **~$10–25** (spot ≈ ⅓) |

`DISK_GB=200` (RFdiffusion + AF2/Boltz weights are large). Deadlines: DRY 4 h, full 24 h.

---

## 6. Feasibility verdict — IS THE PROTOCOL PUBLIC & RUNNABLE?

**YES — it is the published protocol, not a loose reconstruction.** Specifics, each verified against the
live sources on 2026-10-04:

- **RFdiffusion-cyclic backbone generation is merged into the main RFdiffusion repo.** The README states:
  *"We have recently published the RFpeptides protocol … We have added two examples for running macrocycle
  design … One for monomeric design, and one for binder design"* — `examples/design_macrocyclic_binder.sh`,
  `design_macrocyclic_monomer.sh`, `design_cyclic_oligos.sh`, flags `inference.cyclic=True
  inference.cyc_chains='a'`. **Not a fork, not a reconstruction.**
- **ProteinMPNN** is public and unchanged from standard use.
- **Self-consistency filter is paper-sanctioned.** The paper's own text: structure prediction of the
  designed complexes *"using either AfCycDesign and/or RoseTTAFold with the cyclic offset applied."*
  Our **default `FOLDER=afcycdesign`** (ColabDesign cyclic offset) is therefore exactly one of the two
  filters the paper itself uses. `FOLDER=cyclicboltz1` is a newer public AF3-framework alternative
  (better ncAA handling). HighFold3 (`ONERAI/HighFold3`) is a further public option.
- **Full code + scripts** for RFpeptides are released on **Zenodo** and via the RFdiffusion repo.

**Honest build-boundary (the one piece to finalize before the full run):** the stage-3 *predict → pred.pdb*
call is **folder-specific** and is left as a clearly-marked helper hook
(`code/fold_predict_<folder>.sh <seq> <bb.pdb> <out_pred.pdb>`). I did **not** hard-code an unverified
ColabDesign/Boltz invocation, because I cannot run it locally (no GPU) and a wrong command would silently
produce "0 designable" fakes. The launcher is **fail-safe about this**: if the helper is absent it prints a
loud banner, emits candidates as **real ProteinMPNN sequences with `scrmsd_computed:false`**, and the summary
records `self_consistency:"SKIPPED_no_folder_helper"` — never a fabricated score. Stages 1–2 (backbone +
sequence) and the scRMSD scoring/ranking (`scrmsd.py`, self-tested) are fully wired. Finalizing the ~15-line
predict helper against the chosen folder's API is a GPU-side task for the review+launch step.

**Verdict: runnable today for stages 1–2 + ranking; stage-3 predict helper is a short, documented
finalization — not a research gap.**

---

## 7. Honest framing (no over-claim)

- Track B is a **method swap** to the proven-best generator, **not a new method**. (Matches the program plan.)
- RFpeptides' hit-rate claim is *theirs*, on *their* targets; realizing it on 5o45/9xmm is what the run tests.
- Candidates will be **gated by our existing filters** (CREMP strain, CycPeptMPDB permeability) and scored by
  Track-A's real-data binding model (B2), then **head-to-head vs the BoltzGen panels** on designability
  (scRMSD) and predicted binding (B3). That comparison is the deliverable, not a standalone "RFpeptides won."

---

## 8. Follow-ups (not blocking the first run)

1. **Finalize `fold_predict_<folder>.sh`** (the stage-3 predict hook) — see §6.
2. **Bake the envs into an AMI** (extend `bake_cyclic_image.sh` with an `rfp`/`SE3nv` env + pre-staged
   RFdiffusion + AF2 params) to turn ~30 min cold install into seconds — lever #1, same as BoltzGen/MMGBSA.
3. **B2/B3 integration:** route RFpeptides candidates through `peptide_gate.py` + the Track-A binding model;
   emit the BoltzGen-vs-RFpeptides comparison table.

---

## 9. Ready-to-launch commands (DO NOT LAUNCH — parent runs these)

```bash
cd research/guangzhou_all_atom

# (a) local, free, no AWS/GPU — verify all public sources + weights reachable:
PREFLIGHT_ONLY=1 bash launch_rfpeptides.sh

# (b) cheap end-to-end shakeout (N=4, K=2, both targets, on-demand, ~$2–5):
DRY_RUN=1 bash launch_rfpeptides.sh

# (c) full pool, spot→on-demand ladder (N=20, K=8, both targets, ~$10–25):
DRY_RUN=0 MARKET=spot bash launch_rfpeptides.sh

# knobs: TARGETS="5o45 9xmm"  NUM_DESIGNS  NUM_SEQS  DIFFUSER_T=50  FOLDER=afcycdesign|cyclicboltz1
# poll:   aws s3 cp s3://knowledge-datasets-1759951976/cyclic_peptide/runs/<RUNID>/status/rfp_status.json -
# result: candidates_5o45.jsonl · candidates_9xmm.jsonl · rfpeptides_summary.json
```

### Local verification performed (2026-10-04)
- `bash -n` clean on the launcher **and** on the extracted on-GPU driver here-doc.
- All four embedded Python snippets (`CVT`, `POCKET`, `RANK`, `AGG`) `py_compile` clean.
- `scrmsd.py --selftest` → ALL_CHECKS_PASS.
- `PREFLIGHT_ONLY=1` run → all sources **OK** for both `FOLDER` options; exits 0; **does not launch**.
