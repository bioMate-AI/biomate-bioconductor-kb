# peptide_corpus — D0: cyclic-peptide corpus assembly v1 + freeze eval

**Lane D / D0** of the peptide parallel work plan
(`docs/20260927_PEPTIDE_PARALLEL_WORK_PLAN.md`). Implements **Part A + the 4 blocking
data-quality fixes + the leakage/eval-freeze gate** from
`docs/20260927_CYCLIC_CORPUS_AND_TRAINING_STRATEGY.md`.

**Status:** CPU-only ETL. **No GPU, no training, no model touched.** This is *convergence
point ①*: it gates ALL downstream training (M0/M1/M2) by producing one clean schema + a
FROZEN family-disjoint eval set + a leakage report, so no training run can leak the standard
CREMP benchmark into itself.

## What it does — the 4 fixes, one stage each

| Fix | Stage file | What it does | Gate |
|---|---|---|---|
| **#1 HELM2 monomer canonicalization** | `stage1_helm_canon.py` | maps cross-source monomer spellings (Hyp/Aib/Nle/Sar/…) to a canonical alphabet; rebuilds a canonical HELM per record | HELM→SMILES→HELM round-trip on 200 random entries (RDKit HELM where its monomer lib supports it, else a token-level idempotence+reparse round-trip) |
| **#2 SMILES standardization + priority-merge dedup** | `stage2_standardize_dedup.py` | RDKit MolStandardize (normalize → uncharge → canonical tautomer, stereo preserved); dedup on the standardized **stereo-sensitive** InChIKey; exact-match keep order **PDB > NMR > xTB-CREMP > ETKDG**; **merges labels** across duplicates | parse-failure count, duplicates removed, labels merged |
| **#3 conformer provenance tag** | `stage3_provenance.py` | validates every record carries a legal `{PDB_experimental\|NMR_experimental\|xTB_CREMP\|HighFold3\|ETKDG\|none}` tag (assigned at ingest in `sources.py`); tallies the corpus by provenance | raises if any loader forgot a tag; reconciles `has_structure` |
| **#4 cyclic-aware split (NOT Bemis-Murcko)** | `stage4_split.py` | sequence-identity clustering (≤40%, cyclic-rotation aware) + Tanimoto single-linkage (Morgan r=2, 2048-bit) family clustering; **freezes eval first** (premium CREMP-measured → then whole family-disjoint clusters, test+val interleaved); assembles train from the **remainder** | leakage report: test→train nearest-pair Tanimoto table; target **median < 0.35** (see congeneric caveat) |

Orchestrated by `build_cyclic_corpus_v1.py`. Sources loaded by `sources.py`. Shared record
schema in `schema.py`. Unit tests in `test_build_cyclic_corpus.py`.

## Sources (fix #3 provenance assigned at ingest)

| Source | Local file / S3 dataset | Provenance | Notes |
|---|---|---|---|
| **CycPeptMPDB** | `../guangzhou_all_atom/data/raw/CycPeptMPDB_Peptide_All.csv` (present) | `none` | SMILES-rich / **structure-poor** (no coords in CSV); measured log Papp kept as a label. Reuses the validated monomer parser in `cycpeptmpdb_to_pepglad.py`. |
| **approved cyclic drugs** | `../guangzhou_all_atom/data/approved_cyclic_peptide_drugs.csv` | `none` | SMILES-only unless a PDB is attached. |
| **CREMP** | `s3://…/cyclic_peptide/datasets/cremp*/` → `<staging>/cremp/summary.csv` (+ `measured_perm.csv`) | `xTB_CREMP` | the ~3,258 measured-permeability entries → **premium_eval** (frozen, never in train w/o a flag). |
| **PepBDB / PepBench** | `s3://…/pepbdb/…pepbdb_cyclic_index.json` → `<staging>/pepbdb/` | `PDB_experimental` | bound complexes with structure — the generator's scarce resource. |
| **BindingDB-peptide** | `s3://…/bindingdb_peptide/…subset.csv` → `<staging>/bindingdb_peptide/` | `none` | affinity labels (Ki/Kd/IC50). |

Only the two local CSVs run end-to-end here. The S3 loaders are thin adapters written to the
known dataset layout (`../guangzhou_all_atom/collect_cyclic_datasets.sh`); pull + extract the
tarballs into a staging dir and pass `--staging <dir>` — no code change needed.

## Usage

