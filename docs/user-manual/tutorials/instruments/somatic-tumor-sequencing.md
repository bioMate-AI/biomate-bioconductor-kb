# Instrument tutorial — Somatic / tumour sequencing → paired tumour-normal variant calling (nf-core/sarek), plus a note on Sanger (.ab1)

> **Who this is for:** anyone sequencing **cancer** samples — a **tumour** specimen alongside a **matched
> normal** (blood or adjacent healthy tissue) from the same patient — who wants those reads turned into the
> list of **somatic** mutations the tumour acquired: the SNVs and small indels present in the cancer but *not*
> inherited. No coding needed.
> **Time:** ~12 minutes to read; a real somatic run takes from tens of minutes to many hours (heavy cloud
> compute — whole-genome tumour/normal is among the most demanding analyses BioMate runs).
> **Where it fits:** Tutorial 6 (T6) explains how to *get your tumour + matched-normal FASTQs into BioMate*.
> This tutorial explains **the analysis those reads drive, how to run it, and how to read it.** It
> **complements the germline/RNA-seq sequencing tutorial** ([`basespace-sequencing.md`](basespace-sequencing.md))
> — that one covers RNA-seq, germline WGS/WES and 16S; **this one covers the tumour/normal somatic path only.**
> Read the status note in §6 before you trust a result: somatic calling is **registered but not yet validated
> end-to-end** on BioMate.

---

## 1. What this instrument produces

A cancer sequencing study is run on the same NGS sequencer as any other DNA library (Illumina, MGI…), but the
**experimental design is paired**. For each patient you sequence **two** (or more) libraries:

- a **tumour** sample — DNA extracted from the cancer (fresh/frozen or FFPE), and
- a **matched normal** — DNA from the same patient's healthy cells (typically blood, or histologically normal
  adjacent tissue).

Each library comes off the instrument as **FASTQ** reads — the A/C/G/T sequence of millions of fragments, each
with a per-base **Phred** quality score; paired-end runs give two files per sample (**R1** and **R2**). Tumour
libraries are usually sequenced to **higher depth** than germline work (so that mutations present in only a
fraction of the tumour cells are still seen), and the normal is sequenced alongside as the per-patient baseline.

**The matched normal is the whole point.** A tumour genome carries two very different kinds of variant mixed
together: **germline** variants the patient was born with (also present in the normal), and **somatic**
variants the cancer *acquired* (present only in the tumour). Comparing tumour against its own matched normal is
what lets the analysis **subtract the germline** and keep only the somatic events — the biology of the cancer.
That subtraction is the job of the pipeline below; raw reads alone cannot do it.

---

## 2. The BioMate analysis it drives (and why)

The somatic/tumour design routes to a **different pipeline from the germline one**. Germline WGS/WES is covered
by `Wgs Germline Gatk` (see [`basespace-sequencing.md`](basespace-sequencing.md) §2b) — that pipeline treats one
genome against the reference and is **not** appropriate for cancer, because it has no concept of a matched
normal to subtract.

For tumour/normal cancer genomics, BioMate routes to **`nf-core/sarek`**
(`backend/biomni_workflows/nfcore/sarek/main.nf`) — the community-standard nf-core pipeline for germline **and
somatic** variant calling. For somatic work it runs with `analysis_type = somatic` and a tumour-aware caller
(**Mutect2**). Its phases:

1. **Preprocessing** — `FastQC` read QC, `MarkDuplicates`, and GATK **BQSR** (base-quality recalibration), per
   sample.
2. **Alignment** — `BWA-MEM2` aligns reads to the reference → a sorted, indexed **BAM/CRAM** per sample.
3. **Variant calling (somatic)** — with `tools = mutect2`, **GATK Mutect2** calls the tumour against its matched
   normal, emitting the **somatic** SNVs and small indels. sarek can additionally run **Strelka2** (somatic
   SNV/indel), **Manta** (structural variants) and **CNVkit** (copy-number) on the same pair.
