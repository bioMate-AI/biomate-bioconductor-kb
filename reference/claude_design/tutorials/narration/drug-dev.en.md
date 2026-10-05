# T11 Drug-development walkthrough narration (EN)

## Step 1 — Title · the whole journey

Predicting safety on molecules someone hands you is one slice of drug development. A real program is a pipeline — eight stages, each answering a different question and feeding the next. The value BioMate offers is to run that whole chain as hosted workflows, so a team can start a program from a filtered, ranked shortlist without standing up or licensing in-house software — one pipeline, one provenance trail, from a target idea to a defensible candidate record. This tutorial pairs an idea slide, that teaches each concept, with a product slide, that shows it running live inside BioMate. Our demonstration sends three familiar molecules — aspirin, caffeine, and ibuprofen — through the pipeline as an illustrative example. They are not a drug-discovery campaign result and not a clinical claim; they are a clear way to show the mechanics. And we'll be honest at every stage about what is demonstrated here, what is merely available, and what is still a gap — because for a buyer, a claim that is provable is the asset.

---

## Step 2 — Idea · why it's a loop, not a line

Before the stages, one idea that governs all of them. It is tempting to picture drug discovery as a straight line — design once, test once, done. It never works that way. The reliable method is a cycle: design, build, test, learn, then design again — and the benefit compounds every round, because each turn learns from the last. Keep this loop in mind. The eight stages ahead are simply one trip around it, and the two features that make the loop trustworthy are the quality gate in Stage 6 and the reproducibility record in Stage 8.

---

## Step 3 — Stage 1 · framing the goal

Before any molecule exists, you write down three things: the target — the protein you want to act on, for instance JAK1 in an inflammation program; the objectives — bind it, be orally absorbed, stay safe on the heart; and the constraints — keep it novel and makeable. This is a thinking step, not a workflow, but it governs everything after it, because every later stage inherits these choices. The objectives you name become the columns you compare on later, and a safety limit like hERG becomes a quality gate. In our demonstration the goal is deliberately simple: screen a small set of molecules for developability and cardiac safety.

---

## Step 4 — Stage 2 · design and generate

Which molecules should you even consider? Rather than draw them by hand out of ten-to-the-sixtieth possibilities, BioMate proposes candidates by systematically enumerating chemically sensible variations around a seed you supply, then filters and ranks them into a shortlist. Be honest about what is doing the generating: this is systematic enumeration around your seed, and it runs end to end today. A learned, generative de-novo model — one that has been trained to invent molecules for your target — is on the roadmap, not what runs today. So treat this output as ideas to filter and improve downstream, not finished designs.

---

## Step 5 — Stage 3 idea · what ADMET is, and why hERG

Now the key concept behind the next three screens. Binding is not enough. A molecule must also be absorbed, go where it should, survive long enough, leave cleanly, and poison nothing. Those five questions are ADMET — absorption, distribution, metabolism, excretion, toxicity. One toxicity endpoint outranks the rest: hERG. If a molecule blocks that cardiac potassium channel, it can trigger a dangerous rhythm change — and this has ended approved drugs. That is why hERG is the make-or-break number in this example, and why ADMET comes early, before you spend money on anything expensive.

---

## Step 6 — Stage 3 product · the pre-run check

Here is that concept running live in BioMate. BioMate's ADMET prediction is a model trained on more than two million experimental measurements. This is the real pre-run strip: your three SMILES — aspirin, caffeine, and ibuprofen — and every model setting, shown and editable before a single cent of compute is spent. If a required parameter is missing, the panel blocks and offers to fix it. This is the stage with real run evidence here — a run completed on record. We do not attach a blanket accuracy number, because a performance claim needs a named dataset, endpoint, metric, and split.

---

## Step 7 — Stage 3 product · running, gates in view

You confirm, and it runs on hosted cloud compute. Each phase card flips from pending to running to completed in real time as steps finish. Crucially, the quality gates that will be checked — including hERG — are listed alongside the whole time, so nothing is hidden while compute is in flight. To read it, scan the hERG column first and set aside anything above your limit.

---

## Step 8 — Stage 3 product · completed

When it finishes, the workflow panel tells the whole story — a Completed badge, a Run-again action, and the after-run tabs: Summary, Outputs, and the reproducibility record. The chat summary stays in sync with it: same workflow name, same completed state, no undefined text, no stuck spinner. And the honesty rule holds even here: if the outputs could not be read, the findings are withheld and said so, never fabricated.

---

## Step 9 — Stage 4 · docking versus RBFE versus MD

