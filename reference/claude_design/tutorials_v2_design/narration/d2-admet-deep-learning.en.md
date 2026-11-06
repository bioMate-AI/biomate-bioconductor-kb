# D2 — ADMET deep learning walkthrough narration (EN)

Track: Drug-development models. One block per timeline beat (15 scenes).
For edge-tts: acronyms are spelled where that reads more clearly aloud
(A-D-M-E-T is spoken as the word "ad-met"; Q-S-A-R, I-C-fifty, D-I-L-I,
C-Y-P, I-N-D are spelled). Every number traces to a committed run — no
invented figures.

---

## Step 1 — Title · from structure to a safety verdict

The first question you ask about any new molecule is simple: will the body even tolerate it? ADMET deep learning answers that from the chemical structure alone, before the compound is ever made. In this episode we build the idea from the ground up — what the task is, why it is hard, the classical baseline it has to beat, and then the deep-learning model BioMate actually runs. The workflow is Predict ADMET Properties, AI — the ADMET-AI, Chemprop graph neural network. Each idea slide teaches a concept; each product slide shows it running on real output. And the episode ends on a real run, on hosted cloud compute, where the heart-safety gate caught a cardiotoxic candidate — terfenadine — at twelve thousandths of a micromolar. Throughout, remember: these are model estimates for in-silico triage, not a clinical claim, and experimental validation is always required.

---

## Step 2 — Idea · the task, and why hERG leads

Here is the concept behind everything that follows. Binding the target is not enough. A molecule must also be absorbed, distributed where it should go, not broken down too fast, cleared cleanly, and poison nothing. Those five questions are ADMET — absorption, distribution, metabolism, excretion, and toxicity. The input is the structure, written as a SMILES string; the output is a number for each endpoint. One toxicity endpoint outranks the rest: hERG. If a molecule blocks that cardiac potassium channel, it can trigger a dangerous rhythm change — and this has ended approved drugs. That is why hERG is the make-or-break number, and why ADMET comes early, before you spend money on anything expensive.

---

## Step 3 — Idea · why it is hard

Why is this hard enough to need deep learning? Three reasons. First, drug-like chemical space is estimated at around ten-to-the-sixtieth molecules — you can never enumerate it, so the model must interpolate from a tiny labeled fraction. Second, the labels are sparse and noisy: public measurements number only in the thousands to hundreds of thousands per endpoint, and the same compound can read differently across laboratories. Third, and hardest, a good model must generalize to chemotypes it has never seen — which is exactly where estimates are least reliable and where you most want them. And the cost is asymmetric: a missed hERG liability is not a rounding error. So the bar for "state of the art" is a data-driven model that reports calibrated, per-endpoint scores it can defend on held-out chemistry, with its applicability domain made explicit. Performance is reported per endpoint, dataset, and split — not as one headline number.

---

## Step 4 — Idea · the classical baseline

Before the deep model, the method it has to beat. Classical Q-S-A-R — quantitative structure–activity relationship — turns each molecule into a fixed vector of pre-defined numbers: logP, molecular weight, ring counts, fingerprint bits. Then it fits a shallow learner, typically a random forest, to map that vector to the endpoint. BioMate ships this too — a Q-S-A-R random-forest model and a hERG cardiac-safety model. And it is a genuinely strong baseline: interpretable, because you can read which descriptor drove the call; fast to train; and data-efficient on a single endpoint. Its ceiling is the features themselves. They are fixed in advance, so any structural signal the descriptor set does not encode is invisible to the model, and extrapolation to genuinely new scaffolds is weak. This is a strong baseline the deep model has to beat, not a strawman.

---

## Step 5 — Idea · the deep-learning model

Now the deep-learning idea, and it is elegant. A molecule already is a graph: atoms are the nodes, bonds are the edges. A message-passing neural network — Chemprop's directed version — passes information along the bonds for several rounds, so each atom's representation gradually absorbs its chemical neighbourhood. The network then pools those atom representations into one whole-molecule vector and reads off every endpoint. Nothing is hand-engineered; the features are learned from data. This is what BioMate's ADMET-AI workflow runs. ADMET-AI, from Swanson and colleagues in Bioinformatics, bundles pre-trained Chemprop graph models covering fifteen endpoints — hERG, D-I-L-I, blood–brain barrier, Caco-2, the C-Y-P panel, solubility, plasma protein binding, half-life, and more — trained on over two million experimental measurements from ChEMBL and the Therapeutics Data Commons. On that benchmark it reports an area-under-the-curve above zero-point-eight-five on twenty of thirty-one classification tasks: strong, uneven across endpoints, and still an estimator. BioMate runs this frozen, published model; it does not retrain it per request.

---

## Step 6 — Idea · classical versus deep

So which do you use? It is not "deep is always better" — it is two tools with different trade-offs. The graph network usually wins on accuracy across diverse chemistry, and it gives you many endpoints from a single model. The descriptor-plus-forest baseline wins on interpretability, on speed, and when data is scarce. Both, crucially, are estimators of experimental values, and both need wet-lab confirmation before any decision that matters. BioMate keeps both in the catalog and routes to the one that fits the request. For broad ADMET screening on drug-like compounds it defaults to the deep ADMET-AI workflow — the one the rest of this episode runs.

---

## Step 7 — Idea · how BioMate runs it

