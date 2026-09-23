# Epigenomics (ChIP-seq & ATAC-seq)

> One-line promise: go from raw ChIP-seq or ATAC-seq reads to a **peak set**,
> a table of the **genes those peaks sit next to**, and the **pathways** they
> implicate — with the read-quality and enrichment gates that tell you whether
> the peaks are real before you interpret them.
> For: **wet-lab biologists / PIs** mapping where a transcription factor binds
> or where chromatin is open, and **bioinformaticians** who want the nf-core
> production peak-calling chain plus the Bioconductor annotation hand-off run
> and reported for them. No coding required.

<!--
P2 chapter. Every "supported" claim below is green in coverage-ledger.md § "Epigenomics (ChIP-seq / ATAC-seq)".
Honesty rule: a QC threshold is documented as "code-enforced" ONLY where it lives in pipeline code
(qc_trace_monitor.py). Thresholds that live only in the tutorial demo spec are labelled "spec / advisory" and
the real code behaviour is stated where it differs (notably FRiP, which the tutorial calls a hard gate but the
code treats as advisory-only, per ENCODE4). Anything not built is in "What's not covered".
-->

## What this is for

This is the **"where in the genome is this signal, and what genes does it
touch"** path. Two closely related assays share the chapter because they share
the machinery:

- **ChIP-seq** — you pulled down a protein (a transcription factor, a histone
  modification like H3K27ac) with an antibody and want to know *where it binds*.
- **ATAC-seq** — you want to know *which regions of chromatin are open* (Tn5
  transposase inserts preferentially into accessible DNA).

Both produce the same shape of answer: a set of **peaks** (enriched genomic
intervals), which BioMate then annotates to the nearest genes and runs pathway
enrichment on. The through-line is interpretation: every QC number below is
explained as "what it means and what to do next," and the worked example ends on
a *decision* (these peaks, these genes, this confidence), not a process tree.

> **Tip** — If you already have a peak file (a BED / narrowPeak from a previous
> run or a collaborator), you do not need to re-align. The Bioconductor
> annotation chain (`bioc_chipseq_annotation_v2`) takes a peak file directly and
> goes straight to genes + pathways — the cheap, fast lane. Alignment + peak
> calling (nf-core) is the expensive AWS Batch step; run it only when you have
> raw reads.

## Use cases

