# Preprint manuscript — Plan A: Andes virus protein immunogen & epitope informatics (draft)

> **Superseded for publication-style prose:** use **`MANUSCRIPT_PLAN_A_VACCINE_v1_0.md`** (manuscript v1.0). This file remains as a checklist-heavy working draft.

**Target venue:** bioRxiv (Computational biology / Immunoinformatics).  
**Framing:** In silico vaccine-relevant analysis on a defined antigen input, executed reproducibly via **BioMate** + **nf-core/epitopeprediction** on **AWS Batch**, with **explicit non-claims** regarding clinical immunogenicity.  
**Companion:** `PLAN_A_VACCINE_INSILICO_PUBLICATION_CHECKLIST.md`, `PLAN_A_POST_EPITOPE_HANDOFF.txt`, `runs/plan_a_epitope_a44876b7_s3_mirror/`, `MANUSCRIPT_DRAFT_ANDV_CAMPAIGN.md` (combined campaign).

**Status:** Draft **v0.2** — main narrative complete for resource framing; **§8** corpus / orthogonal grounding; **§9** extension programme aligned with `PLAN_A_VACCINE_INSILICO_PUBLICATION_CHECKLIST.md` §B–C.

---

## Title (working)

**In silico MHC–peptide epitope profiling for an Andes virus glycoprotein immunogen candidate using nf-core/epitopeprediction on a cloud Nextflow stack**

**Short title:** ANDV epitopeprediction via BioMate / AWS Batch

---

## Authors and affiliations

| Author | ORCID | Affiliation | Email |
|--------|-------|-------------|-------|
| [Name] | [0000-…] | [Dept, Institution] | [ ] |

**Corresponding author:** [ ]

---

## Keywords

Andes virus; hantavirus; epitope prediction; MHC; MHCnuggets; nf-core; Nextflow; immunoinformatics; AWS Batch; reproducibility

---

## Abstract (draft; tighten word count after figures)

Andes virus (ANDV) remains a priority for **vaccine-oriented structural and immunoinformatics** work. We report a **computational resource** describing execution of **nf-core/epitopeprediction** against a **defined protein antigen** (samplesheet-driven FASTA), orchestrated through **BioMate** with **Nextflow** on **AWS Batch** and **S3-backed** outputs. We provide **frozen execution metadata** (API `run_id`, terminal status, mirrored workflow bundle including **MultiQC**, **MHCnuggets** predictions, and **pipeline_info** execution reports). We do **not** claim **in vivo immunogenicity**, **correlates of protection**, or **population-level vaccine efficacy**. We outline **computational and corpus-based grounding** (literature epitopes, database overlap, allele-frequency context, optional orthogonal predictors) suitable for a **wet-laboratory-free** first deposit. This manuscript is intended as a **transparent methods and data-release** contribution for teams extending ANDV immunogen design under biosafety constraints.

---

## 1. Introduction

### 1.1 Disease and vaccine context

ANDV causes hantavirus cardiopulmonary syndrome in endemic regions. **Subunit or VLP-displayed** immunogens derived from viral surface glycoproteins are plausible design targets when high-quality structural models exist [insert PDB / structural references used in the campaign, e.g. 9P3I if that is the antigen scaffold].

### 1.2 Immunoinformatics gap

Epitope prediction workflows are standard, but **end-to-end reproducibility** (exact tool versions, allele lists, samplesheet provenance, and cloud execution logs) is often under-reported. **nf-core/epitopeprediction** improves standardization; pairing it with **manifested** Batch runs closes part of the audit gap.

### 1.3 Scope of this contribution

We document **one completed Batch run** and its **published artifacts**. This is **not** a clinical immunogenicity study. Claims are limited to: (i) **inputs** we supplied; (ii) **outputs** the workflow produced under recorded parameters; (iii) **interpretation** framed as **candidate peptides** pending orthogonal validation.

---

## 2. Methods

### 2.1 Antigen sequence and samplesheet

