# Three Faculties — Workflow Integration Rollup (handoff matrix)

**Date:** 2026-06-19
**For:** handoff — what's done, what's planned, what's not started, per faculty
**Source surveys:**
- `docs/20260617_RESEARCHER_FIT_DEGUI_ZHI.md`
- `docs/20260617_RESEARCHER_FIT_ZHONGMING_ZHAO.md`
- `business/BioMate_ZhandongLiu_Independent_Analysis.md` + `business/BioMate_ZhandongLiu_Study_Proposal.md`
**Design specs:**
- `reference/claude_design/design_handoff_zhi_lab/Zhi-Lab Demo Requirement.md`
- `reference/claude_design/design_handoff_zhao_lab/Zhao-Lab Demo Requirement.md`
- `reference/claude_design/design_handoff_liu_lab/Liu-Lab Demo Requirement.md`

All evidence verified via DB query + GitHub `gh search` + paper Methods reads. No invented status.

---

## Dr. Degui Zhi (UTHealth, ZhiGroup — 32 repos)

### ✅ DONE this session

| Item | What ships in BioMate today |
|---|---|
| TorchGWAS chain wrapper | `workflow_chains.id=69` `torchgwas_udip_chain` (1-step) + workflow row id 14439. Chain row, qc_evidence (3 gates), rationale rows for A/B/C/D — all verified live via `/api/rationale/torchgwas_udip_chain:A`. |
| `.nf` wrapper | `backend/nf-core-workflows/modules/biomate-ai-tools/torchgwas_udip_phenotype_scan/main.nf` (4-phase stub: phenotype QC + kernel + scan + report) |
| Design spec | `Zhi-Lab Demo Requirement.md` 8-beat tip script ready for recording |

### ⏸ PLANNED (Z02 deferred — not started)

| Item | What blocks it |
|---|---|
| FDA chain | `workflow_chains.id=70` exists but marked DEPRECATED. Upstream `ZhiGroup/FDA` is a paper-reproduction repo (2 conda envs, no inference CLI, no example data). Wrapper effort balloons from ~3 days to 2–3 weeks. **Recommendation: defer until lab provides clean `predict(target, ligand)` function.** |

### ❌ NOT in BioMate — Zhi's actual published-Methods stack

Per audit of his **UDIP-FA paper Methods** (PMC12458571), the real tools his pipeline uses are mostly missing from BioMate's catalog:

| Tool | Role | In BioMate? | Effort to wrap |
|---|---|---|---|
| **MAGMA** v1.08 | gene-based test | ❌ (only `nf-core/magmap` indexed — different tool: assembly-graph mapping) | ~1 day |
| **METAL** | meta-analysis across cohorts | ❌ | ~half day |
| **FUMA** | functional annotation | ❌ (web-based — needs API wrapper or local re-impl) | ~2 days |
| **LDSC** | heritability + cross-trait genetic correlation | ❌ | ~1 day |
| **PRS-CS** | polygenic risk scores | ❌ | ~1 day |
| **GCTA** | mixed-linear-model GWAS (his primary engine) | ❌ | ~1 day |
| **JAGWAS** | multivariate GWAS (likely Zhi-lab tool) | ❌ | TBD — verify if it's published |

**Total wrap effort: ~6–8 days to cover Zhi's complete published pipeline.** Currently the Z01 demo shows only the first step (TorchGWAS) — about 1/9 of what his Nat Commun paper does end-to-end.

### ❌ NOT in BioMate — Zhi's other public repos (Tier-A MIT-licensed)

| Repo | What it does | Wrap effort |
|---|---|---|
| `ZhiGroup/RaPID` (★32, MIT) | IBD segment detection (population genetics) | ~1 day |
| `ZhiGroup/Med-BERT` (★329, Apache) | EHR foundation model | ~2 days (model + serving) |
| `ZhiGroup/UDIP-ViT` (MIT) | Vision transformer for brain MRI image-phenotypes | ~2 days |

### ❌ NOT in BioMate — Tier-B (no LICENSE, needs lab grant)

14 repos: SLAB, Syllable-PBWT, FastRecomb, IBD-Booster, P-smoother, ROH-DICE, bi-PBWT, HiFiMAP, UDIP-FA, UDIP-MoCoV2, UDIP-replicability, pytorch_ehr (150★), CovRNN, PASC-AOU, PK-RNN. **Blocked on license clarification email.**

### ❌ Tier-C — not on GitHub yet

RaPID2, FRAME, RLBWT-LCP. **Blocked — ask Zhi when they'll release.**

---

## Dr. Zhongming Zhao (UTHealth, bsml320 — ~25 repos)

### ✅ DONE this session

