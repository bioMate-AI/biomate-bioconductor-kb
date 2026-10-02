# Instrument tutorial — Oxford Nanopore MinKNOW → long-read analysis

> **Who this is for:** anyone running an Oxford Nanopore sequencer (MinION, GridION, PromethION) through
> MinKNOW. No coding needed to read this.
> **Time:** ~10 minutes.
> **Where it fits:** Tutorial 6 showed how to *register* an instrument. This tutorial answers: *"My nanopore
> run finished — what does BioMate do with the reads, how do I start it, and how do I read the result?"*

---

## 1. The problem this solves

A nanopore sequencer measures DNA or RNA by threading each strand through a tiny pore and recording the
electrical signal it makes — not the letters directly, but a wiggly current trace. Two things have to happen
before that trace becomes biology:

1. **Basecalling** — a model translates the raw electrical signal into the actual sequence of bases (A, C, G,
   T). The raw signal lives in `.pod5` files (the current format) or `.fast5` files (the older one); basecalling
   turns them into `.fastq` reads.
2. **Downstream analysis** — the reads are then aligned to a genome and used to find variants (DNA differences),
   assemble a genome, or measure gene expression (RNA).

Nanopore's advantage is **long reads** — single reads can span thousands of bases, which makes them powerful for
spotting large structural changes and for assembling genomes that short reads cannot resolve. BioMate packages
the steps so you point it at the run folder and get reads and results back.

> **In one sentence:** BioMate takes the raw signal (or reads) your nanopore run produced and runs the
> long-read pipeline — basecalling, alignment, and variant calling — returning the analysed result with a full
> record.

---

## 2. What this instrument produces

MinKNOW (the software controlling the sequencer) writes, into the run's output folder:

- **`.pod5` files** — the raw electrical-signal data in the current format (preferred for modern basecalling).
- **`.fast5` files** — the same raw signal in the older format (still common on existing machines).
- **`.fastq.gz` files** — basecalled reads, *if* basecalling was turned on inside MinKNOW during the run.
- **Run metadata** — the experiment name, sample ID, flow-cell ID, and the **sequencing kit** used (e.g. a
  `SQK-LSK` ligation kit). The kit matters because it tells BioMate whether this was DNA or RNA.

---

## 3. The BioMate analysis it drives (and why)

The MinKNOW connector detects a completed run and suggests a workflow based on what it finds. Confirmed in the
connector code:

- **Default — `nanopore_basecalling`** (input parameter: `input_path`, the folder of `.pod5`/`.fast5` files).
  This is the entry point: translate raw signal into reads. In the BioMate catalog this routes to the
  **nf-core/nanoseq** pipeline — Oxford Nanopore's DNA/RNA pipeline covering basecalling, alignment, QC, and
  variant calling.
- **If the kit looks like a DNA/genome kit** (e.g. `SQK-LSK`, `RAD`, `RBK`, `NBD`) → the connector suggests
  **`wgs_nanopore_variant_call`** — carry on from reads to whole-genome variant calling (finding SNPs and
  larger structural variants).
- **If the kit looks like an RNA kit** (e.g. `SQK-RNA`, direct-RNA) → the connector suggests
  **`rnaseq_nanopore`** — long-read RNA-seq.

**Why kit-based routing:** the kit is the most reliable signal of what the experiment *was*. A direct-RNA kit
means you want RNA analysis, not DNA variant calling — so BioMate pre-selects the matching workflow instead of
guessing from the files alone. You always confirm before anything runs.

<!-- CAPTURE route=/ ; state=New data events list showing a nanopore event (source=minknow, workflow=nanopore_basecalling, pod5 count, kit) with Launch + Dismiss ; focus=nanopore-event ; note=show the nanopore new-data event card mapping a run to the basecalling workflow -->
*(Figure to add: a nanopore New-data event — "POD5 files detected", the kit, and the mapped basecalling
workflow, with Launch and Dismiss.)*

---

## 4. Before you start — getting the reads to BioMate

Do Tutorial 6 (*Connecting instruments*) first if the sequencer is not yet connected:

- Register it under **Connectors → Instruments**, type **Nanopore MinKNOW**, with the sequencing server's
  **host/IP** and **port** (the form suggests MinKNOW's usual port as a hint).
- Residency is **on-prem** — the raw signal and reads stay inside your network.
- MinKNOW writes to the sequencing server's local disk. If BioMate runs on a different machine, that folder has
  to be reachable (NFS-mounted) by the BioMate **watcher**, which an admin sets up once. The watcher notices
  when a run's state turns to `finishing`/`processing` and new `.pod5`/`.fast5` files have appeared. Ask your
  admin whether the MinKNOW watcher is running.
- When a run completes, it appears under **New data events** mapped to the suggested workflow — or you can start
  the analysis yourself by pointing BioMate at the run folder.

---

## 5. Step by step — run the analysis

1. **Start from the New-data event** (if the watcher is set up): find the completed run under **New data
   events** and press **Launch**. BioMate opens a chat with a pre-filled draft to run the suggested workflow on
   that run's `input_path`. *Or* ask in plain English: *"Basecall and call variants on my nanopore run in
   folder X."*
2. **Check the settings.** Confirm the input folder, the input format (`pod5` vs `fast5`), and — importantly —
   that the suggested workflow matches your experiment (DNA variant calling vs RNA-seq). If the kit was
   detected wrongly, change the workflow here.
3. **Confirm and run.** The pipeline runs on cloud computers. Basecalling is the heaviest step and can take a
   while for a large run.
4. **Watch the phases** move from *pending* → *running* → *completed* in real time.
5. **Read the report** when it finishes (see §6).

> **Nothing runs until you confirm** — Launch only opens a reviewed draft.

---

## 6. Reading the result

Open the **After run** report (the three-tab report from Tutorial 3). What to look for depends on which
workflow ran:

- **Basecalling** → `.fastq.gz` reads plus a quality summary (how many reads, read lengths, and average base
  quality). Long average read length and good quality mean the run went well.
- **Variant calling (DNA)** → a **VCF** file listing the DNA differences found against the reference genome
  (SNPs, small indels, and — a nanopore strength — larger structural variants). Each row is one variant with
  its position and quality.
- **RNA-seq (RNA)** → a table of gene expression levels, used to compare which genes differ between groups.
- **Summary tab** — a plain-language account built **from the real outputs**; if an output cannot be read,
  BioMate withholds that finding rather than inventing it (the Tutorial 3 honesty behaviour).
- **Reproducibility record** — every parameter and tool version, downloadable for a methods section.

<!-- CAPTURE route=/ ; state=After-run report for a nanopore run: Outputs tab listing basecalled fastq + (if variant calling) a VCF + read-quality summary ; focus=nanopore-outputs ; note=show basecalled reads and/or a VCF grouped by phase -->
*(Figure to add: the After-run Outputs tab for a nanopore run — basecalled FASTQ reads, a read-quality
summary, and (for the DNA path) a VCF of variants.)*

---

## 7. Honest limits — what to expect

- **Available, but not yet verified end-to-end here.** The connector mapping is real and
  `nanopore_basecalling` resolves to the nf-core/nanoseq pipeline in the catalog — so the route exists and is
  runnable. But unlike the cryo-EM pipeline, BioMate does **not** have documented end-to-end run evidence for
  the full nanopore long-read path on real data in this review. Treat it as **available but untested**: expect
  to verify the first run on your own data rather than assuming a known-good result.
- **The workflow's catalog metadata is thin.** When you inspect `nanopore_basecalling`'s specification, its
  parameters show as generic placeholders (`param0`…`param3`) and some unrelated tool hints appear — a sign the
  catalog entry for this pipeline is under-enriched. The pipeline routes correctly, but don't rely on the
  parameter labels reading cleanly; confirm what each setting does before running.
- **Kit detection is a helpful guess, not a guarantee.** The DNA-vs-RNA routing is inferred from the kit name.
  Always confirm the selected workflow matches your actual experiment before running.
- **The run folder must be reachable.** MinKNOW writes to the sequencer's local disk; if BioMate runs
  elsewhere, that folder must be mounted so the analysis can read it.
- **Basecalling model choice affects accuracy.** Higher-accuracy basecalling models cost more compute. If the
  options are exposed, higher accuracy is usually worth it for variant calling.

---

## 8. Where to go next

| You want to… | Where |
|---|---|
| Register the sequencer / check connectivity | **Tutorial 6 — Connecting instruments** |
| Understand the three-tab report | **Tutorial 3 — Running a workflow and reading the report** |
| View a VCF or read-quality file | **Tutorial 5 — Viewing your results** |
| Bring a run folder in by hand | **Tutorial 4 — Bringing your own data** |

The habit for this instrument: **let the watcher notice the finished run → Launch the reviewed draft → confirm
DNA-vs-RNA workflow → run → read the reads/VCF.**

---

## 9. Key terms

| Term | What it means — and why you care |
|---|---|
| **Basecalling** | Translating the raw electrical signal into actual A/C/G/T bases. The first step for every nanopore run. |
| **POD5 / FAST5** | The raw-signal file formats — POD5 is current, FAST5 is older. Both are the basecaller's input. |
| **FASTQ** | Basecalled reads (the letters plus a quality score per base). The output of basecalling. |
| **Long reads** | Single reads spanning thousands of bases — nanopore's strength for structural variants and assembly. |
| **Sequencing kit** | The chemistry used (e.g. SQK-LSK for DNA). Tells BioMate whether to run DNA or RNA analysis. |
| **VCF** | A file listing the DNA differences found against a reference genome — the output of variant calling. |
| **Structural variant** | A large DNA change (big insertion, deletion, rearrangement) that long reads detect well. |

---

> **Honesty verdict for this instrument:** *Available but untested end-to-end here.* The connector mapping is
> real and `nanopore_basecalling` resolves to nf-core/nanoseq in the catalog, so the analysis route exists and
> is runnable. There is no documented end-to-end run evidence for the full long-read path on real data in this
> review, and the catalog entry's parameters are under-enriched (generic `param0…param3` labels). Verify your
> first run rather than assuming a known-good result.

_Companion references: `docs/user-manual/tutorials/T6-connecting-instruments.md`;
`docs/user-manual/tutorials/T3-running-a-workflow-and-reading-the-report.md`._