```bash
cd research/peptide_corpus

# unit tests (fast, no data)
python3 test_build_cyclic_corpus.py

# local smoke (first 1200 CycPeptMPDB rows, skip slow tautomer)
python3 build_cyclic_corpus_v1.py --out cyclic_corpus_v1 --limit 1200 --no-tautomer

# full local CycPeptMPDB (~22s w/o tautomer; tautomer is much slower on macrocycles)
python3 build_cyclic_corpus_v1.py --out cyclic_corpus_v1 --no-tautomer

# full corpus once CREMP/PepBDB/BindingDB are pulled from S3 + extracted
python3 build_cyclic_corpus_v1.py --out cyclic_corpus_v1 --staging /path/to/cyclic_staging
```

## Output — `cyclic_corpus_v1/`

| File | Contents |
|---|---|
| `records.jsonl` | every deduped record in the ONE schema (`schema.new_record`): `std_smiles`, `inchikey`, `helm_canonical`, `conformer_provenance`, `labels`, `cluster_id`, `split`, `eval_frozen`, `premium_eval`, … |
| `eval_frozen.jsonl` | the frozen held-out eval set (test+val), family-disjoint |
| `premium_eval.jsonl` | the CREMP measured-permeability premium eval subset |
| `train.jsonl` | training remainder (assembled AFTER the freeze) |
| `leakage_report.json` | all 4 gate results + the train/test nearest-pair Tanimoto table |
| `manifest.json` | build provenance (per-stage counts, sources present, dep versions, timing) |

## Realistic post-dedup unique count

- **CycPeptMPDB alone:** CSV = 8,466 rows → **7,988 unique** after standardize+dedup on the
  stereo-sensitive InChIKey (478 removed). The committee's "~7,334" figure sits between this
  and the connectivity-skeleton collapse (3,214, stereo-**insensitive** — which over-merges
  genuine stereoisomers and is reported only as an audit number). We keep stereoisomers
  distinct (they are different molecules), so ~7,988 is the honest CycPeptMPDB count.
- **Full corpus (with CREMP/PepBDB/BindingDB):** committee estimate **~36–42k unique**,
  CREMP-dominated. `31M conformers ≠ 31M molecules` — the model lane must sample **per
  molecule**. The pipeline will report the actual number once the S3 datasets are staged.

## The congeneric-corpus caveat (important — read before trusting the leakage PASS)

CycPeptMPDB is a **congeneric library**: the median molecule's nearest neighbor is **~0.91
Tanimoto**, and even the most-isolated molecule has a neighbor at ~0.56. **No family-disjoint
split can reach median test/train Tanimoto < 0.35 on CycPeptMPDB alone** — the <0.35 bar is
only meaningful on the full **chemically-diverse** corpus (CREMP-dominated ~36–42k).

So on the CycPeptMPDB-only subset the report shows:
- `leakage_gate.PASS = false` (0.55 median > 0.35) — honest, not a bug;
- `intrinsic_corpus.median_nearest_neighbor_tanimoto ≈ 0.91` — the **data floor** that makes
  0.35 unreachable;
- `PASS_or_congeneric_ceiling = true` and `near_duplicate_leak = false` — the actual guarantee
  the split *does* enforce: **no near-duplicate (Tanimoto > the family-cluster threshold)
  straddles the split** (max test→train Tanimoto == the cluster threshold, by construction).

Re-run the gate on the full corpus for the real <0.35 verdict. A single congeneric
**megacluster** (single-linkage chains the bulk into one component) is correctly routed
entirely to **train**; only the family-distinct remainder forms the held-out eval. A future
upgrade (documented, not built here) is a **Tanimoto-MaxMin sub-split *inside* the megacluster**
to enlarge the held-out set on very congeneric corpora.

## Dependency caveats

- **RDKit** ≥ 2023 with **MolStandardize** — required (verified 2026.03.3 locally). Stage 2/4
  hard-fail without it.
- **networkx** — only needed by the sibling `cycpeptmpdb_to_pepglad.py` residue partition, not
  by this D0 pipeline.
- **HELM round-trip:** RDKit's `MolFromHELM` only knows a **core** monomer set and silently
  returns `None` for CycPeptMPDB's non-canonical tokens (Abu/Sar/Me_Bmt/…). Those fall back to
  a token-level idempotence+reparse round-trip (reported as `n_token_level_fallback`). For a
  **true structural** HELM→SMILES→HELM on the non-canonical monomers, wire the **PistoiaHELM
  monomer library** (already on S3 as `helm_monomers`) into a HELM2 expansion step — that is the
  one dependency this pipeline stubs rather than fully implements.
- **Tautomer canonicalization** is O(2^sites) and slow on large macrocycles; capped at
  `_TAUTOMER_MAX_HEAVY=70` heavy atoms and skippable via `--no-tautomer` for large runs.
