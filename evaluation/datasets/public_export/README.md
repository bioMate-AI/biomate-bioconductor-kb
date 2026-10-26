> ⚠️ **Before citing any leaderboard number, read [LEADERBOARD_CAVEATS.md](LEADERBOARD_CAVEATS.md)** — known data-quality caveats (menu-condition split, empties by cause, raw-LLM-vs-production param rows, do-not-claim SFT wins).

---
license: cc-by-4.0
task_categories:
- text-classification
- question-answering
tags:
- bioinformatics
- agents
- benchmark
- workflow
- evaluation
pretty_name: RealBio Benchmark — Real-World Bioinformatics-Agent Benchmarks
---

# RealBio Benchmark — real-world benchmarks for bioinformatics AI agents

**Can it run science, not just discuss it?** Most bio-AI benchmarks test knowledge and reasoning. RealBio
tests **real-world execution** — whether an agent can actually route, parameterize, quality-control, repair,
and dose real pipelines.

**660 items across 8 tasks**, each with **objective ground truth** so *any* system can be scored on the
*same* items with the *same* metric — **no LLM judge required**. Published so results are reproducible and
comparable across systems, not self-reported.

> **This page is the DATASET** — the items + ground truth, to download, evaluate against, and **cite**.
> Two companion surfaces, each with a different job (see `docs/20260827_REALBIO_THREE_SURFACES_ROLES.md`):
> - **Run & submit → GitHub** ([bioMate-AI/realbio-benchmark](https://github.com/bioMate-AI/realbio-benchmark)) — the scorer (`score.py`), committed predictions, leaderboard regeneration, how to add your system.
> - **Understand why it matters → website** ([biomate.ai/realbio](https://biomate.ai/realbio)) — the narrative, the human-readable leaderboard, and the difficulty-stratified figures.

## Why this exists
Benchmarks scored by a system's own judge on its own private test set are not comparable across systems.
This is the opposite: fixed items, published ground truth, an open scorer. Run your system, score it here,
compare directly.

## The tasks
| Benchmark | Items | Task | Ground truth | Metric |
|---|---|---|---|---|
| `cross_domain_routing` | 200 | route a natural-language request to the correct analysis **domain** | `domain` | accuracy |
| `param_prefill` | 170 | extract structured parameters from NL; don't over-fill | `expected_params` + `must_not_fill` | param-F1 + violation rate |
| `protocol_thresholds` | 100 | is a sample valid, and should it PASS/FAIL vs a naive universal threshold | `ground_truth` + `expected_correct_action` | action accuracy |
| `autofix_benchmark` | 100 | classify a pipeline failure into 1 of 10 fix categories | `category` | category accuracy |
| `workflow_generation` | 40 | select the correct analysis category / key tools | `expected_category` \| `key_tools` | accuracy |
| `boin_benchmark` | 20 | correct BOIN dose-escalation decision | `reference` | accuracy |
| `pbpk_benchmark` | 15 | predict PK from SMILES + dose + route | `reference` | within-2-fold |
| `drug_discovery_e2e` | 15 | reproduce ligand affinity rank order | `ligand_rank_order` | Spearman ρ |
| `proteomics_search` † | 1 | **run** an MS/MS search + measure speed & #IDs@1%FDR@entrapment | `entrapment_database` | wall-clock + #peptides@1%FDR + entrapment FMR |

† **`proteomics_search` is a real-execution capability benchmark**, not a prediction item-set: it is
scored by *running* the committed Nextflow search harness on real data (not by a `predictions.jsonl` +
LLM). Targets: ≥5× faster end-to-end than the brute-force (Comet) baseline; no peptide-recall
regression; entrapment FMR ≤1.3% at claimed 1% FDR. Harness:
`evaluation/datasets/proteomics_search_benchmark/`; scorer:
`scripts/score_proteomics_search_benchmark.py`; report:
`docs/20261001_PROTEOMICS_SEARCH_BENCHMARK_REPORT.md`. See `proteomics_search/README.md`.

## How to run
1. For a benchmark, produce `predictions.jsonl` — one line per item: `{"id": "...", "prediction": <answer>}`
   (per-benchmark prediction format is documented at the top of `score.py` and in each subfolder's `README.md`).
2. Score: `python3 score.py <benchmark> predictions.jsonl` → objective metric, no judge.

## Honesty & scope (read this)
- **Neutralized, self-protective export.** These are the *evaluation tasks only*; BioMate's system internals
  are not included, and any BioMate-specific labels have been removed. Two internal benchmarks
  (`license_gating`, `memory_benchmark`) are **withheld** because their ground truth is specific to one
  system's behaviour and is not a neutral cross-system task.
- **Authorship / contamination.** Items were authored by the BioMate team from public sources (GEO accessions,
  RCSB PDB structures, experimental Kd, published PK and BOIN references). They are *original tasks*, not drawn
  from another system's training set. Because BioMate's authors wrote them, we publish them openly precisely so
  other groups can inspect for bias and re-run independently — a self-reported score on a private set is what
  this replaces.
- **`autofix_benchmark`** is scored objectively on **fix-category accuracy** (10 generic failure classes:
  genome_mismatch, resource_failure, container_error, …). A free-text `expected_fix` reference ships alongside
  as an optional secondary (token-overlap) signal only.
- Every numeric result you cite from this benchmark should be produced by `score.py`, not asserted.

## Attribution
BOIN: Liu & Yuan, *JRSS-C* 2015. PBPK/BOIN references: published clinical pharmacology sources (per-item `reference`).
Structures: RCSB PDB. Affinities: experimental Kd (PDBbind-derived where noted). Protocol datasets: public GEO accessions.

## License
CC-BY-4.0.

## Citation
If you use RealBio, please cite the dataset:

```bibtex
@misc{realbio_benchmark_2026,
  title        = {RealBio Benchmark: Real-World Benchmarks for Bioinformatics AI Agents},
  author       = {Zhang, Yaoyun and {BioMate Team}},
  year         = {2026},
  publisher    = {Hugging Face},
  howpublished = {\url{https://huggingface.co/datasets/YaoyunZhangHug/realbio_benchmark}},
  note         = {Code + scorer: \url{https://github.com/bioMate-AI/realbio-benchmark}}
}
```
*(A versioned DOI will be minted on publication; update the `note`/`doi` field then.)*
