# Appendix A — Glossary

Plain-language definitions of the terms used throughout this manual. One line each, written for
wet-lab scientists — no compute background assumed. Where a term is a BioMate-specific concept, the
chapter that covers it in full is noted in *(italics)*.

## Platform & conversation

- **BioMate** — a conversational execution engine: you describe a scientific goal in plain English and
  it picks the workflow, fills in parameters, runs it on real cloud compute, and interprets the result.
- **Lane** — how BioMate decides to run your request: **Instant** or **Cloud**. It restates the lane
  before running so you always know which one you are in. *(Overview §0.1)*
- **Instant lane** — an answer produced in the conversation in seconds (literature answers, quick
  lookups, small in-panel design). No cloud pipeline, not billed as compute.
- **Cloud lane** — a validated pipeline that runs on AWS Batch over minutes to hours (RNA-seq, variant
  calling, cryo-EM, ADMET). This is the "real run" that produces a report and files.
- **Router / intent router** — the step that reads your prompt and decides the lane, the domain, and
  which workflow to propose. It restates its guess; it does not silently pick.
- **Composer** — the message box where you type, attach data, add standing instructions, and pick
  skills & experts before sending. *(Module I.2)*
- **@-ref / dataset chip** — a reference to a live object (a dataset, a run) dropped into your message
  so BioMate acts on that exact thing. A dataset chip deep-links to the file's page.
- **Skill / expert** — an optional add-on persona or capability pack you attach to a message to steer
  how BioMate approaches the task. *(Module I.12)*

## Objects (everything is a referenceable thing)

- **Object model** — the idea that everything in BioMate — dataset, run, step, output, report, model,
  plan — is a live object that opens the same way everywhere. *(Overview §0.2)*
- **Dataset object** — an uploaded or fetched file as a first-class object: name, type, size, quality,
  versions, lineage, and which runs consumed it. *(Module I.5)*
- **Run** — one execution of a workflow: its inputs, steps, live status, outputs, QC results, and
  report. A run belongs to the chat session that launched it. *(Module I.6)*
- **Step** — one stage inside a run (e.g. alignment, quantification). A step is itself an object: you
  can open it to see the exact parameters it ran with and its outputs. *(Module I.7)*
- **Workflow** — an indexed, validated pipeline (e.g. `nf-core/rnaseq`) BioMate can run for you.
- **Workflow chain** — several workflows wired end to end, where one step's output feeds the next
  (e.g. rnaseq → differential abundance → enrichment). *(Data II.1)*
- **Workflow catalog** — the searchable library of indexed workflows and chains BioMate routes into.
- **Model object** — a trained model (a foundation model, scorer, or your fine-tune) you can reuse by
  reference across runs. *(Module I.10)*
- **Plan / hypothesis** — a saved research plan attached to a project, separate from free-text notes.

## Data quality & perception

- **Perception / quality profiling** — BioMate's automatic read of an uploaded file to judge whether it
  is usable before you run anything (e.g. FASTQ read quality). *(Module I.5)*
- **Quality pill / quality dot** — the Good / Watch / Blocked (green / amber / red) badge on a dataset,
  computed by the backend, not self-declared. Grey means "not profilable."
- **Version (dataset)** — an append-only snapshot of a dataset; new uploads add versions rather than
  overwrite, so lineage is preserved.
- **Lineage** — the recorded trail of where a file came from and what it was derived from.
- **Consumers** — the runs that used a given dataset as input.

## Running, QC, and remediation

- **Pre-run restate** — the panel BioMate shows before executing: the workflow name, the inputs it
  mapped, the parameters, and the QC gates — your chance to confirm or adjust. *(Module I.6)*
- **QC gate** — an automatic quality check applied during a run, with a cited threshold; it returns a
  verdict of PASS, ADVISORY, or HALT. *(Appendix C)*
- **HALT** — a gate verdict that stops the run at that point (and, for ADMET, triggers remediation)
  because a hard quality/safety threshold was crossed.
- **ADVISORY** — a gate verdict that flags a concern in the report but lets the run continue.
- **PASS** — a gate verdict meaning the metric met its threshold.
- **Auto-loop / auto-remediation** — BioMate automatically re-tuning screening thresholds and re-running
  after a HALT (currently ADMET only); it tightens the library filter, it does **not** invent new
  molecules. Up to two retries, then it escalates to you. *(Domain: Drug discovery → IND)*
- **QC profile** — a named preset that changes which thresholds apply (e.g. `admet_standard` vs
  `admet_cns` vs `admet_oncology`), so the same compound can pass or fail depending on the program.

## Applicability & confidence

- **out_of_domain / applicability domain** — a flag meaning "the model has not seen chemistry (or data)
  like this before," not "this is a bad result." The item is still ranked and kept, just flagged.
  *(Appendix D; Domain: Drug discovery → IND)*
- **Tanimoto similarity** — a 0–1 measure of how chemically similar two molecules are; a value below
  0.20 to the training set is one trigger for the out_of_domain flag.
- **Leverage** — a statistical distance-from-training-data measure used alongside Tanimoto to decide the
  applicability-domain flag.

## Outputs, viewers & interpretation

- **Output** — a file a run produced (a table, a figure, a structure, a map, a VCF). Outputs render in
  in-app viewers by their evidence type. *(Module I.8; Appendix B)*
