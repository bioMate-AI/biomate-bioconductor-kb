# Claude Design Handoff — QC Gate Alignment Across Demos

**Date:** 2026-06-18
**For:** Claude design team — bioconductor-handoff, tier-0 drug-design, Zhi-lab, Zhao-lab
**Companions:**
- `reference/claude_design/bioconductor-handoff/src/BiocTours.jsx` (3 bioc tutorials)
- `reference/claude_design/design_handoff_tier0_design_pipelines/Tier-0 Demo Requirement.md` (T01–T05)
- `reference/claude_design/design_handoff_zhi_lab/Zhi-Lab Demo Requirement.md` (Z01, Z02-deprecated)
- `reference/claude_design/design_handoff_zhao_lab/Zhao-Lab Demo Requirement.md` (ZZ01, ZZ02)
- `docs/20260617_QC_CONFIG_BIOC_DESEQ2_REQUIREMENT.md` (companion implementation spec)

## Why this doc exists

The 3 bioconductor tutorials promise specific QC gates in the After-run "QC audit" tab (per `BiocTours.jsx` `qcBody` strings). Some of those promises don't map to what real Bioconductor workflows actually emit. The other 8 demos (T01–T05, Z01, ZZ01, ZZ02) don't promise QC gates in their requirement docs — meaning their QC tab will be empty in the recording unless something is done.

This doc tells the design team **for each demo: what to change in the design (if anything) so the recording matches reality.** All claims grounded in real catalog (`backend/database/galaxy_ai_tools.db`) + real `.nf` audits (no invented numbers).

## Three classes of "QC gate" in the design

| Class | Examples in current designs | Reality | Recommended design treatment |
|---|---|---|---|
| **A. Tool-emitted, runtime-measurable** | gene-retention, cells retained, cluster count, probes retained | Tool's code produces a number you can threshold | **Keep in design.** True QC gate. |
| **B. Result metric framed as QC** | significant-CpG count, DMR count, "X DE genes at FDR<0.05", binder_count | These are **findings**, not pass/fail gates. No published threshold exists. | **Move to Findings tab in design**, not QC tab. |
| **C. Methodological / routing decision** | replicate count, replicate-unit gate (sample vs cell), CpG-bias-corrected flag, size-factor range | The chain composer enforces these once at routing time, not per-run | **Reframe in design as AGENT / (why?) decision**, not a runtime QC gate. |

---

## Part 1 — The 3 Bioconductor tutorials (changes recommended)

### BIO — Bioconductor · KB routing & execution (bulk RNA-seq DESeq2)

**Current `BiocTours.jsx:169` qcBody:**
> "Every QC gate that fired — **gene-retention, size-factor range, replicate count** — with threshold, observed value, result and action. **21 CFR Part 11** friendly, with chain-of-custody."

**Audit:**
| Promise | Class | Tool-emitted? |
|---|---|---|
| gene-retention | A | ✅ `edger.qc_steps = ["filter low-expression genes"]`; `deseq2.qc_steps = ["low-count filtering"]` |
| size-factor range | C | ❌ Diagnostic plot only; no tool emits as gate |
| replicate count | C | ❌ Convention (Love 2014 FAQ recommends ≥3); not tool-emitted |

**Recommended new `qcBody`:**
> "Every QC gate that fired — **gene-retention after `filterByExpr`** and **dispersion estimability** — with threshold, observed value, result and action. **21 CFR Part 11** friendly, with chain-of-custody. *Replicate count and size-factor sanity are enforced upstream by the chain router and surfaced in the AGENT/(why?) block, not as runtime QC gates.*"

### BIO2 — Bioconductor · single-cell RNA-seq chain (scRNA → pseudobulk DE)

**Current `BiocTours.jsx:245` qcBody:**
> "Every QC gate — **cells retained, size-factor range, cluster count, pruned clusters, and the replicate-unit gate (sample, not cell)**. Threshold, observed value, result, action."

**Audit:**
| Promise | Class | Tool-emitted? |
|---|---|---|
| cells retained | A | ✅ `dropletutils`, `scater` emit |
| size-factor range | C | ❌ Diagnostic; not a gate |
| cluster count | A | ✅ `scran.qc_steps = ["cell QC metrics", "clustering QC"]` |
| pruned clusters | A | ⚠️ `scran` emits cluster QC; "pruned" is one possible per-cluster flag but not yet in any catalog row |
| replicate-unit gate | C | ❌ **routing decision** — the chain composer routes scRNA→pseudobulk only when N_samples ≥ 2. It's enforced once at chain dispatch. |

