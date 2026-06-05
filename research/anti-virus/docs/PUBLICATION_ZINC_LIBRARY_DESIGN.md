# Publication-scale ZINC library — design survey

**Status:** v1 built (2026-06-05); Vina docking **in progress** (~5006 compounds, chunked)  
**Context:** ZINC600 (AAAC first-600) is **blog / methods-demo tier**, not publication HTS.  
**Evidence:** `zinc600_screen/ZINC600_LIBRARY_PROVENANCE.md`, pharmacophore compare `zinc600_pharmacophore/vina/`

---

## Executive summary

| Tier | Compounds | Purpose | Claim level |
|------|----------:|---------|-------------|
| **Demo** | 6 | Chained pipeline wiring | Internal QA only |
| **Blog / methods** | **600** (AAAC slice) | BioMate workflow at scale, provenance demo | “We executed a reproducible funnel on a **documented** purchasable subset” |
| **Publication HTS** | **2,000–5,000** (target) | Target-informed virtual screen | “Pharmacophore-filtered purchasable deck from **multiple** ZINC20 tranches, docked on 9P3I” |

The current 600 design **does not** support publication claims about chemical-space coverage or lead discovery. It **does** support a blog post on professional workflow (provenance → filter → dock → QC → honest negatives).

---

## Why 600 is the wrong size *for publication*

### What 600 actually is

- **Not** ad hoc: first 600 lines of tranche **AAAC** (`files.docking.org/2D/AA/AAAC.smi`, ~1,013 compounds total).
- **Not** target-informed before docking (pharmacophore filter added later → 91/600 pass).
- **Chemically narrow:** median MW **163 Da**, median logP **−1.57** — polar / fragment-like slice.

### What we learned from the professional follow-on (91 pharmacophore + Vina)

| Observation | Implication |
|-------------|-------------|
| 91/600 pass antiviral-reference pharmacophore (15%) | Pre-filter works; AAAC is mostly non-matching polar noise |
| Top 5 Vina hits **identical** raw vs pharmacophore deck | Library chemistry dominated outcome before pocket physics |
| INH-01: −6.267 (600) vs −6.208 (91-deck) | Rank stable; score noise < 0.1 kcal/mol |
| Z600-R1 beats INH-01 on Vina; INH-01 wins on pose QC | Publication must separate **score** from **lead** |

**Verdict:** 600 is an excellent **blog** dataset. For a paper, reviewers will ask: *Why this slice? Why not drug-like space? Why not multi-tranche?* — and AAAC-first-600 has no good answer.

---

## ZINC20 tranche survey (files.docking.org, 2026-06-05)