- **Viewer** — the in-app renderer chosen for an output type (image, table, structure, density,
  sequence, VCF, single-cell, HTML, text). *(Appendix B)*
- **Findings** — BioMate's plain-language interpretation of a completed run: the headline numbers and
  what they mean, with each number linking back to the output it came from. *(Module I.9)*
- **Interactive tool** — a full session (RStudio, Jupyter, CellxGene) you can launch for hands-on
  re-analysis. Offered only where actually provisioned; it opens empty (does not auto-load your data).
  *(Appendix D)*

## Reports & reproducibility

- **Report / methods report** — the after-run write-up (Results / Reproducibility). It is a
  versioned, editable object, not a throwaway. *(Module I.9)*
- **Reproducibility record** — the machine-readable record of a run: exact parameters, input bindings,
  outputs with sizes and SHA-256 checksums, plus software and citations. *(Module I.9)*
- **Checksum (SHA-256)** — a fingerprint of an output file proving it is exactly the file the run made.
  In the UI it may show "—" until you press **Compute checksums**. *(Appendix D)*
- **Run original / immutable version** — the first, locked version of a report/record (v0); your edits
  create new versions without altering the original.
- **Audit trail (21 CFR 11)** — a tamper-evident, hash-chained log of who did what and when, used for
  regulatory (IND/CRO) work. *(Domain: Drug discovery → IND; CRO / regulatory)*

## Domain terms used in the book

- **DEG / differential expression** — genes whose expression changes between conditions (e.g. treated
  vs control); the core RNA-seq result. *(Domain: Transcriptomics)*
- **Count matrix** — a genes-by-samples table of read counts; the direct entry point for differential
  expression without re-aligning raw reads.
- **Pseudobulk** — summing single-cell counts per sample/cell-type into bulk-like profiles so
  cross-condition differential expression can be done correctly on single-cell data.
  *(Domain: Single-cell)*
- **GSEA / enrichment** — testing whether a gene list is enriched for known pathways (GO / KEGG /
  Reactome). *(Domain: Transcriptomics)*
- **Germline variant** — an inherited DNA variant present in all cells; the default variant-calling
  path. *(Domain: Variant calling)*
- **Somatic variant** — a variant acquired in a tissue (e.g. a tumour), called tumour-vs-normal; a
  distinct path you must ask for by keyword. *(Appendix D, Appendix E)*
- **VCF** — the standard file of called variants; rendered as a variant table in-app.
- **pLDDT** — AlphaFold's per-residue confidence score (0–100); higher means the model is more sure of
  that residue's position. *(Module I.8; Appendix C)*
- **PAE** — Predicted Aligned Error; AlphaFold's confidence in the relative position of two parts of a
  structure (lower is better). *(Appendix C)*
- **FSC (0.143)** — Fourier Shell Correlation at the 0.143 cutoff: the gold-standard way to state a
  cryo-EM map's resolution in ångström. *(Domain: Cryo-EM; Appendix C)*
- **GSFSC** — "gold-standard" FSC computed from two independently refined half-maps; a common way FSC
  resolution is reported.
- **CTF** — Contrast Transfer Function; its fit quality is a cryo-EM image-quality gate. *(Appendix C)*
- **ADMET** — Absorption, Distribution, Metabolism, Excretion, Toxicity — the drug-likeness/safety
  property panel (includes hERG, DILI, Ames, CYPs). *(Domain: Drug discovery → IND)*
- **hERG** — a cardiac ion channel; strong hERG binding signals arrhythmia risk (a HALT gate).
- **DILI** — Drug-Induced Liver Injury risk.
- **Ames** — a bacterial mutagenicity (genotoxicity) prediction.
- **Ro5 (Rule of Five)** — Lipinski's oral-druglikeness heuristic (MW, logP, H-bond donors/acceptors);
  advisory only, never a HALT.
- **PBPK** — Physiologically-Based PharmacoKinetic modelling: simulating drug concentration over time
  across body compartments. *(Domain: Drug discovery → IND)*
- **IND §2.6** — the nonclinical (pharmacology/PK/tox) section of a US FDA Investigational New Drug
  application that BioMate can assemble. *(Domain: Drug discovery → IND)*

## Projects, access & billing

- **Project** — the container for your work: datasets, runs, standing instructions, notes, and plans;
  user-owned and access-controlled. *(Module I.4)*
- **Standing instructions** — persistent guidance the assistant reads on every request in a project
  (the research goal). *(Module I.4)*
- **Notes** — human-only text in a project that the assistant never reads (a trust boundary).
  *(Module I.4, Data II.5)*
- **Roles** — owner / editor / viewer; collaboration is a paid-tier feature.
- **Memory** — project-scoped knowledge plus session summaries the assistant can recall; it does **not**
  read your private Notes. *(Data II.5)*
- **Quota / two-lane cost** — Instant is light/free-flowing; Cloud runs consume metered compute against
  your plan's quota. *(Module I.13)*
- **Accession** — a public-archive identifier (GEO, SRA, PDB, EMPIAR, PRIDE…) BioMate can resolve to a
  fetch workflow. *(Data II.2; note the resolvable-vs-validation-only distinction in Appendix E)*

---
*Cross-references point to the module/domain chapters that define each term in depth. For the honest
list of terms describing features that are not yet built, see Appendix E.*