Property prediction treats a molecule mostly on its own. This stage brings in the target's three-D structure, and three methods answer different questions at different costs. Docking places each candidate and scores a pose — cheap enough to rank hundreds, but a docking score is a prioritization signal, not a measured affinity. R-B-F-E, the free-energy method, estimates a difference in binding free energy between two similar molecules under a defined protocol — more informative, but it needs GPU simulation, so you run only a few, and agreement with experiment has to be shown on relevant data. Molecular dynamics samples whether a pose stays stable over time; it does not, by itself, establish binding. The habit is: dock many, R-B-F-E a few, simulate the last handful. These are available in BioMate, but an end-to-end run is not demonstrated in this walkthrough, and we claim no independent accuracy here.

---

## Step 10 — Stage 5 · multi-objective ranking

After testing, each candidate carries several numbers that disagree — potent but insoluble, safe but hard to make. Which handful is the best all-round compromise? BioMate keeps every goal in its own column and units, never blended into one score that could hide an unsafe molecule, and shows the Pareto front — the trade-off boundary where you can't improve one goal without sacrificing another. That read-it-yourself ranking is real today. But be honest: a deeper optimizer that would actively propose the next batch exists in the code and is not yet wired to the product. Today you read the trade-off; you choose the batch.

---

## Step 11 — Stage 6 · the QC gate

Back on the loop. Inside a single run, a quality gate turns a threshold into a decision. It compares a value to your limit and either passes it or halts and flags it — and it must never silently pass a failed check, because a gate that quietly lets failures through is worse than no gate: it looks like success. In our live run, the native hERG output is a blocker-risk score — an estimate, not a measured IC50. For these three low-risk compounds that score is low; and any IC50 the model prints for a low-risk compound sits at the estimator's ceiling, around ten millimolar, which is a model output, not evidence of safety. And it is not the only signal: in the same run the liver-injury endpoint, D-I-L-I, came back high — above the limit — so the safety gate flags it for follow-up. The lesson is to read the gate, not to trust a single number. And honestly, the gate firing is no longer unproven: on a separate run, the safety gate fired live at its high-risk threshold and produced a cited rationale. The remediation it offers — a suggested parameter change — is an advisory suggestion, not an autonomous re-run.

---

## Step 12 — Stage 7 · P-K and P-B-P-K

A molecule that binds well still has to reach the right concentration at a sensible dose. P-K is what the body does to the drug over time; P-B-P-K is a mechanistic, organ-by-organ model that projects human exposure scenarios, often from animal data. BioMate's chain is designed to combine three steps: allometric scaling from animal to human, the P-B-P-K organ model, and a virtual-patient cohort for variability. From a demonstrated result you would read the peak concentration, the total exposure, and a projected starting-dose scenario — intended for evaluation, not a guaranteed safe human dose. The capability is available, but an end-to-end run is not demonstrated here, and population fitting needs real in-vivo data you upload.

---

## Step 13 — Stage 8 idea · lineage and provenance

Across all these stages, a result is only as good as your ability to prove how you got it. Provenance is the chain from an output back to the exact inputs, parameters, and software that produced it. Without it, a number is just an assertion; with it, a number is evidence — defensible for a manuscript, a patent, or an I-N-D submission. Lineage is that chain made navigable in the interface. This is the concept; the next three screens show it concretely.

---

## Step 14 — Stage 8 product · outputs

First, Outputs. Every file lands under the step that produced it — the ADMET table, the quality metrics, the toxicity report — so you never hunt for a result or guess which stage it came from. Each artifact previews in place: tables as tables, images as thumbnails, text as code.

---

## Step 15 — Stage 8 product · the reproducibility record

Next, the reproducibility record — the provenance idea made concrete. Run id, parameters, software versions, outputs, and citations, all in one record you can download as a single JSON. This is the same kind of evidence a reviewer, a patent examiner, or a regulator would ask for. Where a field is empty in this run — some input bindings and default hashes were — the record shows the gap rather than hiding it.

---

## Step 16 — Stage 8 product · lineage

And lineage walks the chain backward: this output came from this workflow, with these parameters, on these inputs — and forward to everything downstream that consumed it. It is the navigable form of the provenance graph you just saw.

---

## Step 17 — Closing · the pipeline at a glance

So the habit is: frame the goal, design, predict properties, test against the structure, rank the survivors, close the loop behind a quality gate, project the dose, and keep the record. Each idea slide taught the concept; each product slide showed it running. ADMET ran end to end and is demonstrated here. The structure-based methods and P-B-P-K are available, but an end-to-end run is not demonstrated in this walkthrough. The reproducibility record is demonstrated. Multi-objective ranking is partial — the optimizer is written but not wired. The closed-loop gate's firing is demonstrated on a separate run, with its remediation offered as an advisory suggestion rather than an autonomous re-run. And the learned de-novo generator is still on the roadmap. The defensible advantage here is not any one model — it is the closed loop plus an audit-grade provenance record, with every claim scoped to what is provable. This is in-silico triage, not a drug: the value is starting smart and failing cheap, not skipping the lab.

---
