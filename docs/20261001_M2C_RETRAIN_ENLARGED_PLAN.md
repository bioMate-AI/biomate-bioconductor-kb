# M2c Retrain on the Enlarged Bound-Cyclic Corpus — Review Note (ready-to-run, NOT launched)

**Date:** 2026-10-01
**Launcher:** `research/guangzhou_all_atom/launch_m2c_retrain_enlarged.sh`
**Status:** Reviewed, dry-verified, **NOT launched**. One hard blocker must be cleared first (see §6.1).

---

## 1. What this run does (one paragraph)

Retrain the PepGLAD-M2c target-conditioned cyclic-peptide generator on an **enlarged** bound-complex
corpus, on the **pre-baked AMI** (`ami-06e366a5b89d12344`, us-west-2) so it skips the torch/torch-scatter
cold install. It is `run_m2c_ldm_finetune.sh` (the proven 235-complex D2 retrain) with exactly three
deltas and nothing else reinvented:

1. **AMI** = the baked cyclic-peptide image; the driver `source`s `/opt/pepglad-venv` instead of building
   a venv. Only two small fast top-ups remain (not the heavy install the AMI saves): `gemmi` (optional cif
   staging accel; biopython `MMCIFParser` is the built-in fallback) and the DockQ v1.0 build toolchain
   (`git build-essential gfortran` — `evaluation.dockq` git-clones+makes DockQ on first import; the bake
   did not prebuild it).
2. **Corpus** = existing D2 `bound_cyclic_v1` (235) ∪ newest `d2-mine` output (`MINE_S3`) ∪ the
   `suitable:true` approved-drug co-crystals from `data/approved_cocrystals.json`. Merged + deduped on the
   instance into **one** d2-dir, then fed to the **same** `m2c_process_complexes.py`.
3. **Spot-first, on-demand fallback** (user-authorized): the spot GPU ladder runs first; if every spot
   combo is out of capacity, the same type/subnet ladder is retried on-demand. Self-terminate + dead-man's
   switch + 60 s S3 checkpoint streaming unchanged.

---

## 2. Corpus assembly (exact, verified against real data)

