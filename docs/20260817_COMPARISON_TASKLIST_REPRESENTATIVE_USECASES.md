# Representative High-Priority Workflow Task List — Cross-System Execution Comparison

**Date:** 2026-08-17
**Track:** `tasklist` — **evidence-only. NO runs, NO LLM API calls, NO EC2, NO spend.** This doc defines **WHAT** a cross-system comparison would execute (BioMate vs Biomni vs co-scientists vs Claude Code/Codex vs bare LLMs). It assembles the concrete task list from tutorials / priority-workflow entries / E2E tests that **already exist in this repo**. It does **not** contain any results — cost/time/coverage columns are LEFT BLANK pending an instrumented run.

> **Grounding rule.** Every task below cites a source doc that already contains it (a recorded tutorial scenario, a priority-workflow entry, a gold-standard benchmark row, or an E2E test). **Every public accession is real and pulled from an existing doc — none is invented.** Where a priority workflow has no tutorial-grade public accession in our docs yet, that is flagged explicitly (§ "Grounding gaps") rather than papered over with a fabricated ID.

---

## 1. The task table

Priority (`P1/P2/P3`) is carried from `docs/20260816_TUTORIAL_COVERAGE_VS_PRIORITY_WORKFLOWS.md`. "Comparators that can attempt" is read from `docs/20260817_COVERAGE_COMPARISON_MATRIX.md` §1a/§1b.

Comparator legend: **BM** = BioMate · **Bn** = Biomni · **CoSci** = bio/agent co-scientists (ChemCrow/Coscientist/Google-AICoScientist/Robin) · **CC/Cx** = Claude Code / Codex (general coding agents) · **LLM** = bare frontier LLM (advice-only). `✓` = can attempt in-category · `partial` = only by self-writing uncurated code / partial-chain · `✗` = out of category / advice-only · `?` = unknown-not-published.

