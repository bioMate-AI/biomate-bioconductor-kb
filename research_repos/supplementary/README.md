# BioMate Publication Supplementary Materials

Single index for supplementary files cited by the three companion manuscripts:
- Flagship: *Interactive Evidence-Graded QC Governance and Auto-Loop Convergence for Drug Discovery Workflows*
- AutoLoop: *Autonomous Parameter Convergence under Regulatory QC Constraints*
- BioMate-Cryo: *Evidence-Graded Interactive QC Governance for Single-Particle Cryo-EM*

## Files

| ID | File | Description | Cited by |
|---|---|---|---|
| **S1** | `S1_gate_catalog.csv` | Full per-gate catalog: domain, gate, provenance, paper_ref, paper_doi, paper_supports excerpt, rule_text excerpt. 57 rows across 25 domains. | Flagship §3.1, AutoLoop §2.2 |
| **S2** | `../flagship_paper/results/e1_*.csv`, `evaluation/results/autoloop/autoloop_results.csv`, `../autoloop_benchmark_paper/results/e3_provenance_correlation.csv` | Raw experiment scenario data (E1 + E2 + E3) | Flagship §3.2-3.4, AutoLoop §3 |
| **S3** | `../flagship_paper/run_e1.py`, `evaluation/adapters/autoloop_benchmark_adapter.py`, figure scripts | Reproducibility scripts for re-running each experiment | Flagship §5.4, AutoLoop §2.4 |
| **S4** | `../flagship_paper/data/e4_logs/` | 10 BioMate audit logs + 10 baseline-tool logs for E4 audit-completeness experiment | Flagship §3.5 |
| **S5** | `../flagship_paper/figures/figure5_architecture.png` + `.pdf` | System architecture diagram (workflow → SSE → tooltip) | Flagship §5.1 |
| **Table 1** | `../flagship_paper/tables/table1_gate_catalog_summary.{csv,md}` | Per-domain summary: total gates + GOLD/SILVER/BRONZE counts | Flagship §3.1 |

## Key totals from S1

- **25 domains** with QC evidence entries
- **57 gates** in production
- **26 GOLD** (verbatim from cited regulatory guidance or peer-reviewed paper)
- **26 SILVER** (community convention attributed to the paper)
- **5 BRONZE** (operational heuristics; explicitly disclaimed in tooltip)

## Citation provenance

Every gate's paper_ref + paper_doi has been verified against PubMed/Crossref (post the Aronov 2008 correction documented in `docs/20260528_CITATION_CORRECTION_ARONOV.md`). The 5 BRONZE entries explicitly state in their `paper_supports` text that the cited paper does NOT contain the specific cutoff.

## Reproducibility

Each experiment's reproducibility chain:

| Experiment | Script | Data | Figure |
|---|---|---|---|
| E1 | `flagship_paper/run_e1.py` | `flagship_paper/results/e1_*.csv` | `figures/e1_false_rejection.{png,pdf}` |
| E2 | `evaluation/adapters/autoloop_benchmark_adapter.py` + `runners/run_autoloop_benchmark.py` | `evaluation/results/autoloop/autoloop_results.csv` | `autoloop_benchmark_paper/figures/e2_convergence.png` |
| E3 | `autoloop_benchmark_paper/figures/e3_provenance_correlation.py` | `e3_provenance_correlation.csv` | `e3_provenance_correlation.png` |
| E4 | `flagship_paper/scripts/e4_audit_completeness.py` + `e4_generate_logs.py` | `data/e4_logs/{biomate,baseline}/*.json` | `figures/e4_audit_completeness.png` |

Each script is self-contained and runnable against the data files in this supplementary corpus.