- **Samplesheet (frozen run):** `s3://biomate-nextflow-work/inputs/andv_campaign/plan_a_epitope_samplesheet/samplesheet.csv` (see `params_2026-05-14_03-09-35.json` in the mirror under `pipeline_info/`).  
- **Peptide column:** `sequence` (`peptide_col_name` in params).  
- **FASTA / protein identifier in outputs:** the mirrored bundle names the entity **`PLAN_A_SMOKE_GP`** in `predictions/PLAN_A_SMOKE_GP.tsv` and MHCnuggets CSV prefixes — treat as **internal demo label** until replaced by a publication-grade antigen accession (e.g. UniProt segment + strain metadata) in v0.3.  
- **Samplesheet format:** nf-core/epitopeprediction CSV on **S3**; **`filename`** column uses **`s3://`** URIs where required by the executor profile (`ANDV_CAMPAIGN_LESSONS_LEARNED.md`).  
- **Prediction tool:** **MHCnuggets** only for this run (`"tools": "mhcnuggets"` in params).  
- **Reference build:** **GRCh37** (`genome_reference`).  
- **Peptide length classes (class I):** **8–12** residues (`min_peptide_length_classI` / `max_peptide_length_classI`). Class II bounds are also set in params (8–25) for workflow defaults; **report which classes were actually emitted** from `mhcnuggets/` and `predictions/` for the deposited run.  
- **Alleles:** list verbatim from the samplesheet or from merged prediction headers in `PLAN_A_SMOKE_GP.tsv` / MHCnuggets CSVs (do not paraphrase HLA names).

### 2.2 Workflow and compute

- **Workflow:** `nfcore/epitopeprediction/main.nf` (record exact revision / `-r` tag from deployment).  
- **Orchestration:** BioMate `POST /api/nextflow/execute`; poll to terminal status.  
- **Executor:** AWS Batch; **profile** `docker` (document that **`aws` profile is inappropriate** for this pipeline on Batch per campaign lessons).  
- **Outputs bucket / prefix:** `s3://biomate-nextflow-work/nextflow/outputs/plan_a_epitope_continue/20260514T030919Z/` (matches `outdir` in `params_2026-05-14_03-09-35.json`).

### 2.3 Provenance and mirroring

- **Run ID (API):** `a44876b7-5514-4486-a2a6-d53adef623fd` (terminal **succeeded**; see `research/anti-virus/runs/PARALLEL_PLAN_A_AGENT_POLL_SUMMARY.txt`).  
- **Local mirror for reviewers:** `research/anti-virus/runs/plan_a_epitope_a44876b7_s3_mirror/` (see `PLAN_A_EPITOPE_HARVEST_AGENT_SUMMARY.txt`).  
- **Client interruption note:** an early client session logged HTTP 500 during polling; **terminal success** is taken from the **completed poll** and S3 mirror, reconciled in `PARALLEL_PLAN_A_CONTINUE_RESULT.txt`.

### 2.4 Statistics

Not applicable beyond descriptive summaries unless comparative re-runs are added (§8.3 and extension **E1** / **E2** in §9).

---

## 3. Results

### 3.1 Pipeline execution summary

**nf-core/epitopeprediction** completed on AWS Batch with terminal status **succeeded** for API run **`a44876b7-5514-4486-a2a6-d53adef623fd`** (poll log: `research/anti-virus/runs/PARALLEL_PLAN_A_AGENT_POLL_SUMMARY.txt`). Published outputs under **`s3://biomate-nextflow-work/nextflow/outputs/plan_a_epitope_continue/20260514T030919Z/`** were mirrored locally at **`research/anti-virus/runs/plan_a_epitope_a44876b7_s3_mirror/`** (`PLAN_A_EPITOPE_HARVEST_AGENT_SUMMARY.txt`). Claims in this section are limited to **successful workflow completion** and **artifact inventory** under the pinned `params_*.json`.

### 3.2 Pipeline QC (MultiQC)

The mirror includes **`multiqc/multiqc_report.html`** and **SVG panels** under `multiqc/multiqc_plots/svg/` (**peptide binding prediction stats**, **binding affinity distribution**, **binder rank distribution**, **binder length distribution**). **Authors should:** embed **Figure F2**; cite **software versions** from `multiqc/multiqc_data/multiqc_software_versions.txt` and `pipeline_info/nf_core_epitopeprediction_software_mqc_versions.yml`; describe distributions as **QC** only (not immunodominance).

### 3.3 Epitope calls (MHCnuggets + merged predictions)

| Path (relative to mirror root) | Role |
|-------------------------------|------|
| `predictions/PLAN_A_SMOKE_GP.tsv` | Merged peptide-level table (rename in prose when antigen ID is final). |
| `mhcnuggets/*_length_{8,9,10,11,12}_*_predicted_mhcnuggets.csv` | Per-length MHCnuggets outputs. |