ZINC20 2D tranches are indexed by **MW bin × logP bin × reactivity × purchasability** (see [ZINC 2D index](https://files.docking.org/2D/)).

### Current campaign slice

| Tranche | Lines | Role in campaign |
|---------|------:|------------------|
| **AAAC** | 1,013 | Entire AAAC used as 600-head slice — **smallest useful cell we picked** |

### Neighboring AA row (same MW bin as AAAC — smallest / most polar)

| Tranche | Lines |
|---------|------:|
| AAAA | 3,731 |
| AAAB | 4,108 |
| AAAD | 16,546 |
| AAAE | 213,812 |
| AAEE | 39,971 |

AA row is dominated by **polar, low-MW** chemistry — good for explaining guanidine-like Vina hits, poor for drug-like HTS claims.

### Drug-like band (MW bin B, moderate logP — publication candidates)

| Tranche | Lines | Notes |
|---------|------:|-------|
| **ABAA** | 16,718 | In-stock–leaning codes; larger MW than AA |
| **ABAB** | 16,494 | Pair with ABAA for diversity |
| **ABAC** | 2,218 | Smaller cell |
| **BBAA** | 5,084 | Mid logP |
| **BCAC** | 1,626 | |
| **BCAA** | 21,095 | Large; use with cap |
| **BCAB** | 52,863 | Very large; subsample or exclude from first pass |

**Merged raw pool (recommended v1):** ABAA + ABAB + ABAC + BBAA + BCAC ≈ **42,000** purchasable lines (before dedup).

**Pass rate estimate:** pharmacophore min_features=3 on AAAC gave **15%**. On broader AB/BB tranches expect **5–20%** (validate on 1k sample before full merge).

**After pharmacophore filter:** 42k × 10% ≈ **4,200** → aligns with publication target **2k–5k docked**.

---

## Recommended publication library design (v1)

### Step 0 — Controls (always in deck)

| Source | Compounds |
|--------|-----------|
| `reference_actives_antiviral.smi` | ribavirin, favipiravir, umifenovir, oseltamivir |
| Campaign leads | INH-01 SMILES, Z600-R1 SMILES |
| Demo triad | aspirin, paracetamol, phenol (optional; supplement only) |

Dedup by canonical SMILES; never drop controls.

### Step 1 — Tranche union (raw universe)

```
ABAA.smi + ABAB.smi + ABAC.smi + BBAA.smi + BCAC.smi
→ dedup by SMILES
→ retain zinc_substance_id (TSV, not SMILES-only)
```

**Manifest fields:** `source_tranche_url[]`, `selection_method: multi_tranche_union`, `target_informed: false` (at this step).

### Step 2 — RDKit drug-like gate (fast)

| Rule | Threshold |
|------|-----------|
| MW | 150–500 Da |
| logP | −2 to +5 |
| TPSA | ≤ 140 Å² (soft) |
| HBD | ≤ 5 |
| HBA | ≤ 10 |

Drops fragments; keeps lead-like space AB tranches represent.

### Step 3 — Pharmacophore filter (target-informed)

- Model: antiviral reference actives (same as `filter_zinc_library_pharmacophore.py`)
- `min_features = 3` (match BioMate `pharmacophore_filtering` default)
- Output: `publication_zinc_pharmacophore_filtered.tsv`

### Step 4 — Cap and stratify

| Parameter | Value |
|-----------|-------|
| Max dock set | **5,000** (hard cap) |
| If over cap | stratified random sample within matched feature-count bins |
| Min dock set | **2,000** (if pass rate too low, add BBAB/BCAA tranche and re-filter) |

### Step 5 — Dock + QC (same box as campaign)

- Receptor: 9P3I rigid (`s3://…/9P3I.pdb`)
- Box: top pocket from `01_pocket/structure_pockets.json`
- Batch: 50 SMILES/job (proven on ZINC600)
- **Estimate:** 5,000 / 50 = **100 Batch jobs** (~2–6 h wall time, feasible)

### Step 6 — Science gates before manuscript language

| Gate | Publication bar |
|------|-----------------|
| Provenance manifest | Every compound: ZINC substance ID + selection stage |
| Pharmacophore pass rate reported | Not hidden |
| Reference actives docked | Included in results table |
| Ensemble / pose QC on top 10–20 | Required for lead claims |
| Compare to 600 blog deck | Supplement only — “methods-scale pilot” |

---

## Does the current design make sense?

| Question | Answer |
|----------|--------|
| Was 600 a reasonable **first** step? | **Yes** — satisfied ≥500 gate, proved Batch Vina, exposed chemotype bias honestly |
| Is 600 enough for **publication**? | **No** — single polar tranche, no pre-filter, ~1k max cell |
| Is pharmacophore-on-600 enough? | **No** — 91 compounds still same top chemotypes; filters noise, not space |
| Is multi-tranche + pharmacophore + 2–5k dock sensible? | **Yes** — matches ZINC architecture, compute budget, and reviewer expectations |
| Should publication mention 600? | **Yes, as pilot** — blog/methods sidebar, not primary HTS |

---

## Implementation backlog (publication lane)

1. `build_publication_zinc_library.py` — multi-tranche download + TSV + manifest  
2. Extend `filter_zinc_library_pharmacophore.py` — drug-like gate + multi-tranche input  
3. `run_publication_zinc_docking.py` — chunked Vina (reuse `run_zinc_pharmacophore_docking.py` pattern)  
4. Manuscript v1.3 inhibitor — move HTS claims to publication deck; relegate 600 to supplementary methods pilot  

---

## References (internal)

- Blog tier provenance: `runs/publication_20260528T223525Z/zinc600_screen/ZINC600_LIBRARY_PROVENANCE.md`
- Pharmacophore pilot: `runs/publication_20260528T223525Z/zinc600_pharmacophore/`
- Downloader: `scripts/download_open_screening_library.py`
- Feedback gate: `runs/publication_20260528T223525Z/FEEDBACK_CROSSWALK.md` (≥500 compounds = methods milestone, not HTS endpoint)
