# Instrument tutorial — Illumina BaseSpace → RNA-seq, variant calling (WGS) & 16S

> **Who this is for:** anyone whose Illumina sequencer (NovaSeq, NextSeq, MiSeq…) uploads to **Illumina
> BaseSpace**, who wants those reads turned into biology — **gene expression**, **DNA variants**, or
> **microbiome profiles** — without copying FASTQs around by hand. No coding needed.
> **Time:** ~12 minutes to read; a sequencing analysis run takes tens of minutes to many hours (real, heavy
> compute on the cloud).
> **Where it fits:** Tutorial 6 (T6) explains how to *connect* BaseSpace. This tutorial explains **the analyses
> those reads drive, how to run them, and how to read them.** Of the five instrument tutorials, this one is the
> **best-validated** — RNA-seq and WGS variant calling are BioMate's most exercised pipelines.

---

## 1. What this instrument produces

An Illumina sequencer reads millions of short DNA fragments and writes them as **FASTQ** files — text files of
**reads** (the A/C/G/T sequence of each fragment) each with a **per-base quality score** (Phred: how confident
the instrument is in each letter). Paired-end runs produce two files per sample (**R1** and **R2** — the two ends
of each fragment; you bring both). When you sequence on an Illumina machine linked to **BaseSpace**, those FASTQs
(and run metadata — the experiment type, platform, sample sheet) land in Illumina's **cloud**.

**FASTQ reads are not an answer.** Raw reads must be aligned/quantified and interpreted. *What* you do with them
depends entirely on **what kind of library you sequenced** — and that's what decides which BioMate pipeline runs.

---

## 2. The BioMate analysis it drives (and why)

BaseSpace tells BioMate the run's **experiment type**, and BioMate routes to the matching pipeline:

### 2a. RNA-seq → "which genes change between groups?" *(best-validated)*

If the library is RNA/transcriptome, the goal is usually differential gene expression — which genes are up or
down between conditions (disease vs. healthy, treated vs. control).

→ **`nf-core/rnaseq`**: the standard bulk RNA-seq pipeline — QC (FastQC/MultiQC), adapter/rRNA cleanup, alignment
(STAR/HISAT2), and quantification (Salmon/featureCounts), producing **gene-count matrices** ready for
differential expression (DESeq2/edgeR). It handles paired-end/single-end and auto-detects strandedness.

*Why a pipeline, not one tool:* going from reads to a trustworthy count matrix needs trimming, alignment,
quantification, and QC chained correctly — nf-core/rnaseq is the community-standard, tested chain.

### 2b. WGS / WES → "what DNA variants does this genome carry?" *(best-validated)*

If it's whole-genome or whole-exome sequencing, the goal is **variant calling** — finding the SNPs and small
insertions/deletions where this sample differs from the reference genome (for inherited-disease work,
population genetics, etc.).

→ **`Wgs Germline Gatk`**: a 14-step **GATK4 best-practices** germline pipeline —
FastQC → fastp → BWA-MEM2 alignment → MarkDuplicates → BQSR → HaplotypeCaller → GenotypeGVCFs → filtering →
SnpEff annotation. Inputs: `reads` (your FASTQ or an SRA accession), `reference` + `known_sites` + `dbsnp_vcf`,
and a `genome` build (`hg38`/`hg19`/`mm10`). Supports DeepVariant/FreeBayes as alternative callers and trio/family
calling. *(For tumour/somatic samples, use nf-core/sarek instead — this one is germline only.)*

### 2c. 16S / amplicon → "what microbes, in what proportions?"

If it's a 16S/18S/ITS amplicon run (microbiome), the goal is community profiling.

→ **`nf-core/ampliseq`**: DADA2/QIIME2 for ASV calling, taxonomic classification (SILVA/UNITE), and alpha/beta
diversity. Inputs include the primer sequences (`FW_primer`/`RV_primer`), hypervariable `region`, and a
`classifier`.

| BaseSpace run type | Workflow BioMate routes to | Validation |
|---|---|---|
| RNA / transcriptome | **`nf-core/rnaseq`** | **validated on real data** (run on real GEO datasets, e.g. on AWS Batch) |
| Whole genome / exome (germline) | **`Wgs Germline Gatk`** | **validated** (BioMate-curated GATK4 pipeline, exact catalogue match) |
| 16S / 18S / ITS amplicon | **`nf-core/ampliseq`** | available (real nf-core pipeline; confirm on your data) |
| Tumour / somatic | `nf-core/sarek` (ask for it) | available |
| Unknown / other | a generic FASTQ handler | **catch-all — may not route to a specific pipeline; name the analysis yourself** |

