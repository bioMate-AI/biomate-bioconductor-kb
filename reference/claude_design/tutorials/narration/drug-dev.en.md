# T11 Drug-development walkthrough narration (EN)

## Step 1 — Title · the whole journey

Predicting safety on molecules someone hands you is one slice of drug development. A real program is a pipeline — eight stages, each answering a different question and feeding the next. This tutorial pairs an idea slide, that teaches each concept, with a product slide, that shows it running inside BioMate. We'll follow one goal throughout: an oral small molecule that blocks JAK1 for rheumatoid arthritis, but avoids the hERG heart-rhythm risk. And we'll be honest at every stage about what is proven and what is still a gap.

---

## Step 2 — Idea · why it's a loop, not a line

Before the stages, one idea that governs all of them. It is tempting to picture drug discovery as a straight line — design once, test once, done. It never works that way. The reliable method is a cycle: design, build, test, learn, then design again — and the benefit compounds every round, because each turn learns from the last. Keep this loop in mind. The eight stages ahead are simply one trip around it, and the two features that make the loop trustworthy are the quality gate in Stage 6 and the reproducibility record in Stage 8.

---

## Step 3 — Stage 1 · framing the goal

Before any molecule exists, you write down three things: the target — JAK1, the protein you want to block; the objectives — bind it strongly, be orally absorbed, stay safe on the heart; and the constraints — avoid a competitor's scaffold, keep it makeable. This is a thinking step, not a workflow, but it is the most important one, because every later stage inherits these choices. The objectives you name become the columns you compare on later, and the hERG limit becomes a quality gate.

---

## Step 4 — Stage 2 · design and generate

Which molecules should you even consider? Rather than draw them by hand out of ten-to-the-sixtieth possibilities, BioMate proposes candidates around a seed and returns a ranked, safety-filtered shortlist, using the REINVENT4 lead-design workflow in four modes — de novo, scaffold decoration, linker design, and scaffold hopping. Be honest here: the workflow runs end to end today, but a trained, target-conditioned de-novo generator is not yet built. So treat this output as ideas to filter and improve downstream, not finished designs.

---

## Step 5 — Stage 3 idea · what ADMET is, and why hERG

Now the key concept behind the next three screens. Binding is not enough. A molecule must also be absorbed, go where it should, survive long enough, leave cleanly, and poison nothing. Those five questions are ADMET — absorption, distribution, metabolism, excretion, toxicity. One toxicity endpoint outranks the rest: hERG. If a molecule blocks that cardiac potassium channel, it can trigger a fatal arrhythmia — and it has killed approved drugs. That is why, for our JAK1 example, hERG is the make-or-break number, and why ADMET comes early, before you spend money on anything expensive.

---

## Step 6 — Stage 3 product · the pre-run check

Here is that concept running in BioMate. The flagship predicts ADMET properties with graph neural nets trained on two million measurements, fifteen endpoints including hERG. This is the pre-run strip: your SMILES list and every model setting, shown and editable before a single cent of compute is spent. If a required parameter is missing, the panel blocks and offers to fix it. ADMET is the most proven stage here — validated, benchmarked near eighty-nine percent, with a real completed run on record.

---

## Step 7 — Stage 3 product · running, gates in view

You confirm, and it runs on cloud workers. Each phase card flips from pending to running to completed in real time as steps finish on AWS Batch. Crucially, the quality gates that will be checked — including hERG — are listed alongside the whole time, so nothing is hidden while compute is in flight. To read it, scan the hERG column first and set aside anything above your limit.

---

## Step 8 — Stage 3 product · completed

When it finishes, the chat and the right-hand panel tell the same story — same workflow name, same completed state, no undefined text, no stuck spinner. The after-run tabs give you Outputs, Findings, and Parameters. And the honesty rule holds even here: if the outputs could not be read, the findings are withheld and said so, never fabricated.

---

## Step 9 — Stage 4 · docking versus RBFE versus MD

