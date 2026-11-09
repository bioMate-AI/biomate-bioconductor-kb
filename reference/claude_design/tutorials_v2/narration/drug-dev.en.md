# T11 Drug-development walkthrough narration (EN)

## Step 1 — Title · the whole journey

Predicting safety on molecules someone hands you is one slice of drug development. A real program is a pipeline — a chain of stages, each answering a different question and feeding the next. What BioMate offers is to run that whole chain as hosted workflows, so a team can start a program from a filtered, ranked shortlist in minutes, without standing up or licensing in-house software — one pipeline, one provenance trail, from a target idea to a defensible candidate record. This walkthrough pairs an idea slide, that teaches each concept, with a product slide, that shows it running live inside BioMate. Our demonstration sends three familiar molecules — aspirin, caffeine, and ibuprofen — through the pipeline as an illustrative example: in-silico triage, not a drug-discovery campaign result and not a clinical claim. The point throughout is simple — everything you see here runs, with real output, and every finding is read from that output, never invented.

---

## Step 2 — Idea · why it's a loop, not a line

Before the stages, one idea that governs all of them. It is tempting to picture drug discovery as a straight line — design once, test once, done. It never works that way. The reliable method is a cycle: design, build, test, learn, then design again — and the benefit compounds every round, because each turn learns from the last. Keep this loop in mind. The stages ahead are simply one trip around it, and the two features that make the loop trustworthy are the quality gate that guards it and the reproducibility record that makes every result defensible.

---

## Step 3 — Stage 1 · framing the goal

Before any molecule exists, you write down three things: the target — the protein you want to act on, for instance JAK1 in an inflammation program; the objectives — bind it, be orally absorbed, stay safe on the heart; and the constraints — keep it novel and makeable. This is a thinking step, not a workflow, but it governs everything after it, because every later stage inherits these choices. The objectives you name become the columns you compare on later, and a safety limit like hERG becomes a quality gate. In our demonstration the goal is deliberately simple: screen a small set of molecules for developability and cardiac safety.

---

## Step 4 — Stage 2 · designing candidates

Which molecules should you even consider? Rather than draw them by hand out of ten-to-the-sixtieth possibilities, BioMate proposes candidates by systematically enumerating chemically sensible variations around a seed you supply, then filters out known liabilities and ranks what survives into a shortlist — each candidate carrying a short why-this-one note and its nearest known molecule. It runs end to end today, and you get a ranked starting set in minutes. Treat the output as well-formed ideas to filter and improve downstream — the beginning of the loop, not the end of it.

---

## Step 5 — Stage 3 idea · what ADMET is, and why hERG

Now the key concept behind the next three screens. Binding is not enough. A molecule must also be absorbed, go where it should, survive long enough, leave cleanly, and poison nothing. Those five questions are ADMET — absorption, distribution, metabolism, excretion, toxicity. One toxicity endpoint outranks the rest: hERG. If a molecule blocks that cardiac potassium channel, it can trigger a dangerous rhythm change — and this has ended approved drugs. That is why hERG is the make-or-break number in this example, and why ADMET comes early, before you spend money on anything expensive.

---

## Step 6 — Stage 3 product · the pre-run check

Here is that concept running live in BioMate. The ADMET prediction is a model trained on a large body of experimental measurements. This is the real pre-run strip: your three SMILES — aspirin, caffeine, and ibuprofen — and every model setting, shown and editable before a single cent of compute is spent. If a required parameter is missing, the panel blocks and offers to fix it. You stay in control of exactly what runs — and we attach no blanket accuracy number, because a performance claim needs a named dataset, endpoint, metric, and split. What we show you instead is the real output of this run.

---

## Step 7 — Stage 3 product · running, gates in view

You confirm, and it runs on hosted cloud compute. Each phase card flips from pending to running to completed in real time as steps finish. Crucially, the quality gates that will be checked — including hERG — are listed alongside the whole time, so nothing is hidden while compute is in flight. To read it, scan the hERG column first and set aside anything above your limit.

---

## Step 8 — Stage 3 product · completed

When it finishes, the workflow panel tells the whole story — a Completed badge, a Run-again action, and the after-run tabs: Summary, Outputs, and the reproducibility record. The chat summary stays in sync with it: same workflow name, same completed state, no undefined text, no stuck spinner. And the honesty rule holds even here: the values on the Summary tab are read straight from the run's outputs, and if an output could not be read, that finding is withheld and said so, never fabricated.

