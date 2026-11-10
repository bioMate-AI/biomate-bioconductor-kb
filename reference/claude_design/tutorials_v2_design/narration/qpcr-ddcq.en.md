# qPCR ΔΔCq quantification — narration (EN)

## Step 1 — Title · from Cq values to fold-change

Your qPCR machine reports a Cq value for every well — the cycle number at which the signal crosses the threshold. On its own, that table is not yet an answer. BioMate takes it and runs the standard delta-delta-Cq relative-quantification analysis for you. It normalises to your reference genes, compares treated against control, and returns the fold-change for each target gene. It runs on cloud compute and keeps a defensible record of how every number was produced. One request turns raw cycle numbers into relative expression.

---

## Step 2 — The problem

A Cq of twenty-four for your gene means nothing by itself. It depends on how much sample went into the well, on pipetting, and on reaction efficiency. To say whether a gene went up or down, the numbers must be normalised and compared. Doing that by hand in a spreadsheet is fiddly. Every sample needs its target Cq minus its reference Cq, then a control average, then a power of two. One mis-copied formula or mislabelled control quietly shifts every fold-change after it, and the sheet rarely shows which genes and which control group produced a number. The method is standard. The goal is to apply it consistently, every time.

---

## Step 3 — The ideas you need first

Four ideas make a fold-change readable. First, the Cq value: the raw cycle number, where a lower Cq means more starting material. Second, reference genes — genes that should not change between your conditions, such as GAPDH or ACTB. Subtracting them cancels out how much sample was loaded. Third, delta-delta-Cq: each sample's normalised value minus the control group's average, so zero means the same as control. Fourth, fold-change: two to the power of minus delta-delta-Cq. Two point zero is twice the control, and zero point five is half. About one cycle is a two-fold change. The comparison is always treated versus control.

---

## Step 4 — Step 1 · what you provide

You provide three things, and you already know all of them. First, a Cq table: your exported values, one row per well, with the sample, the target gene, and the Cq. Any machine's CSV or text export works. Second, which genes are the references: the gene or genes you designed primers for, listed by name, for example GAPDH and ACTB. Third, the groups: the label that marks your control samples, so every treated sample can be compared against them. There is nothing else to configure. Biological replicates make the result stronger, ideally three or more per group.

---

## Step 5 — Step 2 · how a run works

You describe the analysis the way you would to a colleague. For example: relative expression on this Cq table, treated versus control, reference genes GAPDH and ACTB. BioMate selects the standard delta-delta-Cq method, built on the published Bioconductor NormqPCR package, and opens it with your settings filled in. You review the reference genes, the control label, and the attached table before anything runs. Then you press Confirm and Run. Because this is a small-table calculation, it finishes quickly, on cloud compute, with no software for you to install.

---

## Step 6 — Step 3 · the results

Here are the results. The run returns the delta-delta-Cq table: one row for each target gene, normalised to your reference genes, with its fold-change for treated compared with control. A value above one means the gene is higher in treated. Below one means lower, and close to one means unchanged. The tables are also available as files to download, ready for your figures or your supplement.

---

## Step 7 — Step 4 · reading and trusting it

The calculation is the published delta-delta-Cq method, applied the same way on every run. What makes it defensible is what you can show alongside it. Check that your reference gene looks flat across conditions; if it swings widely, the normalisation is shaky. Replicates matter: a large fold-change from a single well is a hint, while three or more replicates per group make it a result. The reference genes, the control label, the software version, and checksums for the outputs are kept together as a reproducibility record. And as good practice, on your own data, compare your first run against a value you calculate by hand.

---

## Step 8 — Closing · the habit at a glance

The habit is short. Bring your Cq table. Name the reference genes and the control label. Confirm and run. Then read the fold-change for each gene, and keep the record. That is the whole value: raw cycle numbers become relative expression with one request, using the standard published method, on cloud compute, with no spreadsheet formulas and no software to license. And you finish with a record you can defend in a paper or a lab meeting. As always, check your first run against a hand-calculated value.

---
