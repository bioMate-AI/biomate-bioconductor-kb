# Variant calling / genomics

> One-line promise: go from raw sequencing reads (or a SRA accession) to a
> **filtered, annotated VCF of germline variants** — SNVs and indels — with the
> alignment, coverage, and duplication QC gates that tell you whether the calls
> are trustworthy before you interpret a single variant, plus an in-app VCF table
> viewer and a MultiQC report. For: **clinical/translational researchers** who
> need variants called and annotated without writing a Nextflow pipeline, and
> **bioinformaticians** who want the GATK Best-Practices / nf-core/sarek chain run
> and reported for them. No coding required.

<!--
P1 chapter (build order §3, item 4). Every "supported" claim below is green in
coverage-ledger.md § "Variant calling / genomics". Honesty rules:
- A QC threshold is documented as "code-enforced" ONLY where it lives in qc_trace_monitor.py.
  Thresholds that live only in the pipeline .nf report block or qc_evidence.yaml are labelled
  "advisory / in-pipeline" and the code truth is stated where it differs.
- SOMATIC (Mutect2 tumor-normal, TMB, oncoplot) is a COVERAGE GAP: the individual workflows exist
  and route, but there is NO wired end-to-end somatic chain with a gold-standard artifact. It is
  documented as "not covered" → Appendix E. Do NOT claim somatic works.
- Screenshots are run-dependent (VCF viewer, MultiQC) → placeholders + CAPTURE specs; no Batch run fired.
-->

## What this is for

This is the **"which DNA variants does this sample carry, and which ones
matter"** path. You have short-read sequencing of a genome (WGS) or an exome
(WES) — as raw FASTQ, an SRA accession, or already-aligned BAM — and you want the
list of positions where the sample differs from the reference: single-nucleotide
variants (SNVs) and short insertions/deletions (indels), filtered to the ones you
can trust, and annotated with what gene and consequence each hit lands on.

BioMate runs the **germline GATK Best-Practices chain** end to end:

1. **Align** reads to the reference (BWA-MEM2) and mark PCR duplicates.
2. **Recalibrate** base qualities (BQSR) against a known-sites VCF.
3. **Call** germline SNVs/indels (GATK HaplotypeCaller in gVCF mode →
   GenotypeGVCFs), or **DeepVariant** as an alternative caller.
4. **Filter** the raw calls (GATK hard-filtering by default) and **annotate**
   them (VEP / SnpEff: gene, consequence, population frequency).
5. **Report** alignment, coverage, duplication, and variant QC in a MultiQC HTML.

The through-line of this chapter is **interpretation, not a metrics dump**. Every
QC number below is explained as "what it means and what to do next," and the
worked example ends on a *decision* — these calls are benchmark-grade, this is the
Ts/Tv, here is the annotated variant table — not a process tree.

> **Tip** — The reference genome default is **GRCh38** (human). If your sample is
> mouse or a different build, say so ("GRCm38 / mm10", "GRCh37/hg19") — the wrong
> reference is the single most common cause of a low mapping rate and a garbage
> variant list.

> **Pitfall — this chapter is GERMLINE.** It calls the variants a person was born
> with. It is **not** a tumor somatic-mutation pipeline. Somatic calling
> (Mutect2 tumor-vs-normal, TMB, oncoprint) is a **tracked coverage gap** — the
> individual workflows exist and route, but there is no wired end-to-end somatic
> chain with a validated artifact. See **How to ask** for the disambiguation and
> **What's not covered** for the honest status.

## Use cases

