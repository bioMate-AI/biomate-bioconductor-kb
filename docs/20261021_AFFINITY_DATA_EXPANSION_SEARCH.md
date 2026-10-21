# Measured cyclic-peptide affinity — data-expansion search (path B)

**Date:** 2026-10-21 · **Question:** can we expand the measured cyclic-peptide/macrocycle
binding-affinity training set beyond `binding_affinity_v1` with enough NET-NEW, commercial-clean,
measured data to attack the data-limited ~0.42 novel-target ceiling — or is the data limit real?

## What we already have (baseline to beat)
`research/guangzhou_all_atom/data/raw/binding_affinity/binding_affinity_v1.csv` — collected by
`collect_binding_affinity.py`, which **already merges ChEMBL + BindingDB** (the two large measured-bioactivity
repositories):

- 136,730 total rows; source split: **ChEMBL 16,861 (ChEMBL-only) + BindingDB∩ChEMBL 11,168 + BindingDB 108,701**.
- **36,102 cyclic** (RDKit-classified) measured Ki/IC50/EC50/Kd across **924 cyclic targets**; ~28,875 clean after dedup/censor.
- Affinity types (cyclic): IC50 20,657 · Ki 8,749 · EC50 4,754 · Kd 1,942.
- **All cyclic rows are SMILES (0 plain-AA sequence).**
- Program targets: **PD-L1 168 cyclic / αvβ6 169 cyclic** (both among the better-covered targets).
- **Sparsity (the core problem):** median **5 cyclic compounds per target**; only 138 targets have ≥50, 361 have ≥10.
  924 targets but a thin per-target signal — this is *why* novel-target generalization is hard, and it is not
  fixed by any public source below.

## Per-source inventory (net-new assessment)

| Source | Content | Measured cyclic affinity? | NET-NEW vs ChEMBL+BindingDB | License (commercial) | Access |
|---|---|---|---|---|---|
| **ChEMBL (full)** | measured bioactivity | yes | **~0 net-new** — already a primary source of our set | CC-BY-SA 3.0 (attribution+share-alike; commercial-OK) | have it |
| **BindingDB (full)** | measured bioactivity | yes | **~0 net-new** — already our secondary source | CC-BY-4.0 (commercial-OK w/ attribution) | have it |
| **PDBbind v2020** | 19,443 protein–ligand complexes w/ measured Kd/Ki/IC50 | yes, but **structural, overwhelmingly small-molecule; macrocycle/peptide subset small & unquantified** | small; mostly overlaps PDB complexes we don't need structurally | **LICENSING ISSUE — not commercial-clean.** BioLiP *removed 24,809 PDBbind-CN affinities in Jan 2025 over licensing*; PDBbind requires a registration/agreement | gated |
| **Binding MOAD (via BioLiP2)** | ~25,999 affinities, structural complexes | yes, but structural, mostly small-molecule; small cyclic subset | small net-new cyclic; structural not measured-SMILES | BioLiP *code* BSD; affinity data academic/research — **commercial status not explicit (flag)** | downloadable |
| **CPSea** | **2.71M cyclic-peptide–receptor complexes** | **NO — AlphaFold-predicted structures, not measured affinity** | 0 measured affinity | dataset (benchmark) | downloadable |
| **PepBenchmark / PPI_BA** | 1,433 peptide→−lgKd | measured, but **general peptide not cyclic; derived from PDBbind** | ~0 net-new cyclic; too small; inherits PDBbind license | inherits PDBbind | downloadable |
| **Protein–cyclic-peptide MM/PBSA benchmark** | **50** protein–cyclic-peptide complexes w/ affinity | yes but **n=50, eval-only** | negligible (eval set, not training) | paper SI | paper |
| **Display papers (mRNA/phage)** | validated hits | occasional measured Kd on **handfuls** per paper | negligible at scale; manual extraction | per-paper | manual |
| **Patent / SureChEMBL** | extracted structures | mostly **structures without attached measured values**; measured patent affinity largely already in ChEMBL/BindingDB | small | SureChEMBL open | bulk |

## Verdict — the measured-cyclic-affinity universe is essentially what we already have

- The two large **measured** bioactivity repositories are **ChEMBL and BindingDB**, and our set **already merges both**.
  There is **no untapped large measured-cyclic-affinity database** beyond them.
- The remaining public sources are either **structural** (PDBbind / Binding MOAD / BioLiP — small cyclic subset, and
  PDBbind carries a **commercial licensing problem**), **predicted not measured** (CPSea, 2.71M AF structures), or
  **tiny/eval-only** (PepBenchmark 1,433 non-cyclic; the 50-complex benchmark; per-paper display Kd).
- Net-new **commercial-clean measured cyclic affinity** obtainable from public data: **marginal** — a few thousand at
  most (mostly structural Binding-MOAD cyclic subset of uncertain commercial status), and it does **not** densify the
  sparse per-target folds (median 5/target) that drive the ~0.42 novel-target ceiling.

**So the data limit is real.** Re-training on public data will not meaningfully lift ~0.42 — the measured cyclic-affinity
corpus is saturated at the ChEMBL+BindingDB level we already train on, and it is sparse per target. The ceiling breaks
only by **adding new signal**: (A) physics-grounding (requires building the missing SMILES→GAFF MM-GBSA pipeline, then
validating physics tracks affinity), or (B) **new measured experiments** (assay/CRO) — the slow but genuine path.

## Concrete acquisition plan (what's worth pulling, and what isn't)
1. **Binding MOAD cyclic subset** (BioLiP2 affinity table) — the only plausible net-new *measured* cyclic records;
   pull, RDKit-classify cyclic, dedup against our set, **confirm commercial license before use**. Expected yield: low
   thousands, structural, small net gain. Worth a one-time pull as a *validation/held-out* set, not a ceiling-breaker.
2. **Do NOT** adopt PDBbind — commercial licensing issue (BioLiP removed it for exactly this).
3. **CPSea** — usable only as *structure* pretraining (predicted), not measured affinity; separate (structure-model) lever.
4. **Broader (non-cyclic) peptide/small-molecule measured affinity** — abundant in ChEMBL/BindingDB (our full set is 136k;
   cyclic is only 36k) — a *transfer/pretraining* modeling lever, not a cyclic-data-expansion win; cross-modality
   transfer is itself unproven here, so flag as speculative.

**Bottom line:** the public data is exhausted; a strong standalone cyclic-affinity model is **data-bound**, and only
physics-grounding (path A) or new measured experiments (true path B) can add the signal to break ~0.42.

Sources: [PDBbind (Wikipedia)](https://en.wikipedia.org/wiki/PDBbind_database) · [Leak-Proof PDBBind](https://arxiv.org/abs/2308.09639) · [CPSea (NeurIPS 2025)](https://papers.nips.cc/paper_files/paper/2025/hash/3eec719ab86712d32b065c5977f94ad0-Abstract-Datasets_and_Benchmarks_Track.html) · [PepBenchmark](https://arxiv.org/pdf/2604.10531) · [protein–cyclic-peptide MM/PBSA benchmark (PMC12665037)](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC12665037/) · [BioLiP2 (NAR, D1/D404)](https://academic.oup.com/nar/article/52/D1/D404/7233921) · [BioLiP2 downloads](https://seq2fun.dcmb.med.umich.edu/BioLiP2/download.html) · [consensus bioactivity dataset (PMC9028877)](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC9028877/)