Merge is done on-instance by an embedded `merge_corpus.py`. Dedup key = index `pdb_id` (e.g. `7T11_P`);
first source to carry an id wins, priority **v1 → mine → cocrystals** (so a PDB already in the mine keeps
its *real* `peptide_seq` rather than a co-crystal's blank).

Dry-run against real local data (`data/bound_cyclic/v1` as existing-D2, `data/bound_cyclic/v2` (776) as a
mine stand-in, `data/approved_cocrystals.json`):

| Source | Entries |
|---|---|
| existing D2 v1 index | 235 |
| mine index (local v2 stand-in) | 776 |
| v1 ∪ mine (deduped) | 839 |
| suitable co-crystals **added** | 18 |
| **merged total** | **857** |

- **Co-crystals:** 21 `suitable:true` records → 19 unique `(pdb, pep_chain)` (7T11 appears 3× for
  octreotide + 2 dotatate radiopharmaceuticals → 1) → **18 added** (1CWA ciclosporin already present in the
  mine → deduped, keeps the seq-bearing mine copy). Eptifibatide uses the **8T2U** cleaner structure
  (full-length αIIbβ3 + eptifibatide, no Fab), per the task — overridden from the JSON's primary 2VDN.
- **GPCR fusion-chain stripping is automatic:** the merged index names only `[receptor, peptide]`, and
  `process.py → stage_one` extracts exactly those two chains, dropping Gα/Gβ/Gγ/Nb/scFv for free. No manual
  stripping code needed.
- **Expected counts framing (task):** 235 existing + ~N mine (local v2 shows ~541 net-new beyond v1; the
  real `d2-mine-local` upload decides N) + ~18 co-crystals, deduped → **~857 (with the current local mine)**.

### read_d2 + split dry-verification (real processor functions)

| Check | Result |
|---|---|
| `read_d2` rows | 857 |
| rows with real `peptide_seq` | 839 |
| rows with empty seq | 18 — **exactly** the 18 co-crystals (no other row lost its seq) |
| clusters (`id_th=0.6`) | 229 |
| split (processor default **seed=12**, pre-filter) | train 681 / valid 88 / test 88 |
| **max train/test peptide identity** | **0.571 < 0.6 → NO LEAKAGE** |
| co-crystals landing in test/val | 8 (5 test + 3 val) → **all moved to train by the default pin step** |

`m2c_process_complexes.py` is run **unchanged** (preserves the 235-baseline's reproducibility). The split
uses its default `--seed 12` (launcher does not override it).

---

## 3. Train / eval flow (unchanged from the 235 launcher)

1. **Warm-start:** epoch-221 LDM diffusion (`WARM_LDM_S3`) + frozen v1 AE (`V1_AE_S3`, `AE_MODE=v1` —
   matches the DockQ-0.437 released ckpt).
2. **Process:** `m2c_process_complexes.py` stages each complex's mmCIF from RCSB via PepGLAD's own
   converters → stock `process.py` mmap → leakage-aware whole-cluster split.
3. **(default) Pin co-crystals to train** (see §4).
4. **Train:** `m2c_train_ldm.py` (stock LDMPepDesign + CoDesignDataset), 40 epochs, lr 1e-5.
5. **Eval:** `m2c_eval.py` → official `setup_latent_guidance → generate.py → cal_metrics.py` panel on the
   held-out test (DockQ + Slide AAR + RMSD(CA) + Diversity + Consistency). dG N/A (no pyrosetta).
6. **Upload:** ckpts, `m2c_eval_result.json`, `dataset_manifest.json`, `merge_report.json`,
   `gen_codesign/` to `s3://.../runs/m2c-retrain-enlarged-<stamp>/`.

---

## 4. DockQ baseline to beat

The 235-corpus M2c run (`s3://.../runs/m2c-ldm-finetune-20260930T153507Z`) scored:

- **DockQ = 0.4354** (released-ckpt note calls it **0.437**) on its **24-complex** held-out test.
- SOTA PepGLAD DockQ = **0.592** (the gap this run tries to close with ~3.6× more real bound complexes).
- Companion metrics at baseline: Slide AAR 0.232, RMSD(CA) 4.63 Å, Consistency 0.915, diversity ~0.78.

**Success criterion:** test-set DockQ **> 0.437** (ideally toward 0.5+), with no leakage inflation
(the split keeps max train/test identity < 0.6, verified).

---

## 5. Design decision: pin approved-drug co-crystals to TRAIN (default ON)

Co-crystal rows carry a **blank** `peptide_seq` (the curated JSON has no sequence) → each is a **singleton
cluster**. A singleton can land in test/valid, which (a) spends a rare real-drug complex on evaluation
instead of training, and (b) leaves a residual leakage path: if the *same* peptide also appears in the mine
with a real seq, blank-vs-real identity = 0, so they never co-cluster and could split train/test.

`COCRYSTALS_TO_TRAIN=1` (default) moves any co-crystal id out of test/valid into train **after** the split.
This is the root-cause-correct choice: all real approved drugs train the generator; the held-out test then
measures generalization on **mined experimental complexes with proper sequence clustering**. Verified: the
pin step moves exactly the test/valid co-crystals, leaves non-co-crystals untouched, no duplication. Set
`COCRYSTALS_TO_TRAIN=0` to disable.

---

## 6. Blockers & risks (read before launching)

### 6.1 BLOCKER — the mine output is not on S3 yet
Both EC2 `d2-mine` runs **FAILED** and produced no manifest:
- `s3://.../runs/d2-mine-20260930T204156Z/status/status.json` → `{"stage":"failed"}`
- `s3://.../runs/d2-mine-20261001T043807Z/status/status.json` → `{"stage":"failed"}`

There is **no** `d2-mine-local-*` prefix on S3. `MINE_S3` is a **required** env var and the launcher
**preflights** it (fails before spending an instance if `MINE_S3/index.txt` or
`MINE_S3/bound_cyclic_manifest.jsonl` is missing). **Action before launch:** upload the locally-mined
corpus (the repo has `data/bound_cyclic/v2` = 776 complexes). Example:
```bash
BUCKET=knowledge-datasets-1759951976; STAMP=$(date -u +%Y%m%dT%H%M%SZ)
aws s3 cp research/guangzhou_all_atom/data/bound_cyclic/v2/bound_cyclic_manifest.jsonl \
  s3://$BUCKET/cyclic_peptide/runs/d2-mine-local-$STAMP/bound_cyclic_manifest.jsonl
aws s3 cp research/guangzhou_all_atom/data/bound_cyclic/v2/index.txt \
  s3://$BUCKET/cyclic_peptide/runs/d2-mine-local-$STAMP/index.txt
MINE_S3=s3://$BUCKET/cyclic_peptide/runs/d2-mine-local-$STAMP \
  ./research/guangzhou_all_atom/launch_m2c_retrain_enlarged.sh
```
(If a fresh/larger mine finishes first, point `MINE_S3` at that dir instead.)

### 6.2 DATA QUALITY — ~33% of the corpus is insulin
The single largest sequence cluster is **286 members, all length-21 peptides** (ids `1A7F, 1AI0, 1AIY,
1APH, 1B17, 1B18, …` = **insulin / insulin analogs**, 22 distinct seqs chained by single-linkage). If the
mine = local v2, insulin is **~286/857 ≈ 33%** of the corpus. Whole-cluster split keeps them together
(no leakage), but the generator will be **insulin-biased**. **Recommendation:** dedup/cap insulin in the
*mine* (root cause) before this retrain, or add a per-cluster cap. The launcher **does not** silently cap —
it faithfully assembles the specified corpus and streams `merge_report.json` + `dataset_manifest.json` so
you can inspect the insulin fraction early and abort cheaply if undesired. (Decide this before launch.)

### 6.3 Split seed fragility (informational — default is safe)
Because test/valid fill whole clusters first, a giant cluster landing early can inflate a split. Seed sweep:
the **test** set never balloons (always 86–96 ≈ 10%), but seeds 7/99/2024 balloon **valid** (300+) when the
286-insulin cluster lands there, starving train. The processor's **default seed=12 is healthy**
(train 681 / valid 88 / test 88) and the launcher uses it. No action needed unless you override `--seed`.

### 6.4 Multi-chain receptors — single rec_chain only
`process.py` uses one receptor chain. Co-crystals with interface spanning two receptor chains
(eptifibatide 8T2U αIIb+β3, atosiban 9UWI, calcitonin 5II0) keep only the **first** chain → pocket may be
under-represented. This matches `process.py`'s design (same honest limiter documented in
`m2c_process_complexes.py`). Harmless; noted.

### 6.5 Low-priority co-crystals may drop at staging
Nosiheptide 2ZJP (protein + 23S rRNA, 3.7 Å ribosome; rec_chain sanitized to `F`) and thiostrepton 2JQ7
(NMR, protein + RNA) are giant/odd assemblies. They may fail the interface/pocket or parse filters and be
dropped — harmless (merge/stage drops are counted in the manifest, never silent zeros). The 16 clean GPCR/
enzyme co-crystals (cyclosporin, voclosporin, zilucoplan, setmelanotide, the GPCR-peptide tier, etc.) are
the value.

### 6.6 Baked-venv top-ups
`gemmi` is **not** in `/opt/pepglad-venv` (bake installed it only in the `bg`/`mmg` conda envs) — the driver
pip-installs it (non-fatal; MMCIFParser fallback). The DockQ toolchain is apt-installed at runtime; the 235
launcher did the same on the same AMI lineage successfully, so DockQ should build. If apt fails, eval
reports **DockQ unavailable** (never a silent 0).

---

## 7. Expected outcome (prediction, per the "review before deploy" rule)

Given the 235-run dropped ~25% (235 → 175 usable: 7 stage-fail, 52 interface/pocket, 1 degenerate pocket),
expect the merged **~857 → ~640–680 usable**, split roughly **train ~640 / valid ~85 / test ~85** (seed 12,
all 18 co-crystals pinned to train). `merge_report.json` will show `n_cocrystals_added≈18`,
`n_merged_index≈857` (exact N depends on the real mine upload). `dataset_manifest.json` should report
`max_train_test_peptide_identity < 0.6`. Eval produces a `DockQ` on the held-out test to compare against
**0.437**. If `merge_report` shows insulin ≫ 30% of the corpus, consider aborting and de-duping the mine
first (§6.2).

---

## 8. Files

- **Launcher:** `research/guangzhou_all_atom/launch_m2c_retrain_enlarged.sh` (bash `-n` clean; embedded
  `merge_corpus.py` and pin script both `py_compile`-clean and functionally tested on real data).
- **Reuses unchanged:** `m2c_process_complexes.py`, `m2c_train_ldm.py`, `m2c_eval.py`, `m2_train_ldm.py`,
  `m1_closure_ae.py`, `m1_peptide_dataset.py`, `m2_peptide_ldm.py`, the three `m2c_*.yaml`, and
  `runtime/PepGLAD`.
- **Co-crystal source:** `research/guangzhou_all_atom/data/approved_cocrystals.json`.
