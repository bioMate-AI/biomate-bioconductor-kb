# Appendix D — Troubleshooting & Common Routing Pitfalls

The most common confusions when using BioMate, and how to resolve each. These are compiled from the
domain and module chapters; each entry says what you see, why it happens, and what to do. None of these
are bugs — they are the system behaving correctly in ways that can surprise a first-time user.

---

## Routing pitfalls (getting the right workflow)

### 1. Bulk RNA-seq vs single-cell — say which one

**Symptom:** you asked for "differential expression" and got the bulk pipeline when you have single-cell
data (or vice versa).

**Why:** bulk and single-cell share vocabulary ("expression", "clusters", "markers") but are completely
different assays. BioMate has a routing guard that **refuses** to send a single-cell prompt to the bulk
chain unless single-cell context terms are present (`unified_workflow_search.py`).

**Fix:** name the assay explicitly — "**single-cell** RNA-seq" / "scRNA-seq" / "10x" for single-cell;
"**bulk** RNA-seq" or "count matrix, treated vs control" for bulk. For cross-condition differential
expression on single-cell data, ask for **pseudobulk** — that is the correct path, not per-cell DE.
*(Domains: Transcriptomics, Single-cell.)*

### 2. Germline vs somatic variants — add the keyword

**Symptom:** you wanted tumour mutations but got the standard (germline) variant pipeline.

**Why:** **germline** (inherited, all-cells) is the default path with a full gold chain. **Somatic**
(tumour-vs-normal, e.g. Mutect2) is a distinct path.

**Fix:** say "**somatic**" and "tumour/normal" explicitly. Note the honesty caveat: somatic
tumour-normal calling has **no** documented end-to-end chain or gold demo yet — the individual workflows
exist and route, but there is no validated chain. See Appendix E before relying on it.
*(Domain: Variant calling.)*

### 3. FASTQ alone routes to alignment, not the DE chain

**Symptom:** you uploaded raw FASTQ and expected differential-expression results directly.

**Why:** FASTQ-alone correctly routes to `nf-core/rnaseq` (align + quantify), not the full DE chain —
DE needs a design (which samples are treated vs control).

**Fix:** provide a sample sheet / condition labels, or start from a **count matrix** (the freemium fast
lane) which enters `differentialabundance` directly. *(Domain: Transcriptomics.)*

### 4. Microarray / continuous intensities ≠ count model

**Symptom:** DESeq2/edgeR seem wrong for array data.

**Why:** DESeq2/edgeR model integer counts. Microarray/continuous data belong to **limma**.

**Fix:** say the data are microarray/intensity so routing picks limma. *(Domain: Transcriptomics.)*

---

## Interpreting flags & verdicts

### 5. `out_of_domain` / applicability = "not seen this chemistry," not "bad"

**Symptom:** a compound is flagged `out_of_domain` and you assume it failed.

**Why:** the applicability-domain flag means the model has **not seen chemistry like this** (Tanimoto <
0.20 to training set, high leverage) — it is a **confidence** flag, not a verdict on the molecule. The
compound is still ranked, kept, and reported (flagged in IND §2.6.1.5).

**Fix:** read it as "predictions here are lower-confidence; confirm with an assay," not as a rejection.
*(Domain: Drug discovery → IND; Appendix A.)*

### 6. A HALT does not mean "your data is broken"

**Symptom:** a run HALTed on a QC gate and you think it errored.

**Why:** HALT is a deliberate quality/safety stop. For **ADMET**, HALT triggers auto-loop remediation
(the library filter tightens; a flagged compound drops out — no analogue is invented). For **RNA-seq /
variants / cryo-EM**, a fail is surfaced for a manual fix (metadata, reference, re-sequence) — there is
no auto-loop outside ADMET.

**Fix:** read the two-number gate (measured vs threshold), check the tier (Appendix C), and either
adjust the QC profile or fix the input, then re-run. *(Appendix C.)*

---

## Runs, outputs & reports

### 7. Long runs — you can detach

**Symptom:** a Cloud-lane run (RNA-seq, cryo-EM, WGS) takes many minutes to hours and you don't want to
sit on the page.

**Why:** Cloud runs execute on AWS Batch independently of your browser session; the run belongs to its
chat session and keeps going.

**Fix:** leave the panel — the run continues; return to the session to see live SSE status and the
after-run report. *(Module I.6.)*

### 8. Checksums show "—"

**Symptom:** the Reproducibility record shows "—" in the SHA-256 column.

**Why:** checksums are opt-in (`?checksums=1`); the default record fetch omits them to stay fast, so the
column reads "—" until computed.

**Fix:** press **Compute checksums** in the Reproducibility tab; they are then computed on demand
(bounded to ≤ 25 files / ≤ 25 MB). *(Module I.9.)*

### 9. Interactive tools (RStudio / Jupyter / CellxGene) aren't there

**Symptom:** you expected a "Launch RStudio" button and don't see one.

**Why:** interactive tools are **honesty-gated** — the buttons appear only where the tool is actually
provisioned. On dev they are **not** provisioned (`/api/interactive/available` → `available:false`), so
every launch affordance is hidden rather than showing a button that 400s.

**Fix:** if you need hands-on re-analysis and the buttons are hidden, the environment isn't provisioned
for it — see Appendix E. When available, note they open an **empty** session (they do **not** auto-load
your run's data). *(Module I.8; Appendix E.)*

### 10. A saved literature answer is a note, not a versioned document

**Symptom:** you "saved to project" from a literature answer and later can't find it in Files.

**Why:** "Save to project" stores a **knowledge note**, not a versioned Files document. (Formatted
APA/BibTeX is currently populated only for workflow-tool citations, not literature answers.)

**Fix:** treat saved answers as project knowledge; if you need a versioned document, use the after-run
methods report (which *is* a versioned object). *(Module I.3, I.9; Appendix E.)*

---

## Data & privacy

### 11. The assistant reads Instructions, never Notes

**Symptom:** you put context in **Notes** and the assistant didn't use it.

**Why:** by design, **standing instructions** (research goal) are injected into every request; **Notes**
are human-only and never read by the assistant (a trust boundary, enforced end to end).

**Fix:** put anything you want the assistant to act on in **Instructions** (or "Promote ↑" a note to
instructions). *(Module I.4; Data II.5.)*

### 12. Public accession won't fetch (PDB / EMDB / PRIDE / etc.)

**Symptom:** a PDB/EMDB/PRIDE/UniProt accession is recognized but doesn't fetch data.

**Why:** those accessions are **detected for validation only**, not resolvable to an auto-fetch (they
return 422). Only GEO / SRA / ENA / DDBJ / BioProject / ArrayExpress currently resolve to a fetch
workflow.

**Fix:** for non-resolvable archives, import the file via **From-URL** or upload directly. See Appendix E.
*(Data II.2; Appendix B.)*

---
*If a behavior you expect is missing entirely (not just misrouted), check Appendix E — it is the honest
list of what is not yet built. This appendix covers correct-but-surprising behavior only.*
