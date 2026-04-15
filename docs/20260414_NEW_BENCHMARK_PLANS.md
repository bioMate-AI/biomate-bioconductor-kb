# BioMate New Benchmark Plans
## 2026-04-14

Three new benchmarks targeting BioMate's distinctive capabilities that no existing
evaluation suite covers: workflow generation from scratch, parameter auto-filling,
and protocol-to-workflow translation.

---

## 1. Workflow Generation Benchmark

### 1.1 Motivation

BioMate has a three-tier generation pipeline:

| Tier | Condition | Source field | What it tests |
|---|---|---|---|
| Template reuse | Score ≥ 12.0 | `template_reuse` | Routing accuracy (already benchmarked) |
| Template adapt | Score 6.0–11.9 | `template_adapt` | Adaptation quality (not yet measured) |
| Generate from scratch | Score < 6.0 | `nextflow_composed` | Raw generation quality (not yet measured) |

The `nextflow_composed` path calls Claude Sonnet with a structured prompt, validates DSL2
syntax, checks include paths, and retries on errors — a real LLM code generation pipeline
that has never been evaluated end-to-end. The "From Prompt to Pipeline" paper (arxiv
2507.20122) benchmarks GPT-4o and DeepSeek-V3 on exactly this task. BioMate should be
measured on the same surface.

### 1.2 Dataset Design

**40 tasks total across two partitions:**

**Partition A — In-catalog (20 tasks)**
Tasks that map to an existing nf-core/BioMate workflow. Expected behavior: source =
`template_reuse`, correct workflow category returned, ≤1 LLM call.

| # | Intent | Expected category |
|---|---|---|
| A01 | RNA-seq DESeq2 differential expression human cancer | rnaseq |
| A02 | GATK HaplotypeCaller germline variant calling WGS | variant_calling |
| A03 | DIA-NN data-independent acquisition proteomics | proteomics_dia |
| A04 | CryoSPARC SPA cryo-EM single particle reconstruction | cryo_em |
| A05 | AlphaFold2 protein structure prediction from FASTA | alphafold |
| A06 | AMBER PMEMD molecular dynamics simulation | molecular_dynamics |
| A07 | 16S rRNA amplicon microbiome QIIME2 | metagenomics |
| A08 | Single-cell RNA-seq Seurat clustering 10x Genomics | scrna_seq |
| A09 | ATAC-seq open chromatin peak calling nf-core/atacseq | atac_seq |
| A10 | ChIP-seq H3K27ac histone mark MACS2 peak calling | chip_seq |
| A11 | WGBS bisulfite sequencing DNA methylation Bismark | bisulfite_seq |
| A12 | MaxQuant label-free quantification DDA proteomics | proteomics_lfq |
| A13 | ADMET absorption distribution metabolism excretion toxicity | admet |
| A14 | AutoDock Vina molecular docking known binding site | molecular_docking |
| A15 | REINVENT4 generative de novo drug design | generative_design |
| A16 | Mutect2 somatic variant calling tumor-normal WGS | variant_calling |
| A17 | scRNA-seq trajectory analysis Monocle pseudotime | scrna_seq |
| A18 | Kraken2 shotgun metagenomics taxonomic classification | metagenomics |
| A19 | GWAS genome-wide association PLINK2 binary phenotype | gwas |
| A20 | MAGeCK CRISPR pooled dropout screen | crispr_screen |

Scoring (Partition A): 1.0 if correct category returned + source = template_reuse;
0.5 if correct category but source = template_adapt or nextflow_composed (over-generated);
0.0 if wrong category.

**Partition B — Out-of-catalog (20 tasks)**
Tasks without an nf-core pipeline. Expected: source = `nextflow_composed`. Score is
on generated code quality, not routing.