| Goal (researcher's words) | Workflow(s) / chain | Inputs | Outputs (artifact) | Lane |
|---|---|---|---|---|
| "Call peaks from my ChIP-seq FASTQ, then tell me which genes they hit" | `nf-core/chipseq` (id **1492**, bwa + MACS2) → chain `bioc_chipseq_annotation_v2` (ChIPseeker → clusterProfiler) | FASTQ + sample sheet (sample, fastq, antibody, control) | Peak BED + annotated-peaks CSV + peak-distribution plot + pathway dotplot | Cloud (AWS Batch) |
| "I already have peaks — annotate them and run pathway enrichment" | chain **`bioc_chipseq_annotation_v2`**: `chipseeker` (id **11090**) → `clusterprofiler` GO (id **11122**) | BED / narrowPeak / broadPeak | Annotated-peaks CSV + peak-feature-distribution plot + GO dotplot | Cloud |
| "Call open-chromatin peaks from my ATAC-seq FASTQ" | `nf-core/atacseq` (id **12673**, bwa + MACS2 + ataqv QC) | FASTQ + sample sheet (sample, fastq, replicate) | Peak BED + bigWig tracks + MultiQC (TSS enrichment, FRiP) | Cloud |
| "Find peaks that differ between two conditions (differential binding)" | `diffbind` (id **11262**) | BAMs + peak sets + sample sheet | Differential-binding table (log2FC, FDR) | Cloud |
| "What motifs are enriched under my peaks?" | `Find Enriched Motifs With Homer` (id **10667**) | Peak BED + genome | HOMER motif-enrichment table | Cloud |

> **Pitfall — the annotation chain is only two steps.** `bioc_chipseq_annotation_v2`
> is **ChIPseeker → clusterProfiler**. Alignment and MACS2 peak calling
> (`nf-core/chipseq`) are a **separate pre-step run before the chain**, not links
> inside it. That is by design (it is the natural hand-off from an nf-core BED
> output), and it is why you can enter at the annotation step with a peak file you
> already have. Don't expect a single "one-click FASTQ→pathways" chain object —
> the FASTQ path is nf-core/chipseq *then* the chain.

## How to ask

BioMate routes on intent. The disambiguation that matters here is **what you
already have** (raw FASTQ vs a peak BED) and **which assay** (ChIP vs ATAC).

Peak annotation (the fast lane — you already have peaks):

> "Annotate my ChIP-seq peaks and run pathway enrichment."

Full peak calling from FASTQ:

> "Call peaks from my ChIP-seq FASTQ (H3K27ac, with input control), reference
> GRCh38, then annotate the peaks and run GO enrichment."

The annotation chain is triggered by peak-file context: its example queries
include *"annotate my chip-seq peaks"*, *"what genes are near my peaks"*,
*"chipseeker annotation of bed file"*, and it triggers on upstream workflows
`chipseq` / `cut_and_run` / `cutandtag` and on output extensions
`bed` / `narrowPeak` / `broadPeak`
(`backend/lib/galaxy/ai/bioc_chain_templates.py:215-228`).

**Disambiguation to avoid:**

- **ChIP-seq vs ATAC-seq.** They use different nf-core pipelines
  (`nf-core/chipseq` id 1492 needs an **antibody + input control** column;
  `nf-core/atacseq` id 12673 does not — it takes a **replicate** column and adds
  ATAC-specific QC like TSS enrichment). Name the assay so the right pipeline and
  the right QC gates apply.
- **Narrow vs broad peaks.** Point sources (transcription factors, H3K4me3)
  give **narrow** peaks; spread-out marks (H3K27me3, H3K36me3, and by default
  histone marks) give **broad** peaks. The stub default is broad
  (`params.macs2_broad=true`; `backend/biomni_workflows/nfcore/chipseq/main.nf:16-17`).
  For a sharp mark say "narrow peaks" so MACS2 is set correctly.
- **Single-sample peaks vs differential binding.** "Where does it bind" =
  peak calling + annotation. "What changed between conditions" = **DiffBind**
  (id 11262), which needs replicate BAMs per condition. These are different
  questions; name the comparison if you want differential binding.

> **Tip — one word picks the assay.** "ATAC-seq" / "open chromatin" /
> "accessibility" routes to `nf-core/atacseq` and its ENCODE4 ATAC QC (TSS
> enrichment, NRF). "ChIP-seq" / "H3K27ac" / "transcription factor binding"
> routes to `nf-core/chipseq`. The peak-annotation chain is assay-agnostic — it
> annotates whatever peak file you give it.

## Tools & workflows behind this

| Tool / workflow | Role | Where (verified) |
|---|---|---|
| `nf-core/chipseq` (id **1492**) | bwa alignment + MACS2 peak calling + IDR; `qvalue=0.05`, `genome` param, narrow/broad toggle | `backend/biomni_workflows/nfcore/chipseq/main.nf:12-23`; DB id 1492 |
| `nf-core/atacseq` (id **12673**) | bwa + MACS2 + ataqv ATAC QC (TSS enrichment, fragment sizes) | `backend/biomni_workflows/nfcore/atacseq/main.nf:4-18`; DB id 12673 |
| Chain `bioc_chipseq_annotation_v2` | 2-step downstream: annotate peaks → pathway enrichment | `backend/lib/galaxy/ai/bioc_chain_templates.py:184-228`; DB `workflow_chains` |
| `chipseeker` (id **11090**) | Annotate peaks to nearest gene + genomic feature; `tss_region=[-3000,3000]`, `organism=hg38` | DB id 11090; chain step 1 `bioc_chain_templates.py:196-202` |
| `clusterprofiler` (id **11122**) | GO enrichment on annotated genes; `ontology=BP`, `organism=hsa` | DB id 11122; chain step 2 `bioc_chain_templates.py:203-208` |
| `diffbind` (id **11262**) | Differential binding across conditions | DB id 11262 |
| `Find Enriched Motifs With Homer` (id **10667**) | Motif enrichment under peaks | DB id 10667 |

The chain's step-to-step hand-off is real: ChIPseeker's `results` output feeds
clusterProfiler's `gene_list` input
(`bioc_chain_templates.py:210-212`). That is why a peak BED can enter at step 1 —
the contract is the peak file, not a fixed pipeline position.

> **License** — nf-core/chipseq, nf-core/atacseq, and the Bioconductor packages
> (ChIPseeker, clusterProfiler, DiffBind) plus HOMER are open-source academic
> tools; results are yours. GRCh38 and GO/KEGG annotations are the standard
> public releases.

## QC gates & how to read them

A QC gate answers one question: **"are these peaks real signal, or noise?"** The
gates sit at read alignment, library complexity, and signal-to-noise enrichment.

| Gate | Threshold | What a fail means | Enforced where |
|---|---|---|---|
| **Peaks called** | **≥ 1,000** (default) | Almost no peaks = failed IP, wrong antibody, or too few reads. | **Code-enforced.** `qc_trace_monitor.py` peak-calling verdict (`peaks_called` threshold, default 1000) |
| **ChIP FRiP (fraction of reads in peaks)** | Advisory **< 0.01** only | Very low FRiP = poor enrichment (the antibody didn't pull much down). | **Advisory-only** (non-blocking) for ChIP. `qc_trace_monitor.py:2706,4810-4827` — the tutorial's "FRiP ≥ 0.20" is **not** the ChIP code gate; see the pitfall |
| **ATAC TSS enrichment** | **≥ 5** acceptable · **≥ 7** ideal · < 5 halt (< 3 critical) | Low TSS enrichment = the ATAC library isn't enriched at promoters — the transposition didn't preferentially hit open chromatin. | **Code-enforced (ATAC), HALT.** `qc_trace_monitor.py:4832-4845` (threshold 5.0, ideal 7.0); ENCODE4 ATAC-seq 2022 |
| **ATAC FRiP** | **≥ 0.2** acceptable · ≥ 0.3 ideal | Below 0.2, the accessible-chromatin signal is too weak relative to background. | **Code-enforced (ATAC), HALT.** `qc_trace_monitor.py:2773,4846-4858`; ENCODE4 ATAC-seq — note this differs from ChIP, where FRiP is advisory-only |
| **ATAC NRF (non-redundant fraction)** | **≥ 0.9** (< 0.5 critical) | Low NRF = heavy PCR duplication / low library complexity. | **Code-enforced (ATAC), HALT.** `qc_trace_monitor.py:4859-4872`; ENCODE4 ATAC-seq 2022 |
| **Peak overlap with ENCODE consensus** | tutorial target **≥ 80%** | Called peaks that don't overlap the reference call set = your peaks are novel-and-suspect or the run is off. | **Spec / validation only** — computed by the gold-standard validator, not a live in-pipeline gate |

**How to read each:**

- **Peaks called ≥ 1,000** — this is the "did the experiment work at all" gate.
  A run that returns tens of peaks almost always means a failed IP or the wrong
  antibody; don't interpret gene lists from it.
- **FRiP** — read differently by assay. For **ChIP-seq** it's a *quality
  thermometer*, not a pass/fail: BioMate follows ENCODE4 (which declines to set a
  hard ChIP FRiP cutoff), so the system only *advises* below 0.01. For
  **ATAC-seq** FRiP **is** a real code-enforced gate (≥ 0.2 acceptable, ≥ 0.3
  ideal). Same metric, different enforcement — because ENCODE4 defines an ATAC
  FRiP standard but not a ChIP one.
- **TSS enrichment (ATAC)** — this is the single most informative ATAC quality
  number. ≥ 7 is a clean library; 5–7 is acceptable; below 5 the code fails the
  run — the transposition wasn't specific to open chromatin, so downstream peaks
  are unreliable.
- **NRF (ATAC)** — below 0.9 means you sequenced the same few fragments over and
  over (over-amplified, low-complexity library). More sequencing won't help;
  you need a better library.

> **Pitfall — FRiP "≥ 0.20" is a real gate for ATAC but only an advisory for
> ChIP.** The tutorial spec lists "FRiP ≥ 0.20 (active mark)" under the ChIP
> scenario, but for **ChIP-seq** the code treats FRiP as **advisory-only**,
> flagging only an extreme FRiP < 0.01 (non-blocking) — ENCODE4 states ChIP FRiP
> is "collected without defined thresholds" (the 0.01 figure is historical
> ENCODE2/3 practice, Landt et al. 2012). For **ATAC-seq**, ENCODE4 *does* define
> an FRiP standard, so BioMate enforces FRiP ≥ 0.2 as a HALT gate
> (`qc_trace_monitor.py:4846-4858`). So: on a ChIP run, apply 0.20 as your own
> interpretive bar and don't assume the system halted a low-FRiP run; on an ATAC
> run, it will.

> **QC gate — for ATAC, read TSS enrichment first.** Unlike ChIP-seq (where FRiP
> is advisory), ATAC-seq has a real code-enforced TSS-enrichment gate (≥ 5). It
> is the "is my ATAC library real" check — read it before you look at any peak.

### What "fixing" a QC fail looks like here

There is **no epigenomics auto-loop**. QC fails are surfaced for you to correct
and re-run:

- Too few peaks / low FRiP → check the antibody, the input-control pairing in the
  sample sheet, and that narrow/broad matches the mark. Fix the sample sheet and
  re-run.
- Low TSS enrichment / NRF (ATAC) → a library-prep problem; re-sequencing won't
  rescue low complexity. Note it and, if possible, re-prep.
- If you only changed metadata (e.g. a mislabelled control), you can re-run the
  **annotation chain** on the existing peaks without re-aligning.

## Worked example (gold standard)

**Goal.** Call and annotate ChIP-seq peaks on a benchmark where the *right answer
is known*, and read the artifact as a biologist would.

**Dataset.** ENCODE **K562 H3K27ac** — the enhancer/active-promoter histone mark
in the K562 leukemia line. The ground truth is the **ENCODE consensus peak set
for the same biosample** (`ENCFF044JNJ` narrowPeak): we know which regions ENCODE
called, so we can score our peak set against a gold reference, not just eyeball
it. (`evaluation/tutorial_demos/gold_standards.yaml:40-49`;
`Tutorial Demo Scenarios 7-domain.md:219-273`.)

**Prompt** (the recorded tutorial T4):

> "Annotate my ChIP-seq peaks and run pathway enrichment."

**What comes back and how to read it (from the demo spec):**

- **Peak count ≈ 47,000** H3K27ac peaks — comfortably in the expected 25k–80k
  band for K562 H3K27ac, and well over the 1,000-peak gate. Interpretation: the
  IP worked; the peaks are real signal.
- **FRiP ≈ 0.27, NSC ≈ 1.18** — a well-enriched active mark. Interpretation:
  good signal-to-noise (and above your own 0.20 interpretive bar).
- **Overlap with ENCODE consensus ≈ 83%** (fraction of called peaks with ≥ 1 bp
  overlap of `ENCFF044JNJ`) — above the 80% target. Interpretation: the pipeline
  reproduces the ENCODE call set, so you can trust it on regions ENCODE didn't
  publish for you.
- **Annotated peaks** — each peak assigned to its nearest gene and genomic
  feature (promoter / intron / intergenic), with the promoter fraction visible in
  the feature-distribution plot. This is the artifact you carry forward.
- **Top GO BP: regulation of transcription by RNA Pol II (padj ≈ 2.8e-30).**
  Interpretation: the peak-adjacent genes aggregate into a coherent regulatory
  story — this is what you report, not the raw peak list alone.

**The artifact.** An annotated-peaks CSV + a peak-feature-distribution plot + a
GO dotplot. You end on a decision — *these regions are bound/open, these genes
are next to them, this pathway is implicated, at ENCODE-grade confidence*.

> **Note (verification tier).** The chain wiring (ChIPseeker → clusterProfiler),
> the workflow IDs (1492 / 12673 / 11090 / 11122 / 11262 / 10667), default params,
> routing, and the **code-enforced** QC gates (peaks-called, ATAC TSS/NRF, FRiP-as-
> advisory) are **code-verified (C)** by reading source (citations above). The
> numeric outputs (~47k peaks, 83% overlap, top GO) come from the gold-standard
> demo spec; a **fresh live AWS Batch re-run** to reproduce those numbers is
> **pending (L / ⏳)** and was not fired — Batch runs cost real money and the plan
> forbids speculative execution. The peak-overlap Jaccard scoring is a
> **validator metric**, not a live in-pipeline gate, and the validator file
> (`evaluation/tutorial_demos/epigenomics.py`) is **not yet present in the repo**
> (see What's not covered).

## Outputs & visualization

Every output renders in the after-run panel's Outputs tab via the in-app viewer
taxonomy (`frontend/client/src/components/step-output-preview.tsx:66-105`); the
mapping below is by file extension.

| Output | File | In-app viewer | When to go interactive |
|---|---|---|---|
| MultiQC / ataqv QC report | `multiqc_report.html` | **HTML iframe** viewer (sandboxed) | Read per-sample TSS enrichment / FRiP / duplication inline |
| Peak file | `*.bed` | **Annotation** viewer (`ANNOT_EXTS`, `step-output-preview.tsx:74`) | Load into a genome browser (IGV) for track-level review |
| Annotated-peaks table | `annotated_peaks.csv` | **Table** viewer (sortable, 200-row preview + full download) | Download to filter by feature type or target gene |
| Peak-feature-distribution plot | `*.pdf` / `*.png` | **PDF / Image** viewer | Export for the figure panel |
| GO / pathway dotplot | `*.pdf` / `*.png` | **PDF / Image** viewer | Export; read which pathways dominate |
| Pathway enrichment table | `enrichment_results.csv` | **Table** viewer | Download; sort by adjusted p-value |
| bigWig coverage tracks (ATAC) | `*.bigWig` / `*.bw` | **Download** (not browser-renderable) | Load into IGV / UCSC for signal tracks |

> **Pitfall — `.narrowPeak` / `.broadPeak` render as download, not as a table.**
> The in-app viewer maps `.bed` to the annotation viewer, but MACS2's
> `.narrowPeak` / `.broadPeak` extensions fall through to a **download** tile
> (`resolveViewer()`, `step-output-preview.tsx:88-105`). To read them in-app,
> use the annotated-peaks CSV (which the chain produces) — that renders as a
> sortable table. The raw narrowPeak is there to download for IGV.

## Pitfalls & tips

> **Pitfall — ChIP needs an input control; ATAC does not.** nf-core/chipseq
> expects an `antibody` + `control` column in the sample sheet (the input/IgG
> track is how MACS2 separates signal from background). Omitting it degrades peak
> calling. nf-core/atacseq uses a `replicate` column instead. Match the sample
> sheet to the assay.

> **Pitfall — narrow vs broad matters.** The stub defaults histone marks to
> **broad** peaks. For a sharp point-source mark (TF, H3K4me3) say "narrow peaks"
> or you'll get merged broad regions that blur the annotation.

> **Tip — start from the peak file if you have it.** Alignment + MACS2 is the
> expensive Batch step. If you already have a BED/narrowPeak, ask to "annotate my
> peaks and run pathway enrichment" — you skip straight to genes + pathways.

> **QC gate — FRiP is a thermometer, not a gate (ChIP).** Use FRiP to *compare*
> libraries; the system only advises below 0.01. For ATAC, TSS enrichment ≥ 5 is
> the real code-enforced gate — read it first.

## What's not covered

Honest scope — these are **not** claimed as present; they live in **Appendix E
(Coverage & roadmap)**:

- **A one-click FASTQ→pathways chain object.** The FASTQ path is `nf-core/chipseq`
  (or `atacseq`) run **before** the 2-step annotation chain — not a single chain
  with alignment inside it.
- **A hard FRiP gate.** The tutorial spec's "FRiP ≥ 0.20" is **not** enforced;
  the code treats FRiP as advisory-only (ENCODE4 sets no hard cutoff). NSC ≥ 1.05
  is a spec target, not a code gate.
- **Bin/peak-overlap (Jaccard) scoring in the live run.** The 80%-ENCODE-overlap
  metric is a **validator** computation; the domain validator
  `evaluation/tutorial_demos/epigenomics.py` referenced by the demo doc is **not
  yet present in the repo** (only `transcriptomics.py` exists). The overlap number
  is spec-only until the validator ships.
- **Deep coverage of DiffBind / HOMER / CUT&RUN / methylation.** `diffbind`
  (11262), `Find Enriched Motifs With Homer` (10667), and the methylation chain
  `bioc_methylation_dm_v2` (minfi → DSS → missMethyl) **exist and route**, but
  this chapter documents only that they exist and their entry point — end-to-end
  worked examples and gold-standard validation for them are roadmap.
- **An epigenomics auto-loop.** Unlike ADMET, there is no automatic
  parameter-tuning loop; QC fails are surfaced for manual correction and re-run.
- **Interactive tools (RStudio / IGV / Jupyter) launch.** On dev these are **not
  provisioned** (`/api/interactive/available` → `available:false`); the launch
  buttons are correctly hidden. In-app table/plot/HTML viewers cover reading
  outputs; genome-browser track review is environment-dependent.

---
_Verification: this page depends on the coverage-ledger rows under
**"## Epigenomics (ChIP-seq / ATAC-seq)"** — chain `bioc_chipseq_annotation_v2`
(2-step ChIPseeker→clusterProfiler) + nf-core/chipseq (1492) / atacseq (12673) as
pre-steps (C), step IDs 11090/11122/11262/10667 + default params (C), routing +
ChIP-vs-ATAC + narrow-vs-broad disambiguation (C), peaks-called code gate (C), FRiP
advisory-only vs tutorial-0.20 mismatch (C 🔧), ATAC TSS≥5 / NRF≥0.9 code-enforced
(C), viewer taxonomy incl. narrowPeak→download gap (C), ENCODE K562 H3K27ac gold
artifact + 83% overlap (C from demo spec; live-Batch re-run L / ⏳; validator file
absent 🗺️), and the roadmap/gap rows (🗺️)._
