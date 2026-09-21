---
marp: true
theme: default
paginate: true
title: BioMate for Hospital Research Core Facilities
---

<!-- Audience: hospital shared research core-facility leadership + PI/grad-student users (公共科研服务平台).
     External customer deck — states WHAT we deliver, not our internal tool stack. Name the science, not the infra.
     Honest ready-vs-roadmap. Render: `marp 20260920_HOSPITAL_BD_DECK_EN.md -o hospital_deck.pptx` (or --pdf).
     Coverage abstracted from docs/20260920_HOSPITAL_INSTRUMENT_RESOURCE_INVENTORY.md (live-tested). -->

# BioMate
### Turn every instrument's data into publication-ready results — by chat, no coding

**For hospital shared research core facilities**
*BD discussion deck · September 2026*

---

## The gap a new core facility hits on day one

You've built a world-class instrument platform — sequencer, mass spec, flow cytometer, qPCR, plate reader, slide scanner, confocal.

**The instruments generate the data. But who analyzes it?**

- The users are **graduate students and clinicians**, not bioinformaticians.
- Each instrument's output needs different, specialized analysis software and skills.
- Today that means: wait for a core bioinformatician, learn to code, or outsource — slow, expensive, and a single point of failure.

> The bottleneck isn't generating data anymore. It's **turning data into results.**

---

## What BioMate is

**An analysis engine your researchers talk to in plain language.**

A grad student uploads their instrument output, describes their goal ("differential expression between treated and control," "call variants from this WGS," "immunophenotype these flow samples"), and BioMate runs the full, correct analysis and returns a results report — **no software to install, no code to write, no HPC to manage.**

- Covers the **full workflow** the facility declared: molecular biology & genomics · proteomics & metabolomics · cell biology · histopathology.
- Every result comes with a **reproducible, auditable record** — ready for publication methods and review.
- Available in **English and Chinese**.

---

## How a researcher uses it — three steps

1. **Bring data.** Upload the instrument's output file (or point to a public dataset / accession).
2. **Describe the goal in plain language.** BioMate selects the right analysis, fills in the correct parameters, and shows you before it runs.
3. **Get results.** Live progress, quality-control checks that catch bad runs automatically, and a downloadable report with figures, tables, and a methods write-up.

**No pipeline coding. No cluster. No format wrangling.** The scientist stays focused on the science.

---

## Coverage against *your* facility's instruments

| Instrument | Analysis delivered | Status |
|---|---|---|
| **Sequencer** (RNA / DNA / WGS) | RNA-seq differential expression · variant calling · alignment/QC | ✅ Ready today |
| **Mass spectrometer** (proteomics / metabolomics) | protein quantification · metabolite profiling & pathway analysis | ✅ Ready today |
| **Flow cytometer** (.fcs) | immunophenotyping · population QC · differential abundance | 🟢 Available |
| **qPCR** (Ct → ΔΔCt) | normalized relative quantification | 🟢 Available |
| **Plate reader** (ELISA / CCK-8 / dose-response) | plate QC, hit-calling, dose-response / IC50 curve fitting | 🟢 Available |
| **Sample QC** (RIN / NanoDrop / cell counter) | integrity, purity & viability QC reports | 🟢 Newly added |
| **Confocal / fluorescence** | cell & nucleus segmentation, image quantification | 🔧 Enhancing |
| **Digital slide scanner** (whole-slide pathology) | tissue QC · IHC scoring · tumor-content estimation | 🗺️ On roadmap* |

<small>*Pathology needs vendor-format handling for Chinese scanners (.kfb/.sdpc) plus AI tissue models — a deliberate near-term build, see next slide.</small>

---

## Honest today vs. roadmap

**Ready now (proven end-to-end):** sequencing (RNA-seq, variant calling), mass-spec proteomics & metabolomics — the highest-volume lanes in a core facility.

**Available, being hardened:** flow cytometry, qPCR, plate-reader assays, sample QC — real analyses in place; we validate each on your data during the pilot.