| # | Intent | Key tools expected | Why out-of-catalog |
|---|---|---|---|
| B01 | Ribosome profiling + RNA-seq translation efficiency analysis | STAR, ribotricer or xtail, DESeq2 | No nf-core Ribo-seq |
| B02 | CUT&TAG + ATAC-seq joint peak calling with IDR reproducibility | Bowtie2, SEACR, MACS2, IDR | No joint assay pipeline |
| B03 | Direct RNA-seq m6A modification detection with m6anet | minimap2, m6anet, samtools | Nanopore mod-calling not in nf-core |
| B04 | Multi-caller SV consensus from DELLY + Manta + Sniffles2 | bwa-mem2, DELLY, Manta, Sniffles2, SURVIVOR | No consensus SV pipeline |
| B05 | Retrotransposon TE expression from RNA-seq with TEtranscripts | STAR, TEtranscripts, DESeq2 | TE-specific quantification not standard |
| B06 | SLAM-seq metabolic labeling RNA kinetics with GRAND-SLAM | trimgalore, SLAM-DUNK, GRAND-SLAM | No nf-core SLAM-seq |
| B07 | Lipidomics LC-MS data processing with LipidHunter + LipidBlast | LipidHunter, XCMS | No lipidomics nf-core pipeline |
| B08 | Allele-specific expression from phased WGS + RNA-seq | GATK, WhatsHap, WASP, STAR | Multi-assay phasing not standard |
| B09 | RRBS allele-specific methylation with phased genotype integration | Bismark, SNPsplit, GATK | No ASM-from-RRBS pipeline |
| B10 | cfDNA liquid biopsy fragmentomics DELFI analysis | bwa-mem2, samtools, DELFI | DELFI not in nf-core |
| B11 | MNase-seq nucleosome positioning and occupancy analysis | Bowtie2, nucleoATAC or danpos | No nf-core MNase-seq |
| B12 | Proteogenomics: custom protein database from RNA-seq then MS search | STAR, StringTie, Transdecoder, MSFragger | Multi-omics custom DB |
| B13 | Multiome WNN ATAC+RNA joint embedding beyond CellRanger ARC | cellranger-arc, Seurat WNN, Signac | Custom downstream analysis |
| B14 | CRISPResso2 amplicon base editing quantification + efficiency scoring | CRISPResso2, BE-Hive | Base editing specific |
| B15 | ChIP-seq + ATAC-seq footprinting with HINT-ATAC or TOBIAS | TOBIAS, Bowtie2, samtools | TF footprinting not standard |
| B16 | miCLIP/m6A-seq antibody enrichment + m6A site calling | cutadapt, bowtie2, m6A-pipe or MACS2 | miCLIP not in nf-core |
| B17 | CITE-seq + TCR-seq joint clonotype-phenotype analysis | cellranger, scirpy, scanpy | Combined immune profiling |
| B18 | Single-cell ATAC + RNA velocity integration with scVelo+ArchR | cellranger-arc, ArchR, scVelo | Multi-modal velocity |
| B19 | Hi-C loop calling + TAD boundary analysis + compartment calling | HiC-Pro, HiChIP-tools, CTCF loop caller | Sub-pipeline combination |
| B20 | Nanopore adaptive sampling targeted sequencing QC and analysis | NanoStat, NanoPlot, minimap2, mosdepth | Adaptive sampling specific |

Scoring (Partition B) — 4-dimension rubric:

| Dimension | Weight | How measured |
|---|---|---|
| Syntactic validity | Gate (pass/fail) | `nextflow -n lint main.nf` or regex validation in `validate_workflow()` |
| Tool correctness | 40% | LLM judge: are the expected key tools present? |
| Process ordering | 30% | LLM judge: are steps in biologically correct dependency order? |
| Parameter completeness | 30% | LLM judge: are mandatory params declared in `params {}` block? |

A syntactically invalid workflow scores 0.0 regardless of other dimensions.

### 1.3 Implementation

**Files:**
- `evaluation/datasets/workflow_generation/cases.yaml` — 40 tasks with partition, intent, expected_category, key_tools, notes
- `evaluation/adapters/workflow_generation_adapter.py` — calls `client.ask()`, reads `workflow_card.source` + `workflow_card.nextflow_path`, reads generated `.nf` from disk for Partition B, scores with LLM judge
- `evaluation/runners/run_workflow_generation.py` — `--partition A|B|all`, `--dry-run`, `--max-tasks`, results to SQLite

**Key adapter logic:**
```python
response = client.ask(task.question)
source = response.workflow_card.get("source", "")
nf_path = response.workflow_card.get("nextflow_path", "")

if task.metadata["partition"] == "A":
    # Score on routing: did we get the right category?
    score = self._score_partition_a(response, task)
else:
    # Read generated .nf from disk; score with LLM judge
    nf_code = Path(nf_path).read_text() if nf_path and Path(nf_path).exists() else ""
    score = self._score_partition_b(nf_code, task)
```

**Comparison targets:** GPT-4o and DeepSeek-V3 direct code generation (same prompt,
no catalog routing) — these are the models tested in arxiv 2507.20122. BioMate's hybrid
approach (route first, generate only when needed) should win on Partition A and compete
on Partition B.

---

## 2. Parameter Pre-filling Benchmark

### 2.1 Motivation

BioMate infers workflow parameters from user intent via `_infer_params_from_intent_llm()`
and `_apply_parameter_hints()`. This capability — translating a user's natural-language
request into correct parameter values — has never been measured. It directly affects
whether a workflow runs correctly after the user clicks "Execute."

No published benchmark evaluates this for bioinformatics platforms. FReeP (2021) is
the only prior work and uses ML on execution provenance, not LLM-based inference.

