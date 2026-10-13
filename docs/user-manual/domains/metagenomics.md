# Metagenomics (taxonomic profiling & MAG binning)

> One-line promise: go from shotgun metagenomic data to either a **taxonomic
> profile** ("who is in this sample, at what abundance") or a set of
> **metagenome-assembled genomes (MAGs)** with taxonomy and differential
> abundance across conditions — so you end with organisms and community shifts,
> not a pile of contigs.
> For: **microbiome researchers / PIs** profiling gut/environmental communities
> and **bioinformaticians** who want the binning → taxonomy → differential-
> abundance chain (or a Kraken2/Bracken/MetaPhlAn profile) run and reported for
> them. No coding required.

<!--
P2 chapter. Every "supported" claim below is green in coverage-ledger.md § "Metagenomics (profiling / MAG)".
Honesty rule (IMPORTANT): the ONLY code-enforced metagenomics QC gate is read-classification % (Kraken2/Bracken/
MetaPhlAn steps). Bin completeness / contamination (CheckM2) and CAMI recovery are SPEC-ONLY (validator metrics,
not runtime gates) — and CheckM2/MetaSPAdes/MEGAHIT/MetaBAT are NOT catalog workflows at all. The MAG chain
(shotgun_metagenomics_to_mag) starts from ASSEMBLED CONTIGS and uses CONCOCT → MMseqs2 → PathoStat; Kraken2/
Bracken/MetaPhlAn are SEPARATE profiling workflows, not chain steps. This chapter documents both honestly.
Anything not built is in "What's not covered".
-->

## What this is for

This is the **"who's in my sample, and what changed"** path for shotgun
metagenomics. There are two distinct questions, and BioMate answers them with
different tools:

1. **Taxonomic profiling** — "what organisms are present and at what relative
   abundance?" Fast, reference-based read classification with **Kraken2 +
   Bracken** or **MetaPhlAn**. You get a species/genus abundance table directly
   from reads.
2. **MAG recovery (binning)** — "can I reconstruct genomes of the organisms in
   this community, including unknown ones?" From assembled contigs, **bin** them
   into candidate genomes (CONCOCT), assign **taxonomy** (MMseqs2), and compare
   **differential abundance** across conditions (PathoStat).

The through-line is interpretation: the worked example ends on a *decision*
(these genomes recovered, this community shift), not a process tree.

> **Tip** — Profiling and binning answer different questions. If you just want
> "who is here," use the profiling workflows (Kraken2/Bracken/MetaPhlAn) —
> reference-based, fast, no assembly needed. If you want *genomes* (including
> novel organisms with no reference), you need assembly + binning (the MAG chain).
> Don't run the heavy binning path when a profile is all you need.

## Use cases