4. **Annotation** — **VEP** (or ANNOVAR) adds the functional consequence of each variant (which gene, coding
   effect) and population frequencies.
5. **Report** — a **MultiQC** HTML plus variant statistics, and — where configured — a **TMB/MSI** summary
   (tumour mutational burden / microsatellite instability, both clinically relevant cancer biomarkers).

*Why a pipeline, not one caller:* going from paired reads to a trustworthy **somatic** call set requires
duplicate marking, recalibration, alignment, tumour-vs-normal calling, filtering and annotation chained
correctly — and the tumour-vs-normal comparison itself is what removes the germline background. nf-core/sarek is
the tested community chain for exactly this.

### The input shape — the tumour/normal samplesheet

sarek's `input` is a **samplesheet CSV** that pairs each tumour with its normal by patient. The real columns in
the BioMate stub are:

```
patient,sample,status,fastq_1,fastq_2
P001,P001_N,0,/data/P001_normal_R1.fastq.gz,/data/P001_normal_R2.fastq.gz
P001,P001_T,1,/data/P001_tumour_R1.fastq.gz,/data/P001_tumour_R2.fastq.gz
```

- **`patient`** — the patient ID that groups a tumour with its normal (both rows share `P001`).
- **`status`** — **`0` = normal, `1` = tumour** (this flag is what tells sarek which is which).
- **`fastq_1` / `fastq_2`** — the R1 / R2 FASTQs for that library.

| Design / goal | How to run sarek |
|---|---|
| **Tumour + matched normal** (the standard cancer design) | `analysis_type = somatic`, `tools = mutect2` (optionally add `strelka`, `manta`, `cnvkit`) |
| **Tumour-only** (no matched normal available) | `analysis_type = tumor_only` — relies more heavily on population panels; less specific, more germline leakage |
| **Whole-exome / targeted panel** rather than whole-genome | set `wes = true` and supply the panel **`intervals`** BED file |
| Germline (inherited) variants, no cancer design | **not this pipeline** — use `Wgs Germline Gatk` (see the germline sequencing tutorial) |

> **Honest note up front — read §6.** The somatic path **routes** and has a **real parameter spec**, but BioMate
> has **no validated end-to-end somatic run (no "gold" chain) yet**, and tumour **purity/ploidy** estimation via
> **ASCAT/PURPLE** is a **planned upgrade (U13), not yet wired into routing.** Treat somatic results as
> *experimental* until you have checked them against a known case. Do not report a BioMate somatic call set as
> validated.

---

## 3. Before you start — getting the data in (see T6)

This tutorial does **not** cover connecting the sequencer; connection is handled generically in **Tutorial 6**.
In short: **once your tumour + matched-normal FASTQs are in BioMate** — uploaded by hand from the Data area
(Tutorial 4) or arriving via whatever route your site uses (Tutorial 6) — the steps below are the same.

**What you must have ready:**
- **Both members of each pair:** the **tumour** FASTQs *and* the **matched-normal** FASTQs, with R1 and R2 for
  each paired-end library.
- **Which file is which** — your tumour-vs-normal labelling, so the samplesheet's `status` column is correct.
  Getting tumour and normal the wrong way round inverts the entire analysis.
- A **reference genome** build — `GRCh38` (default), `GRCh37`, or `GRCm38` for mouse. BioMate can supply the
  standard human references.
- For **exome/panel** work: the **`intervals`** BED file describing your captured regions (and set `wes = true`).

---

## 4. Step by step — run it

<!-- CAPTURE route=/ ; state=Workflow panel pre-run for nf-core/sarek, somatic mode, param strip showing analysis_type=somatic, tools=mutect2, genome=GRCh38, samplesheet with a tumour+normal pair ; focus=workflow-panel ; note=show the sarek pre-run card: workflow name nf-core/sarek, genomics domain badge, param strip (analysis_type, tools, genome), Confirm & Run -->
*(Figure to add: the sarek pre-run panel — workflow name `nf-core/sarek`, the genomics domain badge, the param
strip showing `analysis_type = somatic`, `tools = mutect2`, `genome = GRCh38`, and the Confirm & Run button.)*