### 2.2 Dataset Design

**100 cases, 7 categories:**

| Category | n | What's tested | Example |
|---|---|---|---|
| Genome inference | 20 | Organism + tissue → correct `genome` param | "human breast cancer" → `GRCh38`; "mouse brain" → `GRCm39` |
| Library strandedness | 15 | Library prep method → `strandedness` value | "TruSeq Stranded" → `reverse`; "ScriptSeq" → `forward`; "SMART-seq2" → `unstranded` |
| Tool flag selection | 15 | Analysis goal → specific tool CLI flags | "tumor-only Mutect2" → `tools: mutect2`, no `normal` param |
| Numeric parameter inference | 15 | Depth/scale → numeric params | "targeted panel ~500 genes" → `target_size: 2e6`; "deep WGS 60×" → `coverage_cap: 1000` |
| Reference file selection | 15 | Platform + version → reference files | "10x Genomics 3' v3.1 chemistry" → `chemistry: 10xv3`; "GRCh38.p14" → correct GTF |
| Multi-param inference | 10 | Complex query → ≥3 correct params | "strand-specific lncRNA total RNA-seq ribo-depleted mouse liver" → genome+strandedness+rrna_database |
| Negative (non-inferrable) | 10 | Params that cannot be inferred → should NOT be filled | "Run STAR alignment" with no genome specified → `genome: null`, not a guess |

**Case format:**
```yaml
- id: pf_001
  workflow: nf-core/rnaseq
  user_query: "RNA-seq differential expression from human lung adenocarcinoma, TruSeq Stranded Total RNA library"
  expected_params:
    genome: GRCh38         # must be exact or equivalent
    strandedness: reverse  # TruSeq Stranded = dUTP protocol = reverse
    aligner: star          # default for human, acceptable
  must_not_fill:
    - accession            # not provided — should not invent
    - input                # file path not specified
  tolerance: semantic      # "GRCh38" == "hg38" == "Homo_sapiens_GRCh38"
```

**Scoring per case:**
```
precision = n_correct_filled / n_total_filled   (penalizes hallucinated params)
recall    = n_correct_filled / n_expected        (penalizes missed params)
F1        = 2 * precision * recall / (precision + recall)
penalty   = 1.0 for each must_not_fill param that was incorrectly filled
score     = max(0, F1 - penalty)
```

### 2.3 Implementation

**Files:**
- `evaluation/datasets/param_prefill/cases.yaml` — 100 cases
- `evaluation/adapters/param_prefill_adapter.py` — calls `/api/ai_assistant/search_nextflow_workflow` directly (bypasses chat; returns `generated_parameters` field), computes F1
- `evaluation/runners/run_param_prefill.py` — `--category`, `--dry-run`, results to SQLite

**Key adapter logic:**
```python
# Call the Python backend directly to get generated_parameters
resp = self.http.post(f"{base_url}/api/ai_assistant/search_nextflow_workflow",
                      json={"user_intent": task.question, "inline_parameters": {}})
data = resp.json()
generated_params = {p["name"]: p["value"] for p in data.get("generated_parameters", [])}
score = self._compute_f1(generated_params, task.ground_truth)
```

---

## 3. Protocol-to-Workflow Benchmark

### 3.1 Motivation