**Authors should:** (i) assemble **Table T1** (top *N* by a **pre-declared** ranking rule stated in **Methods** when Table T1 is built — e.g. best affinity or consensus rank); (ii) report **row counts** per length / allele; (iii) state explicitly that scores are **binding/presentation proxies**, not **T cell readouts**.

### 3.4 Reproducibility bundle

Cite **`pipeline_info/execution_report_2026-05-14_03-09-22.html`**, **`execution_timeline_2026-05-14_03-09-22.html`**, **`pipeline_dag_2026-05-14_03-09-22.html`**, and **`params_2026-05-14_03-09-35.json`**. Optional **`co2footprint_*`** files → supplement if required.

---

## 4. Discussion

### 4.1 Interpretation limits

Epitope predictors prioritize **binding motif compatibility**, not **processing**, **TCR recognition**, or **in vivo immunodominance**. **Glycosylation**, **conformational masking**, and **VLP geometry** can reorder true epitopes relative to linear-protein predictions.

### 4.2 Relation to vaccine design

These results support **early triage** only. **MSA**, **consensus immunogen design**, and **structural display hypotheses** remain separate work items (`PLAN_A_VACCINE_INSILICO_PUBLICATION_CHECKLIST.md` §B).

### 4.3 Data and code availability

- Mirror path and manifest-style logs under `research/anti-virus/runs/`.  
- Zenodo snapshot recommended before journal transfer.

### 4.4 Conclusions

We deliver a **reproducible, cloud-executed** **nf-core/epitopeprediction** bundle for an ANDV-oriented **immunoinformatics** workflow with **frozen parameters**, **QC reporting**, and **MHCnuggets**-based peptide tables. The work **does not** establish vaccine efficacy or immunogenicity. **Extension packages** (§9) map directly to publication checklist items for **allele coverage**, **MSA/consensus immunogen**, **structural hypotheses**, **surface exposure**, and **corpus grounding**—all completable without wet lab for a **computational resource** preprint, provided language remains appropriately bounded.

---

## 5. Acknowledgments, CRediT, competing interests, ethics

**Ethics:** Not applicable (computational study).

---

## 6. Tables, figures, and supplementary layout

| ID | Description |
|----|-------------|
| **Table T1** | Top epitope candidates: sequence, length, allele, score(s), rank (from §3.3). |
| **Figure F1** | Workflow schematic: samplesheet → epitopeprediction → MultiQC + predictions (export Mermaid → SVG as in combined campaign). |
| **Figure F2** | MultiQC summary panels (binding affinity / length / rank distributions). |
| **Figure F3** | (Post–extension E2) sequence logo or conservation track along antigen. |

| Supplement | Contents |
|------------|----------|
| **S1** | Full `params_*.json` + samplesheet CSV (redact secrets if any). |
| **S2** | Full MHCnuggets CSV set + `PLAN_A_SMOKE_GP.tsv` as submitted. |
| **S3** | MultiQC data folder (`multiqc_data/`) for reproducibility. |
| **S4** | Long-form epitope table (all rows, all alleles). |
| **S5** | Corpus grounding tables (§8.1): IEDB/literature overlap for top-*k*. |
| **S6** | Optional second-predictor or MSA mapping (§8.3 / §9 E2). |

---

## 7. References (seed)

1. nf-core/epitopeprediction — cite version used.  
2. Nextflow; nf-core community papers.  
3. ANDV / hantavirus reviews and structure citations.  
4. MHCnuggets primary literature.

---

## 8. Experimental and corpus grounding (without wet lab)

**Purpose:** Strengthen a **computational** preprint without claiming new **in vitro** or **in vivo** data. Integrate outputs into **Supplement S5–S6** and Discussion before any language on “vaccine-ready epitopes.”

### 8.1 Literature and database overlap (highest priority)

- **IEDB / literature scan:** For **top-*k*** peptides from Table T1, annotate whether **substring / similar** motifs appear in published **T cell** or **B cell** epitope records for **hantaviruses** or **related bunyaviruses** (explicitly warn: **homology ≠ immunological cross-reactivity**).  
- **Positive controls:** Re-score **literature-documented** epitopes (same alleles where possible) with the **same** epitopeprediction configuration; report **rank calibration** (does the pipeline recover known binders in the top decile?).  
- **Deliverable:** Supplement **S5** as a single spreadsheet with columns: peptide, allele, our score, literature hit (Y/N), citation ID, notes.