1. **Ask for it (or pick the card).** Type your goal, stating that it is **somatic / tumour-normal**, e.g.
   *"Somatic variant calling on this tumour and matched normal with nf-core/sarek, Mutect2, against GRCh38."*
   Being explicit about *tumour + matched normal* is what steers it to the somatic path rather than germline.
2. **Check the workflow.** Confirm the panel opened **`nf-core/sarek`** (not "undefined", and not
   `Wgs Germline Gatk`). The domain badge should read genomics.
3. **Build / confirm the samplesheet.** Make sure each patient has **both** a `status = 0` (normal) and a
   `status = 1` (tumour) row, pointing at the right FASTQs (§2). This pairing is the single most important input.
4. **Set the key parameters:**
   - `analysis_type = somatic` (or `tumor_only` if you genuinely have no matched normal),
   - `tools = mutect2` (add `strelka`, `manta`, `cnvkit` if you also want SNV cross-check, SVs, or copy-number),
   - `genome = GRCh38` (or your build),
   - for a panel/exome: `wes = true` and attach `intervals`.
5. **Confirm and run.** Click **Confirm & Run**. Expect a **long, heavy** cloud run (whole-genome tumour/normal
   is demanding — up to `max_memory = 128 GB`). Watch phases move *pending → running → completed* in the Phases
   tab, and let any mid-run **QC gate** pause-and-report rather than silently passing (see Tutorial 3).

<!-- CAPTURE route=/ ; state=Workflow panel running for nf-core/sarek, phase cards (Preprocessing, Alignment, Variant Calling, Annotation, Report) with Variant Calling running ; focus=workflow-panel ; note=show the sarek pipeline mid-run with the somatic Variant Calling phase in the running state and the overall running badge -->
*(Figure to add: the sarek pipeline mid-run — the Preprocessing / Alignment / Variant-Calling / Annotation /
Report phase cards, with the somatic Variant-Calling phase in the running state.)*

---

## 5. Reading the result / report

Open the **After run** section (three tabs — see **Tutorial 3**):

- **Summary** — the headline count of **somatic** variants, and the most consequential ones. These are the
  mutations the tumour *acquired* (the germline has already been subtracted using the matched normal), read by
  **gene**, **consequence** (e.g. missense, stop-gained) and, if present, driver/biomarker annotation.
- **Outputs** —
  - an annotated **somatic VCF** (the headline file: each variant's position, reference vs. alternate base, the
    **variant allele fraction / VAF** — what proportion of tumour reads carry it — and the VEP consequence),
  - the recalibrated **BAM/CRAM** alignments for tumour and normal,
  - structural-variant / copy-number outputs if you ran Manta/CNVkit,
  - the **MultiQC** report and, where configured, the **TMB/MSI** summary.
  All downloadable for your figures.
- **Reproducibility record** — the genome build, the caller and its filters, tool versions, and outputs with
  checksums — the audit trail that makes a cancer-genomics result defensible for a paper or a tumour board.

Previewing: a VCF previews as a variant table; a **BAM/CRAM** is download/interactive (no inline genome-browser
track yet — see Tutorial 5).

> **What good looks like, and what to watch.**
> - **Depth matters more here than in germline work** — somatic sensitivity depends on sequencing the tumour
>   deeply enough to see low-fraction mutations; check tumour coverage before trusting a *negative*.
> - **Low tumour purity hides mutations.** A specimen that is mostly normal tissue dilutes the tumour signal, so
>   true somatic variants fall below the caller's threshold. Purity/ploidy estimation (ASCAT/PURPLE) is exactly
>   what corrects for this — and it is a **pending upgrade** here (U13, §6), so interpret VAFs and any
>   copy-number result cautiously until that lands.
> - **Tumour/normal swap** — if the somatic call set looks implausibly large and germline-like, confirm the
>   `status` column wasn't inverted.

---

## 6. Honest limits — what to expect (read this carefully)