| Goal (researcher's words) | Workflow(s) / chain | Inputs | Outputs (artifact) | Lane |
|---|---|---|---|---|
| "Call germline variants from my WGS/WES and annotate them" | Chain `bioc_variant_annotation_workflow`: **nf-core/sarek** (id **1493**, BWA-MEM2 → HaplotypeCaller → VEP) → VariantAnnotation → variantfiltering → maftools | FASTQ samplesheet (or SRA accession) + reference (`genome=GRCh38`) | Filtered **VCF** + annotated variant table + MultiQC HTML | Cloud (AWS Batch) |
| "Run the full GATK4 Best-Practices germline pipeline, one workflow" | **Wgs Germline Gatk** (id **10685**): FastQC → fastp → BWA-MEM2 → MarkDuplicates → mosdepth → BQSR → HaplotypeCaller → GenotypeGVCFs → hard-filter → SnpEff → MultiQC (14 steps) | Paired FASTQ or SRA accession + reference FASTA + known-sites VCF | gVCF, raw + filtered VCF, annotated VCF, coverage + MultiQC reports | Cloud |
| "Use DeepVariant instead of GATK for germline calling" | **nf-core/deepvariant** (id **1805**) — alternative deep-learning caller | Aligned BAM/CRAM + reference | VCF (DeepVariant PASS calls) | Cloud |
| "Just annotate/filter a VCF I already have" | `variantfiltering` (id 12605) + `variantannotation` (id 12603) Bioconductor workflows | An existing VCF | Filtered + annotated variant table | Cloud |

> **Pitfall — VQSR vs hard-filter.** The tester-guide draft mentions "VQSR
> tranches," but the production `Wgs Germline Gatk` workflow defaults to
> **GATK hard-filtering** for single samples (`vqsr_mode=false`) — VQSR needs many
> samples / large truth sets to train and is not the single-sample default. The
> chapter documents the hard-filter path the code actually runs.

## How to ask

BioMate routes on intent. The two disambiguations that matter here are
**germline vs somatic** and **variant-calling vs microbiome/metagenomics**.

Germline calling (the supported path):

> "Run whole-genome germline variant calling with nf-core/sarek and GATK
> HaplotypeCaller, reference GRCh38, then annotate with VEP."

Or, from an SRA accession directly:

> "Call germline SNVs and indels on SRR-accession — GATK Best Practices, hg38."

**Disambiguation to avoid:**

- **Germline vs somatic — the load-bearing keyword.** If you say
  **"somatic", "tumor-normal", "mutect", or "cancer"**, the QC-profile selector
  switches to the somatic tumor-only profile (80× coverage floor) *before* it ever
  considers germline (`qc_trace_monitor.py:1095-1097`: *"Somatic (must check BEFORE
  germline / wgs)"*). Germline terms ("germline", "haplotypecaller",
  "deepvariant", "wgs") select the standard 30× germline profile
  (`qc_trace_monitor.py:1100-1103`). **Add the word that matches your assay** — it
  changes both the caller expectation and the coverage gate. Be aware that while
  the router recognises somatic intent, the somatic *end-to-end chain* is not
  built (see What's not covered) — germline is the path this chapter documents.
- **Variant-calling vs metagenomics.** WES/somatic vocabulary ("exome",
  "tumor normal", "somatic") is explicitly steered toward genomics and away from
  microbiome workflows in the ranker (`unified_workflow_search.py:1126-1131`:
  preferred `genomics/variant_calling/cancer_biology`, penalised
  `microbiology/metagenomics`). You rarely need to do anything here — it is
  automatic — but if you are calling variants *in a microbial isolate*, name the
  organism so the router doesn't over-steer to human genomics.
- **WGS vs WES.** Exome data uses target intervals and a different coverage
  expectation (50× research / 80× clinical vs 30× WGS). Say "exome" / "WES" so the
  `wes_research` profile and interval handling apply
  (`qc_trace_monitor.py:1106-1108`, profile at `:193-201`).

> **Tip — you can start from an SRA accession, not just files.** The
> `Wgs Germline Gatk` workflow detects an SRA accession pattern (`SRR/ERR/DRR…`)
> and runs `fasterq-dump` for you before alignment
> (`wgs_germline_gatk/main.nf` workflow entry, `FASTERQ_DUMP` process). Give it the
> accession and a reference and it fetches the reads itself.

## Tools & workflows behind this

| Tool / workflow | Role | Where (verified) |
|---|---|---|
| Chain `bioc_variant_annotation_workflow` | 4-step germline path: sarek call → VariantAnnotation → filter → maftools summary; **this is the gold-standard demo chain** | DB `workflow_chains` (steps: nf-core/sarek → BIOC_VariantAnnotation → variantfiltering → BIOC_maftools) |
| `nf-core/sarek` (id **1493**) | Germline/somatic caller stub; BWA-MEM2 → MarkDuplicates → BQSR → HaplotypeCaller → VEP → MultiQC; default `genome='GRCh38'`, `analysis_type='germline'` | DB id 1493; `backend/biomni_workflows/nfcore/sarek/main.nf:12,14,15` (params), `:47,79,95,112` (processes) |
| `Wgs Germline Gatk` (id **10685**) | Full 14-step GATK4 Best-Practices DSL2 pipeline (real gatk/bwa-mem2/mosdepth/SnpEff processes) | DB id 10685; `backend/biomni_workflows/nextflow_nfcore/subworkflows/genomics/wgs_germline_gatk/main.nf:10-25` (step list), `:workflow{}` (entry) |
| `nf-core/deepvariant` (id **1805**) | Alternative deep-learning germline caller | DB id 1805 |
| `variantfiltering` (12605) / `variantannotation` (12603) | Filter by consequence/pop-freq; annotate against TxDb | DB `workflows` |
| QC-gate monitor | Reads flagstat / MarkDuplicates / mosdepth metrics from run trace, applies DNA-seq gates | `backend/lib/galaxy/jobs/qc_trace_monitor.py:1479-1489` (dispatch), `:4636-4700` (gates) |
| QC-profile selector | germline vs somatic vs WES profile from prompt keywords | `qc_trace_monitor.py:1095-1108`; profiles `:147-210` |
| Somatic workflows (exist, not chained) | tumor-normal GATK (1771), tumor-only GATK (1779), Strelka (1744), `Detect And Annotate Somatic Mutations` (10608) | DB `workflows`; subworkflow `nextflow_nfcore/subworkflows/cancer_biology/detect_and_annotate_somatic_mutations/main.nf` |

The germline chain terminates at a **gold-standard-comparable artifact** (a VCF
scored against a truth set), not a process tree — see the worked example.

> **License** — GATK4 (Apache 2.0), BWA-MEM2, DeepVariant (Google, open-source),
> SnpEff, and Ensembl VEP are open-source; results are yours. GRCh38 and the
> gnomAD / ClinVar annotations VEP applies are the standard public releases.

## QC gates & how to read them

A QC gate answers one question for a variant analyst: **"can I trust the VCF I'm
about to interpret?"** For germline calling the gates sit at the three places
things silently go wrong — alignment, library complexity, and depth — plus one
advisory whole-VCF sanity check (Ts/Tv).

| Gate | Threshold | What a fail means | Enforced where |
|---|---|---|---|
| **Mapped %** (samtools flagstat) | **≥ 70%** | Reads aren't landing on the genome — wrong reference, contamination, or bad library. Calls downstream are unreliable. | **Code-enforced (GOLD).** `qc_trace_monitor.py:4640` (hardcoded 70.0, GATK Best Practices); parse at `:2434-2456` |
| **Duplicate %** (MarkDuplicates) | **≤ 40%** default (profile can override, e.g. FFPE 65%, tumor 50%) | Low library complexity — a lot of your "reads" are PCR copies of the same fragment, so effective depth is lower than it looks. | **Code-enforced.** `qc_trace_monitor.py:4649` (default 40.0), MarkDuplicates path `:4661-4683`; profile overrides `:161,175,188` |
| **Mean coverage** (mosdepth) | **≥ 30×** WGS germline · 50× WES research · 80× WES clinical / somatic | Not enough depth to call confidently, especially heterozygous sites. | **Code-enforced.** default 30 via `wgs_germline_standard` profile (`:147-151`, empty overrides = platform default); gate `:4773-4790`; profile switch `:1100-1108` |
| **Ts/Tv ratio** | **~2.0–2.1** (WGS); flagged outside **1.8–2.2** | A transition/transversion ratio far from the expected ~2.0–2.1 for human WGS signals contamination, a mismatched reference, or false-positive-heavy calls. | **In-pipeline advisory, NOT a qc_trace_monitor gate.** Computed + range-checked in `wgs_germline_gatk/main.nf` MULTIQC block (`1.8 <= tv <= 2.2`); anchored SILVER in `qc_evidence.yaml`. There is **no Ts/Tv failure in `qc_trace_monitor.py`** — you read it |

**How to read each:**

- **Mapped ≥ 70%** — for human WGS with the right reference this is routine
  (95%+ is typical). A number well under 70% almost always means a wrong/unindexed
  reference or heavy contamination — fix the reference before trusting any call.
- **Duplicate ≤ 40%** — high duplication means you paid for depth you didn't get.
  It is *expected* to be higher for FFPE (up to 65%) and tumor libraries (50%), and
  the profile system relaxes the gate accordingly — so a 45% duplicate rate on a
  named FFPE sample is not flagged, while the same number on a fresh-blood germline
  sample is.
- **Mean coverage ≥ 30×** — this is the depth floor for reliable germline
  genotyping (GATK Best Practices). Below it, heterozygous calls get unreliable
  first. If you asked for WES or somatic, the floor rises automatically (50×/80×).
- **Ts/Tv ~2.0–2.1** — the whole-VCF sanity check. Read it *after* the run: a value
  inside 1.8–2.2 says the SNV set looks like real human biology; a value pushed
  toward 1.0 says false positives (often from contamination or a reference
  mismatch) are diluting your calls. It is an interpretive signal you apply, not a
  hard halt the system enforces.

> **QC gate — coverage before conclusions.** A germline VCF called from a 12×
> library will *look* complete but silently miss heterozygous variants. Check the
> mosdepth mean coverage against the 30× floor before you interpret absence of a
> variant as real.

> **Pitfall — Ts/Tv is advisory, not a code gate.** The 1.8–2.2 range lives in the
> pipeline's own MultiQC report block and in `qc_evidence.yaml` (SILVER), **not** in
> `qc_trace_monitor.py`. The chapter states the code truth: the automatic DNA-seq
> gates the platform enforces are **mapped %, duplicate %, and mean coverage**. Use
> Ts/Tv as your own quality read, not something the system halted on.

### What "fixing" a QC fail looks like here

There is **no automatic auto-loop remediation** for variant calling (unlike the
ADMET chapter). A QC fail is surfaced to you to correct and re-run:

- **Low mapping** → you almost certainly have the wrong or unindexed reference
  (`genome`); correct it and re-run from alignment.
- **High duplication** → deeper/less-amplified sequencing is the real fix; or, if
  the sample is legitimately FFPE/tumor, name it so the correct (relaxed) profile
  applies and the flag clears.
- **Low coverage** → top up sequencing; there is no software fix for missing depth.
- **Off Ts/Tv** → suspect contamination or a reference mismatch; re-check the
  reference build matches the reads.

## Worked example (gold standard)

**Goal.** Run the germline chain on a benchmark where the *right answer is known*,
and read the artifact as an analyst would.

**Dataset.** **GIAB HG002 (chr20), v4.2.1** — the Genome in a Bottle Ashkenazi son
reference sample. GIAB publishes a high-confidence truth VCF for HG002, so we know
exactly which variants are real and can score the pipeline's calls against it, not
just eyeball them.
(`evaluation/tutorial_demos/gold_standards.yaml:28-38`; inputs at
`s3://biomate-workflow-inputs/tutorial-gold/variant_calling/giab_hg002_chr20/`;
anchors: Wagner et al., *Cell Genomics* 2:100129 (2022); Zook et al., *Sci Data*
3:160025 (2016).)

**Chain.** `bioc_variant_annotation_workflow` (the registered gold demo):
nf-core/sarek germline call → VariantAnnotation → filtering → maftools summary.

**Prompt** (the recorded tutorial):

> "Variant calling annotation filtering on this WGS sample."

**Metric.** **hap.py** (`happy_snv_f1`) — the GA4GH-standard benchmarking tool that
compares your VCF to the GIAB truth set and reports precision, recall, and F1 per
variant type. The pass thresholds are **SNV F1 ≥ 0.99** and **indel F1 ≥ 0.95**
(`gold_standards.yaml:36-38`).

**What comes back and how to read it:**

- **Alignment + coverage QC (MultiQC).** Mapped % well over the 70% gate; mean
  coverage over the 30× germline floor. Interpretation: the reads are clean and
  deep enough — the calls are worth interpreting.
- **Ts/Tv.** ~2.0–2.1, inside the 1.8–2.2 band. Interpretation: the SNV set looks
  like real human biology, not a false-positive-inflated list.
- **The VCF (the artifact).** A filtered, annotated variant table — CHROM/POS/REF/
  ALT/QUAL/FILTER plus VEP/SnpEff consequence and population frequency — that you
  carry forward. This is a filterable list, not a picture.
- **The ground-truth check (hap.py).** SNV F1 scored against the GIAB HG002 truth
  set, with the **≥ 0.99** SNV / **≥ 0.95** indel bar. Interpretation: if the
  pipeline recovers the known variants at benchmark grade, you can trust it on the
  variants you *don't* know the answer to.

**The artifact.** A filtered, annotated VCF (variant table) + a MultiQC HTML +
hap.py concordance numbers. You end on a decision — *these calls are
benchmark-grade, this is the coverage and Ts/Tv, here are the annotated variants* —
exactly the "gold-standard-comparable artifact" the tutorial-demo plan mandates.

> **Note (verification tier).** The chain wiring, workflow IDs (1493 / 10685 /
> 1805), default params (`genome='GRCh38'`, hard-filter), routing keywords, QC
> gates, and the gold-standard dataset + hap.py metric are **code/spec-verified (C)**
> by reading source (citations above). The numeric hap.py F1 for a fresh run comes
> from a **live AWS Batch re-run that is pending (L / ⏳)** and was **not** fired —
> Batch WGS runs cost real money and the plan forbids speculative execution. The
> pass bars (SNV F1 ≥ 0.99, indel F1 ≥ 0.95) are the spec thresholds, not a claimed
> achieved score.

## Outputs & visualization

Outputs render in the after-run panel's Outputs tab via the in-app viewer taxonomy
(`frontend/client/src/components/step-output-preview.tsx`); the mapping is by file
extension. See **I.8 Outputs, viewers & interactive panels** for the full taxonomy.

| Output | File | In-app viewer | When to go interactive |
|---|---|---|---|
| Filtered / annotated variants | `*.vcf` · `*.vcf.gz` · `*.bcf` | **VCF table viewer** — `InlineVcfViewer`, CHROM/POS/ID/REF/ALT/QUAL/FILTER/INFO columns, first 100 data rows (`step-output-preview.tsx:75,96,364-372`) | Download the VCF to filter by gene/consequence, or load in IGV for locus-level inspection |
| MultiQC QC report | `multiqc_report.html` | **HTML iframe** viewer (sandboxed) | Read mapped %, duplicate %, coverage, and Ts/Tv per-sample inline |
| Coverage summary | `*.mosdepth.summary.txt` / `coverage_report.json` | **Table / text** viewer | Confirm mean coverage cleared the 30× floor before trusting absence of a variant |
| BED/GFF annotation intervals | `*.bed` · `*.gff` | **Annotation viewer** (`InlineAnnotationViewer`, `:379-386`) | Download for genome-browser overlay |

> **Tip — read the VCF in-app, don't re-parse it.** The VCF viewer renders the
> variant table right in the panel (header row parsed from `#CHROM`, first 100
> variants shown, full file downloadable). Sort/filter your top hits from the
> download; you only need IGV or a genome browser when you want to eyeball a
> specific locus's read pileup. Cross-ref **I.8** for the viewer taxonomy.

## Pitfalls & tips

> **Pitfall — germline vs somatic is an assay difference, not a preference.** This
> chapter calls inherited variants. For tumor somatic mutations you need matched
> tumor/normal and a somatic caller (Mutect2), a higher coverage floor (80×), and
> different filtering — and that end-to-end path is **not built** (Appendix E). Say
> "somatic" / "tumor-normal" only if you understand the somatic components exist
> individually but are not wired into a validated chain yet.

> **Pitfall — wrong reference = low mapping = garbage VCF.** The `genome` default is
> GRCh38. If your reads are mouse or an older human build, set it explicitly. A
> sub-70% mapping rate is almost always this, and no downstream filter can rescue
> variants called against the wrong reference.

> **Tip — name FFPE / tumor libraries so the duplicate gate relaxes.** The default
> duplicate ceiling is 40%, but FFPE (65%) and tumor (50%) libraries legitimately
> run higher and the profile system knows this. Naming the sample type prevents a
> spurious "high duplication" flag.

> **QC gate — read Ts/Tv yourself.** The platform's enforced DNA-seq gates are
> mapped %, duplicate %, and coverage. Ts/Tv (~2.0–2.1 for WGS) is produced in the
> report but is not an automatic halt — treat a value outside 1.8–2.2 as your own
> contamination/reference-mismatch warning.

> **Tip — VQSR isn't the single-sample default.** For one sample the pipeline
> hard-filters (`vqsr_mode=false`). VQSR needs cohorts/truth sets to train; don't
> expect VQSR tranches on a single-sample germline run.

## What's not covered

Honest scope — these are **not** claimed as present in this chapter; they live in
**Appendix E (Coverage & roadmap)**:

- **Somatic variant calling (Mutect2 tumor-normal, TMB, oncoprint) end-to-end.**
  This is a **tracked coverage gap** (`docs/20260701_TESTER_GUIDE_21_USE_CASES.md`,
  Q16 "Somatic variants — ⚠ Coverage gap tracked"). The individual pieces exist and
  route — `nf-core/bam_tumor_normal_somatic_variant_calling_gatk` (id 1771),
  tumor-only GATK (1779), Strelka (1744), and the `Detect And Annotate Somatic
  Mutations` subworkflow (id 10608) — and the QC-profile selector recognises
  somatic intent (`qc_trace_monitor.py:1095-1097`). **But there is no wired
  end-to-end somatic chain** (no somatic entry in `workflow_chains`) and **no
  gold-standard somatic demo** in `gold_standards.yaml`. Do not treat somatic
  calling as a one-click, validated path — it is roadmap.
- **hap.py numeric benchmark for a live run.** The GIAB HG002 gold dataset, the
  hap.py metric, and the pass bars (SNV F1 ≥ 0.99 / indel F1 ≥ 0.95) are wired and
  code-verified, but a fresh AWS Batch run to reproduce the exact F1 has **not** been
  fired (L / ⏳). The worked example states the spec, not an achieved score.
- **Auto-loop / auto-remediation for variant QC.** Unlike ADMET, there is no
  automatic parameter-retuning loop. Low mapping, low coverage, high duplication,
  or off Ts/Tv are surfaced for you to correct (reference / depth / sample-type) and
  re-run — the fix is manual, and the manual says so.
- **VQSR (variant quality score recalibration) as a default.** The production
  germline path hard-filters single samples; VQSR (`vqsr_mode`) exists as a flag but
  is not the validated default and has no worked example here.
- **Structural variants / CNVs, joint cohort genotyping, and the specialised
  Bioconductor variant workflows** (structural-variant annotation 12482, CNV/manta,
  rare-variant burden, etc.) **exist in the catalog and route**, but this chapter
  documents only germline SNV/indel calling end-to-end. Deep coverage of SV/CNV and
  cohort joint-calling is roadmap.
- **Interactive tools (IGV / RStudio / Jupyter) launch.** On dev these are not
  provisioned; the in-app VCF/table/HTML viewers cover reading outputs, and
  locus-level inspection means downloading the VCF into your own IGV.

---
_Verification: this page depends on the coverage-ledger rows under
**"## Variant calling / genomics"** — germline gold chain `bioc_variant_annotation_workflow`
(sarek 1493 → annotation → filter → maftools) (C), full GATK4 pipeline `Wgs Germline Gatk` id 10685
14 steps (C), sarek default `genome='GRCh38'`/`analysis_type='germline'` + VEP annotation (C),
DeepVariant id 1805 alternative caller (C), routing germline-vs-somatic keyword profile switch
(C), WES/somatic-vs-metagenomics ranker steering (C), code-enforced DNA-seq gates mapped≥70%
(GOLD) / duplicate≤40% (profile-overridable) / mean-coverage≥30× (C), Ts/Tv 1.8–2.2 in-pipeline
advisory NOT a qc_trace_monitor gate (C 🔧), hard-filter default (vqsr_mode=false) (C), VCF table
viewer `InlineVcfViewer` first-100-rows + MultiQC HTML iframe (C), GIAB HG002 chr20 gold + hap.py
SNV-F1≥0.99/indel-F1≥0.95 (C spec; live Batch numeric run L / ⏳), and the SOMATIC coverage gap +
auto-loop/VQSR/SV-CNV roadmap rows (🗺️)._