A bioinformatics platform that can read a paper's methods section and translate it into
an executable workflow provides unique value over both LLM chat assistants (which describe
but don't execute) and Galaxy-style drag-and-drop tools (which require manual assembly).

BioWorkflow (Briefings in Bioinformatics 2025) demonstrated LLM-based workflow extraction
from papers, but only extraction to JSON — not routing to an executable platform. BioMate
can complete the pipeline: extract → route → fill params → execute.

No benchmark currently evaluates this end-to-end translation for a live platform.

### 3.2 Dataset Design

**35 protocol cases** drawn from three sources:

**Source A: Condensed published methods (20 cases)**
Realistic 100–300 word excerpts modeled after published papers, describing a specific
bioinformatics analysis with enough detail to route and fill key params. Each excerpt
is synthetically written to match the style of published methods sections but avoids
direct copy.

**Source B: Lab SOP descriptions (10 cases)**
Shorter, more instructional descriptions ("as per our standard ChIP-seq protocol: ..."),
testing extraction from informal lab documentation rather than formal paper prose.

**Source C: Ambiguous/incomplete protocols (5 cases)**
Protocol text that intentionally omits one key decision (e.g., says "RNA-seq was performed"
without specifying bulk vs single-cell, or "DDA proteomics" without specifying label-free
vs TMT). Tests whether BioMate correctly asks for clarification rather than guessing.

**Case format:**
```yaml
- id: proto_001
  source_type: published_methods
  domain: transcriptomics
  protocol_text: |
    "Total RNA was extracted from 50 mg of frozen liver tissue using TRIzol reagent
    (Thermo Fisher). rRNA was depleted using the NEBNext rRNA Depletion Kit. Strand-
    specific libraries were prepared using the dUTP method. Paired-end 150bp sequencing
    was performed on NovaSeq 6000. Raw reads were trimmed with Trim Galore (v0.6.7),
    aligned to GRCm39 using STAR 2.7.10a, and quantified with featureCounts. Differential
    expression was analyzed with DESeq2 v1.38 using a paired design to account for
    individual variability."
  expected_workflow: rnaseq
  expected_params:
    genome: GRCm39
    strandedness: reverse      # dUTP = reverse strand
    aligner: star
    deseq2_contrasts: required # paired design mentioned — need contrast file
    rrna_database: required    # rRNA depletion implies rRNA reference
  expected_clarifications: []  # protocol is complete enough to route directly
  notes: "Mouse liver RNA-seq; dUTP method = reverse strand; paired design for DESeq2"

- id: proto_030
  source_type: ambiguous
  domain: proteomics
  protocol_text: |
    "Protein samples were prepared by in-solution digestion with trypsin. LC-MS/MS
    analysis was performed on an Orbitrap Exploris 480. Data were searched against
    the UniProt human proteome database using MaxQuant software."
  expected_workflow: proteomics_lfq   # MaxQuant = DDA, label-free
  expected_params:
    database: uniprot_human
    enzyme: trypsin
  expected_clarifications:
    - quantification_method   # MaxQuant mentioned but LFQ vs SILAC vs TMT not stated
  notes: "MaxQuant + Orbitrap = DDA. But TMT vs LFQ ambiguity is real."
```

**Three evaluation dimensions:**
1. **Routing accuracy** (40%): Did BioMate identify the correct workflow?
2. **Parameter extraction** (40%): F1 score of extracted params vs expected_params
3. **Clarification handling** (20%): For Source C cases, did BioMate ask rather than guess?

### 3.3 Implementation

**Files:**
- `evaluation/datasets/protocol_to_workflow/cases.yaml` — 35 protocol cases
- `evaluation/adapters/protocol_to_workflow_adapter.py` — wraps protocol text in a prompt, calls `client.ask()`, scores routing + param extraction + clarification
- `evaluation/runners/run_protocol_to_workflow.py` — `--source-type`, `--dry-run`, results to SQLite

**Key adapter prompt:**
```python
PROMPT_TEMPLATE = """\
I have the following protocol from a bioinformatics experiment. Please identify the
appropriate analysis workflow and set up the parameters based on what's described.

PROTOCOL:
{protocol_text}

Please confirm which workflow you would run and what parameters you can determine
from the protocol text.
"""
```

---

## 4. Comparison Surface Summary

| Benchmark | BioMate's advantage | External competitor | Gap measured |
|---|---|---|---|
| Workflow Gen Partition A | Zero LLM calls on known tasks (template_reuse) | GPT-4o must generate from scratch | Efficiency + accuracy of catalog lookup |
| Workflow Gen Partition B | `nextflow_composed` with tool DB + validation | GPT-4o, DeepSeek-V3 raw generation | Quality of novel workflow generation |
| Param pre-filling | 100 cases, F1 scoring | No prior LLM benchmark | First measured result for this capability |
| Protocol-to-workflow | Full pipeline: extract → route → fill → execute | BioWorkflow: extract only | End-to-end translation quality |

---

## 5. Implementation Timeline

All three benchmarks are built in the same directory structure:

```
evaluation/
  datasets/
    workflow_generation/   cases.yaml (40 tasks)
    param_prefill/         cases.yaml (100 cases)
    protocol_to_workflow/  cases.yaml (35 cases)
  adapters/
    workflow_generation_adapter.py
    param_prefill_adapter.py
    protocol_to_workflow_adapter.py
  runners/
    run_workflow_generation.py
    run_param_prefill.py
    run_protocol_to_workflow.py
```

All runners follow the existing pattern:
- `--dry-run` to preview without API calls
- `--max-tasks N` for partial runs
- `--output` for results directory
- Parallel execution via `ThreadPoolExecutor(max_workers=8)`
- Results to SQLite via `ResultsStore`

Score targets:
- Workflow Generation Partition A: ≥90% (routing should be near-perfect for in-catalog)
- Workflow Generation Partition B: ≥60% tool correctness (novel generation is hard)
- Param pre-filling: ≥70% F1 overall, ≥85% on genome/strandedness (high-signal params)
- Protocol-to-workflow routing: ≥80%; param extraction: ≥60% F1; clarification: ≥90%