**On the roadmap (the one honest gap):** routine **digital pathology** — reading your specific slide-scanner format and adding AI tissue models. We'd prioritize this build directly with your pathology team.

> We tell you exactly what is production-ready and what we'd build with you — no overselling.

---

## Why it fits a hospital core facility

- **Self-service for non-experts.** Grad students get results without a bioinformatician in the loop — removes your single point of failure.
- **Reproducible & auditable.** Every run is recorded end-to-end — the provenance reviewers and journals ask for.
- **Automatic quality control.** Built-in gates flag failed or low-quality runs before they reach a manuscript.
- **No IT burden.** Nothing to install or maintain on facility machines; compute scales on demand.
- **Bilingual.** Full Chinese-language interface for your users.

---

## Data security & deployment — your data, your rules

Hospitals handle sensitive patient-derived data. BioMate supports:

- **Cloud (managed):** fastest to start; isolated per-institution workspaces.
- **On-premises / private deployment:** BioMate runs **inside the hospital network** — patient data never leaves.
- **The AI itself can stay on-prem — not just the data.** The AI assistant can run on a **local, on-premises model**, and the language model is **fully configurable**: run a self-hosted model entirely inside your network (no external API calls), or connect a provider of your choice. Both the data *and* the AI reasoning stay on your infrastructure.
- **Access control & audit logs** aligned to institutional data-governance requirements.

> The deployment model is a decision we make **with** your IT and ethics governance — not a fixed constraint.

---

## Proof of depth

- **Thousands of validated analysis workflows across dozens of biological domains** — genomics, transcriptomics, proteomics, metabolomics, single-cell, imaging, drug discovery, and more.
- **Verification-first:** analyses are checked against known-good results, not just "it ran."
- Spans the whole facility scope — from nucleic acids and proteins through cells and tissue — in **one interface**.

*(Full instrument-by-instrument capability map available for your technical team.)*

---

## Fit to your four declared platform scopes

| Facility scope (declared) | BioMate delivers |
|---|---|
| **Molecular biology & genomics** | sequencing analysis, variant calling, qPCR quantification |
| **Proteomics & metabolomics** | MS protein/metabolite quantification & pathway analysis |
| **Cell biology** | flow-cytometry immunophenotyping, imaging segmentation, viability QC |
| **Histopathology** | tissue QC & IHC scoring (co-developed near-term) |

One platform covers the facility's full declared remit.

---

## Proposed pilot — prove it on your data

**A focused 4–6 week pilot on one high-volume lane** (we suggest RNA-seq or mass-spec proteomics):

1. Your team brings a **real dataset** from the facility.
2. We run it end-to-end in BioMate — results, QC, methods report.
3. A facility scientist reproduces it self-service.
4. Joint review: accuracy, usability, and the roadmap for the rest of your instruments.

**Low commitment, concrete outcome:** a real result on your real data, plus a costed plan for full-facility rollout.

---

## To scope the pilot, we need four answers

These determine effort more than anything on our side:

1. **Mass spectrometer model** (Orbitrap / timsTOF class vs. triple-quad) — decides which proteomics/metabolomics analyses apply.
2. **Sequencer model** (Illumina / MGI / Sanger / Nanopore) — decides the sequencing pipelines.
3. **Slide-scanner vendor** (output format) — decides pathology-imaging effort.
4. **Data-governance terms** — can data go to managed cloud, or is on-prem required?

---

## Summary

- Your facility solved data **generation**. BioMate solves data **analysis** — by chat, no coding.
- **One platform** covers the full instrument set your researchers use.
- **Ready today** for your highest-volume lanes; **honest roadmap** for pathology imaging.
- **On-prem option** keeps patient data — *and the AI itself* — inside the hospital, with a configurable local or provider LLM.
- **Next step:** a 4–6 week pilot on one real dataset.

**Let's turn your instruments into results.**

*Contact: BioMate BD team*
