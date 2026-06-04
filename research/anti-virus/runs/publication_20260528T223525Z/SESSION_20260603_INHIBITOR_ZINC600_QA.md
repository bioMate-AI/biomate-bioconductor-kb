# Session 2026-06-03 — ZINC600 completion, triage, and library Q&A

Publication run: `publication_20260528T223525Z`

## Completed this session

| Item | Artifact | Result |
|------|----------|--------|
| ZINC600 Vina merge | `zinc150_screen/vina/docking_autodock_vina_results.json` | **600/600** SMILES docked (9P3I top pocket) |
| ADMET top 20 | `zinc600_screen/ZINC600_TOP20_ADMET_TRIAGE.md` | 20/20 hits with ADMET-AI |
| Synthesizability top 20 | `zinc600_screen/ZINC600_TOP20_SYNTHESIZABILITY.md` | RDKit SA score; **20/20** SA ≤ 5 |
| Rank-1 pose QC submit | `zinc600_screen/rank1_pose_qc/RANK1_POSE_QC_MANIFEST.json` | GROMACS run `b89f1662` (poll in flight) |
| Merge audit | `zinc600_screen/ZINC600_MERGE.json` | Batch run_ids + merge counts |

### Top Vina hits (full 600-compound screen)

| Rank | Vina (kcal/mol) | ID / notes |
|------|-----------------|------------|
| 1 | **−6.527** | Z600-R1 — guanidine oligomer; needs pose QC before promoting over INH-01 |
| 2 | −6.275 | |
| 3 | −6.267 | **INH-01** — validated lead (ligand RMSD ~0.20 nm) |
| 4 | −6.099 | |
| 5 | −6.065 | |

**Compute lead:** INH-01 until Z600-R1 passes GROMACS pose QC (`poll_zinc600_rank1_pose_qc.py`).

---

## Synthesizability (SA score proxy)

Method: RDKit `Contrib.SA_Score.sascorer` (Ertl & Schuffenhauer, 2009).

| Tier | SA range | Top-20 count |
|------|----------|--------------|
| EASY | ≤ 3 | 2 (ranks 3 INH-01, 15) |
| MODERATE | 3–5 | 18 |
| HARD / VERY_HARD | > 5 | 0 |

**Not run:** SynCraft retrosynthesis (BioMate stub / external API). SA score is a heuristic only — not route feasibility.

Regenerate:

```bash
python3 research/anti-virus/scripts/triage_zinc600_synthesizability.py \
  --publication-run research/anti-virus/runs/publication_20260528T223525Z
```

---

## FAQ — structure origin (existing vs generated)

| Track | Source | New structures? |
|-------|--------|-----------------|
| ZINC600 screen | Pre-existing SMILES from `assets/zinc600_library.smi` | **No** — virtual screening only |
| INH-01 / top 20 | Ranked library hits | **No** |
| Pharmacophore demo (`032000Z`) | 6-compound demo + reference actives | **No** |
| REINVENT4 | Aspirin seed, scaffold decoration | **Attempted; 0 retained** after filters |

No de novo lead is in the publication package. All inhibitor candidates are **existing catalog-style structures** selected by docking/ADMET triage.

Plan A peptides are **natural GP sequence fragments** ranked by MHC binding — selected, not chemically designed.

---

## FAQ — ZINC20 vs 600 compounds

| Scope | Size |
|-------|------|
| **ZINC20 database** (maintained; lead/drug-like focus) | **Millions+** purchasable entries (ZINC22 successor cites 230M+) |
| **This campaign local mirror** | **600 SMILES** — first 600 of ZINC20 2D tranche **AAAC**; see `ZINC600_LIBRARY_PROVENANCE.md` |

### Why 600?

1. **Science gate:** Replace 6-compound demo with **≥500** compounds (`FEEDBACK_CROSSWALK.md`).
2. **Compute budget:** Vina on 9P3I GP tetramer is expensive; batched as **50 compounds/job** (`ZINC600_CHUNK=50`, ~12 Galaxy batches).
3. **Two-phase execution:** ZINC150 first (~145–150 docked May 29) → ZINC600 completion June 3.
4. **Library profile:** Median MW ~163 Da, median LogP ~−1.6 — polar, small, lead-like **curated subset**, not a random ZINC20 draw.

**Important:** 600 is the **entire bundled mirror**, not a statistical sample of ZINC20. Scaling up requires filtered ZINC API queries or vendor subsets, not blind full-database docking.

---

## Merge recovery note

The merged docking JSON can revert if overwritten (e.g. partial re-run). Re-merge:

```bash
python3 research/anti-virus/scripts/poll_merge_zinc600_docking.py
# If Galaxy API unavailable, local cache under zinc600_screen/cache/ holds batch JSONs.
```

Verify: `len(results)` in docking JSON should equal **600** (unique SMILES from `zinc600_library.smi`).

---

## In flight / optional

| Item | Action |
|------|--------|
| Z600-R1 pose QC | `python3 research/anti-virus/scripts/poll_zinc600_rank1_pose_qc.py` |
| IEDB population cross-check | Upload `plan_a_epitope/PLAN_A_CHILE_POP_COVERAGE_INPUT.tsv` vs **48.81%** Chile tier A+B |
| ZINC purchasability | **Done** — `lookup_zinc_purchasability.py` (local tranche + PubChem) |

---

## Library provenance (600 compounds)

**Authoritative doc:** `zinc600_screen/ZINC600_LIBRARY_PROVENANCE.md`

| Question | Answer |
|----------|--------|
| Ad hoc? | **No** — deterministic first **600** lines of ZINC20 2D tranche **AAAC** (`files.docking.org/2D/AA/AAAC.smi`) |
| Ground truth / ANDV SAR? | **No** — no experimental inhibitor panel; reference antivirals not in deck |
| Target-informed? | **No** — no 9P3I pharmacophore pre-filter on library before docking |
| Why 600? | Campaign gate **≥500** compounds + Vina batch economics (~50/job) |

**Assets (2026-06-04):**

- `assets/zinc600_library.smi` — Vina input (SMILES only, legacy)
- `assets/zinc600_library.tsv` — `zinc_substance_id` + `smiles`
- `assets/zinc600_library.manifest.json` — selection metadata

Regenerate IDs/manifest:

```bash
python3 research/anti-virus/scripts/build_zinc600_library_manifest.py \
  --publication-run research/anti-virus/runs/publication_20260528T223525Z

python3 research/anti-virus/scripts/lookup_zinc_purchasability.py \
  --publication-run research/anti-virus/runs/publication_20260528T223525Z --top-n 5
```

New downloads (preserve IDs):

```bash
python3 research/anti-virus/scripts/download_open_screening_library.py \
  --source zinc --max-compounds 600
```