> **Honest note up front:** BaseSpace is the one connector that reaches a **cloud service**, not a file-watcher on
> your LAN. The connector reads BaseSpace run metadata and maps the **experiment type** to one of the pipelines
> above (its internal label for RNA-seq is `rnaseq_differential`, for WGS `wgs_germline_gatk`, for amplicon
> `metagenomics_16s`). When you Launch, BioMate routes to the real catalogue pipeline named above. If a run's
> experiment type is blank or mislabeled, state what the library is so it routes correctly.

---

## 3. Before you start — get the data in (see T6)

BaseSpace is different from the bench instruments in two ways you must know:

- **Residency = cloud.** BaseSpace is an Illumina **cloud** service, so your data lives in (and is pulled from)
  Illumina's systems — it is **not** on-prem. For patient or otherwise restricted data, that residency is
  something you're accountable for. Every instrument row shows this badge; **check it before connecting
  restricted data.** (T6 explains residency.)
- **Connecting = OAuth, plus a running poll.** You connect BaseSpace with an **API key / OAuth token**, not a
  LAN file-watcher. Registering the key lets BioMate **check and store** the connection; a cloud connector/poll
  must still run with your key before completed runs appear as events. Ask your admin whether that poll is
  running. Full steps: **Tutorial 6**.

Once connected, BioMate lists your **completed** BaseSpace runs with their experiment type, platform, and sample
count, and pre-fills a workflow suggestion per run.

**What you'll need per analysis:** for **WGS**, a reference genome build (`hg38`/`hg19`/`mm10`) and known-sites
VCFs (BioMate can inject standard references); for **RNA-seq**, your sample/condition grouping for the
differential comparison; for **16S**, your primer sequences and target region.

---

## 4. Step by step — run it

<!-- CAPTURE route=/ ; state=New data events / BaseSpace runs list showing a completed run (experiment type RNA-seq, platform NovaSeq, N samples) with Launch ; focus=instrument-event ; note=show a BaseSpace run card: run name, experiment-type badge, platform, sample count, cloud residency badge, Launch -->
*(Figure to add: a BaseSpace completed-run event — run name, experiment-type badge, platform, sample count, the **cloud** residency badge, and the Launch button.)*

1. **Start from the run event (or ask).** Click **Launch** on the completed BaseSpace run (opens a pre-filled
   draft, nothing runs yet), or type your goal, e.g. *"Run nf-core/rnaseq on this BaseSpace run, then differential
   expression treated vs. control"* or *"Germline variant calling (GATK) on this WGS run against hg38."*
2. **Check the workflow.** Confirm the panel opened the right pipeline for your run type (§2) — `nf-core/rnaseq`,
   `Wgs Germline Gatk`, or `nf-core/ampliseq`. Not "undefined"; if the experiment type was blank and it guessed
   wrong, restate what the library is.
3. **Confirm the key inputs:**
   - **RNA-seq:** confirm the FASTQs are linked (R1/R2 for paired-end) and set your sample/condition grouping.
   - **WGS:** set the `genome` build (e.g. `hg38`); BioMate can supply standard reference/known-sites.
   - **16S:** set the primers and region.
4. **Confirm and run.** Click **Confirm & Run**. Expect a **long** cloud run — watch phases move *pending →
   running → completed* in the Phases tab, and let any mid-run **QC gate** pause-and-report (it never silently
   passes a failed check — see T3).

<!-- CAPTURE route=/ ; state=Workflow panel running for Wgs Germline Gatk, 14-step phase cards (QC, Alignment, Variant Calling…) with one phase running ; focus=workflow-panel ; note=show the WGS pipeline mid-run with a phase in the running state and the overall running badge -->
*(Figure to add: the WGS pipeline mid-run — the FastQC / Alignment / Variant-Calling phase cards with one phase in the running state.)*

---

## 5. Reading the result / report

Open the **After run** section (two tabs — see **Tutorial 3**):

**RNA-seq:**
- **Summary** — the differentially expressed genes: read by **log2 fold-change** (how many doublings up/down; +1
  = doubled, −1 = halved) and **adjusted p-value / FDR** (confidence; smaller is stronger, common cut 0.05). A
  gene with a large fold-change *and* small FDR is a solid hit.
- **Outputs** — the **gene-count matrix**, differential-expression tables, and the **MultiQC** report (overall
  run quality). Downloadable for your figures.

**WGS / variant calling:**
- **Results** — an annotated **VCF** (the list of variants: position, reference vs. alternate base, and
  SnpEff annotation of likely effect), a recalibrated **BAM** (the alignment), and coverage/QC metrics. The VCF
  is the headline; coverage tells you whether you sequenced deeply enough to trust the calls.
