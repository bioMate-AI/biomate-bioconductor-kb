# Tutorial VIDEO Coverage & QA Audit

**Auditor role:** Coverage / QA Auditor, skeptical audit committee
**Date:** 2026-10-04
**Scope:** The 6 produced tutorial videos (EN+ZH = 12 MP4s) vs. the required-coverage universe (data-centric v2 spec modules 00–14, the P1/P2 priority-workflow Excel, the full instrument set, and the mandate "cover the ENTIRE drug-development pipeline, the ENTIRE set of important instrument workflows, search & DB, and other important function modules").
**Method:** Read all 6 walkthrough HTMLs + 12 narration files; parsed `series/catalog.json` (the editorial plan of record), `20261002_TUTORIAL_COVERAGE_MATRIX.md`, and `20260715_WORKFLOW_USECASE_PRIORITIZATION.xlsx` (all 10 sheets). Audit only — no tutorial files were edited.

---

## 1. Verdict

**NOT READY — produced video coverage is a thin slice (~9%) of the required set, and every produced video sits on an UNVERIFIED (1 BLOCKED / 5 PENDING) editorial entry.** Six chapter videos exist; the series' own `catalog.json` plans **70 episodes (28 chapters + 42 focused) × 2 languages = 140 editions**, status `IN_PRODUCTION_NOT_RELEASED`. The six produced videos are internally clean on the mechanical checks that matter most — **narration-step ↔ scene timing is 1:1 for all six, EN/ZH step counts are identical, and every referenced image/clip asset exists** — but they fail the committee's substantive bars:

1. **Mandate coverage is largely absent.** Of the P1 priority workflows, only the drug-discovery flagship chain (ADMET→RBFE/MD→PBPK→IND) is shown. **Cryo-EM, WGS cohorts, RNA-seq, single-cell, variant calling, AlphaFold/Foldseek/MMseqs DB search, count-matrix DE — all P1/P2 — have ZERO video coverage.** All 10 instruments have ZERO video coverage.
2. **Honesty-badge scheme is inconsistent across the set.** Only `drug-dev` uses the formal three-way verdict (*Demonstrated here / Available / Still a gap*). t0–t4 use ad-hoc inline "honest" prose, and t1 introduces a fourth, unshared word ("roadmap"). There is no shared badge component.
3. **t0 was filmed against a route its own catalog entry marks BLOCKED** ("New Chat … does not mount the expected cold-start module dashboard. Do not film the documented route as working until corrected and verified"). The produced t0 video therefore likely depicts a cold-start that does not match the shipped product.

The clean mechanics mean the *production pipeline* is sound; the *coverage and verification* are not. Do not treat "6 videos done" as proximate to "the tutorial videos are done."

---

## 2. Coverage matrix

### 2a. Produced-video inventory (ground truth)

| Video (file stem) | Catalog id | Written twin | Scenes (data-seconds) | Narration steps EN/ZH | Catalog verification |
|---|---|---|---|---|---|
| `t0-getting-started` | t0-getting-started | T0 | 9 | 9 / 9 | **BLOCKED** |
| `t1-design-and-generate` | t1-design-and-generate | T1 | 11 | 11 / 11 | PENDING |
| `t2-models-and-the-closed-loop` | t2-models-and-the-closed-loop | T2 | 11 | 11 / 11 | PENDING |
| `t3-run-and-report` | t3-running-a-workflow-and-reading-the-report | T3 | 8 | 8 / 8 | PENDING |
| `t4-bringing-your-own-data` | t4-bringing-your-own-data | T4 | 11 | 11 / 11 | PENDING |
| `drug-dev` | t11-drug-development-end-to-end | T11 | 17 | 17 / 17 | PENDING |

All 12 MP4s present in `recording/output/`. Scene↔step parity is exact in every row (see §4, defect-free).

### 2b. Data-centric v2 modules (00–14) → coverage

Legend: 🎬 video · 📄 written-only · ◐ partial/folded · ❌ none