Property prediction treats a molecule mostly on its own. This stage brings in the target's three-D structure and asks: does it physically fit the pocket, and how tightly? Three methods climb a ladder of cost and accuracy. Docking places each candidate and scores a pose — cheap enough to rank hundreds. R-B-F-E, the free-energy method, precisely compares two similar molecules — but it needs GPU simulation, so you run only a few. And molecular dynamics checks the final handful are actually stable in the pocket. The rule is simple: dock many, R-B-F-E a few, simulate the last handful. All three are validated on BioMate's cloud and GPU workers.

---

## Step 10 — Stage 5 · multi-objective ranking

After testing, each candidate carries several numbers that disagree — potent but insoluble, safe but hard to make. Which handful is the best all-round compromise? BioMate keeps every goal in its own column and units, never blended into one score that could hide an unsafe molecule, and shows the Pareto front — the trade-off boundary where you can't improve one goal without sacrificing another. That read-it-yourself ranking is real today. But be honest: a deeper optimizer that would actively propose the next batch exists in the code and is not yet wired to the product. Today you read the trade-off; you choose the batch.

---

## Step 11 — Stage 6 · the QC gate

Back on the loop. Inside a single run, a quality gate turns a threshold into a decision you can trust. It compares a measured value to your limit and either passes it or halts and flags it — and it must never silently pass a failed check, because a gate that quietly lets failures through is worse than no gate: it looks like success. Here predicted hERG risk is zero-point-seven-one against a limit of zero-point-five, so the run flags it and, for some workflows, adjusts a filter and re-runs, logging the change as a diff. The internal suite passes ninety-six of ninety-six. But honestly: the live hERG gate firing on the development site is still unproven, so watch for it before relying on it mid-run.

---

## Step 12 — Stage 7 · P-K and P-B-P-K

A molecule that binds well still has to reach the right concentration at a sensible dose. P-K is what the body does to the drug over time; P-B-P-K is a mechanistic, organ-by-organ model that projects human exposure, often from animal data. BioMate's chain runs three steps: allometric scaling from animal to human, the P-B-P-K organ model, and a virtual patient cohort for variability. You read the peak concentration, the total exposure, and the projected first-in-human dose. It's validated near ninety-eight percent — but population fitting needs real in-vivo data you upload.

---

## Step 13 — Stage 8 idea · lineage and provenance

Across all these stages, a result is only as good as your ability to prove how you got it. Provenance is the chain from an output back to the exact inputs, parameters, and software that produced it. Without it, a number is just an assertion; with it, a number is evidence — defensible for a manuscript, a patent, or an I-N-D submission. Lineage is that chain made navigable in the interface. This is the concept; the next three screens show it concretely.

---

## Step 14 — Stage 8 product · outputs

First, Outputs. Every file lands under the step that produced it — admet, qc, toxicity for an ADMET run — so you never hunt for a result or guess which stage it came from. Each artifact previews in place: tables as tables, images as thumbnails, text as code.

---

## Step 15 — Stage 8 product · the reproducibility record

Next, the reproducibility record — the provenance idea made concrete. Run id, parameters, software versions, outputs, SHA-256 checksums, and citations, all in one record, downloadable as a single JSON. This is the same evidence a reviewer, a patent examiner, or a regulator would ask for — produced automatically, every run.

---

## Step 16 — Stage 8 product · lineage

And lineage walks the chain backward: this output came from this workflow, with these parameters, on these inputs — and forward to everything downstream that consumed it. It is the navigable form of the provenance graph you just saw. The record and lineage are validated today.

---

## Step 17 — Closing · the pipeline at a glance

So the habit is: frame the goal, design, predict properties, test against the structure, rank the survivors, close the loop behind a quality gate, project the dose, and keep the record. Each idea slide taught the concept; each product slide showed it running. ADMET, structure-based methods, P-B-P-K, and the report are validated today. Multi-objective ranking is partial — the optimizer is written but not wired. The closed-loop gate's live firing is unproven on dev. And the trained de-novo generator is still a gap. This is in-silico triage, not a drug: the value is starting smart and failing cheap, not skipping the lab.

---
