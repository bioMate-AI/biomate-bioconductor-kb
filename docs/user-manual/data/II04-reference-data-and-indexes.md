# Reference data & indexes

> One-line promise: know exactly which **reference data** BioMate carries — genome builds and their
> pre-wired iGenomes paths, structure search indexes (AlphaFold DB / Foldseek / MMseqs2), and the
> chemical/target databases (ChEMBL, DepMap, GTEx, BindingDB) — and, just as important, which of those
> are *wired and callable* versus *not yet verified end-to-end*. For: bioinformaticians and
> drug-discovery scientists who need to know what BioMate can already resolve against, and where the
> honest edges are.

<!--
Part II.4 (Databases & retrieval). Tier C, cited file:line. HONESTY RULE FOR THIS CHAPTER: distinguish
three states cleanly — (1) WIRED & INDEXED (code exists, workflow is in the routable DB, callable),
(2) VERIFIED (a benchmark/live run confirmed it end-to-end), (3) NOT BUILT. Several structure indexes
are (1) but not (2): their evaluation tasks T17–T21 are marked unverified=True. Say so. Do NOT claim a
benchmark result we haven't produced. Do NOT fire Batch/LLM runs.
-->

## What this is for

Before BioMate can align your reads, fold your protein, or profile your compound, it needs **reference
data** to run against: a genome build, a structure database, a target/activity database. This chapter is
the inventory — what is already carried and pre-wired, so you don't have to supply it, and what is
present in code but not yet confirmed by an end-to-end run.

The honesty commitment for this chapter is a **three-state distinction** you should keep in mind while
reading:

- **Wired & indexed** — the code and (where relevant) the workflow exist and the workflow is in the
  routable catalog, so BioMate can select and launch it.
- **Verified** — an actual run (benchmark or live) confirmed it produced the right artifact end to end.
- **Not built** — genuinely absent; it lives in Appendix E.

Most reference data below is **wired & indexed**. A few structure-search paths are wired but **not yet
verified** — those are called out explicitly, never sold as proven.

> **Pitfall — "wired" is not "verified."** A workflow being in the catalog means BioMate can *route* to
> it and *launch* it; it does **not** mean we have a benchmark number confirming its output. Where that
> gap exists (Foldseek, MMseqs2), this chapter says so and points at Appendix E.

## Use cases

| Goal (researcher's words) | What reference data it uses | Wiring state | Where |
|---|---|---|---|
| "Align my human RNA-seq — I didn't upload a genome" | Genome build param (GRCh38…) + pre-wired iGenomes S3 FASTA | Wired & indexed | `ai_assistant.py:2544-2558`; `nfcore/rnaseq/main.nf:12` |
| "Find structures similar to this fold" | Foldseek web-API search vs AlphaFold DB (afdb50/afdb-swissprot/pdb100) | Wired & indexed; **not yet verified** (T17) | `.../drug_discovery/alphafold_db_search/main.nf`; `run_phase1.py:76-77` |
| "Find homologous sequences" | MMseqs2 search vs a pre-built target DB | Wired & indexed; **not yet verified** (T18) | `.../proteomics/mmseqs2_sequence_search/main.nf`; `run_phase1.py:78-79` |
| "Get the AlphaFold structure for this UniProt" | AlphaFold DB EBI REST fetch by accession | Wired & callable | `tools/biomate_ai_tools/alphafold_client.py:14-62` |
| "Off-target / selectivity for this compound" | ChEMBL activity lookup; BindingDB affinities | Wired | `.../drug_discovery/proteome_selectivity_profiling/main.nf`; BindingDB data-lake wrapper |
| "CRISPR dependency for this gene" | DepMap CRISPR effect/dependency tables (data lake) | Wired (data lake) | `tools/biomate_data_management/…DepMap_CRISPRGeneEffect_csv.py` |

## Tools & workflows behind this

### Genomes & annotations

BioMate carries the common reference builds so you rarely have to supply one:

- **Genome build param.** nf-core/rnaseq declares the accepted builds inline:
  `GRCh38 | GRCm39 | GRCz11 | BDGP6 | Rnor_6.0 | R64-1-1` (`backend/biomni_workflows/nfcore/rnaseq/main.nf:12`).
- **Build detection from your prompt.** A regex extracts a build you mention —
  `hg38|hg19|GRCh38|GRCh37|mm10|mm39|GRCm38|GRCm39|T2T-CHM13|dm6|ce11|danRer11|sacCer3` — so "align my
  human reads to GRCh38" fills the param automatically (`ai_assistant.py:2544`,
  `_extract_genome_build` at `:2572`).
- **Alias normalisation.** `GRCh38→hg38`, `GRCh37→hg19`, `GRCm38→mm10`, `GRCm39→mm39` — user-facing names
  are mapped to canonical builds (`ai_assistant.py:2578`).