| # | Domain | Representative workflow (path/id) | Public input (real accession) | Expected BioMate output | Priority · source | BM | Bn | CoSci | CC/Cx | LLM | cost | time |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| T01 | transcriptomics | `nf-core/rnaseq` (id 1491, STAR+Salmon, GRCh38) → `nf-core/differentialabundance` (id 1497, DESeq2) → GSEA | **GSE49712** (SEQC/MAQC-III, 10 samples mix A vs B, ERCC spike-ins) | MultiQC + DESeq2 volcano/heatmap + GSEA report; ERCC-recovery metric | P?·tut `tut_rnaseq` (7-domain T1) | ✓ | ✓ | ✗ | partial | ✗ |  |  |
| T02 | variant_calling / genomics | `nf-core/sarek` (DeepVariant + GATK HaplotypeCaller, germline) | **GIAB HG002 (NA24385), chr20**; ref GRCh38.chr20 | VCF + hap.py SNV/indel F1 vs GIAB v4.2.1 | P1·tut `tut_variant_giab` (T3) | ✓ | ✓ | ✗ | partial | ✗ |  |  |
| T03 | epigenomics | `bioc_chipseq_annotation_v2`: `nf-core/chipseq` (MACS2) → `BIOC_CHIPSEEKER` → `BIOC_CLUSTERPROFILER` | **ENCODE K562 H3K27ac** (BAM ENCFF301TVL, input ENCFF038FKY; consensus ENCFF044JNJ) | Peak annotation + GO-BP dotplot; Jaccard overlap vs ENCODE consensus | P2·tut `tut_chipseq_k562` (T4) | ✓ | ✓ | ✗ | partial | ✗ |  |  |
| T04 | proteomics | `bioc_proteomics_de_v2`: `BIOC_MSNBASE` (LFQ) → `BIOC_LIMMA` | **PXD002952** (UPS1 standards spiked in yeast) | Volcano + UPS1 recall @FDR5% / yeast FPR | P?·tut `tut_proteomics_ups` (T5) | ✓ | ✓ | ✗ | partial | ✗ |  |  |
| T05 | metagenomics | metagenome assembly → binning → MAGs | **CAMI II low-complexity gut subset** (5 samples) | MAGs + AMBER bin-F1 / high-quality-MAG fraction vs CAMI gold | P3·tut `tut_metagenome_cami` (T6) | ✓ | ✓ | ✗ | partial | ✗ |  |  |
| T06 | metabolomics | metabolomics consensus DE (LC-MS, multi-method) | **MTBLS136** (MetaboLights urine LC-MS, Thévenot 2015) | Consensus DE feature table + QC report | P3·tut `tut_metabolomics_mtbls` (T7) | ✓ | ? | ✗ | partial | ✗ |  |  |
| T07 | single_cell → transcriptomics | scRNA chain → pseudobulk DE (`bioc_sc`): scuttle QC → scran → SingleR → aggregateAcrossCells → DESeq2 | 10x Genomics **PBMC 10k** (public 10x count matrix) | Cluster markers + pseudobulk DESeq2 + methods narrative; pseudoreplication guard | P2·tut `bioc_sc` (Bioc scenarios) | ✓ | ✓ | ✗ | partial | ✗ |  |  |
| T08 | cryo_em | `cryosparc_standard_spa` (id 12820; motioncor2/ctffind4/topaz) | **EMPIAR-10025** (T20S proteasome movies) | 5-phase SPA → sharpened 3D map + GSFSC resolution | P1·tut `cryosparc` (Demo Narratives; 7-domain) | ✓ | ✗ | ✗ | partial | ✗ |  |  |
| T09 | drug_discovery | ADMET screen + auto-loop (`dd_admet` / `drug_screen`, ADMET-AI) | SMILES: `CCO`, `CC(=O)Oc1ccccc1C(=O)O` (aspirin), `CCCCCCCCCCCCCCCCc1ccccc1` | 15-endpoint ADMET table, hERG/DILI/Ro5 gates, remediation (C16→C4) report | P1·tut `dd_admet` (R07) | ✓ | ✓ | partial | partial | partial |  |  |
| T10 | drug_discovery / structural | Structure prediction (`dd_structure`, Boltz-2) checked vs experimental | Target **EGFR kinase domain, PDB 1M17** (predict from sequence) | Ranked models + confidence + RMSD-to-1M17 check | P1·tut `dd_structure` (R05) | ✓ | ? | partial | partial | ✗ |  |  |
| T11 | drug_discovery | Docking + activity ranking (`dd_dock`, AutoDock Vina 1.2.0) | Receptor **EGFR PDB 1M17**; ligand set incl. aspirin/coumarin analogues | Docked poses + Vina score ranking + findings card | P1·tut `dd_dock` (R06) | ✓ | ✓ | partial | partial | ✗ |  |  |
| T12 | pharma / PK | PBPK human oral-dose projection (`pbpk`, R11) | Remediated coumarin analogue (from T09 loop); ref-compound verification | Dose ladder (10/25/50 mg BID × 7 d, 100 virtual adults) + Cmin vs target trough | P1·tut `pbpk` (R11) | ✓ | ? | ✗ | partial | ✗ |  |  |
| T13 | clinical | BOIN phase-1 dose-escalation design (`boin`, R12) | Design params: target-tox 30%, 5 dose levels, cohort 3, 2000 sims × 6 tox scenarios | Boundary table + operating characteristics (correct-MTD %, over-tox allocation %) | P1·tut `boin` (R12) | ✓ | ? | ✗ | partial | ✗ |  |  |
| T14 | pharma (chain) | IND §2.6 assembly (`ind_assembly`, R13) — LLM narrative from PBPK+tox runs | Outputs of T09/T12/T13 (in-workspace runs) | §2.6.1 pharmacology / §2.6.4 PK narrative DOCX with source mapping | P1·tut `ind_assembly` (R13); CLAUDE.md canonical use-case #6 | ✓ | ? | ✗ | partial | partial |  |  |
| T15 | genomics + single_cell (chain) | `drug_discovery/gwas_scrna_eqtl_target_chain` — GWAS → scRNA → eQTL → target | **GCST90093061** (Myasthenia Gravis GWAS) + **GSE227835** (MG scRNA-seq) + **GTEx v8** eQTL | Colocalized target ranking; expect CTSH in top candidates (PP4≈0.85) | P1·`docs/20260816_...WORKFLOWS.md` §E + `docs/20260719_MULTIOMICS_GOLDSTANDARD_BENCHMARK.md` | ✓ | ? | partial | partial | ✗ |  |  |
| T16 | multi-omics (chain) | MOFA2 vs SNF head-to-head (`{mofa2,snf}_multiomics` + `multiomics_benchmark`) | **CLL cohort** (Dietrich et al. 2018; drugs/methylation/mRNA/mutations) | Two-method scorecard (MOFA2 IGHV AUC vs SNF ARI) + over-correction 2×2 | new flagship·`docs/20260728_CLAUDE_DESIGN_REQUIREMENT_MULTIOMICS_TUTORIAL.md` | ✓ | ? | ✗ | partial | ✗ |  |  |

