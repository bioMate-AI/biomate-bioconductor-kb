# Binding free energy (relative BFE / FEP) — narration (EN)

One narration block per scene, in order, for edge-tts. Episode D4, "Drug-development models" track. Grounded in BioMate's real `openfe_rbfe` workflow — OpenFE Relative Binding Free Energy (RBFE), domain drug_discovery, engine OpenFE + OpenMM 8 (MIT), processes PREP → RBFE_SETUP → OPENFE_ANALYSIS, verified from the reviewed Nextflow + entrypoint (`backend/biomni_workflows/nextflow_nfcore/subworkflows/drug_discovery/openfe_rbfe/`). ΔΔG is read aloud as "delta-delta-G"; FEP is spelled "F-E-P". No invented ΔΔG values — accuracy is framed as a general method expectation, not a measured result.

---

## Step 1 — Title · which analog binds harder?

You have a lead compound and a handful of close analogs — the same scaffold, one group swapped. The question that governs the whole round is simple, and expensive to get wrong: which one binds the target more tightly? Relative binding free energy — F-E-P — answers that with physics, in silico, before anything is made. So you synthesize and assay the winners instead of the entire series. BioMate runs the real calculation, a workflow called openfe_rbfe, built on OpenFE and OpenMM, on cloud GPUs. In this episode we'll build the idea from the ground up — what the quantity is, why the method works, what you bring, and exactly what the workflow does.

---

## Step 2 — The problem this solves

Lead optimization is, at its heart, a ranking problem. You have one scaffold and many small variations, and you can't make them all. You need to know, before synthesis, which swap gains potency and which loses it — and that difference is often smaller than one kilocalorie per mole. This is exactly where fast methods fall short. Docking scores are good at the gross question — is this a binder at all — but they're unreliable for the fine, sub-kilocalorie ranking of close analogs. Meanwhile every compound you make is weeks of chemistry plus an assay, so making the wrong ones burns the round's time and budget. What you actually want is a prediction tied to real thermodynamics, accurate enough to order the series before the bench.

---

## Step 3 — The ideas you need first

Four ideas, and the whole method follows. First, delta-G: the binding free energy, how favorably a ligand binds — more negative means tighter, and it's the quantity that maps to potency. Second, delta-delta-G: F-E-P doesn't compute either absolute value; it computes the difference between two close analogs, and that difference is what ranks them. Third, the alchemical transformation: a non-physical path that gradually morphs one ligand into the other through a series of intermediate lambda states — the trick that makes the difference computable. And fourth, the thermodynamic cycle: you run that transformation both inside the pocket and free in solvent, and the cycle isolates the binding part while giving you an internal consistency check. Build a map, morph A into B along lambda windows in the pocket and in water, read the delta-delta-G from the difference.

---

## Step 4 — In BioMate · goal, workflow, GPU

Here's how it runs. You ask to rank your analogs by binding free energy, and BioMate routes to openfe_rbfe — relative binding free energy built on OpenFE and OpenMM 8, which is the open, peer-reviewed community standard for small-molecule alchemical F-E-P. This matters: it's the field-standard engine, not a bespoke approximation. The production calculation needs a GPU and hours of sampling, so it runs on BioMate's GPU Batch queue — you confirm once, and the work runs in the cloud. Under the hood it's three stages: prep, then setup, then the analysis that produces the number, with that last stage on the GPU.

---

## Step 5 — Inputs · what you bring

Because F-E-P is comparative, the inputs are a pair of related ligands in the same binding site. Three things. First, the receptor: the target protein structure as a PDB file, with the binding site defined by a bound pose — the starting structure matters, because F-E-P assumes it's right. Second, the ligand pair: ligand A is your reference, the known compound, and ligand B is the query analog you're testing, each supplied as an SDF; they must be close relatives — the same scaffold with a local change. And third, the network, which you don't have to build: LOMAP finds the atom-mapping between the two ligands and plans a minimal-spanning ligand network — the edges that F-E-P will actually compute. A whole series is just handled as a set of pairwise edges across that network.

