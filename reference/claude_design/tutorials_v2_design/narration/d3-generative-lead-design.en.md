# Generative lead design — narration (EN)

One narration block per scene, in order, for edge-tts. Episode D3. Grounded in BioMate's real REINVENT4 Generative Lead Design workflow (nextflow_nfcore/subworkflows/drug_discovery/reinvent4_lead_design/main.nf; search_workflow + get_workflow_spec, captured 2026-10-05). REINVENT4: Loeffler et al., J. Cheminform. 2024, 16:20 (MolecularAI / AstraZeneca, Apache-2.0).

---

## Step 1 — Title · generative lead design with reinforcement learning

Most computational chemistry starts from a library you already have, and screens it for winners. Generative design works the other way around: instead of picking from a list, it invents new molecules aimed at a goal you state. BioMate runs REINVENT4, a reinforcement-learning generator from MolecularAI and AstraZeneca, to propose novel, drug-like candidates — and then filters and ranks them. You describe the starting scaffold — the core skeleton you want to build on — and what "good" means, and BioMate proposes new structures to take toward synthesis. In this walkthrough we'll follow the real workflow the whole way through, from a plain goal to ranked, testable candidates.

---

## Step 2 — The problem this solves

The space of synthesizable, drug-like molecules is enormous — commonly estimated near ten to the sixtieth power. That's more than any library, any high-throughput screen, or any amount of compute could ever cover. You simply cannot list it. And brute-force enumeration around a scaffold doesn't rescue you: decorating one core with a handful of fragments already produces millions of analogs, and most of them are undrug-like, hard to make, or trivial. So the real need isn't more enumeration — it's a way to search that vast space intelligently, proposing only candidates that are novel, synthesizable, and actually aimed at your objective.

---

## Step 3 — The ideas you need first

Four plain language describe the whole method. First, a generative model: a policy trained on known chemistry that writes new molecules, one piece at a time — a trained model, not a lookup table. REINVENT4 is that generator. Second, a scoring function: a reward that judges each proposed molecule — its drug-likeness, how easy it is to make, or how well it docks. That scoring function is your objective, made numeric. Third, the reinforcement-learning loop: generate, score, and learn, over many rounds, so the generator leans toward higher-scoring molecules with experience. And fourth, multi-parameter optimization: the reward can combine several goals at once, so candidates balance potency, drug-likeness, and synthesizability rather than chasing just one.

---

## Step 4 — In BioMate · plain goal to workflow to cloud

You don't configure a neural network. You state the intent in plain language — design novel, drug-like analogs of this scaffold — and BioMate routes it to the REINVENT4 Generative Lead Design workflow, fills in the parameters, and runs it on cloud compute. It's a four-step pipeline, and every step is real system behaviour. Step one validates your seed molecule — written as a SMILES string, the standard text notation for a chemical structure — and records its drug-likeness, how easy it is to make, and its molecular weight. Step two runs the learned REINVENT4 generator. Step three filters for drug-likeness, interference compounds, and novelty, then ranks what survives. Step four writes a ranked table, a 3D structure file, a score plot, and a readable report. You can also choose the design mode: de novo, building from scratch; scaffold decoration, adding groups around a fixed core; linker design, joining two fragments; or scaffold hopping, swapping the core for a fresh one.

---

## Step 5 — The scoring function · what you optimize toward

Here's the most important idea in the whole method: reinforcement learning optimizes exactly what you tell it to, and the scoring function is what you tell it. BioMate exposes three real choices. The default, qed_sa, rewards high drug-likeness and low synthetic-accessibility cost — it's fast, needs no target structure, and is a good general objective. The second, docking_gnina, scores a docking pose against a receptor you supply, so it's target-aware — but remember it's an in-silico estimate, not measured affinity. And the third, a custom TOML, lets you combine many components into your own reward — the most flexible route to true multi-parameter optimization. Whatever the reward rewards is what you'll get, so a weak or mis-specified objective produces high-scoring molecules that aren't actually better drugs.

---

## Step 6 — The engine · generate, score, improve

The generator is a trained model that writes a molecule one piece at a time — much like a language model writing a sentence — rather than picking from a fixed list. Over many rounds it proposes a batch, scores each molecule with your reward, and updates so the next batch leans toward higher scores. BioMate exposes the real controls for that loop. The number of epochs, n_steps, defaults to five hundred — about fifteen minutes on a GPU — with two hundred for a quick run. The batch size, how many molecules are sampled each epoch, defaults to a hundred and twenty-eight. Sigma and the learning rate govern how sharply the reward steers the policy and how large each update is. And temperature controls how adventurous the sampling is. One practical detail: this is a learned policy, so if the model or its prior is missing, the run fails loudly — it never quietly falls back to enumeration.

---

## Step 7 — The result · ranked, filtered candidates

Before anything is ranked, BioMate applies real medicinal-chemistry filters, so what you see isn't raw model output — it's candidates that survived quality checks. The filter stage keeps only molecules that are drug-like enough, easy enough to make, within the molecular-weight limit from Lipinski's well-known rule of thumb for oral drugs, free of the structural alerts that flag compounds likely to interfere with many lab assays, and genuinely different from your seed — then selects a diverse top set by chemical skeleton. The outputs are files you can open and hand off: a spreadsheet listing every accepted molecule with its score, drug-likeness, ease-of-synthesis, and weight; a 3D structure file of the top compounds, ready for docking or viewing; a plot of the score improving over the run; and a readable report with a grid of the structures and the exact settings behind the run.

---

## Step 8 — Using it responsibly

It matters how you read these results. Every generated molecule is a computational estimate — a structure the model believes will score well under your objective. None of it is measured. What you've gained is a prioritized, novel shortlist: a list of promising experiments, not a list of answers. So treat the top ranks as the molecules most worth a chemist's attention, a hypothesis queue rather than a verdict. Synthesize before you trust — a predicted score is not a real compound, and synthesizability filters reduce risk without guaranteeing a route. And validate at the bench: confirm activity, selectivity, and safety experimentally, because even a docking score is an estimate that has to be measured. Generative design narrows an impossible space to a testable few; the experiment, not the model, decides which are real.

---

## Step 9 — Exactly what you get

The capability is real and specific, and knowing exactly what it does is what makes it trustworthy for a program you'll defend. First, choose a good objective: RL optimizes the scoring function you give it, not the abstract idea of being a drug. The default qed_sa is built from cheap descriptors, and docking is an in-silico pose rather than measured affinity — so the ranking is only as good as the reward you pick. Second, there are two modes. The default is the real trained REINVENT4 policy; a BRICS enumeration baseline is also offered, but it's labeled plainly as a non-reinforcement-learning comparator, never dressed up as a training curve. And third, this is a design engine: it proposes and ranks novel, synthesizable structures aimed at your target. That hands your chemists the right molecules to make first.

---

## Step 10 — The value at a glance

The whole point is one sentence: you should be able to design new chemical matter toward an objective, rather than enumerate or hope. You state the goal and a seed scaffold, you choose the design mode, you pick the reward — drug-likeness, docking, or your own recipe — and you confirm the routed workflow with its reinforcement-learning parameters. BioMate runs REINVENT4's generator on cloud compute and gives you ranked candidates, three-dimensional structures, and a report you can defend. From an impossibly large chemical space down to a novel, filtered, testable shortlist — designed toward your objective. The candidates are hypotheses; the lab makes them real. Generative design, used correctly.