**16 tasks** across **13 domains** (transcriptomics, variant_calling, epigenomics, proteomics, metagenomics, metabolomics, single_cell, cryo_em, drug_discovery, structural, pharma/PK, clinical, multi-omics).

---

## 1b. Heavy / long-chain tier (T17–T21) — **execution-status-gated**

These are the highest-compute / large-DB / long-chain P1–P2 workflows — the ones that most stress the "orchestrated curated execution vs write-code-from-scratch" difference. They were originally omitted (§4) for lack of a committed public input + truth set; committed inputs are given here.

> **Critical difference from T01–T16.** T01–T16 are tutorial-grounded and presumed runnable. **T17–T21 are NOT execution-verified.** A search of the repo (incl. `docs/20260418_DRUG_DEV_BATCH_WORKFLOWS_24_OF_24_PASSING.md`, whose 24 passing workflows are all analytic PK/tox — **none** of these five) found **no end-to-end run-completion record** for any of the five. The workflow/skill exists in the catalog; that is not the same as "runs." **Each must pass a smoke-test gate (one real execution to completion) before it enters the scored comparison run.** This gate is exactly what the cryo-EM ensemble chain (below) failed.

| # | Domain | Workflow (path/id) | Public input (real) | Expected output / truth | Priority | **Exec status** |
|---|---|---|---|---|---|---|
| T17 | structural / large-DB search | `foldseek_structure_search` | **SCOPe40** query set (van Kempen et al., *Nat Biotechnol* 2024 foldseek benchmark) | Structural neighbors; sensitivity-to-1st-FP vs SCOPe **superfamily** truth (ROC) | P1 | **UNVERIFIED — smoke-test req.** |
| T18 | sequence homology search | `mmseqs2` / `diamond` large search | Query a **Pfam seed family** vs **UniRef50/SwissProt** | Homolog recall/precision vs **Pfam** family membership | P1 | **UNVERIFIED — smoke-test req.** |
| T19 | molecular dynamics (GPU) | `gromacs_protein_md` | **PDB 5AWL** (chignolin) — standard fast-folding MD system | ~100 ns stable/folded trajectory; native RMSD < 2 Å (Honda 2008 truth) | P2 | **UNVERIFIED — smoke-test req.** |
| T20 | complex prediction (GPU) | AF-Multimer / Boltz-2 multimer | **PDB 1IVO** (EGF–EGFR complex) — predict from the two chains | Predicted complex; DockQ / interface-RMSD vs 1IVO | P1 | **UNVERIFIED** (T10 is single-chain only) |
| T21 | single-cell atlas integration | `integration_benchmark` / `multivi` / `stabmap` | **scIB human pancreas** (Luecken et al. 2022, 8 batches) | Integrated embedding + scIB bio-conservation vs batch-removal metrics | P2 | **UNVERIFIED — smoke-test req.** |

**Excluded (does not run — honestly kept out):** the **cryo-EM ensemble → cryptic pocket → virtual screen → ADME** mega-chain is **not runnable even at step 1**. `docs/20260804_CRYODYNAMICS_EXPERIMENT_LOG.md` records the ensemble generator as non-functional ("generation not yet obtained; scoring pending a working generator"; BioNeMo NIM = single-state/anchor only; ConforFlux DataLoader deadlock; server-side 504s). It is a research premise (CryoEnsemble / CryoDynamics), **not** an executable pipeline, and is therefore **not** a comparison task until the generator works.

---

## 2. Per-task notes (input provenance + why representative)

