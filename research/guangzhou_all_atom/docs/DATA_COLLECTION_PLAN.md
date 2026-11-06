# Cyclic-peptide data collection plan (training + test)

Goal: collect the additional training/test data for the cyclic-peptide direction
(INNOVATION_ASSESSMENT.md §6), beyond the baseline already staged in S3. Every dataset is
pinned, hash-verified, uploaded to `s3://knowledge-datasets-1759951976/cyclic_peptide/datasets/`,
and read back before use. Acquisition manifests record exact source revision, bytes, and SHA256.

## Already in S3 (do NOT re-collect)
- **PepBench v2** — `datasets/pepbench/v2/` : train_valid, LNR held-out test, ProtFrag, README (structural peptide–protein complexes; baseline train/test).
- **CycPeptMPDB** — `raw/CycPeptMPDB_Peptide_All.csv` (permeability, ~19 MB).
- **PepMSND** (PeptideCLM-2) — `datasets/peptideclm2_pepmsnd/` (stability; folds rebuilt in `derived/pepmsnd_stability_folds/`).
- **MacroConf** — `datasets/macroconf/` (solution-NMR conformations, 68 macrocycles).

## To collect (this plan)

| # | Dataset | Source (pinned) | ~Size | Purpose | Where |
|---|---------|-----------------|-------|---------|-------|
| 1 | **PepBDB** peptide–protein complexes | huanglab pepbdb-20200318.tgz | 691 MB | structural breadth; extract **cyclic** subset for the cyclic-peptide plugin | AWS |
| 2 | **RCSB cyclic-peptide complex index** | RCSB search API (macrocyclic peptide + protein) | small | curated PDB-ID train/test manifest, structure-disjoint | AWS |
| 3 | **BindingDB peptide subset** | bindingdb.org All-TSV (current release) | ~1.5 GB raw → small subset | binding-affinity conditioning / property labels | AWS |
| 4 | **HELM monomer library** | PistoiaHELM/HELMMonomerSets (pinned commit) | ~2 MB | non-natural monomer + building blocks for cyclic/stapled/N-Me/D-AA representation & synthesizability-by-construction | AWS |
| 5 | **Developability** | already covered by CycPeptMPDB + PepMSND + MacroConf | — | note gap; no strong new public set identified | — |

Local disk is 92% full (~1.5 GB free), so all downloads/extraction run on a short-lived AWS
collector instance (cheap CPU, `AutoimmuneCorpusProfile` which grants `PutObject` on
`cyclic_peptide/*`), terminating on completion. Small artifacts (manifests, ID lists, subset
CSVs) are synced back for the repo.

## Provenance & verification (per dataset)
1. Pin the source: git commit SHA (GitHub) or URL + release date (PepBDB, BindingDB).
2. Download; compute SHA256; for GitHub also verify the git-blob SHA.
3. Upload to S3 with `Metadata.sha256`; GET back and re-hash; fail on mismatch.
4. Write `results/<name>_acquisition.json` (source, revision, bytes, sha256, s3_uri).

## Splits (leak-free, structure-aware)
- Structural (PepBDB cyclic subset, RCSB index): split by **peptide+receptor sequence/structure
  cluster**, so no identical or near-identical complex crosses train/test — same discipline as
  the PepMSND fold rebuild. Reserve a held-out test set that never touches fitting or checkpoint
  selection.
- Affinity (BindingDB subset): temporal + target-family split; record assay type, units, censoring.
- Report every filter and any silent truncation.

## Collection results (2026-09-14)

Ran on short-lived AWS instances (AutoimmuneCorpusProfile). All artifacts under
`s3://knowledge-datasets-1759951976/cyclic_peptide/datasets/`; verification + manifests in
`datasets/_collect_status/`.

| Dataset | Status | Result |
|---|---|---|
| **HELM monomers** | ✅ | pinned commit `fecc972f…`; `helm_monomers/<commit>/helm_monomers.tgz` (224 KB) |
| **PepBDB** | ✅ | raw 691 MB (SHA256 verified) + `pepbdb_cyclic_index.json`; **13,481 peptide entries → 890 cyclic** (446 unique-seq clusters); leak-free split **799 train / 91 test** |
| **RCSB cyclic index** | ✅ | 28,662 "cyclic peptide" + Protein-entity candidate PDB IDs (text-based, cyclicity not structurally verified) |
| **BindingDB peptide subset** | ✅ | release 202609; scanned 3,237,052 rows → **171,006 peptidic** rows; `bindingdb_peptide/202609/bindingdb_peptide_subset.csv` (48 MB) |

All four collected; both collector instances self-terminated (no lingering cost).

Two environment fixes on the way: wrong IAM profile (403 on the datasets bucket → use
`AutoimmuneCorpusProfile`); and Ubuntu 24.04 has no `awscli` apt package (→ install AWS CLI v2
from the official zip; collector now self-installs it).

## Honest limits
- "Cyclic" detection from PDB is heuristic (head-to-tail / disulfide / side-chain macrocycles);
  the extracted subset is a candidate set requiring review, not a curated gold standard.
- BindingDB peptide subsetting depends on ligand-peptidic heuristics; assay protocols are not
  uniform. Affinity labels are conditioning signal, not ground-truth potency for a new design.
- Licensing/assay provenance must be reviewed before any downstream release.