### 8.2 Population / allele coverage (computational)

- **Preferred:** Re-run `run_plan_a_epitopeprediction_batch.py` with an **expanded allele column** in the samplesheet (`PLAN_A_POST_EPITOPE_HANDOFF.txt` §1); publish second `run_id` + mirror.  
- **Minimum:** If no re-run, add a **limitations paragraph + table** listing **exact alleles** from the samplesheet and a **static** population-frequency annotation (manual join to public allele frequency tables). **Do not** imply global coverage.

### 8.3 Orthogonal in silico comparators

- **Second predictor:** If licensing and containers allow, run **NetMHCpan** / **NetMHCIIpan** (when workflow supports) on the **same peptide set**; report **Spearman** rank correlation vs MHCnuggets per allele and flag **discordant** peptides (Discussion: model disagreement as uncertainty, not as biological truth).  
- **MSA → conservation:** Submit **`nextflow_nfcore/subworkflows/bioconductor/msa/main.nf`** via the same BioMate execute pattern as epitopeprediction (`PLAN_A_POST_EPITOPE_HANDOFF.txt` §2); map Table T1 peptides to **column entropy** or **consensus frequency** — **Figure F3**.

### 8.4 Structural context (optional)

- **Solvent exposure / disorder:** short Python/RDKit notebook on the **antigen PDB** segment windows (checklist §B4); supplement figure.  
- **VLP / oligomer geometry:** only with **frozen** heavy-model inputs (Boltz-2 / Chai-1 / structure_prediction_docking per checklist §A); otherwise one paragraph **Methods limitation**.

### 8.5 What this section does **not** replace

**ELISPOT**, **tetramer**, **HLA-matched APC assays**, **animal challenge**, **human correlate studies** — required for **efficacy** claims; list under **Future directions** without implying this preprint contains them.

---

## 9. Extension work programme (planned — checklist §B–C)

Each **package** has: **goal** → **primary artifact** → **entry command or path** → **acceptance criterion**.

| ID | Goal (publication claim) | Primary artifact | Entry point | Acceptance criterion |
|----|--------------------------|-------------------|-------------|------------------------|
| **E1** | Population / allele coverage | Supplementary allele × peptide coverage table | `run_plan_a_epitopeprediction_batch.py` + edited samplesheet (`PLAN_A_VACCINE_INSILICO_PUBLICATION_CHECKLIST.md` §E) | Second run **succeeded** **or** main text states **fixed panel** with frequency annotation |
| **E2** | Immunogen sequence design | Consensus/mosaic FASTA + MSA figure | `nextflow_nfcore/subworkflows/bioconductor/msa/main.nf` via API (`PLAN_A_POST_EPITOPE_HANDOFF.txt` §2) | MSA deposited; **Figure F3** shows conservation mapped to epitope ranks |
| **E3** | VLP / display geometry (hypothesis) | Oligomer model or explicit “not attempted” | Boltz/Chai / structure_prediction_docking (registry IDs in checklist §A) | **Either** deposited coordinates + methods **or** boxed limitation + external tool citation |
| **E4** | Solvent exposure / disorder | Per-residue CSV + figure | RDKit notebook or new thin workflow (checklist §B4) | Epitope windows ranked by exposure metric; cross-reference to Table T1 |
| **E5** | Peptide-level safety / immunotoxicity (optional) | Annotated table | `predict_admet_properties` on peptide SMILES with **off-label** disclaimer (`PLAN_A_POST_EPITOPE_HANDOFF.txt` §5) | Methods paragraph on **limits of small-molecule ADMET** for peptides |
| **E6** | Glycan-aware masking (stretch) | Updated structural inputs or gap statement | Checklist §C.3 | Document **manual** glycan masking **or** defer with **non-goal** clarity |

**Scheduling suggestion:** complete **E1 + S5 (§8.1)** before first bioRxiv deposit if any sentence in the Abstract mentions “population” or “vaccine design”; **E2** before implying “conserved immunogen”; **E3–E6** as revision waves.

---

## Internal versioning

| Version | Notes |
|---------|--------|
| v0.1 | Skeleton + early §8 roadmap. |
| v0.2 | §2–§4 tightened; §3 Results filled with mirror paths + author extraction instructions; §8–§9 extension matrix; S1–S6 layout. |
| v0.3 | Replace `PLAN_A_SMOKE_GP` label; fill Table T1 numerics; attach S5 corpus sheet. |