Here is how that actually happens in the product. There is no environment to set up and no model to license. You describe the goal in plain language — screen these compounds for ADMET and cardiac safety. BioMate routes your request to the validated Predict ADMET Properties workflow, opens its panel for you to review, and, once you confirm, runs the graph network on managed cloud compute — streaming live progress and a quality gate the whole time. Chat, route, review, run, read. The next slides show each of those running on real output.

---

## Step 8 — Product · the pre-run check

First, the pre-run check. Everything the model will use is shown, and editable, before a single cent of compute is spent: your SMILES list, the model type — M-P-N-N — and the shard size that controls parallelism. We attach no blanket accuracy number here, because a real performance claim needs a named dataset, endpoint, metric, and split. What we show you instead is the real output of this run. If a required parameter is missing, the panel blocks and offers to fix it. You stay in control of exactly what runs.

---

## Step 9 — Product · the live progress stream

You confirm, and the run streams into the chat, step by step, as it happens on hosted cloud compute. First the ADMET-inference shard runs and finishes; then the predict-and-merge step begins. When the DILI risk comes back high, a safety quality-gate pauses the run right there in the stream — it names the failing metric, blocks, and adjusts the parameters — then the step completes and the chat reads, workflow finished. Nothing is hidden: every stage, and the gate that caught the liability, is narrated as it goes.

---

## Step 10 — Product · the hero beat, the gate halts

This is the beat that matters. On a real run on AWS Batch, we screened two compounds: aspirin, a safe control, and terfenadine — a known hERG liability that was withdrawn from the market. The graph network scored both. Aspirin came back clearly safe, with an estimated hERG I-C-fifty at the model's ceiling. Terfenadine, with a logP of seven and a molecular weight near five hundred, came back at twelve thousandths of a micromolar. The panel aggregation takes the worst compound, so that value drove the gate — and the GOLD hERG gate halted the screen, below the one-micromolar high-risk threshold, citing Sanguinetti and Tristani-Firouzi and the F-D-A E-fourteen guidance: high-risk hERG inhibition predicts Q-T prolongation and Torsade de Pointes. A naive pipeline would have shipped this silently. On a failing gate, BioMate also suggests a grounded fix — tighten the developability envelope, logP maximum from five down to four, molecular-weight maximum from five hundred to four hundred — logged as a clear before-and-after diff. That is an advisory suggestion you decide whether to act on, not an autonomous restart. And the proof the gate is meaningful: re-run on the safe panel, aspirin, caffeine, and ibuprofen, it completed with no gates fired at all. The gate discriminates; it is not always on.

---

## Step 11 — Product · the findings table

When the run finishes, the After-run panel reads the verdict straight from the result files — a per-compound findings table with every endpoint: hERG, DILI, oral bioavailability, blood-brain-barrier penetration, clinical toxicity, plasma-protein binding, Caco-2 permeability, and the C-Y-P panel. Each row carries a plain-language interpretation and the exact output file it was read from — never written by hand, and withheld if a value could not be read. These are computational estimates, to confirm with wet-lab assays.

---

## Step 12 — Product · the QC-gate metrics file

Behind the summary, every output file previews in place. Here is the quality-metrics file the safety gate read from — the hERG I-C-fifty in micromolar, whether it clears the ten-micromolar safety margin, the Ames mutagenicity call, and the DILI risk, high, with its probability against the threshold that tripped the gate. Tables render as tables, and every file — this one, the toxicity report, the P-K summary, the main results, and the versions file — is yours to download.

---

## Step 13 — Product · the reproducibility record

Next, the reproducibility record — and for a model prediction this matters doubly. Run id, parameters, the exact model and software versions, the outputs with their S-H-A-two-fifty-six checksums, and citations, all in one record you can download as a single J-S-O-N file. A reviewer can see precisely which model, on which inputs, produced the number. This is the same kind of evidence a reviewer, a patent examiner, or a regulator would ask for. Where a field is empty in this run, the record shows it rather than hiding it.

---

## Step 14 — Idea · how to read these outputs

Finally, how to read these numbers well. The native hERG output is a blocker-risk probability; the I-C-fifty you see is an estimate derived from that probability — a power law anchored to terfenadine — not a measured value. A low-risk compound's I-C-fifty sits at the estimator's ceiling, which is a model output, not proof of safety. So read in this order. First, every value is an estimate, not an assay: advance nothing on it without wet-lab confirmation — hERG patch-clamp, hepatocyte and liver-enzyme panels, Ames testing. Second, know the edge: the network generalizes from ChEMBL and T-D-C chemistry, so the further a scaffold sits from that space, the less you should trust the estimate. Third, trust the gate: it compares a worst-case value to a cited threshold and either flags it or halts, and it never silently passes a failed check. The defensible output is not a single number — it is the per-compound table, the cited gate decision, and the reproducibility record that ties both back to the exact model and inputs.

---

## Step 15 — Closing · at a glance

So, ADMET deep learning at a glance: structure in, learned graph features in the middle, a cited safety verdict out. A graph neural network learns its own representation by passing messages along bonds, beating hand-engineered descriptors on diverse chemistry, while staying an estimator that needs wet-lab confirmation. BioMate runs the published ADMET-AI, Chemprop model on managed compute, behind a cited quality gate that caught a cardiotoxic candidate on a real run and kept a record defensible enough for a reviewer. What you saw delivered a fifteen-endpoint graph model trained on over two million measurements; a real run whose hERG gate halted terfenadine at twelve thousandths of a micromolar; a gate that stays silent on safe chemistry; and an audit-grade record behind every estimate. This is in-silico triage, not a clinical result — the value is catching the unsafe candidate early and cheaply, not skipping the lab.

---