**Recommended new `qcBody`:**
> "Every QC gate — **cells retained, cluster count, and pruned-cluster flag**. Threshold, observed value, result, action. *The replicate-unit decision (sample vs cell as the unit of biological replication) is enforced at chain dispatch by the AGENT block — it fires once, before execution, not per phase.*"

### BIO3 — Bioconductor · 450k methylation chain

**Current `BiocTours.jsx:321` qcBody:**
> "Every QC gate — **samples read, probes retained, significant-CpG count, DMR count, and the CpG-bias-corrected flag**. Threshold, observed value, result, action."

**Audit:**
| Promise | Class | Tool-emitted? |
|---|---|---|
| samples read | A | ⚠️ `minfi` emits via `read.metharray` but catalog row has empty `qc_steps` — needs backfill |
| probes retained | A | ✅ `missmethyl.qc_steps = ["array detection QC"]` |
| significant-CpG count | B | ❌ **finding**, not QC. Result of `limma` DMP analysis. |
| DMR count | B | ❌ **finding**, not QC. Result of `dmrcate`/`dmrseq`. |
| CpG-bias-corrected flag | C | ❌ **method-choice gate** — the chain routes to `gometh` instead of generic GO; fires at dispatch. |

**Recommended new `qcBody`:**
> "Every QC gate — **samples read, detection-p pass rate, probes retained after SNP/cross-reactive filtering**. Threshold, observed value, result, action. *Significant-CpG count and DMR count are reported in the Findings tab; the CpG-bias-corrected method choice is surfaced in the AGENT/(why?) block at chain dispatch.*"

---

## Part 2 — The 5 tier-0 drug-design demos (T01–T05)

**Status:** the tier-0 `.nf` files **do not emit `qc_metrics.json`**. The `Tier-0 Demo Requirement.md` does not promise QC gates. So the design and implementation are consistent — **nothing is misaligned**.

**But:** the After-run report's "QC audit" tab will be **empty** when these demos record. The design needs to choose:

| Option | Implication |
|---|---|
| **A. Hide the QC audit tab** when no gates fire | Cleanest visual; the 7-tab structure becomes 6-tab for tier-0 |
| **B. Render an empty-state in QC audit tab** ("No QC gates fired for this run") | Keeps consistent 7-tab structure across demos; honest |
| **C. Add domain-specific QC gates** to each tier-0 .nf file | Requires per-demo scientific lead curation of what gates make sense. Months of work; not justified for the demo recording. |

**Recommended design change:** option **B** — render a brief empty-state in QC audit tab with one line per demo's nearest-fit gate:

| Demo | Empty-state line |
|---|---|
| T01 bispecific format triage | "Format scoring uses biophysical-axis rubric (Labrijn 2019 Nat Rev Drug Discov, Zhong 2024 iScience). Threshold-based gates are not emitted; ranking is by composite score." |
| T02 in-vivo CAR-T | "Atlas safety check is rule-based (fratricide flag, off-target tissue). No numeric threshold gates; output is a yes/no logic-gated recommendation." |
| T03 in-vivo base edit | "Editor selection + guide design are deterministic. CMC flag emission is binary (hepatotoxicity precedent per VERVE-101)." |
| T04 GLP-1 bake-off | "Modality scoring uses 6-axis rubric. Indication weighting (MASH→GCGR bonus) is a routing decision, not a runtime gate." |
| T05 modality triage | "Atlas tier check + CAR-T viability are categorical (CAR-T VIABLE / NOT VIABLE). No numeric thresholds; outputs are ranked." |

This is honest design — explicit absence of numeric gates, with one line saying why.

---

## Part 3 — The latest single-cell + GWAS demos (Z01, ZZ01, ZZ02)

### Z01 — TorchGWAS on UDIP brain phenotypes (Zhi lab)

**Status:** `torchgwas_udip_phenotype_scan/main.nf` emits 4 phase JSONs (`phenotype_qc.json`, `kernel.json`, `scan.json`, `loci_report.json`) but no `qc_metrics.json` with threshold/observed/action triples.

**Reality vs design:** the Zhi-Lab Demo Requirement.md does NOT promise QC gates in `qcBody`. Same as tier-0 — design + implementation consistent, but QC tab will be empty.

**Recommended empty-state line:**
> "GWAS QC follows GCTA + MAGMA conventions (lambda inflation, MAF, HWE, call rate). Per-variant gates are not emitted by this demo; production workflows would surface lambda_gc + manhattan-region QC. See `docs/20260618_BC10_CHAIN_RANKING_REQUIREMENT.md` for the per-workflow `qc_metrics.json` plumbing path."