- **Pre-wired iGenomes paths.** For those builds, the WholeGenome FASTA (and GATK known-sites for
  variant work) are pre-filled from the public `ngi-igenomes` S3 bucket, e.g. GRCh38 →
  `s3://ngi-igenomes/igenomes/Homo_sapiens/Ensembl/GRCh38/…/genome.fa`
  (`_IGENOMES_REFERENCE`, `ai_assistant.py:2551-2558`; `_IGENOMES_KNOWN_SITES`, `:2559-2561`).

> **Tip — you usually don't upload a reference genome.** Name the build ("human / GRCh38", "mouse /
> mm10") and BioMate resolves the FASTA (and dbSNP known-sites for variant calling) from iGenomes. Only
> supply your own reference when you need a build BioMate doesn't carry.

### Structure indexes (verify hard — several are wired-but-unverified)

This is the honesty-critical section. Each of the three structure paths **exists as code and is in the
routable catalog** — but two of them have **unverified** benchmark status.

**AlphaFold DB (fetch by accession) — wired & callable.** A REST client fetches predicted structures
from EBI by UniProt ID (PDB/CIF/JSON), checks availability, and does gene→UniProt→AlphaFold lookup
(`alphafold_client.py:14-62, 65-92, 95-121`), with an MCP-tool wrapper as a fallback path
(`mcp_client.py:120-135`). It is indexed as workflow **"AlphaFold DB Search" (id 12647)** and
**"alphafold" (id 14469)** in the routable catalog.

**Foldseek (structural search) — wired & indexed; NOT yet verified.** The `alphafold_db_search` workflow
does structural similarity search via the **free public Foldseek web server** (`search.foldseek.com`),
not a local database copy: upload PDB → ticket → poll → results, against `afdb50, afdb-swissprot, pdb100`
(`.../drug_discovery/alphafold_db_search/main.nf:4-33`). It is indexed as
**"foldseek_structure_search" (id 14456)**. **But** its evaluation task **T17** is explicitly marked
`unverified=True` — the SCOPe40 benchmark has not been run to confirm sensitivity end to end
(`evaluation/comparison/run_phase1.py:76-77`).

**MMseqs2 (sequence homology) — wired & indexed; NOT yet verified.** A containerised MMseqs2 search runs
against a pre-built target DB (UniRef/nr/Swiss-Prot on S3), with GPU support
(`.../proteomics/mmseqs2_sequence_search/main.nf`). Indexed as **"mmseqs2_sequence_search" (id 14462)**
(plus metagenomics MMseqs workflows `nf-core/mmseqs_contig_taxonomy` id 1760 and
`nf-core/mmseqs_fasta_cluster` id 1813). **But** its evaluation task **T18** is marked `unverified=True`
— the Pfam/UniRef50 recall benchmark has not been run (`run_phase1.py:78-79`).

> **QC gate — the honest status of the structure indexes.** AlphaFold-DB fetch-by-accession is a real
> callable API client. Foldseek and MMseqs2 are wired workflows in the routable catalog, but their
> end-to-end benchmark verification (**T17, T18**) is **UNVERIFIED / smoke-test-gated**. GPU-tier
> structure tasks **T19 (GROMACS MD)** and **T20 (AF-Multimer / Boltz multimer)** are likewise
> `unverified=True` (`run_phase1.py:85-88`). Treat these as *available to try*, not *proven*. This
> matches the coverage-ledger note "T17–T21 … UNVERIFIED / smoke-test-gated" and lives in Appendix E.

### Chemical / target databases

| Database | What it provides | Wiring | Where |
|---|---|---|---|
| **ChEMBL** | Bioactivity / similarity for selectivity profiling | REST client + indexed workflow | `.../drug_discovery/proteome_selectivity_profiling/main.nf` (id 12871); ChEMBL client smoke-imported `docker/biomni-pharma/smoke.py` |
| **GTEx** | Median tissue expression (live) | REST lookup in the research agent (see II.3) | `research_agent.py:570-596` |
| **DepMap** | CRISPR gene effect / dependency, cell-line metadata, expression | Data-lake table wrappers (query CSVs) | `tools/biomate_data_management/…DepMap_CRISPRGeneEffect_csv.py`, `…_Model_csv.py`, `…_OmicsExpression…TPMLogp1_csv.py` |
| **BindingDB** | Binding affinities; TDC pre-trained affinity models | Data-lake wrapper + TDC model loading | `tools/biomate_data_management/…BindingDB_All_202409_tsv.py` |
| **TDC / DeepPurpose** | ADMET model training data (see Drug discovery → IND) | Model libraries in the pharmacology tools | `biomni_workflows/galaxy/tools/biomni/_lib/pharmacology.py` |

> **Pitfall — DepMap and BindingDB are *data-lake tables*, not live web APIs.** BioMate queries a staged
> copy (CSV/TSV wrappers under `biomate_data_management/`), so results reflect the staged snapshot's
> version (e.g. `BindingDB_All_202409`), not a live upstream query. GTEx, by contrast, is a live REST
> lookup (via the research agent, II.3).

