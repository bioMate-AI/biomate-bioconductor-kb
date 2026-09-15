# Phase 1 scoping — cyclic-peptide plugin (code-grounded)

What must change in the PepGLAD codebase (pinned `bad015ca`) to make the validated backbone
generate **cyclic** peptides. Grounded in reading the source, not assumptions.

## What the code actually does (key facts)
- **No explicit bonds/edges.** No `radius_graph`/`bond`/`edge`/`cyclic` anywhere in model or
  data. The model emits residue types `S` + all-atom coordinates `X`; **topology is implicit in
  the geometry.** ⇒ closure cannot be a "closure edge + loss."
- **All-atom, arbitrary elements.** `data/format.py` `MoleculeVocab`: atom vocab = full periodic
  table; block vocab = specials + amino acids (`aas`) + small molecules (`sms`); 14 atoms/block.
  Non-natural chemistry is representable at the atom level, but the **sequence-design head
  predicts over the fixed AA block set**.
- **Guidance hook already exists** (`models/LDM/ldm.py`): `sample()` accepts
  `sample_opt['energy_func']`; `'default'` → `latent_geometry_guidance`, which calls
  `dist_energy(X, mask_generate, batch_ids, consec_dist_mean, consec_dist_std, tolerance)`.
  `set_consec_dist(mean,std)` holds target stats; `setup_latent_guidance.py` computes them by
  encoding the training set and measuring the distance between **consecutive** latent points
  (`Z[1:]-Z[:-1]` where `position_ids` differ by 1). Guidance operates in **latent space**
  during diffusion sampling.

## Approach: closure via guidance + cyclic fine-tuning (no architecture surgery)
1. **Closure guidance term.** Write a `cyclic_geometry_guidance` energy analogous to
   `latent_geometry_guidance` that adds a `dist_energy` between the **first and last** latent
   point of each generated peptide (per `batch_ids`), targeting a head-to-tail distance; for
   disulfides, add a term on CYS-pair points. **Compose** it with the existing consecutive-
   distance guidance (sum the energies) and pass as `energy_func`. No model retraining needed to
   add guidance.
2. **Target stats.** Extend `setup_latent_guidance.py` to also compute the first↔last latent
   distance distribution over the **cyclic** training peptides (`set_cyclic_dist(mean,std)`),
   the same way consec dist is computed.
3. **Cyclic fine-tuning.** Fine-tune the LDM (and optionally AE) on the PepBDB cyclic subset
   (799 train) so the prior favors closable conformations; keep the 91 held-out cyclics for test.
   Reuse `run_pepglad_ec2.sh` with the cyclic dataset + our validated eval.

## Files to touch
- `models/LDM/ldm.py` — add `set_cyclic_dist` + `cyclic_geometry_guidance` (mirror the consec
  versions); allow `energy_func='cyclic'` (or compose 'default'+cyclic).
- `setup_latent_guidance.py` — also measure/store first↔last (and CYS-pair) latent distances.
- Data: a cyclic index/split from the PepBDB cyclic subset (already in S3:
  `datasets/pepbdb/20200318/pepbdb_cyclic_split.json`) → PepGLAD's processed format
  (`scripts/data_process/pepbdb.py` + `process`/`split`). Verify the cyclic entries carry the
  ring residues; PepBDB peptide.pdb may need head-to-tail annotation.
- `generate_validation.py` — add closure metrics (N-term N ↔ C-term C distance; CYS SG-SG
  distances) → **closure rate**.

## Validation (success criteria)
- **Closure rate**: fraction of generated peptides with terminal N–C distance ≤ ~1.5 Å (peptide
  bond) or a disulfide SG–SG ≤ ~2.5 Å, on the 91 held-out cyclics. Target: high closure without
  wrecking quality.
- **Design quality preserved**: DockQ / Cα-RMSD / Consistency on held-out cyclics comparable to
  the general baseline (DockQ ~0.5) — closure guidance must not collapse quality (report the
  tradeoff, per PLAN §4).
- **Diversity** maintained.