**MORE IMPORTANT design opportunity** (per audit of Dr. Zhi's actual paper methods, PMC12458571):

Zhi's real published pipeline uses **GCTA + JAGWAS + METAL + MAGMA + FUMA + LDSC + PRS-CS** — all standard tools, none currently in BioMate's catalog. The demo currently shows the UDIP→TorchGWAS hop only. To make Z01 represent the *real* Zhi workflow, the design should:

| Add to demo timeline | Backing |
|---|---|
| Phase E — gene-based test (MAGMA) | Per Zhi's UDIP-FA Methods §"MAGMA (version 1.08)" |
| Phase F — meta-analysis (METAL) across discovery + replication cohorts | Per Zhi's Methods §"METAL to perform the meta-analysis" |
| Phase G — functional annotation (FUMA) | Per Zhi's Methods §"FUMA functional annotation" |
| Phase H — heritability + cross-trait genetic correlation (LDSC) | Per Zhi's Methods §LDSC |
| Phase I — PRS replication in independent cohort (PRS-CS) | Per Zhi's Methods §"polygenic score…using PRS-CS" |

This would make Z01 a 4 → 9 phase demo and represent Zhi's actual paper end-to-end. **Effort: BioMate-side wrap of 5 standard tools (~6–8 days total, per `docs/20260618_RESEARCHER_TOOL_AUDIT.md` if that exists, or to be authored).**

If 9 phases is too long for a 3-minute demo, alternative: keep Z01 as 4 phases (current), and add a chat-side "this is one of 9 typical phases in a Zhi-paper GWAS — full pipeline available via [link to extended demo]" beat at the end.

### ZZ01 — Tumor-reactive T-cell chain (Zhao lab: turep + Scupa + ImmuneApp)

**Status:** 3 workflows × 3 phases = 9-phase chain. The `.nf` files emit phase JSONs (cell counts, polarization scores, binder counts) but no `qc_metrics.json`.

**Reality vs design:** Zhao-Lab Demo Requirement.md does not promise QC gates in qcBody. Demo's "QC audit" tab will be empty.

**Recommended empty-state line:**
> "Per-step calibration (turep ECE 0.038, Scupa polarization scoring, ImmuneApp rank-percentile ≤2%) is reported in the Findings tab as calibration metrics, not as pass/fail QC gates. Underlying tools emit prediction confidence rather than threshold-gated alerts."

**Important consistency note:** the `binder_count: 147` value in the `.nf` (`immuneapp_phaseB.json`) is a **finding**, not a QC gate. Design correctly does not promise it as a gate.

### ZZ02 — Single-cell GWAS for immune cell types (Zhao lab: scGWAS)

**Status:** `scgwas_immune_cell/main.nf` rewritten with real `java -jar` invocation; Phase C emits `significance.json` with z-cutoff source cited.

**Reality vs design:** Zhao-Lab Demo Requirement.md does not promise QC gates. But the real scGWAS run (verified live this session in container) produces these natural gates from its log:
- `Read in GWAS genes: 18787` — input completeness
- `Identified 25 cell types`
- `# nodes = 7970 (with weights from both GWAS and scRNAseq files)`
- `Shared genes: n = 8529` — overlap quality

**Recommended design enhancement for ZZ02 QC tab** (cheap — backfillable):
| Gate | Threshold suggested | Tool-emitted? |
|---|---|---|
| `gwas_genes_loaded` | ≥10,000 | ✅ scGWAS JAR stdout |
| `cell_types_identified` | ≥10 | ✅ |
| `shared_genes` | ≥3,000 (per scGWAS paper validation) | ✅ |
| `significant_modules` (per cell type) | reported, no hard threshold | finding, not gate |

These are all in class **A** (tool-emitted, runtime-measurable). The .nf wrap could parse the JAR log and emit `qc_metrics.json` for the design's QC tab to render real numbers.

---

## Part 4 — Liu-lab demo (L01)

### L01 — Rare Disease Multi-Modal Workup (chain id 1)

**Pipeline:** sarek → vcf_annotate_ensemblvep → rnaseq → drop (OUTRIDER+FRASER) → case_report_aggregation. Already exists in BioMate today.

**Catalog `qc_steps` state:** 1 of 5 phases populated (OUTRIDER has 1 tag); rest are empty.

**Gates that the underlying tools naturally emit:**

| Phase | Tool | Tool-emitted gates (all class A) | Effort to surface |
|---|---|---|---|
| A | sarek | ts/tv ratio, depth-of-coverage, het/hom ratio, dbSNP overlap %, callable-region pct | Backfill qc_steps (~30 min) |
| B | VEP | pct-annotated (class A); novel-vs-known split (class B → Findings) | ~15 min |
| C | nf-core/rnaseq | alignment rate, rRNA %, mt %, exonic-rate, gene-detection count, duplication rate, junction-rate, FastQC pass | Backfill (~30 min) |
| D | nf-core/drop (OUTRIDER+FRASER) | OUTRIDER dispersion convergence, aberrant_gene_count; FRASER psi-coverage pass, theta-fitting convergence, aberrant_event_count | A: convergence + coverage gates; B: aberrant counts → Findings (~30 min) |
| E | case_report_aggregation | evidence-stream completeness, missing-data flag, sample-count match | All class A (~15 min) |

**Net for L01 design:** 8–10 class-A gates available across 5 phases. Recommended `qcBody` text drafted in `reference/claude_design/design_handoff_liu_lab/Liu-Lab Demo Requirement.md` §"QC gates — what each phase actually emits". No invented thresholds; all from MultiQC + sarek/RSeQC/STAR/OUTRIDER/FRASER native outputs.

**Engineering open item:** extend the `qc_steps` backfill script (the one that ran for 34 RNA-seq DE workflows in commit `4e47c14f8`) to cover sarek + VEP + rnaseq + drop + fraser + case_report_aggregation. ~1–2 hours.

---

## Summary of design changes requested (final)

| Demo | Change | Why |
|---|---|---|
| BIO DESeq2 | Edit qcBody (drop size-factor range + replicate count from gate list; reframe as AGENT/router decisions) | Class C, no tool emits |
| BIO2 scRNA | Edit qcBody (drop size-factor range; reframe replicate-unit gate as AGENT/dispatch) | Class C |
| BIO3 methyl | Edit qcBody (move significant-CpG count + DMR count to Findings; reframe CpG-bias as AGENT) | Class B + C |
| T01–T05 | Add empty-state line to QC tab (or hide tab) | No QC emissions; honest signal |
| Z01 TorchGWAS | Add empty-state line **+** consider extending demo to 9 phases representing Zhi's real paper pipeline (MAGMA, METAL, FUMA, LDSC, PRS-CS) | Current demo shows 1/2 of the published Methods section |
| ZZ01 turep+Scupa+ImmuneApp | Add empty-state line (calibration ≠ QC) | No threshold-gated QC; only model calibration metrics |
| ZZ02 scGWAS | Add 3 tool-emitted gates (gwas_genes_loaded, cell_types_identified, shared_genes) | Smoke test verified jar emits these to stdout |
| **L01 Liu RareCollab** | **Adopt the 8–10 class-A gates spec'd in the Liu-Lab Demo Requirement doc** | All from sarek/VEP/rnaseq/drop native MultiQC output; cleanest QC-tab story of any demo because tools are mature + already used in his published Methods |

## Out of scope

- Adding gates that no published tool emits (no invented thresholds — per `CLAUDE.md` discipline)
- The 13 other curated chains (CRO, drug discovery, regulatory) — separate audit
- Per-workflow `qc_metrics.json` plumbing — already specced in `docs/20260617_QC_CONFIG_BIOC_DESEQ2_REQUIREMENT.md`

## Background reading

- `docs/20260617_QC_CONFIG_BIOC_DESEQ2_REQUIREMENT.md` — per-workflow qc_metrics emission plan
- `docs/20260618_BC10_CHAIN_RANKING_REQUIREMENT.md` — chain ranking + LLM fallback fixes
- `docs/20260617_RESEARCHER_OUTREACH_SESSION.md` — session-end state
- `reference/claude_design/bioconductor-handoff/src/BiocTours.jsx` — design source for 3 bioc tutorials
- `reference/claude_design/bioconductor-handoff/src/PhaseCard.jsx:101-126` — design's QcBlock component
- Live evidence (verified this session):
  - `bsml320/scGWAS@main` jar runs end-to-end in `biomate/scgwas:v1` container, completes through quantile normalization
  - Zhi's UDIP-FA Methods §"GCTA … MAGMA … METAL … FUMA … LDSC … PRS-CS" (PMC12458571)
  - Zhao's scGWAS Methods §"MAGMA v1.07 … PathwayCommons v12 … recommends Seurat / Scanpy" (PMC9575201)