- **Status: 🟡 Registered, NOT yet validated end-to-end.** `nf-core/sarek` is a **real pipeline** and the
  somatic path **routes with a real parameter spec** — but BioMate has **no validated somatic "gold" chain
  recorded**: there is no end-to-end somatic run on a known tumour/normal case proving the full
  reads→somatic-VCF path on the development site. This is different from the germline and RNA-seq pipelines in
  the companion tutorial, which are validated. **Treat every somatic result as experimental** and check it
  against a known case or your prior analysis before reporting it.
- **Tumour purity / ploidy (ASCAT/PURPLE) is a planned upgrade, not live.** Accurate somatic interpretation —
  especially copy-number, VAF correction and clonality — needs a purity/ploidy estimate. That routing (**U13**)
  is **not yet wired in**. Without it, VAFs are uncorrected and copy-number calls should be read as provisional.
- **This is germline-subtraction, so the matched normal is mandatory for best results.** `tumor_only` mode
  exists, but with no patient-specific normal it leans on population panels and leaks more residual germline —
  less specific. Supply the matched normal whenever you can.
- **Get the pairing right.** The `status` column (0 = normal, 1 = tumour) and the shared `patient` ID drive the
  whole comparison. A mislabelled pair silently inverts the result — no error, just wrong biology.
- **These are real, heavy cloud runs.** Whole-genome tumour/normal needs large memory and can run for hours.
  Don't launch speculatively — confirm the samplesheet, build, and caller first.
- **FFPE and low-input caveats apply.** FFPE-derived tumour DNA carries deamination artefacts that can mimic
  low-VAF somatic SNVs; standard sarek does not, by default, apply FFPE-specific artefact filtering here —
  interpret low-fraction C>T/G>A calls on FFPE material with care.
- **No connector/auto-routing is claimed.** How the FASTQs *arrive* is out of scope (Tutorial 6); this tutorial
  assumes they are already in BioMate.

---

## 7. Sanger sequencing (.ab1) — honest status: not yet supported

Some facilities also run a **Sanger** (capillary) sequencer, which produces a **`.ab1` chromatogram** per read —
the classic four-colour trace used for single-amplicon confirmation, plasmid/insert checks, and variant
confirmation.

**BioMate does not yet analyse `.ab1` chromatograms.** There is **no workflow** that reads a trace, base-calls or
quality-trims it, or assembles reads into a consensus/contig. This is a **known gap**, tracked as roadmap item
**B5** (a **Tracy**-based chain: chromatogram trim → consensus / contig assembly). Until B5 ships:

- Do **not** expect to upload an `.ab1` and get a result — there is no pipeline to route to, and we will not
  pretend one exists.