## Non-natural monomers — Phase 1b (deferred, with reason)
Requires extending the block vocab (`aas` → include non-natural monomers from the HELM library)
AND the sequence-design head's output space AND the data pipeline to map HELM monomers → block +
atom sets. The atom-level representation already supports the chemistry; the *generative head*
does not yet. This is a real model change (new classes, retrain the head) — scope separately
after natural-residue cyclization works. Head-to-tail + disulfide cyclics with natural residues
already cover a large therapeutic class.

## Risks
- **Guidance may not reliably close** without cyclic training data → do fine-tuning too, not
  guidance alone.
- **Latent-space closure ≠ atom-space closure**: the guidance acts on latent points; the decoded
  terminal atoms may not perfectly meet. Measure closure on **decoded atoms**, not latent, and
  iterate on the guidance target if needed.
- **PepBDB cyclic detection was heuristic** (head-to-tail <2 Å or disulfide) — the 890/799 set is
  a candidate set; spot-check a sample before trusting it as ground-truth cyclic.

## Guidance-only closure smoke — RESULT (2026-09-14)

Ran `closure_smoke.sh` on the existing (linear-trained) checkpoint: 20 valid complexes × 2
attempts, default vs cyclic guidance, `energy_lambda=0.8`.

| | default | cyclic guidance |
|---|---:|---:|
| serialized_rate | 1.00 | 1.00 |
| **mean N-term↔C-term distance** | **19.9 Å** | **6.7 Å** |
| closure_rate (≤ 2 Å) | 0.0 | 0.025 |
| disulfide_rate | 0.0 | 0.0 |
| slide AAR (quality check) | 0.146 | 0.150 |

**Reading:** the closure guidance **works directionally and strongly** — it pulls the termini
from ~20 Å to ~6.7 Å (3×) **with no quality loss** (AAR flat). But true closure (≤2 Å bond) is
only 2.5%, because this checkpoint was trained on **linear** peptides and never learned closed
conformations — exactly the risk noted below. So: **the guidance mechanism is validated; guidance
alone cannot close a linear-trained model.** Greenlight the real Phase-1 step: **fine-tune on the
PepBDB cyclic set** so the prior produces near-closed conformations, then guidance snaps them
shut. Artifacts: `results/closure_smoke/summary_{default,cyclic}.json`.

## Fine-tune attempt (2026-09-14) — BLOCKED on a model↔data compatibility bug

Cyclic data-prep succeeded (**697 train / 77 valid / 88 test** processed cyclic complexes in
S3). The warm-start fine-tune (`cyclic_finetune.sh`) then wired up correctly — data synced,
warm-start checkpoints resolved (AE epoch38 + LDM epoch99), config built (batch 40000, 60
epochs) — but **`train.py` crashed in the LDM forward** on the cyclic data:

```
models/LDM/ldm.py:98  H_0[mask] = H
RuntimeError: CUDA error: device-side assert triggered
```

A device-side assert is almost always an **out-of-range index** (embedding / position lookup),
reported asynchronously. Root hypothesis: the pubmatch model was trained on **PepBench**, but
**PepBDB cyclic** data differs — non-standard residues (`pepbdb.py` flagged `non_standard`) and/or
larger receptors / longer peptides producing position indices the base model's encoding wasn't
sized for. This is a genuine integration bug, not an env paper-cut — do NOT relaunch blindly.

**Diagnostic next step:** rerun a single cyclic batch with `CUDA_LAUNCH_BLOCKING=1` (+ optionally
`TORCH_USE_CUDA_DSA`) through `model.forward` to get the true failing op and the offending index;
then either (a) filter cyclic entries whose residue/atom/position indices exceed the base model's
tables, or (b) extend the model's embeddings/position range. Also worth checking: whether PepGLAD
expects PepBDB processed via its own `pepbdb.py` path to match PepBench tensor conventions (block
counts, position_ids), since the two datasets may not be drop-in interchangeable for a warm-start.

Env fixes already applied along the way (all committed): py3.10 AMI (biopython 1.80), direct
split-index build, `build-essential`+`python3-dev` (moot on py3.10), `tensorboard` for train.py.

## Fine-tune RESULT (2026-09-15) — cyclic fine-tuning clearly works