- Previewing: a VCF previews as a variant table; a **BAM** is download/interactive (no inline genome-browser
  track yet — see T5).

**16S:** a taxonomy table (who's there) and diversity metrics (how varied each community is).

- **Reproducibility record** (all) — the genome build, parameters, tool versions, and outputs with checksums —
  the audit trail that makes the result defensible for a paper or submission.

> **What good looks like, and what to watch.**
> - **RNA-seq:** MultiQC should show clean per-base quality and a sensible alignment rate; a flat volcano (no
>   significant genes) can mean a real null *or* an underpowered design (too few replicates).
> - **WGS:** check **mean coverage** (the pipeline warns if it's low, default < 20×) and **alignment rate**
>   (warns < 70%) — low values mean you shouldn't over-trust the variant calls.

---

## 6. Honest limits — what to expect

- **Status: the best-validated of the five instruments — but with honest caveats.** `nf-core/rnaseq` and
  `Wgs Germline Gatk` are **real, indexed, and the most-exercised BioMate pipelines** (RNA-seq has been run
  end-to-end on real public datasets on AWS Batch; WGS germline is a BioMate-curated GATK4 pipeline that matches
  the catalogue exactly). `nf-core/ampliseq` is a real nf-core pipeline but with less BioMate-specific run
  evidence — confirm on your data.
- **The connector label is a routing hint, not a literal workflow.** The BaseSpace connector maps run
  *experiment type* to an internal label; BioMate routes your Launch to the real catalogue pipeline above. If the
  run's experiment type is blank/mislabeled, the connector falls back to a **generic FASTQ** handler that may not
  route to a specific pipeline — so **state the library type yourself** when that happens.
- **Cloud residency is your responsibility.** BaseSpace data leaves your organisation's systems (it's in
  Illumina's cloud). For restricted/patient data, confirm this is acceptable under your governance **before**
  connecting — the residency badge is shown for exactly this reason.
- **Connecting ≠ data flowing.** Entering the API key lets BioMate check/store the connection; a cloud poll must
  be running with your key before completed runs appear. If no events show up, that poll is the first thing to
  check (T6).
- **These are real, heavy cloud runs.** WGS in particular needs large memory and can run for hours. Don't launch
  speculatively — check the inputs and genome build first.
- **Somatic/cancer needs a different pipeline.** `Wgs Germline Gatk` is **germline only**; for tumour samples ask
  for `nf-core/sarek`.

---

## 7. Where to go next

| You want to… | Where |
|---|---|
| Connect BaseSpace (API key + poll, residency) | **Tutorial 6** |
| Understand the two-tab report and the QC gate | **Tutorial 3** |
| View a VCF / BAM and other outputs | **Tutorial 5** |
| Measure a few genes instead of genome-wide | the **qPCR tutorial** (`qpcr-quantification.md`) |
| Call variants in tumour samples | ask for **`nf-core/sarek`** |

The habit: **connect BaseSpace (mind the cloud residency) → Launch a completed run → confirm it routed to
rnaseq / WGS-GATK / ampliseq → set genome build or sample grouping → run → read fold-changes or the VCF, checking
QC/coverage.**

---

## 8. Key terms

| Term | What it means — and why you care |
|---|---|
| **FASTQ** | The sequencer's output: reads (A/C/G/T) + per-base quality. Paired-end = R1 + R2 (bring both). |
| **Phred / quality score** | How confident the instrument is in each base. Low quality → trimming/QC flags. |
| **BaseSpace** | Illumina's **cloud** platform where the sequencer uploads. **Cloud residency — data leaves your org.** |
| **Experiment type** | The run's library kind (RNA, WGS, amplicon…). What decides the pipeline. |
| **RNA-seq / nf-core/rnaseq** | Measuring gene expression genome-wide; the standard tested pipeline for it. |
| **Variant calling / VCF** | Finding where a genome differs from the reference; the VCF lists those variants. |
| **GATK4 best practices** | The community-standard germline variant-calling chain (the WGS pipeline here). |
| **log2 fold-change / FDR** | RNA-seq result terms: size of change (+1 = doubled) and confidence (smaller FDR = stronger). |
| **Coverage (depth)** | How many reads cover each position; too low → don't trust variant calls (warns < 20×). |
| **16S amplicon** | Microbiome profiling by sequencing a marker gene; who's there and in what proportion. |

---

_Grounded in: `biomate-connector/lab_instruments/illumina_basespace_connector.py` (`detect_workflow_from_run`:
experiment type → workflow routing) and BioMate catalogue entries `nf-core/rnaseq`, `Wgs Germline Gatk`,
`nf-core/ampliseq` — all confirmed via workflow search (WGS an exact high-confidence match). Companion:
Tutorials 3, 4, 5, 6._
