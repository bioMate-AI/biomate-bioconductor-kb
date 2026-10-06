# Accession → dataset → workflow — narration (EN)

One narration block per scene, in order, for edge-tts. Episode M3. Grounded in BioMate's live resolve_accession + context-aware routing (captured 2026-10-05) and the capability inventory in docs/20261005_ACCESSION_TO_WORKFLOW_CAPABILITY.md.

---

## Step 1 — Title · from an accession number to a running pipeline

A paper cites a dataset — a GEO series like GSE52778, or an SRA run like SRR1039508. Normally that number is the start of a day's work: find the data, figure out what kind of data it is, choose the right pipeline, and wire up all the parameters. BioMate does that from the ID itself. You paste the accession, you say what you want to learn, and it fetches the data and routes it to the correct, correctly-parameterized workflow. In this walkthrough we'll follow real accessions the whole way through, and you'll see the actual decisions the system makes.

---

## Step 2 — The problem this solves

Reusing public data looks easy, and it rarely is. The same kind of identifier can point to a microarray study, a bulk RNA-seq experiment, or a single-cell dataset — and each one needs a completely different analysis. So before you can start, you have four manual steps: find which archive holds it, identify what modality the data is, pick the workflow that fits, and fill in the parameters correctly. Get the archive, the modality, the workflow, or a single parameter wrong, and you've either wasted a run or, worse, quietly produced the wrong answer. What you actually want is to turn the ID straight into the correct run, without the archaeology.

---

## Step 3 — The ideas you need first

Four plain words describe the whole journey. First, the accession: the stable identifier in the paper — a GEO series, or an SRA run or project. That's your starting point. Second, the archive: the repository that holds it — GEO for curated series, SRA, ENA and DDBJ for raw sequencing reads — and each needs its own way of fetching. Third, the modality: whether the data is microarray, bulk RNA-seq, or single-cell, because the modality decides which analysis is even valid. And fourth, routing: matching that modality and your goal to the right pipeline, with its parameters filled in. The whole trick is turning ID, archive, modality, routing from four careful manual steps into one paste-and-confirm.

---

## Step 4 — Stage one · the ID becomes a fetcher

The first stage is fast and deterministic. BioMate reads the shape of the accession — a GSE is GEO, an SRR or SRP is a sequencing archive — and hands back the matching fetch workflow with the ID already filled in, ready to run. There's no network guesswork and no wrong tool. GEO series route to the GEO data connector; raw-read archives route to fetchngs, which pulls the FASTQ files and a sample sheet. You've gone from a bare number to a prepared download in one step.

---

## Step 5 — Stage one, live · what resolve returns

This is the real output. Every GEO identifier — GSE, GSM, GDS — resolves to the GEO connector. Every sequencing identifier — the SRA, ENA, and DDBJ runs and projects — resolves to fetchngs, which fetches the raw reads and their metadata. In each case the accession is placed into the correct parameter, so the next step is a single confirmation. And if an identifier isn't recognized, it's rejected honestly, rather than quietly mishandled. This is deterministic identification by the type of the ID — exact, and free.

---

## Step 6 — Stage two · it reads the study

Here's where the intelligence begins. The identifier alone doesn't tell you whether a GEO series is a microarray or RNA-seq — but the study's own record does. BioMate reads GEO's metadata directly and infers the modality from the authoritative series type and the design description, so the analysis fits the data instead of a guess. It distinguishes microarray from bulk RNA-seq from single-cell. And it's careful: it won't assume single-cell without explicit single-cell signals, and an unclear study is handed back to you rather than mis-routed. The data decides the method — not the filename.

---

## Step 7 — Stage two, live · same ID, your goal picks the pipeline

This is the whole capability in one view. Take the same family of GEO data and ask three different questions. Ask for microarray differential expression, and BioMate routes to the Affymetrix differential-expression workflow and sets the study type to "affy" for you. Ask for bulk RNA-seq differential expression, and it routes to a full chain — alignment, then DESeq2, then enrichment — and sets the genome to GRCh38. Ask for pathway enrichment, and it routes to gene-set enrichment with fgsea and clusterProfiler, and fills in the species and the organism code. One identifier, three intents, three correctly-parameterized pipelines — and every workflow and every filled parameter you see is the real system's own output.

---

## Step 8 — Fetch, then run

Once the workflow is chosen, BioMate retrieves the data and runs the pipeline. GEO series come through the connector; raw-read studies are fetched as FASTQ and flow into the sequencing pipeline. You confirm once, and the work runs on cloud compute while you carry on. And this accession-awareness isn't only for sequencing: when a workflow needs them, BioMate also pulls structures from the PDB and EMDB, protein and reference sequences from UniProt and Ensembl, and chemical identifiers from ChEMBL and PubChem — fetched automatically, by their IDs.

---

## Step 9 — The honest edges

The intelligence is real, and it is specific — and knowing the edges is what makes it trustworthy for work you'll publish. A GEO RNA-seq series carries no count table in its record, so counts come from fetching the raw reads, or from a matrix you provide — never invented. Modality inference reads GEO's record, so raw-read archives go straight to fetching the reads, without that inference. The system is strongest on GEO and on sequencing archives; some other archives and file types are fetched on demand, and others are on the roadmap. This is a specific, honest capability — not a black box that pretends to do everything.

---

## Step 10 — The value at a glance

The whole point is one sentence: an accession number should become a correct, running analysis, without a day of setup. You paste the identifier, you say what you want to learn, you confirm the routed workflow and its pre-filled parameters, and BioMate fetches the data and runs it in the cloud — leaving you a reproducible record. It recognizes the archive, reads what the data is, routes your question to the right pipeline, and fills in the parameters. From a published accession to a running, parameterized, reproducible analysis — the manual archaeology, done for you. Public data, reused correctly.