### FAERS — a mismatch worth stating

Prior notes list **FAERS (adverse-event pharmacovigilance) as a coverage gap.** That is **out of date at
the code level**: an indexed Bioconductor workflow exists — **"faers" (id 11363)**,
`.../bioconductor/faers/main.nf` (FAERS metadata → quarterly download/parse → MedDRA standardisation →
de-dup → signal analysis). It is **wired & indexed**, but like the structure indexes it has **not been
verified end-to-end** in this manual's audit. So: available to route to, not yet proven. (Recorded as a
mismatch in the ledger; treated as wired-but-unverified in Appendix E, not sold as a finished feature.)

### Accession resolution (see II.2)

Fetching public data *by accession* (GEO/SRA/PDB/EMPIAR/PRIDE/UniProt/ChEMBL/PubChem/dbSNP/ClinVar…) is
its own topic — the detection registry and skip-local-validation logic live in
`nextflow_executor.py:2365` (`_is_public_accession`) and are classified in
`backend/tests/test_accession_detection.py`. That belongs to **II.2 — Public datasets & accession
resolver**; this chapter only notes that reference data is often resolved *from* an accession you name.

## QC gates & how to read them

Reference data doesn't have "QC gates" in the ADMET sense; the gate that matters here is a **status
gate** — is what you're about to run *verified*, or merely *wired*?

- **Verified** (a benchmark/live run confirmed the artifact): genome-backed RNA-seq / variant chains
  (see Transcriptomics, Drug discovery → IND), and AlphaFold-DB fetch-by-accession.
- **Wired but unverified** (routable, launchable, no confirming run): Foldseek (T17), MMseqs2 (T18),
  GROMACS MD (T19), AF-Multimer/Boltz-multimer (T20), FAERS.

If you launch a wired-but-unverified path, treat its first run as *your* verification, and compare
against a gold standard before you trust the number.

## Outputs & visualization

Reference data surfaces through the workflows that consume it — a genome-aligned BAM/VCF, a Foldseek hit
table, a ChEMBL selectivity profile — and those render in the standard in-app viewers documented in
**I.8 — Outputs, viewers & interactive panels** (structure viewer with pLDDT colouring for predicted
structures; table viewer for hit lists and activity tables). There is no separate "reference data
browser" surface.

![Placeholder: workflow panel pre-run strip showing an auto-filled GRCh38 genome param resolved from the user's "human" prompt](../assets/ii04-1-genome-prefill.png)

## Pitfalls & tips

> **Tip — name the organism/build, not the file.** "Human / GRCh38" or "mouse / mm10" auto-resolves the
> reference FASTA and known-sites from iGenomes. You only need to upload a reference for a build BioMate
> doesn't carry.

> **Pitfall — Foldseek/MMseqs2 are callable but unproven here.** They route and launch, but their
> benchmark verification (T17/T18) is pending. Don't cite a "Foldseek result on BioMate" as validated;
> run it against a gold standard first. (Appendix E.)

> **Pitfall — chemical DBs are snapshots, not live.** DepMap and BindingDB are staged data-lake tables;
> results are as current as the staged version. GTEx is the exception (live REST).

## What's not covered

Honest scope — **not** claimed as verified-and-present; these live in **Appendix E (Coverage &
roadmap)**:

- **End-to-end benchmark verification of Foldseek (T17), MMseqs2 (T18), GROMACS MD (T19),
  AF-Multimer/Boltz-multimer (T20).** Wired and indexed; benchmark runs are `unverified=True`
  (`run_phase1.py:76-88`).
- **FAERS as a *verified* pharmacovigilance feature.** The workflow is indexed (id 11363) but not
  verified end-to-end in this audit — a code-vs-ledger mismatch, recorded, not oversold.
- **A local Foldseek/AlphaFold database copy.** Structure search uses the free public Foldseek web API,
  not a self-hosted structure index (`alphafold_db_search/main.nf:6-7`).
- **Live DepMap / BindingDB web-API queries.** Only staged data-lake snapshots are queried for these.
- **A user-facing reference-data browser.** Reference data is resolved by workflows, not browsed
  directly.

---
_Verification: this page depends on the coverage-ledger rows under **"## II.4 Reference data &
indexes"** — genome build param + regex detection + iGenomes pre-wired FASTA/known-sites (C); AlphaFold
DB fetch-by-accession client + indexed workflow (C); Foldseek workflow wired & indexed but T17 unverified
(C / 🗺️); MMseqs2 workflow wired & indexed but T18 unverified (C / 🗺️); GROMACS-MD T19 & AF-multimer T20
unverified (C / 🗺️); ChEMBL selectivity workflow (C); GTEx live REST (C, shared with II.3); DepMap &
BindingDB data-lake wrappers, snapshot-not-live (C); FAERS workflow indexed id 11363 = ledger mismatch,
wired-but-unverified (🔧); accession resolver pointer to II.2 (C)._
