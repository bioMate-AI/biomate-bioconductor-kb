## Step 1 — Welcome to BioMate

BioMate is a conversational bioinformatics platform. Describe your experiment in plain English — BioMate picks the right validated pipeline, fills in the parameters, runs on cloud infrastructure, and returns publication-ready results. No code, no configuration.

---

## Step 2 — Ask in plain English

Type your experiment the way you'd explain it to a colleague: "Run cryo-EM single-particle analysis on my MRC movies — pixel size 1.06 ångströms, 300 kV." BioMate understands domain vocabulary. You never need to know the pipeline name or parameter flags.

---

## Step 3 — BioMate proposes a workflow

A workflow card appears directly in the chat — pipeline name, domain, and a one-line description. If BioMate isn't certain which pipeline you meant, it shows ranked candidates and lets you choose. Nothing runs until you confirm.

---

## Step 4 — The Workflow Panel opens

Clicking the card opens the Workflow Panel on the right. At the top: pipeline name, scientific domain, and a live status badge. The panel stays open alongside the chat so you can run, explore outputs, and keep the conversation going at the same time.

---

## Step 5 — Parameters are pre-filled

BioMate extracts values from your message — pixel size, voltage, file paths — and maps them to the right parameters automatically. Every parameter has an Edit button if you want to override a value before the run starts.

---

## Step 6 — Confirm & Run — one button

When the parameters look right, click Confirm and run workflow. The job submits to AWS Batch — GPU or CPU instances, automatically right-sized for your pipeline. The footer always shows exactly one primary action. No wall of options.

---

## Step 7 — Live progress in real time

The status badge flips to running. Inside each phase, individual steps show their status — queued, running, completed — updated live via a streaming connection to AWS Batch. You see exactly which step is executing without opening a single log file.

---

## Step 8 — QC gates catch problems automatically

BioMate monitors outputs as they arrive. When a quality metric falls below threshold — CTF resolution, particle yield, alignment score — it pauses the run and flags the gate. The auto-loop proposes a parameter fix and reruns automatically.

---

## Step 9 — Run completes

The status badge flips to completed and the progress bar fills green. Your dataset has traveled from raw input through every validated step to a final result — without a single manual intervention from you.

---

## Step 10 — AI Findings — the executive summary

Below the phase list, the AI Findings card gives a specific assessment of this run on this dataset. Resolution, particle yield, quality warnings — all sourced from the actual output files, not generic documentation. Every claim is cited.

---

## Step 11 — Methods Report — publication-ready

One click generates a complete IMRaD-format methods section: the software used, parameters applied, dataset size, and validation statistics — with citations for every tool. Export as DOCX, Markdown, or LaTeX and paste directly into a manuscript.

---

## Step 12 — You're ready to go deeper

That's the core BioMate loop: ask, review, run, results. The same workflow works for RNA-seq, ADMET profiling, variant calling, PBPK modeling, and more — 2,000 validated workflows across 34 biological domains. Start with a question.

---