After fixing the position overflow (filter to peptides < 29 residues: train 697→564, valid
77→64, test 88→68), the warm-start fine-tune (60 epochs on 564 cyclic) trained cleanly, no NaN,
val loss 1.02→0.91. Big improvement over the general baseline on the during-training validation:

| during-training Validation | general baseline | cyclic fine-tuned |
|---|---:|---:|
| Seq/AAR | ~0.06 | **0.19** (rising) |
| Struct/Cα-RMSD | ~12 Å | **6.5 Å** (falling) |

So cyclic fine-tuning substantially improves both sequence and structure recovery — the core
Phase-1 hypothesis holds. Checkpoint synced to S3 (`training/cyclic_ldm/`).

**Open eval-harness bug (not a model failure):** the post-training `generate_validation` run
serialized **0/272** for BOTH default and cyclic guidance, while the during-training sampler
(no energy-guidance, no calibration) produced the good numbers above. So the guided+calibrated
generation path is the culprit — most likely `setup_latent_guidance` on the small cyclic set
gave degenerate `consec_dist` stats → guidance drives coords to NaN/out-of-range → the finite
check rejects every sample. `attempts.json` (with per-sample errors) was not synced, so the next
step is an eval-only run that (a) syncs `attempts.json`, (b) adds a `--guidance none` control to
confirm the fine-tuned model samples fine without guidance, (c) then tunes/repairs calibration
or lowers energy_lambda. The model is good; only the guided-eval tooling needs fixing.

## Phase-1 generation result (2026-09-15) — held-out cyclic test (68 complexes × 4)

The 0-serialized was a path bug (reference PDBs at `mmap_dir/../pdbs`, not `processed/pdbs`),
not calibration. Fixed. Full eval of the fine-tuned cyclic model, 100% serialized all modes:

| guidance | serialized | slide_aar (rand 0.17) | mean N-term↔C-term | closure ≤2Å | disulfide ≤2.5Å | diversity |
|---|---:|---:|---:|---:|---:|---:|
| none | 1.00 | **0.231** | 11.3 Å | 0.4% | 3.5% | 1.00 |
| default | 1.00 | 0.228 | 12.2 Å | 0.0% | 1.3% | 1.00 |
| cyclic | 1.00 | 0.229 | **6.97 Å** | 0.0% | 1.3% | 1.00 |

**Honest read — partial success:**
- **Sequence design improved and is real:** slide_aar 0.231 vs composition-random 0.170 — the
  fine-tuned cyclic model beats baseline by ~0.06, whereas the general PepBench model sat *at*
  baseline (~0.15/0.16). Combined with the during-training gains (AAR 0.06→0.19, Cα-RMSD 12→6.5 Å),
  cyclic fine-tuning clearly helps. Outputs are 100% valid and fully diverse.
- **Closure guidance works directionally but does NOT achieve true macrocyclization:** it pulls
  the termini from 11.3 Å → **6.97 Å** (~40% closer) with no quality loss, but bond-distance
  closure (≤2 Å) stays ~0%. So even with cyclic fine-tuning + guidance, we do not yet produce
  genuinely closed head-to-tail macrocycles.

**Why closure falls short (for the next iteration):**
1. Our "cyclic" training set was heuristic (head-to-tail <2Å OR disulfide) — likely
   disulfide-dominated, so the prior never strongly learned head-to-tail closure.
2. The closure guidance acts in LATENT space (first↔last latent point); latent proximity does
   not fully translate to ~2Å atom-space bond closure (the risk flagged in this doc).

**Next-iteration fixes:** (a) build a head-to-tail-specific cyclic training set (verify actual
N–C peptide bonds, separate from disulfide macrocycles); (b) add an atom-space closure term
(guide the decoded N-term N ↔ C-term C directly, or a post-hoc closure/relax step), since latent
guidance under-reaches; (c) longer fine-tune / more cyclic data. Artifacts:
`results/cyclic_eval/summary_{none,default,cyclic}.json`.

## Immediate first task
Add `set_cyclic_dist` + `cyclic_geometry_guidance` to a fork of `models/LDM/ldm.py`, extend
`setup_latent_guidance.py`, build the cyclic processed split, and run a guided-generation smoke
on the existing checkpoint to measure closure rate **before** any fine-tuning (cheap baseline:
does guidance alone move the closure rate?).