| Item | What ships in BioMate today |
|---|---|
| 3-step tumor-reactive T-cell chain | `workflow_chains.id=71` `tumor_reactive_t_cell_chain` (turep → Scupa → ImmuneApp) + 3 workflow rows + 9 rationale rows (verified live) |
| scGWAS chain | `workflow_chains.id=72` `scgwas_immunology_chain` (1-step) + workflow row + 4 rationale rows |
| **scGWAS real-data wrap** | `biomate/scgwas:v1` container BUILT locally (eclipse-temurin + R + jar + 88 MB ref panels). **Smoke runs end-to-end** — completes through quantile normalization, produces all 3 canonical scGWAS outputs. **Container NOT yet pushed to ECR.** |
| `.nf` real wrap (scGWAS) | `backend/nf-core-workflows/modules/biomate-ai-tools/scgwas_immune_cell/main.nf` — replaces JSON-emit stub with real `java -jar` invocation. 3 phases (input validation, jar run, R significance call). |
| Design spec | `Zhao-Lab Demo Requirement.md` 8-beat tip script for ZZ01 + ZZ02 |

### ⏸ PLANNED (in flight, not finished)

| Item | What's needed |
|---|---|
| scGWAS ECR push | `docker tag biomate/scgwas:v1 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/scgwas:v1 && docker push ...` — needs AWS ECR write creds; ~30 min |
| scGWAS real-data e2e dispatch on dev | Once image is in ECR, dispatch chain via fixture login and verify outputs land in S3 — ~half day |
| turep + Scupa + ImmuneApp `.nf` stubs → real wraps | Stubs emit placeholder JSON today. Real wraps need each tool's container image. **Scupa is BLOCKED on license clarification (NOASSERTION).** |

### ❌ NOT in BioMate — other Tier-A MIT repos

| Repo | Wrap effort |
|---|---|
| `bsml320/NetBCE` (★7, MIT) — B-cell epitope prediction | ~1 day |
| `bsml320/CytoRescue` (MIT) | ~1 day |
| `bsml320/fadvi` (MIT) — single-cell factor disentanglement | ~1 day |
| `bsml320/ImmuneApp` (★14, MIT) — standalone HLA-I (besides being in ZZ01) | ✅ partial — wrapped as ZZ01 step 3; could expose as standalone demo |

### ❌ NOT in BioMate — Tier-B (no LICENSE, needs ask)

11 repos including NetRNApan, **Scupa**, GENEVIC, VAEN (★21), BrainGeneBot, DeepTR, DeepFun, DeepHTLV, MSEA, BrainSpan, CancerGen-RAG. **Scupa specifically blocks ZZ01 from going to real-data validation.**

### ❌ Tier-C — not on GitHub yet

VISDB 2.0 (web-hosted DB), PRISM-xQTL, MethConvTransformer, BDCD. **Ask lab when published.**

### ❌ NOT in BioMate — Zhao's actual scGWAS-paper stack

Per audit of Genome Biology 2022 (PMC9575201):

| Tool | Role | In BioMate? |
|---|---|---|
| **MAGMA v1.07** | gene scoring (his upstream of scGWAS) | ❌ same as Zhi's gap — wrapping MAGMA helps both labs |
| **PathwayCommons v12** | network reference data | ❌ as data source; could be staged dataset |

---

## Dr. Zhandong Liu (Baylor — rare neurological disease)

### ✅ DONE — entirely from prior sessions (none from THIS session beyond design spec)

| Item | What ships in BioMate today |
|---|---|
| **`workflow_chains.id=1` `rare_disease_multimodal_workup`** | **5-step chain that matches Liu's RareCollab paper verbatim** — exists since before this session. Steps: nf-core/sarek (germline) → nf-core/vcf_annotate_ensemblvep → nf-core/rnaseq (star_salmon) → nf-core/drop (OUTRIDER + FRASER) → case_report_aggregation |
| Upstream tools all indexed | nf-core/sarek (id 1493), vcf_annotate_ensemblvep (id 1793 + 1734 with SnpEff), nf-core/rnaseq (id 1491), nf-core/drop (id 12696), outrider (id 11997), fraser (id 11414) |
| L01 design spec | `Liu-Lab Demo Requirement.md` — added this session with 8-beat tip script + QC gate audit per phase |

### ⏸ PLANNED — engineering open items for L01 recording

| Item | Effort |
|---|---|
| qc_evidence.yaml entry for `rare_disease_multimodal_workup` | citations for DROP (Yepez 2021), OUTRIDER (Brechtmann 2018), FRASER (Mertes 2021), sarek, RareCollab (arXiv 2602.04058), AI-MARRVEL (NEJM AI 2024) — ~half day |
| rationale_mapping.yaml entries for chain id 1 | 5 phase rows pairing each phase to a gate — ~half day |
| Per-phase qc_steps backfill | sarek, VEP, rnaseq, drop, fraser have empty qc_steps; populate from MultiQC schemas — ~1–2 hours |
| Real-data smoke (Phase 1 of pilot) | Public benchmark cohort + dispatch end-to-end via fixture login; verify outputs concord with Liu's reference run | ~half day |

### ❌ NOT in BioMate — Liu's own lab tools (the real differentiator if added)