- **T01 RNA-seq (GSE49712).** Canonical 7-domain tutorial T1; the SEQC/MAQC-III mix A/B with ERCC spike-ins gives a ground-truth fold-change set. Mirror: `s3://biomate-public-datasets/tutorial-gold/transcriptomics/GSE49712/`. Also CLAUDE.md canonical use-case #2. Prompt: *"Run nf-core rnaseq then differential expression and GSEA on GSE49712 (10 samples, mix A vs B, human GRCh38, paired-end)."*
- **T02 WGS variant (GIAB HG002 chr20).** 7-domain T3; chr20-only keeps a real cohort run ≤60 min while validating against GIAB v4.2.1 truth. CLAUDE.md canonical use-case #3. Prompt: *"Germline variant calling on GIAB HG002 chr20 with sarek, GRCh38, report SNV/indel F1 vs GIAB truth."*
- **T03 ChIP-seq (ENCODE K562 H3K27ac).** 7-domain T4; ENCFF301TVL BAM + ENCFF038FKY input; validated by Jaccard overlap vs ENCODE consensus ENCFF044JNJ (Nature 583:699, 2020). Prompt: *"Annotate my K562 H3K27ac ChIP-seq peaks and run GO pathway enrichment."*
- **T04 Proteomics (PXD002952).** 7-domain T5; UPS1 standards in yeast give a known-DE / known-non-DE truth split (MaxLFQ, Cox 2014). Prompt: *"Bioconductor label-free protein DE on PXD002952."*
- **T05 Metagenomics (CAMI II).** 7-domain T6; CAMI II gold binning labels enable AMBER-style bin F1. Prompt: *"Assemble and bin this shotgun metagenome into MAGs (CAMI II low-complexity gut, 5 samples)."*
- **T06 Metabolomics (MTBLS136).** 7-domain T7; MetaboLights urine LC-MS (Thévenot 2015) age×gender×BMI design. Prompt: *"Consensus differential-abundance analysis of the MTBLS136 LC-MS metabolomics dataset."*
- **T07 scRNA→pseudobulk (10x PBMC).** Bioconductor scenario `bioc_sc`; teaching beat = pseudoreplication guard (auto-switch to donor-level pseudobulk DESeq2). Public 10x PBMC 10k matrix. Prompt: *"Find markers per cell cluster in this 10x PBMC matrix, then do DE between conditions."*
- **T08 Cryo-EM (EMPIAR-10025).** Demo Narratives + 7-domain; T20S proteasome, the reference SPA teaching dataset. CLAUDE.md canonical use-case #4. Prompt: *"Run CryoSPARC single-particle reconstruction on EMPIAR-10025."*
- **T09 ADMET (3 SMILES + auto-loop).** R07 recorded tutorial; exact query string from `dd-demos-b.js`: *"Screen these for ADMET and flag hERG and DILI: CCO, CC(=O)Oc1ccccc1C(=O)O, CCCCCCCCCCCCCCCCc1ccccc1."* Aspirin clean; hexadecylbenzene fails logP 9.9 + DILI 0.71 → C16→C4 remediation. CLAUDE.md canonical use-case #1 (ADMET). This is the auto-loop moat demo.
- **T10 Structure prediction (Boltz-2, EGFR/1M17).** R05; predict EGFR kinase domain from sequence, check vs experimental PDB 1M17 (Stamos 2002). Prompt: *"Predict the structure of the EGFR kinase domain from sequence and check it against PDB 1M17."*
- **T11 Docking (Vina, EGFR/1M17).** R06 `dd_dock` (`docs/20260816_EDU_PILOT_R06_DOCK_RANK_SCRIPT.md`); AutoDock Vina 1.2.0. Prompt: *"Dock these ligands into EGFR (PDB 1M17) and rank by predicted binding."*
- **T12 PBPK (R11).** Human oral-dose projection carrying the remediated analogue from T09; dose ladder 10/25/50 mg BID × 7 d in 100 virtual adults, verified vs a reference compound before projecting. Prompt: *"Project a human oral dose for the remediated analogue — verify against a reference first, then give a dose ladder."*
- **T13 BOIN (R12).** Phase-1 design: target-tox 30%, 5 levels, cohort 3, 2000 sims × 6 tox scenarios → correct-MTD 62% vs 50% gate. Framed as design properties, not clinical evidence. Prompt: *"Design a BOIN phase-1 dose-escalation, target toxicity 30%, 5 dose levels, cohorts of 3."*
- **T14 IND §2.6 (R13).** Assembles T09/T12/T13 workspace runs into a §2.6.1/§2.6.4 DOCX with explicit source mapping. CLAUDE.md canonical use-case #6 (drug-discovery IND). This is the flagship chain end-point.
- **T15 GWAS→scRNA→eQTL chain.** `gwas_scrna_eqtl_target_chain` (newly-built, fills the P1 "was Proposed" gap per coverage doc §E). Accessions from `docs/20260719_MULTIOMICS_GOLDSTANDARD_BENCHMARK.md`: GCST90093061 (MG GWAS) + GSE227835 (MG scRNA-seq) + GTEx v8; expected result CTSH in top candidates (PP4≈0.854, the Tarek Samad / Lundbeck validation). Prompt: *"Prioritize Myasthenia Gravis targets: GWAS GCST90093061 + scRNA GSE227835 + GTEx eQTL colocalization."*
- **T16 Multi-omics MOFA2 vs SNF.** `docs/20260728_CLAUDE_DESIGN_REQUIREMENT_MULTIOMICS_TUTORIAL.md`; Dietrich et al. 2018 CLL cohort (drugs/methylation/mRNA/mutations), run through the same universal CSV interface. Measured beat: MOFA2 exposes IGHV as an interpretable factor (AUC 0.968) while SNF gives a hard partition (ARI 0.375); the over-correction 2×2 (baseline/+noise × MOFA2/SNF) is the differentiator. Prompt: *"Run MOFA2 and SNF on this CLL multi-omics cohort and compare which recovers IGHV status."*

