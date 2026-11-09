## Step 1 — A result you can inspect

In this lesson, follow a real BioMate ADMET run from its inputs to its report. Learn what the predictions mean, where the underlying files live, and how to preserve the record. The demonstration uses three familiar small molecules. It demonstrates a prediction workflow; it does not establish that a new drug works.

---

## Step 2 — Begin with a precise question

A SMILES string is a compact way to describe a molecular structure. This example submitted aspirin, caffeine and ibuprofen. Keep that input order, because the report refers to compound one, two and three. This is an ADMET demonstration with known molecules. No target-binding experiment or JAK1 activity measurement is included.

---

## Step 3 — Five questions beyond binding

ADMET stands for absorption, distribution, metabolism, excretion and toxicity. These are different questions: whether a compound enters circulation, where it goes, how it changes, how it leaves, and what harm it might cause. No single endpoint answers all five. Use predictions to identify questions for follow-up testing, not as a certificate of safety.

---

## Step 4 — Open the completed run

Open the example conversation and select the ADMET workflow. In After run, Summary presents the findings. The completed label confirms execution finished. It does not certify biological validity. Here the report describes predictions for three compounds and explicitly asks for experimental confirmation. Keep that distinction in mind throughout the review.

---

## Step 5 — Inspect the source files

Now choose Outputs. This run contains six downloadable files. The prediction results and toxicity report contain the molecular predictions; the quality-control file records checks and thresholds. A filename in the list is not enough. Open the file and confirm that it is readable and belongs to the current run. These six downloads were checked through BioMate for this review.

---

## Step 6 — Read one endpoint across molecules

hERG is a potassium channel important for cardiac electrical activity. The displayed model scores predict channel-blocking classification, in the order aspirin, caffeine and ibuprofen. Higher scores favor the blocker class within this model. These are unitless predictions, not measured concentrations or probabilities of arrhythmia in a patient. Calibration and applicability to a new chemical series require separate evaluation.

---

## Step 7 — Keep the endpoints separate

A classification score has no concentration unit. An IC50 describes the concentration associated with fifty percent inhibition in a defined assay or model. You cannot turn one into the other without a justified and validated relationship. Cardiac risk assessment also considers exposure and additional evidence. Read the raw classification output separately from heuristic estimates in this report.

---

## Step 8 — A QC check needs a defined rule

DILI means drug-induced liver injury. This run uses the highest per-compound DILI score as its panel value: caffeine’s score, rounded to zero point eight seven five. It exceeds the configured zero point five threshold, so the recorded check does not pass. This is a model screening flag, not a diagnosis or an estimated patient incidence. A failed check also does not prove the workflow stopped or reran; those actions need their own evidence.

---

## Step 9 — Preserve the result and its context

Open Reproducibility record. It links the result to a run and lists the outputs. Before sharing, check that the actual input list, relevant settings and software details are available. A blank field is missing evidence. In this example, input bindings and tool parameters were empty in the default record, and checksums were not included by default. Preserve the submitted input list alongside the downloaded outputs.

---

## Step 10 — Turn a prediction into a testable next step

The useful next step is a better research decision. Confirm the inputs, inspect the per-compound values, and choose follow-up measurements appropriate to the question. Keep experimental measurements separate from predictions when comparing them. This is how a computational workflow contributes to a design, test and learn cycle: by producing inspectable evidence, with its limits visible.
