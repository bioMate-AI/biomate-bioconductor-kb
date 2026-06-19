# Researcher Fit — Dr. Degui Zhi (UTHealth Houston)

**Date:** 2026-06-17
**Scholar:** https://scholar.google.com/citations?user=9dmZ3lkAAAAJ
**Lab GitHub:** https://github.com/ZhiGroup (32 public repos)
**Role:** Department Chair, Professor, School of Biomedical Informatics, UTHealth Houston
**Research areas:** EHR foundation models, imaging genetics, population-genetics informatics

## Last 3 years — publication clusters

| Cluster | Recent papers | Common method |
|---|---|---|
| **Population genetics / PBWT family** | TorchGWAS (arXiv 2026), RaPID2, HiFiMAP, SLAB, FRAME, RLBWT-LCP pangenome | Compressed haplotype indexing, IBD detection, ancestry estimation |
| **Brain imaging × genetics** | UDIP on FA maps (Nat Commun 2026), contrastive multimodal brain rep, learning-dynamics epoch-specific GWAS | Unsupervised deep image phenotyping → GWAS on derived embeddings |
| **EHR clinical ML** | Vancomycin two-compartment (JMIR AI 2026), candidemia two-step (medRxiv 2026), LLM-vs-clinical-foundation-model (medRxiv 2026), RL dosing simulator (AMIA 2026), cognitive-decline multimodal (Front Neuroimaging 2026) | EHR foundation models + RL + PK |

## Code availability — verified 2026-06-17

| Tool | Repo | License | Last update | Stars |
|---|---|---|---|---|
| **TorchGWAS** | `ZhiGroup/TorchGWAS` | **MIT** | 2026-05-03 | 2 |
| **RaPID** | `ZhiGroup/RaPID` | **MIT** | 2026-05-07 | 32 |
| **FDA** (Folding-Docking-Affinity) | `ZhiGroup/FDA` | **MIT** | 2026-06-15 | 30 |
| **Med-BERT** | `ZhiGroup/Med-BERT` | **Apache-2.0** | 2026-06-04 | 329 |
| **UDIP-ViT** | `ZhiGroup/UDIP-ViT` | **MIT** | 2026-05-20 | 1 |
| SLAB | `ZhiGroup/SLAB` | no LICENSE | 2026-04-28 | 4 |
| Syllable-PBWT | `ZhiGroup/Syllable-PBWT` | no LICENSE | 2026-01-20 | 12 |
| HiFiMAP | `baihongguo/HiFiMAP` (lab fork) | no LICENSE | 2026-06-03 | - |
| bi-PBWT, FastRecomb, IBD-Booster, P-smoother, ROH-DICE | `ZhiGroup/*` | no LICENSE | 2025–2026 | <10 each |
| pytorch_ehr | `ZhiGroup/pytorch_ehr` | no LICENSE | 2026-04-05 | 150 |
| UDIP-FA, UDIP-MoCoV2, UDIP-replicability, CovRNN, PASC-AOU, PK-RNN, terminology_representation | `ZhiGroup/*` | no LICENSE | 2024–2026 | mixed |
| RaPID2, FRAME, RLBWT-LCP | **not found** | — | — | — |

## BioMate fit assessment

### Tier-A — drop-in workflows this week (license-clean, mature, demo-ready)

1. **FDA (Folding-Docking-Affinity)** — wraps ESMFold → docking → affinity prediction. Direct overlap with BioMate's existing drug-discovery domain (ADMET auto-loop, docking auto-loop, CYP-DDI). Wrap as `nf-core-workflows/modules/biomate-ai-tools/fda/main.nf`, 4-phase pipeline (fold → dock → affinity → report). Their citation goes in `qc_evidence.yaml` so Citations tab populates on every run.
2. **TorchGWAS** — GPU-accelerated GWAS for thousands of phenotypes. Slots into BioMate's GPU queue; matches the `gwas_variant` benchmark family already in `evaluation/`. Pairs with their **RaPID** for an IBD-aware GWAS chain.
3. **Med-BERT** — Apache-2.0 EHR foundation model, 329★. Hostable via `run_code` for benchmark work; aligns with their own 2026 "LLM vs specialized clinical foundation model" paper.

**Effort:** ~3 days each, identical to the tier-0 demos shipped 2026-06-16. Outcome: their group runs their own tools via NL queries, gets the 7-tab After-run report + auto-loop QC + Lago-tracked billing without managing Slurm.

### Tier-B — needs a license conversation (mature code, no LICENSE file)

SLAB, Syllable-PBWT, FastRecomb, IBD-Booster, P-smoother, ROH-DICE, bi-PBWT, HiFiMAP, UDIP-FA / MoCoV2 / replicability, pytorch_ehr, CovRNN, PK-RNN. All current (most touched April–June 2026), all without LICENSE. One-line ask: "we'd like to integrate — please add a permissive license or grant integration terms."

### Tier-C — not yet released or renamed

**RaPID2**, **FRAME**, **RLBWT-LCP**: papers say published, but no repo at the org. Either renamed (RaPID2 may be the current `RaPID` HEAD) or pre-release. Worth asking directly.

## Concrete pitch (one paragraph)

> Dr. Zhi — your group publishes ~10 new tools a year, each on GitHub, each requiring users to manage their own compute. BioMate wraps any nf-core / Python / R tool as a chat-routable workflow, runs it on AWS Batch (CPU or GPU), and produces a 7-tab report (Findings, Outputs, Methods, Parameters, Software, Citations, QC audit). Your TorchGWAS / FDA / RaPID would slot in this week — your students would run them from a chat prompt, your collaborators would download a regulatory-style methods report, and the (why?) anchor on each run cites your papers directly. We'd start with FDA + TorchGWAS as a free integration; if useful, we'd map your imaging-genetics UDIP stack as a paid second phase.

## Open items before reaching out

- [ ] Confirm RaPID2 / FRAME / RLBWT-LCP repo status with the group
- [ ] Decide pricing for Tier-B integrations once they grant license
- [ ] Pre-build Tier-A workflows (FDA + TorchGWAS) so the demo lands warm
