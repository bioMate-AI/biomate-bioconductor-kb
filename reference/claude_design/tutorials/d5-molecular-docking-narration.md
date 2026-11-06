# D5 — Molecular docking walkthrough narration (EN)

Track: Drug-development models. One block per timeline beat (10 scenes).
For edge-tts: acronyms are spelled where that reads more clearly aloud
(R-M-S-D, P-D-B, S-M-I-L-E-S, G-P-U, A-T-P). No numeric result values are
invented — the output is described by what it is, never by fabricated
scores or affinities.

---

## Step 1 — Title · does it fit the pocket?

The first question you ask of a new molecule and a target is the simplest one: could it even fit the binding site, and in what orientation? Molecular docking answers that before any assay. It searches for the ligand's best placement inside the pocket and scores each pose, so you can triage a long list down to the candidates worth pursuing. In this walkthrough we build the idea from the ground up — what the task is, the few concepts you need, and then the real engine BioMate runs. That engine is AutoDock Vina, the workflow named Docking Autodock Vina, in the drug-discovery domain, executed on managed cloud compute. Each idea beat teaches a concept; one beat shows it running on real product output.

---

## Step 2 — The problem this solves

Here is why docking exists. Early in a campaign you hold one target structure and anywhere from dozens to thousands of candidate molecules. You cannot solve a crystal structure for each, and wet binding assays cost time and material, so they belong on a shortlist, not the long list. What you need is a cheap, physics-aware way to predict whether a molecule can occupy the pocket, and how it would sit there, fast enough to run across the whole set. That prediction — a plausible bound pose and a comparable score for every candidate — is exactly the filter docking provides. It turns an unmanageable list into a ranked one you can act on.

---

## Step 3 — The ideas you need first

You do not need the scoring-function mathematics, only four concepts, in order. First, the pocket: the cavity on the protein where a ligand binds. Docking needs to know where to look, which we give it as a search box centred on that site. Second, the pose: one concrete way the ligand sits in the pocket — its position, its rotation, and the conformation of its rotatable bonds. Third, the score: a function that estimates binding affinity in kilocalories per mole, where a more negative value means a predicted tighter fit. Fourth, search: the engine samples many poses, scores each, and returns the best. Point it at the pocket, let it search, and read the ranked scores.

---

## Step 4 — In BioMate · goal to workflow

Here is how that happens in the product. There is no environment to set up and no software to license. You describe the goal in plain English — for example, dock this ligand S-M-I-L-E-S into my receptor P-D-B in the A-T-P pocket. BioMate routes the request to the real Docking Autodock Vina workflow and opens its panel for review. You bring the molecules as a SMILES list, the target as a receptor P-D-B file, and the pocket as a box centre and box size. The defaults are handled for you — exhaustiveness at eight, nine poses returned — and the search runs on managed cloud compute. As the Owner, a single confirmation launches the real AutoDock Vina calculation.

---

## Step 5 — Inputs you bring

Docking here is site-directed by default, which means you tell the engine where to look. Three inputs carry the run. The ligands come as a SMILES list — one molecule or many — from which the engine builds three-dimensional conformers. The target comes as a receptor P-D-B file, and the pocket as a box centre and a box size, the region the engine will sample inside. There is an optional fourth: a reference ligand SMILES, which switches on validation mode so the docked pose can be checked against the known crystal pose. And if you do not know the pocket, blind docking is available — Run Autosite detects cavities to define the box, or Run Diffdock With Smiles docks without a predefined box at all.

---

## Step 6 — The method · what it actually does

The method is concrete and sequential. First, preparation: each SMILES string is turned into a three-dimensional structure, and the receptor together with your box defines the grid the engine scores poses on. Second, search: Vina's optimizer explores positions, rotations, and rotatable-bond conformations inside the box, and the exhaustiveness setting — eight by default — controls how thorough that exploration is. Third, score and rank: every kept pose receives a Vina binding-affinity score in kilocalories per mole, and the requested number of poses — nine by default — is returned, ordered from most negative, the best-looking fit. In validation mode, a reference ligand is added and the engine reports the pose's R-M-S-D to the crystal structure, where a deviation of two angstroms or less is the conventional pass.

---

## Step 7 — The output · ranked poses with scores

The result is a set of placed poses for each ligand you docked, ranked by a Vina binding-affinity score in kilocalories per mole, where a more negative value is the predicted tighter fit. Crucially, the pose travels with the score: you also get the three-dimensional coordinates of each placement, so you can see how and where the ligand was positioned, which is half of the interpretation. When you supplied a reference ligand, the pose additionally carries its R-M-S-D to the known crystal pose. If the engine recovered that geometry within two angstroms, the scoring on related ligands becomes far more credible than it would from a blind setup. You never receive a bare number stripped of its context.

---

## Step 8 — Using the result · triage, then confirm

Docking earns its keep by cutting a long list down to a credible shortlist. Rank your candidates by their best Vina score, set aside the obvious non-binders, and keep the top poses whose geometry makes chemical sense inside the pocket. From there the shortlist escalates. To rank close analogs by potency, docking is deliberately too coarse — hand those compounds to the free-energy workflow, the sibling Binding Free Energy tutorial, for the fine ranking. And whatever survives, the pose and score remain predictions: co-crystallography and binding assays are the ground truth. A sound habit is to run validation mode first on a ligand with a known pose, confirming the box and setup before trusting scores on new molecules.

---

## Step 9 — Honest limits · what you get, precisely

Being precise about scope is what makes docking trustworthy. Three limits matter. First, it is a gate, not a ruler: Vina scores separate binders from non-binders well, but are unreliable for the fine affinity ranking of close analogs — for that, use the F-E-P or R-B-F-E free-energy workflow in the sibling tutorial. Second, the receptor is rigid by default, so induced fit, where a pocket rearranges around a ligand, is largely not captured and can be mis-scored. Third, a good score is a hypothesis of a pose, not a measured affinity, and blind docking without a known pocket is lower-confidence than docking into a defined site. Know these edges, and docking is a fast, honest triage rather than a false oracle.

---

## Step 10 — Closing · at a glance

So, molecular docking at a glance: a target and a list of molecules in, ranked and placed poses out. Point the engine at the pocket with a box, let AutoDock Vina search for low-energy poses, and read the ranked affinity scores, more negative being the better-looking fit. BioMate routes your plain-English goal to the Docking Autodock Vina workflow, runs the real engine on managed compute, and returns each pose with its score and coordinates — plus an R-M-S-D to a reference crystal pose when you run validation mode. Triage by score, escalate the shortlist to free energy or confirm at the bench, and remember the honest edges: a gate not a ruler, rigid by default, a pose hypothesis rather than a measured number.

---
