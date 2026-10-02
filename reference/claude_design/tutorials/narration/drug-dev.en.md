# T11 Drug-development walkthrough narration (EN)

## Step 1 — Title · the whole journey

Predicting safety on molecules someone hands you is one slice of drug development. A real program is a pipeline — eight stages, each answering a different question and feeding the next. We'll follow one goal throughout: an oral small molecule that blocks JAK1 for rheumatoid arthritis, but avoids the hERG heart-rhythm risk. And we'll be honest at every stage about what is proven and what is still a gap.

---

## Step 2 — Stage 1 · framing the goal

Before any molecule exists, you write down three things: the target — JAK1, the protein you want to block; the objectives — bind it strongly, be orally absorbed, stay safe on the heart; and the constraints — avoid a competitor's scaffold, keep it makeable. This is a thinking step, not a workflow, but it is the most important one, because every later stage inherits these choices. The objectives you name become the columns you compare on later, and the hERG limit becomes a quality gate.

---

## Step 3 — Stage 2 · design and generate

Which molecules should you even consider? Rather than draw them by hand, BioMate proposes candidates around a seed and returns a ranked, safety-filtered shortlist, using the REINVENT4 lead-design workflow in four modes — de novo, scaffold decoration, linker design, and scaffold hopping. Be honest here: the workflow runs end to end today, but a trained, target-conditioned de-novo generator is not yet built. So treat this output as ideas to filter and improve downstream, not finished designs.

---

## Step 4 — Stage 3 · property prediction

Of the molecules you now have, which are absorbed, safe, and worth the bother? BioMate's flagship predicts ADMET properties — absorption, distribution, metabolism, excretion, toxicity — from a SMILES list, fifteen endpoints including hERG, the one our example cares about most. On the left, the pre-run strip shows every parameter before any compute is spent. On the right, it runs on cloud workers with the quality gates in view. To read it, scan the hERG column first and set aside anything above your limit. ADMET is the most proven stage here — validated, benchmarked near eighty-nine percent, with a real completed run on record.

---

## Step 5 — Stage 4 · structure-based evaluation

Property prediction treats a molecule mostly on its own. This stage brings in the target's three-D structure and asks: does it physically fit the pocket, and how tightly? Three methods, in increasing cost. Docking places each candidate and scores a pose — fast enough to rank hundreds. R-B-F-E, the free-energy method, precisely compares two similar molecules. And molecular dynamics checks the pose is actually stable. The rule is simple: dock many, R-B-F-E a few, simulate the final handful. All three are validated on BioMate's cloud and GPU workers.

---

## Step 6 — Stage 5 · multi-objective ranking

After testing, each candidate carries several numbers that disagree — potent but insoluble, safe but hard to make. Which handful is the best all-round compromise? BioMate keeps every goal in its own column and units, never blended into one score that could hide an unsafe molecule, and shows the Pareto front — the trade-off boundary. That read-it-yourself ranking is real today. But be honest: a deeper optimizer that would actively propose the next batch exists in the code and is not yet wired to the product. Today you read the trade-off; you choose the batch.

---

## Step 7 — Stage 6 · the closed loop and the QC gate

No single pass gives a finished drug. The reliable method is a loop — design, build, test, learn, then design again — and the benefit compounds every round. Inside a single run, a quality gate never silently passes a failed check: here predicted hERG risk is zero-point-seven-one against a limit of zero-point-five, so the run flags it and, for some workflows, adjusts a filter and re-runs, logging the change. The internal suite passes ninety-six of ninety-six. But honestly: the live hERG gate firing on the development site is still unproven, so watch for it before relying on it mid-run.

---

## Step 8 — Stage 7 · P-K and P-B-P-K

A molecule that binds well still has to reach the right concentration at a sensible dose. P-K is what the body does to the drug over time; P-B-P-K is a mechanistic, organ-by-organ model that projects human exposure, often from animal data. BioMate's chain runs three steps: allometric scaling from animal to human, the P-B-P-K organ model, and a virtual patient cohort for variability. You read the peak concentration, the total exposure, and the projected first-in-human dose. It's validated near ninety-eight percent — but population fitting needs real in-vivo data you upload.

---

## Step 9 — Stage 8 · results and the reproducibility record

What did you find across all these stages, and can you prove it? Every run ends in the same three-tab report. Outputs files every result under the step that made it. The reproducibility record is the full audit trail — run id, parameters, software versions, checksums, and citations, downloadable as one JSON. And lineage ties each output back to the workflow and inputs that produced it. Crucially, if BioMate cannot read the outputs, it withholds the findings and says so rather than inventing a summary. That honesty is the feature.

---

## Step 10 — Closing · the pipeline at a glance

So the habit is: frame the goal, design, predict properties, test against the structure, rank the survivors, close the loop, project the dose, and keep the record. ADMET, structure-based methods, P-B-P-K, and the report are validated today. Multi-objective ranking is partial — the optimizer is written but not wired. The closed-loop gate's live firing is unproven on dev. And the trained de-novo generator is still a gap. This is in-silico triage, not a drug: the value is starting smart and failing cheap, not skipping the lab.

---