| Module | Topic | Video? | Written | State | Note |
|---|---|---|---|---|---|
| 00 | Foundations & cold start | 🎬 t0 | T0/S1 | ◐ | video exists but on a **BLOCKED** route; re-verify cold start vs live |
| 01 | Search and evidence | ❌ | M1 (in prog) | 📄 | **No video.** t0 only names the Instant lane. Catalog `m1` = BLOCKED |
| 02 | Data analysis | ◐ t3/t4 | M2 (in prog) | ◐ | Instant-vs-Cloud touched; no dedicated video |
| 03 | Models | 🎬 t2 | T2 | ✅ | reuse/run + wet-lab loop strong; Train/Adapt/Optimise light |
| 04 | Files & the dataset object | 🎬 t4 | T4 | ✅ | ingest+quality strong; versions/lineage thinner |
| 05 | Design and generate | 🎬 t1 | T1 | ✅ | small molecule only |
| 06 | The composer | ◐ t0 | — | ◐ | focused `composer` episode planned, not produced |
| 07 | The workflow panel | 🎬 t3 | W1 | ✅ | run-bar/phases/gate shown |
| 08 | The full step view | ◐ t3 | W3 | ◐ | no dedicated video; focused episode planned |
| 09 | Worked examples — search answers | ❌ | — | ❌ | no video, no chapter twin |
| 10 | Worked examples — model use cases | ◐ t2 | T2 | ◐ | folded into t2 |
| 11 | Design & generate — all modalities | ❌ | — | ⛔ | small-molecule only; protein/peptide/biologics **not built** (do not film) |
| 12 | Reports as editable files | ◐ drug-dev/t3 | T8 | ◐ | reproducibility record shown; **edit/export focused episodes not produced** |
| 13 | Run cards by domain | ◐ drug-dev | — | ◐ | one domain (drug-dev) only |
| 14 | Panes & output previews | ◐ t3/t4 | T5/W2 | ◐ | previews touched; viewer-type focused episodes not produced |

**Video-covered modules: 5 of 15 solidly (03,04,05,07 + 00-on-blocked-route). 10 of 15 are partial-or-none.**

### 2c. Priority-Excel P1/P2 workflows → coverage

| Pri | Workflow / use case | Domain | Video? | Written | State |
|---|---|---|---|---|---|
| P1 | ADMET→REINVENT4→PBPK→IND §2.6 (flagship chain) | drug_discovery+pharm | 🎬 drug-dev | T11 | ✅ demonstrated |
| P1 | Compound-library ADMET fan-out (1000s SMILES) | drug_discovery | 🎬 drug-dev (◐) | T11 | ◐ chain-level only |
| P1 | Single-compound ADMET (freemium front door) | drug_discovery | ◐ drug-dev/t1 | — | ◐ |
| P1 | Molecule generation / REINVENT4 lead design | drug_discovery | 🎬 t1/drug-dev | T1 | ✅ |
| P1 | PBPK simulation | pharmacology | 🎬 drug-dev | T11 | ✅ (stage 7) |
| P1 | Full Bioconductor chains + IND prose | multi-domain | ◐ drug-dev | T11 | ◐ |
| P1 | **Cryo-EM SPA (cryosparc_standard_spa)** | cryo_em | ❌ | instruments/cryoem | **📄 only** |
| P1 | **AlphaFold-Multimer / AlphaFold3** | structural_biology | ❌ | — | **❌ none** |
| P1 | **Large WGS cohorts (sarek/GATK joint)** | variant_calling | ❌ | — | **❌ none** |
| P1 | **Bulk RNA-seq from FASTQ (nf-core/rnaseq)** | transcriptomics | ❌ | — | **❌ none** |
| P1 | **Count-matrix DE (DESeq2/edgeR/limma)** | transcriptomics | ❌ | — | **❌ none** |
| P1 | **Foldseek structure homology search** | structural_biology | ❌ | — | **❌ none** |
| P1 | **Chemical similarity screen (FPSim2/ChEMBL)** | drug_discovery | ◐ t1 | — | ◐ weak |
| P1 | **Variant/entity annotation lookups (gnomAD/ClinVar)** | DB search | ❌ | — | **❌ none** |
| P1 | **MMseqs2 sequence homology search** | genomics | ❌ | — | **❌ none** |
| P1 | **GWAS→scRNA→eQTL target-ID (autoimmune)** | genomics+single_cell | ❌ | — | **❌ none** |
| P2 | MD trajectories (OpenMM/GROMACS) | biophysics | ◐ drug-dev | — | ◐ named in stage 4 |
| P2 | Single-cell atlas integration | single_cell | ❌ | — | **❌ none** |
| P2 | scRNA cellranger (nf-core/scrnaseq) | single_cell | ❌ | — | **❌ none** |
| P2 | Germline variant calling (nf-core/sarek) | variant_calling | ❌ | — | **❌ none** |
| P2 | Large sequence-homology (nr/UniRef) | genomics | ❌ | — | **❌ none** |
| P2 | Literature/cross-archive retrieval (MedCPT) | DB search | ❌ | M1 (◐) | **❌ no video** |
| P3 | ChIP-seq/ATAC-seq | epigenomics | ❌ | — | ❌ |
| P3 | Metagenome assembly/binning | metagenomics | ❌ | — | ❌ |
| P3 | NCA/allometric PK | pharmacology | ◐ drug-dev | — | ◐ |

**Video coverage of priority workflows: the entire drug-discovery P1 chain is covered; every non-drug-discovery P1 workflow (cryo-EM, WGS, RNA-seq, DE, single-cell, AF/Foldseek/MMseqs DB search, target-ID) has NO video.**