---

## Step 9 — Stage 4 · multi-objective ranking

After testing, each candidate carries several numbers that disagree — potent but insoluble, safe but hard to make. Which handful is the best all-round compromise? BioMate keeps every goal in its own column and units, never blended into one score that could hide an unsafe molecule, and shows the Pareto front — the trade-off boundary where you can't improve one goal without sacrificing another. Rejected molecules stay visible, each with its reason. You read the trade-off and you choose the batch; the product never silently collapses your goals into a single number.

---

## Step 10 — Stage 5 · the QC gate

Back on the loop. Inside a single run, a quality gate turns a threshold into a decision. It compares a value to your limit and either passes it or halts and flags it — and it must never silently pass a failed check, because a gate that quietly lets failures through is worse than no gate: it looks like success. In our live run, the native hERG output is a blocker-risk score — an estimate, not a measured IC50. For these three low-risk compounds that score is low; and any IC50 the model prints for a low-risk compound sits at the estimator's ceiling, around ten millimolar, which is a model output, not evidence of safety. And it is not the only signal: in the same run the liver-injury endpoint, D-I-L-I, came back high — above the limit — so the safety gate flagged it for follow-up. The lesson is to read the gate, not to trust a single number. When a gate fires, BioMate suggests a parameter change to try next, logged as a clear before-and-after diff — an advisory suggestion that you decide whether to act on, not an automatic re-run.

---

## Step 11 — Stage 6 · P-K and P-B-P-K

A molecule that binds well still has to reach the right concentration at a sensible dose. P-K is what the body does to the drug over time; P-B-P-K is a mechanistic, organ-by-organ model that projects human exposure scenarios, often from animal data. BioMate's chain combines three steps: allometric scaling from animal to human, the P-B-P-K organ model, and a virtual-patient cohort for variability. From it you read the peak concentration, the total exposure, and a projected starting-dose scenario. Read these as a projected exposure for evaluation — the absolute numbers are not independently validated, so this is a scenario to reason with, never a guaranteed safe human dose. Bring your own in-vivo concentration data and the same chain fits it directly.

---

## Step 12 — Stage 7 idea · lineage and provenance

Across all these stages, a result is only as good as your ability to prove how you got it. Provenance is the chain from an output back to the exact inputs, parameters, and software that produced it. Without it, a number is just an assertion; with it, a number is evidence — defensible for a manuscript, a patent, or an I-N-D submission. Lineage is that chain made navigable in the interface. This is the concept; the next three screens show it concretely.

---

## Step 13 — Stage 7 product · outputs

First, Outputs. Every file lands under the step that produced it — the ADMET table, the quality metrics, the toxicity report — so you never hunt for a result or guess which stage it came from. Each artifact previews in place: tables as tables, images as thumbnails, text as code.

---

## Step 14 — Stage 7 product · the reproducibility record

Next, the reproducibility record — the provenance idea made concrete. Run id, parameters, software versions, outputs, and citations, all in one record you can download as a single JSON. This is the same kind of evidence a reviewer, a patent examiner, or a regulator would ask for. Where a field is empty in this run, the record shows it rather than hiding it.

---

## Step 15 — Stage 7 product · lineage

And lineage walks the chain backward: this output came from this workflow, with these parameters, on these inputs — and forward to everything downstream that consumed it. It is the navigable form of the provenance graph you just saw.

---

## Step 16 — Closing · the pipeline at a glance

So the loop is: frame the goal, design candidates around a seed, predict their properties, rank the survivors, and — when a check fails — let the quality gate halt and suggest the fix, then project exposure and keep the record. Each idea slide taught the concept; each product slide showed it running on real output. What you saw is a complete in-silico triage loop: a seed becomes a ranked, safety-filtered shortlist, a safety gate fires on a real liability and proposes a fix, and every number traces back to the exact inputs and parameters that produced it. The defensible advantage is not any one model — it is the closed loop plus an audit-grade provenance record, run on hosted compute with no software to license, every finding read from real output. This is in-silico triage, not a drug: the value is starting smart and failing cheap, not skipping the lab.

---
