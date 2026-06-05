# ZINC600 library — provenance and design rationale

**File:** `assets/zinc600_library.smi`  
**Count:** 600 SMILES (unique)  
**Last verified:** 2026-06-04

---

## Short answer

The 600 compounds are **not** an ad hoc hand-picked set and **not** ANDV-target-informed ground truth. They are the **first 600 SMILES** from a single **ZINC20 2D tranche download** (`AA/AAAC.smi` on `files.docking.org`), chosen to satisfy a **campaign scale gate (≥500 compounds)** and compute budget—not because of known ANDV inhibitor chemistry.

---

## How the library was built

| Step | What happened |
|------|----------------|
| 1 | `download_open_screening_library.py --source zinc --max-compounds 600` |
| 2 | Default URL: `https://files.docking.org/2D/AA/AAAC.smi` (~1,013 compounds in tranche) |
| 3 | Output: `research/anti-virus/libraries/zinc20_2d_aaac_20260510T040610Z.smi` |
| 4 | `launch_andv_publication_campaign.py` copied that file → `assets/zinc600_library.smi` |
| 5 | Uploaded to S3: `…/publication_20260528/zinc600_library.smi` |

**Important bug/loss:** the download script writes **SMILES only** (drops `zinc_id` column). Purchasability lookup must use tranche re-match or fix the downloader to emit `zinc_id<TAB>smiles`.

---

## What guidance existed (and what did not)

### Present (operational / methods gates)

| Guidance | Source |
|----------|--------|
| Replace 6-compound demo with **≥500** compounds | `FEEDBACK_CROSSWALK.md` / expert review |
| Use real ZINC purchasable space (not Delaney ESOL benchmark) | `download_open_screening_library.py` `--source zinc` |
| Batch size **50 compounds/job** for Vina on 9P3I | `track_zinc600_docking_batch.py` |
| Two-phase screen: **ZINC150** ADMET pilot → **ZINC600** full dock | campaign logs May–Jun 2026 |

### Absent (no ground truth / target knowledge)

| Missing | Implication |
|---------|-------------|
| No ANDV GP pocket pharmacophore pre-filter on the 600 | Library not tailored to 9P3I features before docking |
| Reference antivirals **not included** in the 600 (0/4 overlap) | Ribavirin/favipiravir etc. are separate `reference_actives` |
| No experimental ANDV inhibitor SAR | Hits are compute-ranked only |
| No claim that AAAC tranche covers “correct” chemotype | AAAC is one arbitrary ZINC20 2D cell |
| Not a random draw from full ZINC20 | **Deterministic:** first 600 lines of AAAC tranche |

---

## Physicochemical profile (explains hit types)

Computed from RDKit on all 600 SMILES:

| Property | Median | Range |
|----------|--------|-------|
| MW (Da) | 163 | 64 – 199 |
| LogP | −1.57 | −3.83 – −1.0 |
| TPSA (Å²) | 85 | 31 – 170 |
| HBD | 3 | 0 – 7 |

This is a **polar, small-molecule / fragment-like** slice of ZINC—not drug-like lipophilic lead space. Top Vina hits (guanidine-rich scaffolds) are consistent with that chemistry.

---

## ZINC IDs (recoverable)

Exact order match: `zinc600_library.smi` == first 600 entries of `AAAC.smi`.

Example — **INH-01** (`N=C(N)NC(=O)c1nccnc1N`): **ZINC33753639** (substance id in tranche file; map to ZINC000… via CartBlanche/substances API).

Regenerate lookup:

```bash
python3 research/anti-virus/scripts/lookup_zinc_purchasability.py \
  --publication-run research/anti-virus/runs/publication_20260528T223525Z \
  --backend local_tranche --backend pubchem
```

---

## Honest manuscript framing

**Say:** “We screened a **600-compound subset** of the ZINC20 purchasable catalog (2D tranche AAAC) against the 9P3I pocket as a **methods-scale virtual screen**, not an exhaustive ZINC20 search or target-informed library design.”

**Do not say:** “ZINC20 representative sample,” “ANDV-guided library,” or “ground-truth hit list” without experimental validation.

---

## Recommended upgrades (backlog)

1. Re-download with **`zinc_id<TAB>smiles`** preserved in library manifest.
2. **Target-informed deck (done):** `zinc600_pharmacophore/` — antiviral-reference pharmacophore filter on the AAAC 600 → **91** compounds (`filter_zinc_library_pharmacophore.py`). Next: Vina dock filtered deck.
3. Include reference actives + known hantavirus small molecules in every screen deck.
4. Expand beyond one tranche when claiming “broader chemical space.”