---

## Step 6 — The calculation · what it actually simulates

The three stages are real and sequential. First, prep: RDKit standardizes both ligands and generates three-dimensional conformers, and the protein is prepared inside OpenFE's own handling. Second, setup: LOMAP builds the atom-mapping and the ligand network, then the alchemical protocol and its task graph are constructed — built, but not yet sampled, so there's deliberately no delta-delta-G at this stage. Third, the analysis: OpenMM runs molecular dynamics across the lambda windows on the GPU, and then MBAR gathers the per-edge delta-delta-G, with its standard error, from the overlapping states. The defaults are sensible and tunable — room temperature, a nanosecond of equilibration, five nanoseconds of production per window, eleven lambda windows, and three independent repeats to estimate the error. This is real sampling, not a scoring heuristic.

---

## Step 7 — The output · a ranked, defensible number

The result is a free-energy difference for each edge, and — crucially — the Monte-Carlo error that tells you whether to trust it. A negative delta-delta-G means the query analog binds more tightly than the reference; a positive one means it binds less tightly. The sign and the size are what order your series. Two things make this defensible. The error travels with the number: every delta-delta-G carries an MBAR uncertainty, so a tight, converged edge is distinguishable from a noisy one. And there's a quality gate — cycle closure: around a closed loop of three or more edges the differences should sum to zero, and the deviation is a convergence check. A single edge can't compute that, so it's honestly reported as "not computed," never as a fake pass. And when there's no GPU or not enough sampling, the workflow records a status and a null — it never invents a number.

---

## Step 8 — Using the result · decide, then confirm

F-E-P earns its cost by reshaping the synthesis queue. Make the analogs it ranks as gains; deprioritize the ones it ranks as losses. The round's chemistry effort goes where the physics says it will pay off. But it is a prediction, so the loop closes at the bench: the measured potency of the compounds you actually make is the ground truth — F-E-P narrows the list, the wet lab confirms the winners. And the workflow helps you trust it: a built-in validate option compares an edge against a published experimental delta-delta-G, using the OpenFE benchmark pairs such as Tyk2 and CDK2, so you can see the method's accuracy on your own setup. As a general expectation, well-converged small-molecule RBFE lands within roughly a kilocalorie per mole of experiment — enough to rank — but that depends on the system, the pose, the force field, and convergence, so it's checked, not assumed.

---

## Step 9 — The honest edges

F-E-P is powerful, and it is bounded — and knowing the boundaries is what makes it usable for decisions you'll defend. First, it is relative, not absolute: it gives the difference between congeneric analogs, ranking a series against a reference; it is not an absolute affinity, and it needs the ligands to be close relatives with a good atom-mapping. Second, it depends on the pose and the sampling: it assumes a correct starting structure and enough sampling to converge, and a wrong pose or under-sampling gives a confident but wrong answer — which is exactly why the standard error and the cycle-closure check are there. And third, it costs: production RBFE needs a GPU and hours of molecular dynamics per edge, and the accuracy depends on the force field and on convergence. This is a deliberate, expensive calculation with stated assumptions — not a quick filter, and not a black box.

---

## Step 10 — The value at a glance

The point in one sentence: before you spend a synthesis round, F-E-P tells you which analog is worth making. You bring a target structure and a congeneric pair; BioMate maps them, routes to openfe_rbfe on the GPU queue, samples the alchemical transformation across the lambda windows in the cloud, and returns a per-edge delta-delta-G with its uncertainty — ranking the series, with an honest null when it can't be computed. Then you prioritize synthesis by that ranking and validate the winners by assay. From a lead and its analogs to a physics-grounded decision about what to make — the uncertainty attached, and the number withheld when it can't be earned. Chemistry effort, spent where it pays.