| Goal (researcher's words) | Workflow(s) / chain | Inputs | Outputs (artifact) | Lane |
|---|---|---|---|---|
| "Recover genomes (MAGs) from my assembled contigs, with taxonomy and abundance" | chain **`shotgun_metagenomics_to_mag`**: CONCOCT binning (id **10499**) → MMseqs2 contig taxonomy (id **10541**) → PathoStat differential abundance (id **12019**) | Assembled contigs (FASTA) + coverage + sample metadata | MAGs (FASTA) + taxonomy TSV + differential-abundance TSV | Cloud (AWS Batch) |
| "Taxonomic profile: who's in my sample and how abundant" | `nf-core/fasta_build_add_kraken2_bracken` (id **1807**) | Reads / contigs | Kraken2 + Bracken abundance table | Cloud |
| "MetaPhlAn taxonomic profile from FASTQ" | `nf-core/fastq_taxonomic_profile_metaphlan` (id **1811**) | FASTQ | MetaPhlAn species-abundance table | Cloud |
| "Screen my reads for contamination against Kraken2" | `nf-core/fastq_contam_seqtk_kraken` (id **1765**) | FASTQ | Contamination classification | Cloud |

> **Pitfall — the MAG chain starts from assembled contigs, not raw reads, and it
> does not use CheckM2/MEGAHIT.** `shotgun_metagenomics_to_mag` is **CONCOCT →
> MMseqs2 → PathoStat**. It expects **assembled contigs + coverage** as input
> (you assemble first). The tutorial checklist mentions CheckM2 (bin QC),
> MetaSPAdes/MEGAHIT (assembly), MetaBAT — **none of these are catalog workflows**
> in BioMate. Bin quality (completeness/contamination) is a *validator* concept,
> not a step in this chain. Document what runs: bin the contigs you provide →
> assign taxonomy → compare abundance.

## How to ask

BioMate routes on intent. The disambiguation that matters here is **profiling vs
MAG recovery** and **reads vs assembled contigs**.

MAG recovery (the binning chain):

> "MAG recovery with binning and taxonomy assignment." — or —
> "Shotgun metagenomics with CONCOCT binning and taxonomy, differential abundance
> across conditions."

Taxonomic profiling:

> "Give me a taxonomic profile of my metagenome with Kraken2 and Bracken." — or —
> "MetaPhlAn species abundance from my FASTQ."

The MAG chain triggers on binning context — its example queries include
*"shotgun metagenomics with CONCOCT binning and taxonomy"*, *"metagenome
assembled genomes from shotgun sequencing"*, *"MAG recovery with binning and
taxonomy assignment"*, *"metagenomics differential abundance analysis across
conditions"*
(`backend/lib/galaxy/ai/chain_composer/proposed_chains/shotgun_metagenomics_to_mag.json`).

**Disambiguation to avoid:**

- **Profiling vs binning.** "Who's here / relative abundance" = Kraken2/Bracken/
  MetaPhlAn (reference-based, from reads). "Recover genomes / find novel
  organisms" = the MAG chain (assembly-based). These are different tools; name the
  goal.
- **Reads vs contigs.** The MAG chain needs **assembled contigs + coverage**. If
  you have raw FASTQ and want MAGs, you assemble first (assembly is not part of
  this chain — see What's not covered). If you have reads and want a *profile*,
  Kraken2/MetaPhlAn take reads directly.
- **Amplicon (16S) vs shotgun.** This chapter is **shotgun** metagenomics. 16S
  amplicon profiling is a different assay/pipeline; name it if that's your data.

> **Tip — provide coverage with your contigs.** CONCOCT bins using both sequence
> composition and per-sample coverage. Supplying the coverage table (not just the
> contigs) markedly improves bin quality.

## Tools & workflows behind this

| Tool / workflow | Role | Where (verified) |
|---|---|---|
| Chain `shotgun_metagenomics_to_mag` | 3-step: bin contigs → assign taxonomy → differential abundance | `backend/lib/galaxy/ai/chain_composer/proposed_chains/shotgun_metagenomics_to_mag.json`; DB `workflow_chains` |
| `Fasta Binning Concoct` (id **10499**) | CONCOCT contig binning into candidate MAGs | DB id 10499; chain step 1 |
| `Mmseqs Contig Taxonomy` (id **10541**) | MMseqs2 taxonomy assignment to bins/contigs | DB id 10541; chain step 2 |
| `PathoStat` (id **12019**) | Statistical microbiome analysis / differential abundance | DB id 12019; chain step 3 |
| `nf-core/fasta_build_add_kraken2_bracken` (id **1807**) | Kraken2 classification + Bracken abundance re-estimation | DB id 1807 |
| `nf-core/fastq_taxonomic_profile_metaphlan` (id **1811**) | MetaPhlAn marker-gene profiling | DB id 1811 |
| `nf-core/fastq_extract_kraken_krakentools` (id **1795**) | KrakenTools read extraction by taxon | DB id 1795 |

The chain's hand-off is real: CONCOCT's `bins` feed MMseqs2's `contigs`; MMseqs2's
`taxonomy_table` feeds PathoStat's `taxa_abundance` (chain JSON `connections`).

> **License** — CONCOCT, MMseqs2, PathoStat, Kraken2, Bracken, and MetaPhlAn are
> open-source academic tools; results are yours. Reference databases (Kraken2 DB,
> MetaPhlAn markers) are the standard public releases.

## QC gates & how to read them

**Honest statement up front: the only code-enforced metagenomics QC gate is
read-classification %.** It fires on Kraken2/Bracken/MetaPhlAn/Kaiju steps
(`qc_trace_monitor.py:4874-4909`). Bin completeness / contamination (the tutorial's
CheckM2 gates) and CAMI recovery are **spec / validator** concepts — there is no
code gate for them in the pipeline monitor, and CheckM2 is not a catalog workflow.

| Gate / check | Threshold | What it means | Enforced where |
|---|---|---|---|
| **Read classification %** | **< 30% critical (HALT)** · **30–60% warning (advisory)** · ≥ 60% pass | Fraction of reads assigned a taxon. Critically low = contamination, wrong database, or highly divergent organisms — verify sample and DB before trusting the profile. | **Code-enforced (profiling).** `qc_trace_monitor.py:4874-4909`; Wood, Lu & Langmead 2019 (Kraken2), QIIME2 practice |
| **Bin completeness** | tutorial target **≥ 80%** per high-quality MAG | How complete each recovered genome is (single-copy marker recovery). | **Spec / validator only** — no code gate; CheckM2 is not a catalog workflow |
| **Contamination** | tutorial target **≤ 5%** per high-quality MAG | How much a bin mixes multiple organisms. | **Spec / validator only** — no code gate |
| **Taxonomy assigned to bins** | tutorial target **≥ 70%** | Fraction of bins that got a taxonomic label from MMseqs2. | **Spec / advisory** — read from the taxonomy output |
| **CAMI II HQ-MAG recovery** | tutorial target **≥ 70%** | Benchmark score: fraction of reference genomes recovered as high-quality MAGs. | **Validator metric, not a runtime gate** |

**How to read each:**

- **Read classification %** — the one real gate, and it applies to *profiling*
  (Kraken2/MetaPhlAn), not to the CONCOCT binning chain. A gut sample against a
  matched database classifies well; novel environments routinely sit at 40–80%
  (database-dependent). Below 30%, the code halts — suspect contamination, the
  wrong DB, or organisms with no reference. 30–60% is a "look closer" warning.
- **Completeness / contamination** — the standard MAG-quality dimensions (a
  "high-quality MAG" is conventionally ≥ 80% complete, ≤ 5% contaminated). BioMate
  does **not** compute these as a live gate; you read them from bin-QC output if
  you run a separate CheckM-style step. Interpret them as: a complete,
  low-contamination bin is a genome you can trust; a fragmentary or mixed bin is a
  draft.
- **CAMI recovery** — the *benchmark* number for the gold-standard demo (how many
  known genomes the pipeline reconstructs), computed by the validator. It
  calibrates the pipeline; it is not a gate on your own community.

> **Pitfall — the CheckM2 bin gates are not enforced (and CheckM2 isn't a
> workflow).** The tutorial lists "bin completeness ≥ 80% / contamination ≤ 5%
> (CheckM2)," but there is **no code gate** for these and **no CheckM2 catalog
> workflow** in BioMate. Bin quality is something you assess from output, not a
> halt the system applies. Don't assume the pipeline filtered your bins to
> high-quality-only for you.

> **QC gate — classification % applies to profiling, not binning.** The one
> enforced gate lives on the Kraken2/MetaPhlAn read-classification step. If you
> run the CONCOCT MAG chain, that gate does not fire — bin quality is on you to
> read.

### What "fixing" a QC issue looks like here

There is **no metagenomics auto-loop**. Issues are surfaced for you to correct
and re-run:

- Low classification % → verify the reference database matches the sample type,
  check for host/adapter contamination, and re-run profiling.
- Poor bins (fragmentary, mixed) → provide per-sample coverage to CONCOCT, or
  improve the upstream assembly, then re-bin.
- Few bins get taxonomy → check the MMseqs2 database; annotate at a higher rank.

## Worked example (gold standard)

**Goal.** Recover MAGs on a benchmark where the *right answer is known*, and read
the artifact as a microbiologist would.

**Dataset.** **CAMI II low-complexity gut subset** (5 samples) — the Critical
Assessment of Metagenome Interpretation challenge. The ground truth is the CAMI II
gold-standard taxonomy and binning labels: we know exactly which genomes are in
the community and which contigs belong to each, so we can score bin-level F1 and
high-quality-MAG recovery against a reference, not just count bins.
(`evaluation/tutorial_demos/gold_standards.yaml:63-72`;
`Tutorial Demo Scenarios 7-domain.md:333-386`.)

**Prompt** (the recorded tutorial T6):

> "MAG recovery with binning and taxonomy assignment."

**What comes back and how to read it (from the demo spec):**

- **38 bins from CONCOCT; 27 kept as high-quality** (completeness ≥ 80,
  contamination ≤ 5). Interpretation: CONCOCT proposed 38 candidate genomes;
  bin-QC keeps 27 that are complete and clean enough to call genomes.
- **MMseqs2 assigned taxonomy at genus rank to ≈ 89% of bins** — above the 70%
  target. Interpretation: most recovered genomes have a taxonomic identity.
- **The ground-truth check.** **≈ 71% of CAMI II reference genomes recovered as
  high-quality MAGs**, above the 70% pass. Interpretation: the pipeline
  reconstructs the known community at the CAMI II benchmark standard, so you can
  trust its bins on communities without a reference.
- **PathoStat differential abundance** — the community-level shifts across your
  conditions, as a testable table.

**The artifact.** A set of MAG FASTAs + a taxonomy TSV + a differential-abundance
TSV. You end on a decision — *these genomes were recovered, this is who they are,
this is how the community shifted, at CAMI-grade recovery* — which is exactly the
"gold-standard-comparable artifact" the tutorial-demo plan mandates.

> **Note (verification tier).** The chain wiring (CONCOCT → MMseqs2 → PathoStat),
> workflow IDs (10499 / 10541 / 12019; profiling 1807 / 1811 / 1795), and routing
> are **code-verified (C)** by reading source (citations above). The one enforced
> QC gate is read-classification % (profiling only); bin completeness/contamination
> and CAMI recovery are **spec / validator, not runtime gates**. The numeric
> outputs (38 bins / 27 HQ / 71% recovery) come from the gold-standard demo spec;
> a **fresh live AWS Batch re-run** to reproduce them is **pending (L / ⏳)** and
> was not fired — Batch runs cost real money and the plan forbids speculative
> execution. The AMBER-based F1/recovery scoring is a **validator metric**, and
> the validator file (`evaluation/tutorial_demos/metagenomics.py`) referenced by
> the demo doc is **not yet present in the repo** (only `transcriptomics.py`
> exists) — see What's not covered.

## Outputs & visualization

Every output renders in the after-run panel's Outputs section via the in-app viewer
taxonomy (`frontend/client/src/components/step-output-preview.tsx:66-105`); the
mapping below is by file extension.

| Output | File | In-app viewer | When to go interactive |
|---|---|---|---|
| MAG genomes | `*.fasta` / `*.fa` | **Sequence** viewer (`SEQ_EXTS`, `step-output-preview.tsx:73`) | Download bins for downstream annotation (Prokka etc.) |
| Taxonomy table | `taxonomy.tsv` | **Table** viewer (sortable, 200-row preview + full download) | Download to inspect per-bin taxonomic assignment |
| Differential-abundance table | `differential_abundance.tsv` | **Table** viewer | Download; sort by effect size / p-value across conditions |
| Kraken2 / Bracken profile | `*.tsv` / `*.report` | **Table** viewer | Download the abundance table for plotting |
| PathoStat / QC plots | `*.pdf` / `*.png` / `*.html` | **PDF / Image / HTML** viewer | Read community composition; export for figures |

> **Tip — MAGs are the start of the next analysis.** The recovered bins are FASTA
> genomes; download the high-quality ones to annotate (gene calling / functional
> annotation) or place them phylogenetically. In-app, read the taxonomy and
> abundance tables directly.

## Pitfalls & tips

> **Pitfall — profiling vs binning are different jobs.** Kraken2/MetaPhlAn tell
> you *who's here* from reads (fast, reference-based). The MAG chain reconstructs
> *genomes* from assembled contigs (heavy). Pick the one that matches your
> question.

> **Pitfall — the MAG chain needs assembled contigs.** Assembly is not part of
> the chain (and MetaSPAdes/MEGAHIT are not catalog workflows). Assemble first,
> then bin.

> **Pitfall — no bin-quality gate.** CheckM2 completeness/contamination is not
> enforced and not a workflow; read bin quality from output before calling a bin a
> genome.

> **Tip — supply coverage with contigs.** CONCOCT bins better with per-sample
> coverage than with composition alone.

## What's not covered

Honest scope — these are **not** claimed as present; they live in **Appendix E
(Coverage & roadmap)**:

- **Assembly in the MAG chain.** The chain starts from assembled contigs;
  MetaSPAdes / MEGAHIT are **not** catalog workflows — assembly is a prerequisite
  you do upstream.
- **CheckM2 bin QC as a workflow or gate.** Completeness/contamination are not
  computed as a live gate and CheckM2 is not indexed; MetaBAT/MaxBin (alternative
  binners) are also absent.
- **A CAMI-recovery gate on your data.** CAMI recovery / bin F1 is a **validator**
  metric for the demo, not a runtime gate. The validator file
  `evaluation/tutorial_demos/metagenomics.py` (and its AMBER dependency) is **not
  yet present in the repo**.
- **A metagenomics auto-loop.** No automatic parameter-tuning; binning/profiling
  fixes are manual.
- **16S amplicon profiling.** This chapter is shotgun only.
- **Deep coverage of viral metagenomics / functional annotation / Bracken
  abundance modelling.** Profiling workflows **exist and route**, but end-to-end
  worked examples and gold-standard validation for them are roadmap.
- **Interactive tools (RStudio / Jupyter) launch.** On dev these are **not
  provisioned** (`/api/interactive/available` → `available:false`); the launch
  buttons are correctly hidden. In-app table/sequence/plot/HTML viewers cover
  reading outputs; interactive re-analysis is environment-dependent.

---
_Verification: this page depends on the coverage-ledger rows under
**"## Metagenomics (profiling / MAG)"** — chain `shotgun_metagenomics_to_mag`
(CONCOCT→MMseqs2→PathoStat, starts from contigs) + step IDs 10499/10541/12019 +
profiling 1807/1811/1795 (C), routing + profiling-vs-binning + reads-vs-contigs
disambiguation (C), read-classification-% code gate (profiling only) (C),
bin-completeness/contamination + CAMI recovery as spec/validator-not-gate + CheckM2/
MetaSPAdes/MEGAHIT/MetaBAT absent (C 🔧/🗺️), viewer taxonomy (C), CAMI II gold
artifact + 71% recovery (C from demo spec; live-Batch re-run L / ⏳; validator file
absent 🗺️), and the roadmap/gap rows (🗺️)._