### 2d. Instruments (10) → coverage

| Instrument | Written doc | Video? |
|---|---|---|
| Illumina BaseSpace sequencing | ✅ | ❌ |
| Nanopore MinKNOW | ✅ | ❌ |
| LC-MS proteomics/metabolomics | ✅ | ❌ |
| Plate-reader assays | ✅ | ❌ |
| qPCR quantification | ✅ | ❌ |
| Flow cytometry gating | ✅ | ❌ |
| Opentrons liquid handling | ✅ | ❌ |
| Cryo-EM reconstruction | ✅ | ❌ |
| Benchling ELN/LIMS | ✅ | ❌ |
| SiLA2 devices (generic) | ✅ | ❌ |

**All 10 instruments: written-only. ZERO instrument videos** — a direct miss against the mandate's "ENTIRE set of important instrument workflows." The catalog plans all 10 as chapters + 7 instrument-analysis focused episodes (wgs/rnaseq/proteomics-dda/dia/metabolomics/dose-response/hts), none produced.

---

## 3. Prioritized gap list

Priorities blend the Excel's P1/P2 tags with the requester's explicit mandate (whole drug-dev pipeline, whole instrument set, search & DB, other key modules).

### P1 — mandate-critical, no video today

1. **Search & evidence video (module 01/09).** Mandate names "search & DB" explicitly; produced set has none. Written M1 exists but catalog `m1` is **BLOCKED** (cold-start dashboard doesn't mount) — unblock the route before filming.
2. **Large-DB search videos (Foldseek / MMseqs2 / FPSim2 / annotation lookups).** Four P1 "Large DB Search" rows, all `Implemented` per Roadmap, zero video. This is the hosted-index moat — the mandate's "DB" pillar.
3. **Cryo-EM SPA video (P1 GPU).** Flagship GPU workflow; written instrument doc exists, no video. High marketing value (core-facility beachhead).
4. **WGS cohort + germline variant-calling video (P1/P2).** Genomics-core beachhead; no video, no written chapter twin.
5. **Bulk RNA-seq + count-matrix DE videos (P1).** Freemium front door and the highest-repeat Tier-1/2 workflows; no coverage at all.
6. **Instrument video set (10).** Mandate requires the ENTIRE instrument set. Start with the highest-traffic connectors (BaseSpace, Nanopore, LC-MS, cryo-EM) to pair with the P1 analysis videos above.
7. **Re-verify + re-cut t0.** Its catalog entry is BLOCKED; a video is already published against a route flagged "do not film as working." Either fix the cold-start mount and re-shoot, or re-record against the actual shipped New-Chat behavior.

### P2 — real surface, partially folded, deserves its own video

8. **Reports edit & export video (module 12).** drug-dev/t3 show only the immutable reproducibility record; the *editable* report + 5-format export (focused `report-editing`, `report-export`) are unshot. T8 written exists.
9. **Full step-view video (module 08).** Folded into t3; W3 written exists; catalog `w3-full-step-view` planned.
10. **Composer deep-dive video (module 06).** Only t0 basics; focused `composer` planned.
11. **Single-cell (scRNA cellranger / atlas integration) videos (P2).** No coverage.
12. **Output-viewer focused videos (table/sequence/variant/structure/interactive, module 14).** T5 written; none filmed.
13. **Projects & collaboration / instructions video.** T7 written; focused `project-instructions`, `project-sharing` planned, none filmed.

### P3 — lower priority / confirm-first

14. Models Train/Adapt/Optimise focused videos (t2 covers run/reuse only).
15. ChIP/ATAC, metagenomics, dose-response/HTS focused episodes.
16. Dataset versions/lineage focused videos (module 04 deep-dive).

### Do NOT film (not-built / disabled)
- Design & generate **other modalities** (protein/peptide/biologics) — spec 11.6 marks biologics not-built.
- Billing/quota, IND Report entry point, CRO Library — disabled in product (per CLAUDE.md + memory).

---

## 4. QA / consistency defects (produced videos)

**Clean (verified defect-free):**
- **Scene ↔ narration integrity: PASS.** Per-scene `data-seconds` markers equal narration `## Step` counts exactly in all six (17/9/11/11/8/11). No orphan narration step without a scene, no orphan scene without narration.
- **EN/ZH step parity: PASS.** Identical step counts EN vs ZH in all six. (Deeper translation-quality/pronunciation review is out of scope for a static audit and must be done on the encoded audio per the series' own release checklist.)
- **Asset references: PASS.** Every `assets/…` image and `assets/live/*.{png,mp4}` clip referenced by the six HTMLs exists on disk. No broken media references.

**Defects:**

**D1 — Honesty-badge scheme is NOT consistent across the set (medium-high).** `drug-dev` uses a disciplined three-way verdict system — *Demonstrated here* (2×), *Available* (4×), *still a gap* (1×) — declared in its opening caption. **None of t0–t4 use this scheme.** They fall back to ad-hoc inline "honest"/"HONEST LIMITS" prose, and **t1 introduces a fourth label ("roadmap", 3×) that appears nowhere else.** There is no shared CSS badge class for honesty (only generic `badge concept` / `badge flow` exist). A skeptical viewer sees a different trust-signalling convention per video. Recommendation: lift drug-dev's Demonstrated/Available/Gap badge into a shared component and apply to all six.

**D2 — Naming/ID inconsistency across filename ↔ catalog ↔ written twin (medium).**
- Video `t3-run-and-report` vs catalog id `t3-running-a-workflow-and-reading-the-report` vs written `T3-running-a-workflow-and-reading-the-report.md`.
- Video `drug-dev` vs catalog id `t11-drug-development-end-to-end` vs written `T11-…`. The flagship video carries no "t11" in its filename, breaking the otherwise tN-aligned naming.
Pick one canonical slug per episode and use it for MP4, HTML, narration, catalog id, and written twin.

**D3 — Produced videos ship against UNVERIFIED catalog entries (high).** Catalog status is `IN_PRODUCTION_NOT_RELEASED`; release requires "Demonstrated function verified in real BioMate with reproducible evidence." Of the 6 produced: **t0 = BLOCKED**, the other 5 = **PENDING** (never marked verified). **t0 specifically was filmed against a route the catalog says not to film as working** (cold-start module dashboard does not mount). These are, by the series' own standard, not release-eligible masters.

**D4 — Content overlap / future duplication risk (low-medium).** drug-dev already *demonstrates* content that the catalog also plans as standalone focused episodes: `molecule-generation`, `multi-objective-ranking`, `molecular-docking`, `rbfe`, `pk-pbpk`, `wet-lab-loop`, `admet-evidence` (the last is catalog-status PARTIAL). Likewise t1↔drug-dev (design/ranking), t2↔drug-dev (closed loop), t3↔drug-dev (run/report/reproducibility record) overlap. This is acceptable as chapter-vs-end-to-end layering, but when the focused episodes are produced, lift clips from drug-dev rather than re-shooting, and cross-link to avoid the viewer seeing the same ADMET run explained twice with different numbers.

**D5 — "Available" vs "Demonstrated" honesty claims need live re-verification (medium).** drug-dev labels some stages *Available* (not demonstrated on camera) — e.g., RBFE/MD and parts of the PBPK/IND chain. Given D3 (all entries PENDING) and the Excel Roadmap (several of these are "Implemented (dev Batch pending)" / "Proposed"), each *Available* claim must be checked against real execution evidence before release, or downgraded to *still a gap*. Do not let an on-screen "Available" badge outrun the Roadmap status.

---

## 5. Recommended production order (remaining work)

Sequenced to (a) unblock verification first, (b) close mandate P1 gaps with maximum reuse, (c) then fill breadth.

1. **Fix + re-verify the shared surfaces, then re-cut t0.** Unblock the cold-start mount (catalog `m1`/`t0` BLOCKED cause); re-verify t1–t4 + drug-dev against live product; stamp each catalog entry verified with evidence. Nothing else should ship until the already-produced six are release-eligible.
2. **Standardize the honesty badge (D1) + canonical slugs (D2)** across the six — cheap, done once, before more videos multiply the inconsistency.
3. **Search & evidence video** (mandate "search" pillar; module 01) — once `m1` route is unblocked.
4. **Large-DB search video(s)** (Foldseek / MMseqs2 / FPSim2 / annotation lookups; mandate "DB" pillar; all Implemented).
5. **Cryo-EM SPA video** + **Cryo-EM instrument video** (pair them; P1 GPU, core-facility beachhead).
6. **RNA-seq + count-matrix DE video** (P1 freemium front door) + **BaseSpace/Nanopore instrument videos**.
7. **WGS cohort / germline variant-calling video** (P1/P2 genomics beachhead).
8. **Reports edit & export** + **full step-view** + **composer** videos (module 12/08/06 — written twins T8/W3 exist; fast to film).
9. **Single-cell, output-viewer focused set, projects/collaboration** videos (P2 breadth).
10. **Remaining instruments** (LC-MS, plate-reader, qPCR, flow, Opentrons, Benchling, SiLA) and **P3 focused episodes** (Models Train/Adapt/Optimise, ChIP/ATAC, metagenomics, dose-response/HTS, dataset versions/lineage).

Throughout: reuse drug-dev clips for the focused drug-dev episodes (D4); verify every *Available* badge against live evidence before it ships (D5); keep EN/ZH in lockstep (the current clean parity is the one thing not to regress).

---

*Audit only. No tutorial, narration, HTML, or catalog files were modified.*