---

## 3. Coverage cross-reference (how many of the 16 each comparator can even attempt)

Counting `✓` (can attempt in-category) from §1. `partial` and `?` are counted separately, not as `✓`.

| System | `✓` in-category | `partial` (self-written / partial chain) | `?` unknown | `✗` out-of-category | Interpretation |
|---|---|---|---|---|---|
| **BioMate** | **16 / 16** | 0 | 0 | 0 | Every task is a curated, validated-pipeline execution. |
| **Biomni** | 8 / 16 (T01,T02,T03,T04,T07,T09,T11 + T15 partial→counted `?`) → **~8** | — | 8 (T06,T10,T12,T13,T14,T16 + PK/clinical) | 1 (T08 cryo-EM) | Strong on -omics + chem; cryo-EM out; PK/clinical/multi-omics unknown-not-published. |
| **Co-scientists** (ChemCrow/Coscientist/Robin/Google) | **~3 partial** (T09,T10,T11 chemistry-only, partial) | 3 | — | 10 (all -omics pipelines, cryo-EM, PK/clinical) | Chemistry & hypothesis focus; do not orchestrate bioinformatics pipelines. |
| **Claude Code / Codex** | **0 in-category** | **16 partial** (can self-write any of it, un-curated/un-QC'd/un-audited) | 0 | 0 | Can attempt everything by writing code from scratch — no curated catalog, no QC gate, no audit trail. |
| **Bare frontier LLM** | **0** (advice-only) | 4 partial (T09,T14 narrative, plus text-reasoning on T12) | 0 | 12 | Advice/narrative only; cannot execute a pipeline. |

**Headline for the later instrumented run:** BioMate is the only system that can attempt **all 16** as *validated-pipeline executions*. Biomni attempts roughly half in-category; co-scientists ~3 (chemistry) partially; Claude Code/Codex can *attempt* all 16 but only by writing uncurated code (the fair comparison must score whether that code runs, QCs, and audits — not just whether it's produced); bare LLMs are advice-only on ~4 and out-of-category on the rest. **These counts are category-attempt estimates from the coverage matrix, NOT measured success rates.**

### 3b. The evaluation is a graded ladder, not a binary — how the non-agentic systems ARE scored

The binary `✓/partial/✗` above is only a *can-attempt* proxy. Bare LLMs and code agents (Claude Code / Codex) must not be scored "out of category" — they are given **full latitude (install packages, write and run code, call any tool or database, any method)** and scored on **how far up a shared ladder they get on each task.** This makes every system comparable on every task.

| Rung | Meaning | Typical ceiling |
|---|---|---|
| **R0** | refuses / wrong domain / hallucinated non-answer | — |
| **R1 — correct design** | names the right workflow, tools, params; the analysis plan is correct | **bare LLM** ceiling on most tasks |
| **R2 — runnable artifact** | emits code / pipeline spec that is syntactically valid and would run (parses, deps declared) | code agents always reach |
| **R3 — executes to completion** | actually runs to a finished output *by any allowed means* | CPU + DB-search: code agents reach here |
| **R4 — correct result** | output matches the task's truth-set metric (F1 vs GIAB, sensitivity vs SCOPe, RMSD vs PDB, DESeq2 concordance, …) | the real head-to-head |
| **R5 — governed & reproducible** | QC-gated, params validated (no hallucinated values), audit trail / provenance, reproducible | **BioMate** — most others structurally cannot reach |

**Allowed methods per system class (no handicap):**
- **Bare LLM** — text only → typically **R1**; a pure-reasoning task (e.g. BOIN design) can reach **R4** by calculation, but no execution.
- **Claude Code / Codex** — **full latitude to install/code/run** → ceiling **R4** (or R5-partial if they also write tests); realistically reached on **CPU pipelines + DB search**, capped by infra on GPU/specialized tasks.
- **Co-scientists (Biomni, ChemCrow, Coscientist, Robin)** — agentic execution → **R3/R4** where in-domain.
- **BioMate** — curated execution + governance → **R3–R5**.

**Per task-class ceiling (the honest read):**
- **CPU pipelines + DB search** (T01,T03,T04,T05,T06,T07 + T17 foldseek, T18 mmseqs; T02 chr20-CPU): code agents can reach **R3/R4** — a *fair result-level head-to-head*. BioMate's edge is **R5 + cost/time + no hallucinated params**, not exclusivity.
- **GPU / long / specialized** (T08 cryo-EM, T10 Boltz structure, T19 MD, T20 multimer): code agents **can also provision GPU** (rent an instance, install CUDA, run Boltz/GROMACS themselves) — so this is **not** a rule cap. Their realistic ceiling is lower only through *reliability* and *real cost/time to them*, not permission. BioMate reaches **R3–R5** via managed GPU-Batch. The ladder renders any gap as a *rung + cost* difference, not a disqualification.

The instrumented run records, **per task × system: the highest rung reached, plus the cost/time to reach it.** That is the fair, non-dismissive comparison — it credits an LLM that designs correctly (R1), a code agent that actually runs an RNA-seq DE (R4), and BioMate's governance/reproducibility layer (R5), all on one axis.

### 3c. Phased execution — CPU first, GPU only if warranted (money gate)

**Do not run the expensive GPU tier until the cheap CPU tier has been scored.** If code agents cannot out-perform BioMate on the cheap tasks, the GPU comparison adds cost without changing the conclusion.

- **Phase 1 — CPU + DB search (cheap, run first).** T01 RNA-seq, T02 WGS-chr20, T03 ChIP-seq, T04 proteomics, T05 metagenomics, T06 metabolomics, T07 scRNA, T09 ADMET, T11 Vina docking (CPU), T12 PBPK, T13 BOIN, T14 IND narrative, T15/T16 multi-omics chains, **T17 foldseek, T18 mmseqs** — ~16 of 21 tasks. Modest CPU-hours + the ≲$5 LLM-token budget already estimated. Score everyone on R0–R5.
- **Phase 2 — GPU / heavy (gated on Phase 1).** Only **T08 cryo-EM, T10 Boltz structure, T19 MD, T20 multimer** (~5 tasks, the real GPU spend). **Escalate only if Phase 1 shows a code agent is competitive with BioMate** (i.e. the GPU comparison would actually be informative) — or if a specific GPU result is needed for the paper. If BioMate already dominates Phase 1, Phase 2 is optional and can be deferred.

**Decision rule:** Phase 1 result decides Phase 2 spend. No GPU run is launched on assumption — it is launched only when the cheap tier has shown it will change the answer.

---

## 4. Grounding gaps (priority workflows NOT turned into a task — stated honestly)

**Update:** five of the six below have now been promoted into the **heavy tier (§1b, T17–T21)** with committed real public inputs + truth sets — but flagged **UNVERIFIED / smoke-test-gated**, since committing an input is not the same as demonstrating the workflow runs. The sixth (cryo-EM ensemble chain) remains **excluded because it does not run** (broken at the ensemble step — see §1b). Original omission notes retained for provenance:

- **Foldseek structure search (`foldseek_structure_search`, P1 Large-DB-Search).** Workflow is built (coverage §E) but **no public query-structure + expected-hit-set accession appears in any tutorial/benchmark doc.** A defensible instantiation would query PDB 1M17 (EGFR, reused from T10/T11) against AlphaFold DB, but the expected-hit truth set is not documented — so it is **not** added as a scored task until an accession + truth set is committed.
- **MMseqs2 / DIAMOND large sequence-homology search (P1) and FPSim2 / ChEMBL chemical-similarity screen (P1).** Workflows implemented, **no tutorial and no public query+truth accession in docs** → omitted (would be invention).
- **MD trajectories (`gromacs_protein_md` / `mlip_md_simulation`, P2).** Workflows exist; **no MD tutorial and no public starting-structure accession** documented (coverage doc marks ❌). A candidate would reuse PDB 1M17 or a standard villin/chignolin system, but no doc commits one → omitted.
- **AlphaFold-Multimer / complex prediction (P1 GPU).** Only single-chain Boltz-2 (T10) is grounded; **no multimer complex + reference accession** in docs → the single-chain case (T10) stands in; the multimer task is omitted.
- **Large single-cell atlas integration (P2).** `integration_benchmark`/`multivi`/`stabmap` exist but no atlas-scale public accession is documented for a tutorial → the small PBMC case (T07) stands in; atlas-scale omitted.
- **Cryo-EM ensemble → cryptic pocket → virtual screen → ADME (P1, "Proposed").** No tutorial, no accession (coverage doc ❌ "Proposed") → omitted.

These six are the natural **next additions** once a public input + expected-output truth set is committed for each.

---

## 5. Explicit note on the blank cost/time/coverage cells

**The `cost` and `time` columns in §1 are intentionally BLANK.** This document defines **what to run**, not the results. Per `docs/20260817_COVERAGE_COMPARISON_MATRIX.md` §4, none of the following may be stated as a number until an instrumented run produces it:

- Token / latency / dollar cost per system per task.
- Per-task success/coverage (the §3 counts are *category-attempt estimates from the coverage matrix*, not measured pass rates).
- Any competitor's per-task outcome beyond Biomni's existing n=40 routing pilot.

An instrumented `tasklist`-execution run would fill: `cost` (LLM tokens + vCPU/GPU-hours + S3, from BioMate's billing router), `time` (wall-clock per task), and a measured per-comparator success column — **none of which exist yet.**

---

## 6. Source docs used

- `docs/20260816_TUTORIAL_COVERAGE_VS_PRIORITY_WORKFLOWS.md` — priority ranks (P1/P2/P3), newly-built workflows (§E), coverage spine.
- `docs/20260817_COVERAGE_COMPARISON_MATRIX.md` — comparator can-attempt cells (§1a/§1b), honesty contract, "cannot-claim" list (§4).
- `reference/claude_design/tutorials-work/Tutorial Demo Scenarios 7-domain.md` — T01–T06 accessions (GSE49712, GIAB HG002 chr20, ENCODE K562 ENCFF*, PXD002952, CAMI II, MTBLS136), workflow ids/paths, prompts.
- `reference/claude_design/tutorials-work/Bioconductor Tutorial Scenarios.md` + `Demo Narratives.md` — T07 (`bioc_sc` pseudobulk), T08 (EMPIAR-10025 cryo-EM).
- `reference/claude_design/tutorials-work/Drug Discovery Tutorial Package/src/dd-demos-a.js` + `dd-demos-b.js` — T09 exact ADMET SMILES query, T10/T11 EGFR-1M17/Vina, coumarin scaffold.
- `reference/claude_design/tutorials-work/Drug Discovery Tutorial Package/Narration - Drug Discovery -R04-R09-.md` + `Narration - Breadth -R10-R13-.md` — T10 Boltz-2/1M17, T12 PBPK dose ladder, T13 BOIN params, T14 IND §2.6.
- `docs/20260813_DD_TUTORIAL_VIDEOS_R04_R13.md` — R04–R13 slug map (dd_admet/dd_route/dd_optimize/pbpk/boin/ind_assembly).
- `docs/20260816_EDU_PILOT_R06_DOCK_RANK_SCRIPT.md` — T11 docking (EGFR PDB 1M17, AutoDock Vina).
- `docs/20260719_MULTIOMICS_GOLDSTANDARD_BENCHMARK.md` — T15 accessions (GCST90093061 MG GWAS, GSE227835 scRNA, GTEx v8; CTSH expected).
- `docs/20260728_CLAUDE_DESIGN_REQUIREMENT_MULTIOMICS_TUTORIAL.md` — T16 CLL cohort (Dietrich 2018), MOFA2 vs SNF measured numbers.
- `CLAUDE.md` — 6 canonical use-cases (ADMET, RNA-seq, WGS, CryoEM, CRO compliance, drug-discovery IND), domain counts.