| Tool | Repo | In BioMate? | Wrap effort |
|---|---|---|---|
| **AI-MARRVEL v1.1.2** | `LiuzLab/AI_MARRVEL` (public, updated 2026-06-01) | ❌ | ~1 day (Python tool, MIT) |
| **PolyAMiner-Bulk** | `YalamanchiliLab/PolyAMiner-Bulk` (public, updated 2026-04-16) | ❌ | ~1–2 days (STAR + C/PAS-BERT + β-binomial) |
| **SEAGAL** | Bioinformatics 2023 paper — repo not found in `gh search`; need URL from lab | ❌ | TBD — ~1 day once URL confirmed |
| **RareCollab** orchestrator | arXiv 2602.04058 — preprint only, code not yet on GitHub | ❌ | BioMate's chain composer IS the RareCollab analog already; await lab's released code to confirm pattern overlap |

Per user's prior direction: **"sarek → VEP → rnaseq → DROP is enough"** for the Liu pilot Phase 1 recording. AI-MARRVEL + PolyAMiner + SEAGAL deferred to L01-v2 onward.

---

## Cross-faculty common gap

Both **Zhi and Zhao use MAGMA** in their published pipelines. Neither's BioMate demo would be paper-faithful without it. **Wrapping MAGMA once (~1 day) covers both labs.** Same logic applies to PathwayCommons (data source, not a workflow — could be a staged BioMate dataset).

The Liu pilot also benefits from MAGMA indirectly via the case_report aggregation step (which could optionally cite MAGMA gene-set evidence).

**Priority recommendation: wrap MAGMA + LDSC + METAL first (3 standard GWAS-evidence tools)** — closes the biggest gap across all 3 labs in ~3 days.

---

## Summary table — what each faculty would see if they tried BioMate today

| Faculty | Their flagship workflow | Runs end-to-end in BioMate today? | Notes |
|---|---|---|---|
| Zhi (Z01 TorchGWAS+UDIP) | UDIP→TorchGWAS GWAS scan | ⚠️ scaffold only — .nf is a stub | Backend metadata is real; .nf needs upstream code wrap |
| Zhi (Z02 FDA) | Folding-Docking-Affinity | ❌ deferred | Upstream is paper-reproduction repo, not inference tool |
| Zhao (ZZ01 turep+Scupa+ImmuneApp) | Tumor-reactive T-cell pipeline | ⚠️ scaffold only — Scupa license blocks one step | turep + ImmuneApp wrappable; Scupa blocked |
| Zhao (ZZ02 scGWAS) | scGWAS for immune cell types | ✅ **REAL CONTAINER BUILT, SMOKE PASSES** — needs ECR push + dev e2e | Closest to "lab can actually use it today" |
| Liu (L01 RareCollab upstream) | sarek+VEP+rnaseq+DROP | ✅ **ALL UPSTREAM ALREADY IN BIOMATE** (chain id 1, pre-existing) | Needs qc_evidence backfill + real-data smoke; ~1 day to demo-ready |

---

## Recommended handoff order (1 person, 2 weeks)

| Day | Item | Faculty unlocked |
|---|---|---|
| 1 | qc_evidence + rationale for chain id 1 + qc_steps backfill | **Liu pilot recording-ready** |
| 1-2 | scGWAS ECR push + dev e2e dispatch | **Zhao ZZ02 ready** |
| 3-5 | Wrap **MAGMA** + **LDSC** + **METAL** | **Zhi + Zhao both paper-faithful** |
| 6 | Extend Z01 chain from 1 step → 5 steps (TorchGWAS+UDIP→MAGMA→METAL→FUMA→LDSC) | **Zhi flagship demo paper-faithful** |
| 7 | Wrap **RaPID** (population genetics) | Zhi IBD evidence |
| 8 | Wrap turep + ImmuneApp standalone | Zhao Tier-A complete (Scupa still blocked) |
| 9 | Wrap **AI-MARRVEL** | **Liu L01 → L01-v2 (his actual paper)** |
| 10 | Wrap **PolyAMiner-Bulk** | Liu L02 demo possible |

If you parallelize across 2-3 engineers, this collapses to ~1 week. If outreach-driven (i.e. only wrap what each lab confirms they'll use), starts at day 1 (Liu pilot path is shortest, ~1 day to demo).

---

## Open items needing lab response (before further wraps)

| Faculty | Ask |
|---|---|
| Zhi | (a) Add LICENSE to UDIP-FA + 13 other Tier-B repos. (b) Release RaPID2 / FRAME / RLBWT-LCP. (c) Provide cleaner inference entry point for FDA (or pause Z02). (d) UKB credential sponsorship for paper-faithful Z01 demo. |
| Zhao | (a) Add LICENSE to Scupa (blocks ZZ01). (b) Confirm release timing for PRISM-xQTL + MethConvTransformer. (c) Wrap VISDB 2.0 as queryable BioMate dataset (or share its query API spec). |
| Liu | (a) SEAGAL repo URL. (b) RareCollab code release timing. (c) Confirm public benchmark cohort for Phase 1 pilot. (d) When Phase 2 IRB ready, share PHI compliance scope (HIPAA / 21 CFR Part 11 / etc.). |

These three emails would unblock most of the deferred items above.
