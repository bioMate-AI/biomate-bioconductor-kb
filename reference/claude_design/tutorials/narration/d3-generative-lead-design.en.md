# Generative lead design — narration (EN)

One narration block per scene, in order, for edge-tts. Episode D3. Grounded in BioMate's real REINVENT4 Generative Lead Design workflow (nextflow_nfcore/subworkflows/drug_discovery/reinvent4_lead_design/main.nf; search_workflow + get_workflow_spec, captured 2026-10-05). REINVENT4: Loeffler et al., J. Cheminform. 2024, 16:20 (MolecularAI / AstraZeneca, Apache-2.0).

---

## Step 1 — Title · generative lead design with reinforcement learning

Most computational chemistry starts from a library you already have, and screens it for winners. Generative design works the other way around: instead of picking from a list, it invents new molecules aimed at a goal you state. BioMate runs REINVENT4, a reinforcement-learning generator from MolecularAI and AstraZeneca, to propose novel, drug-like candidates — and then filters and ranks them. You describe the scaffold and what "good" means, and BioMate produces structures you can take to synthesis. In this walkthrough we'll follow the real workflow the whole way through, and be honest about what the results are and aren't.

---

## Step 2 — The problem this solves

The space of synthesizable, drug-like molecules is enormous — commonly estimated near ten to the sixtieth power. That's more than any library, any high-throughput screen, or any amount of compute could ever cover. You simply cannot list it. And brute-force enumeration around a scaffold doesn't rescue you: decorating one core with a handful of fragments already produces millions of analogs, and most of them are undrug-like, hard to make, or trivial. So the real need isn't more enumeration — it's a way to search that vast space intelligently, proposing only candidates that are novel, synthesizable, and actually aimed at your objective.

---

## Step 3 — The ideas you need first

Four plain words describe the whole method. First, a generative model: a policy trained on known chemistry that writes new molecules, one piece at a time — a trained model, not a lookup table. REINVENT4 is that generator. Second, a scoring function: a reward that judges each proposed molecule — its drug-likeness, how easy it is to make, or how well it docks. That scoring function is your objective, made numeric. Third, the reinforcement-learning loop: generate, score, and learn, over many rounds, so the generator leans toward higher-scoring molecules with experience. And fourth, multi-parameter optimization: the reward can combine several goals at once, so candidates balance potency, drug-likeness, and synthesizability rather than chasing just one.

---

## Step 4 — In BioMate · plain goal to workflow to cloud

You don't configure a neural network. You state the intent in plain English — design novel, drug-like analogs of this scaffold — and BioMate routes it to the REINVENT4 Generative Lead Design workflow, fills in the parameters, and runs it on cloud compute. It's a four-step pipeline, and every step is real system behaviour. Step one validates your seed SMILES with RDKit and records its drug-likeness, synthetic accessibility, and molecular weight. Step two runs the learned REINVENT4 generator. Step three filters for drug-likeness, interference compounds, and novelty, then ranks what survives. Step four writes a ranked table, an SDF of three-dimensional structures, a score plot, and a readable report. You can also choose the design mode — de novo, scaffold decoration, linker design, or scaffold hopping.

---

## Step 5 — The scoring function · what you optimize toward

Here's the most important idea in the whole method: reinforcement learning optimizes exactly what you tell it to, and the scoring function is what you tell it. BioMate exposes three real choices. The default, qed_sa, rewards high drug-likeness and low synthetic-accessibility cost — it's fast, needs no target structure, and is a good general objective. The second, docking_gnina, scores a docking pose against a receptor you supply, so it's target-aware — but remember it's an in-silico estimate, not measured affinity. And the third, a custom TOML, lets you combine many components into your own reward — the most flexible route to true multi-parameter optimization. Whatever the reward rewards is what you'll get, so a weak or mis-specified objective produces high-scoring molecules that aren't actually better drugs.

---

## Step 6 — The engine · generate, score, improve

The generator is a trained autoregressive policy. It writes molecules token by token — it does not enumerate a list. Over many rounds it proposes a batch, scores each molecule with your reward, and updates so the next batch leans toward higher scores. BioMate exposes the real controls for that loop. The number of epochs, n_steps, defaults to five hundred — about fifteen minutes on a GPU — with two hundred for a quick run. The batch size, how many molecules are sampled each epoch, defaults to a hundred and twenty-eight. Sigma and the learning rate govern how sharply the reward steers the policy and how large each update is. And temperature controls how adventurous the sampling is. One honest detail: this is a learned policy, so if the model or its prior is missing, the run fails loudly — it never quietly falls back to enumeration.

---

## Step 7 — The result · ranked candidates, filtered honestly

Before anything is ranked, BioMate applies real medicinal-chemistry filters, so what you see isn't raw model output — it's candidates that survived quality checks. The filter stage keeps only molecules above a drug-likeness threshold, below a synthetic-accessibility limit, within Lipinski's molecular-weight bound, free of pan-assay-interference alerts, and sufficiently novel relative to your seed — then selects a diverse top set by scaffold. The outputs are files you can open and hand off: a CSV listing every accepted molecule with its score, drug-likeness, synthetic accessibility, and weight; an SDF of the top compounds as three-dimensional conformers, ready for docking or viewing; a score-versus-epoch plot; and an HTML report with a structure grid and the configuration behind the run.

---

## Step 8 — Using it responsibly

It matters how you read these results. Every generated molecule is a computational estimate — a structure the model believes will score well under your objective. None of it is measured. What you've gained is a prioritized, novel shortlist: a list of promising experiments, not a list of answers. So treat the top ranks as the molecules most worth a chemist's attention, a hypothesis queue rather than a verdict. Synthesize before you trust — a predicted score is not a real compound, and synthesizability filters reduce risk without guaranteeing a route. And validate at the bench: confirm activity, selectivity, and safety experimentally, because even a docking score is an estimate that has to be measured. Generative design narrows an impossible space to a testable few; the experiment, not the model, decides which are real.

---

## Step 9 — The honest edges

The capability is real and specific, and knowing its limits is what makes it trustworthy for a program you'll defend. First, it's bound by the reward: RL optimizes the scoring function, not the abstract idea of being a drug. The default qed_sa is built from cheap descriptors, and docking is an in-silico pose rather than measured affinity — a poor objective yields poor leads, confidently. Second, there are two honest modes. The default is the real trained REINVENT4 policy; a BRICS enumeration baseline is also offered, but it's labeled plainly as a non-reinforcement-learning comparator, never dressed up as a training curve. And third, there's no wet lab here: the workflow proposes and ranks structures, but it does not synthesize them, test toxicity, or confirm a synthetic route. Those remain experimental work. This is a design engine — not an oracle.

---

## Step 10 — The value at a glance

The whole point is one sentence: you should be able to design new chemical matter toward an objective, rather than enumerate or hope. You state the goal and a seed scaffold, you choose the design mode, you pick the reward — drug-likeness, docking, or your own recipe — and you confirm the routed workflow with its reinforcement-learning parameters. BioMate runs REINVENT4's generator on cloud compute and gives you ranked candidates, three-dimensional structures, and a report you can defend. From an impossibly large chemical space down to a novel, filtered, testable shortlist — designed toward your objective and honest about its limits. The candidates are hypotheses; the lab makes them real. Generative design, used correctly.