- For now, confirm Sanger traces in your usual desktop tool (e.g. a chromatogram viewer / SnapGene / Tracy run
  locally), and bring BioMate only the downstream question (e.g. "does this confirmed variant match the somatic
  call?").

This section will be replaced with a real how-to once B5 lands.

---

## 8. BioMate also offers — related genomics & variant-calling capability

Beyond the somatic path, BioMate's **variant-calling** domain (≈180 workflows) and broader genomics catalogue
give a tumour-genomics facility more to work with:

| You also want to… | Real BioMate resource |
|---|---|
| Call **germline** (inherited) variants — GATK4 best-practices | **`Wgs Germline Gatk`** (validated — see [`basespace-sequencing.md`](basespace-sequencing.md)) |
| A second somatic caller / lightweight tumour-normal mutation + SnpEff annotation | **`detect_and_annotate_somatic_mutations`** (`backend/biomni_workflows/nextflow/subworkflows/cancer_biology/`) — tumour BAM vs. normal BAM, SnpEff |
| **Structural variants** (fusions, large rearrangements) in the tumour | Manta via sarek (`tools = manta`) |
| **Copy-number** alterations | CNVkit via sarek (`tools = cnvkit`) |
| Alternative germline/somatic callers (**DeepVariant, Strelka2, FreeBayes**) | available as sarek `tools` options |
| Quantify tumour **gene expression** (RNA-seq) on the same cohort | `nf-core/rnaseq` → DESeq2 (see the germline/RNA-seq tutorial) |
| Look up a gene's **cancer relevance / tractability** | **`query_opentarget`** (`…/subworkflows/database/query_opentarget.nf`) — Open Targets |
| Enrich a somatic gene list into pathways | pathway-enrichment workflows (clusterProfiler/GSEA, systems-biology domain) |

Public cancer reference resources the annotation step draws on include **COSMIC**, **dbSNP**, **gnomAD** and
**ClinVar** (population frequency and clinical significance for the variants sarek reports).

---

## 9. Where to go next

| You want to… | Where |
|---|---|
| Get your tumour + matched-normal FASTQs into BioMate | **Tutorial 6** (connection) / **Tutorial 4** (manual upload) |
| Run germline / RNA-seq / 16S instead | the sequencing tutorial ([`basespace-sequencing.md`](basespace-sequencing.md)) |
| Understand the three-tab report and the QC gate | **Tutorial 3** |
| View a VCF / BAM output | **Tutorial 5** |
| Analyse a Sanger `.ab1` trace | **not yet supported** — roadmap item **B5** (§7) |

The habit: **get the tumour + matched-normal FASTQs into BioMate → ask for somatic calling with nf-core/sarek →
confirm the tumour/normal samplesheet (status 0/1) and `analysis_type = somatic`, `tools = mutect2`, genome
build → run (expect a long job) → read the somatic VCF and VAFs, treating results as experimental until the
somatic chain and purity (U13) are validated.**

---

## 10. Key terms

| Term | What it means — and why you care |
|---|---|
| **Somatic vs. germline** | Germline = inherited (present in the normal too); somatic = acquired by the tumour (present only in the tumour). Cancer genomics is about the somatic set. |
| **Matched normal** | The patient's own healthy-cell DNA, sequenced alongside the tumour so the germline can be subtracted. The core of the design. |
| **Samplesheet `status`** | `0` = normal, `1` = tumour — the flag that pairs and orients each library. Get it wrong and the analysis inverts. |
| **Mutect2** | GATK's tumour-aware somatic caller — the default somatic caller in sarek. |
| **VAF (variant allele fraction)** | The proportion of tumour reads carrying a variant; low VAF = a mutation in a minority of tumour cells (or low purity). |
| **Tumour purity / ploidy** | How much of the specimen is actually tumour, and its copy-number state. Estimated by **ASCAT/PURPLE** — a pending BioMate upgrade (U13). |
| **TMB / MSI** | Tumour mutational burden / microsatellite instability — cancer biomarkers sarek can summarise. |
| **VCF** | The variant list: position, reference vs. alternate base, VAF, and functional annotation. The headline output. |
| **`.ab1`** | A Sanger chromatogram trace file. **Not yet analysable in BioMate** (roadmap B5). |

---

_Grounded in: `backend/biomni_workflows/nfcore/sarek/main.nf` (real local stub — params `input` samplesheet
`patient,sample,status,fastq_1,fastq_2`, `analysis_type ∈ {germline,somatic,tumor_only}`, `tools ∈
{mutect2,haplotypecaller,strelka,freebayes,deepvariant,cnvkit,manta}`, `genome`, `wes`/`intervals`; phases
Preprocessing→Alignment→Variant Calling→Annotation→Report with TMB/MSI), and
`backend/biomni_workflows/nextflow/subworkflows/cancer_biology/detect_and_annotate_somatic_mutations.nf`
(tumour BAM vs. normal BAM + SnpEff). Status per `docs/20260920_HOSPITAL_INSTRUMENT_RESOURCE_INVENTORY.md`:
somatic = 🟡 Registered, U13 ASCAT/PURPLE purity routing pending, no validated somatic gold chain yet; Sanger
`.ab1` = 🛑 B5 (Tracy trim→consensus/contig), not yet supported. Companion: the germline/RNA-seq sequencing
tutorial (`basespace-sequencing.md`); Tutorials 3, 4, 5, 6._
