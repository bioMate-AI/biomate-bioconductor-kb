# Structural biology (structure prediction, docking, homology & dynamics)

> One-line promise: fold a protein from its sequence, dock a ligand into it, and
> read the confidence honestly — BioMate runs **structure prediction**
> (AlphaFold3 / Boltz-2 / AlphaFold2 / OpenFold2) and **protein–ligand docking**
> (AutoDock Vina, with DiffDock blind docking) on the cloud, and renders the
> resulting 3-D model with its **per-residue pLDDT confidence** in an in-app
> viewer. Structure/sequence **homology search** (Foldseek, MMseqs2) and
> **molecular dynamics** (GROMACS) are wired and routable but **not yet verified
> end-to-end** — this chapter tells you exactly which is which.
> For: **structural biologists**, **computational / medicinal chemists**, and
> **protein engineers** who want a model + a docked pose + a confidence number
> without standing up AlphaFold, Vina, or a GROMACS box themselves. No coding.

<!--
P1 chapter (largest NEW writing; several parts smoke-test-gated → verified hard). Every "supported"
claim below is green in coverage-ledger.md § "Structural biology".

HONESTY RULE FOR THIS CHAPTER (this domain is the biggest honesty risk in the book):
- SUPPORTED (present as working): structure prediction (Boltz-2 / AlphaFold2 / OpenFold2 via the
  BioNeMo inference API; AlphaFold3 via the alphafoldserver.com API in structure_prediction_docking)
  and docking (AutoDock Vina, DiffDock rescoring). These genuinely run.
- WIRED-BUT-UNVERIFIED (mark clearly, → Appendix E): Foldseek (T17), MMseqs2 (T18), GROMACS-MD (T19),
  AlphaFold-Multimer / Boltz-multimer (T20) are E2E-UNVERIFIED / smoke-test-gated
  (evaluation/comparison/run_phase1.py:76-88, unverified=True). qc_evidence.yaml:358-361 also labels
  structure_prediction + docking QC gates as "Unwired-but-cited domains … no auto-loop bridge entry yet"
  — so there is NO auto-loop remediation in this domain (unlike ADMET). Say so.
- The in-app PAE heatmap component exists but is NOT wired into the .pdb/.cif routing today
  (step-output-preview renders pLDDT only). Documented as such.
- No Batch runs; live numeric outputs are ledger tier L / ⏳.
Cross-refs: II.4 (reference data / structure indexes, BioNeMo ids, Foldseek/MMseqs2 unverified),
I.8 (structure viewer + PlddtChart real capture pattern).
-->

## What this is for

This is the **"sequence → model → pose"** path. You bring a **protein sequence**
(FASTA, or inline amino acids) and, for docking, a **ligand** (SMILES or SDF);
BioMate predicts the **3-D structure** with a modern folding model, runs
**protein–ligand docking** into it, and returns the model, the docked poses, and
the **confidence signals** you need to decide whether to trust them.

Two things genuinely run end-to-end today, and this chapter presents only those
as supported:

1. **Structure prediction** — fold a protein (or protein/RNA/DNA/ligand complex)
   from sequence. Boltz-2, AlphaFold2 and OpenFold2 run through the hosted
   **BioNeMo inference API** (`bionemo_client.py:65-108`); AlphaFold3 runs through
   the `alphafoldserver.com` API inside the structure-prediction-docking pipeline
   (`structure_prediction_docking/main.nf:75-231`). Output: a **PDB/mmCIF model**
   plus **pLDDT** (per-residue confidence) and, where the model emits it,
   **PAE** (pairwise aligned error).
2. **Docking** — dock a ligand into the predicted (or supplied) structure with
   **AutoDock Vina**, with **DiffDock** as a diffusion-model blind-docking pass in
   parallel. Output: **ranked poses** with binding scores
   (`docking_autodock_vina/main.nf`; `structure_prediction_docking/main.nf:238-433`).

Two more families are **wired and routable but not yet verified end-to-end** — and
this chapter is scrupulous about the line between them:

3. **Homology search** — **Foldseek** (structure-based, via 3Di) and **MMseqs2**
   (sequence-based) search a query against a database. Both exist as workflows in
   the catalog; **neither has passed its benchmark** (Foldseek = task **T17**,
   MMseqs2 = task **T18**, both `unverified=True` in
   `evaluation/comparison/run_phase1.py:76-79`).
4. **Molecular dynamics** — a **GROMACS** protein–ligand MD + MM-GBSA pipeline
   exists (`gromacs_protein_md/main.nf`), but MD (**T19**) and multimer complex
   prediction (**T20**) are `unverified=True` (`run_phase1.py:85-88`).

The through-line of the chapter is **interpretation, not a metrics dump**: pLDDT,
PAE and the Vina score are each explained as "what this number means and what to
do next," and you end on a decision (this model, this pose, this confidence), not
a job tree.

> **Pitfall — the honest edge of this domain.** BioMate can *fold* and *dock*
> today. It can *route to and launch* Foldseek, MMseqs2 and GROMACS, but their
> end-to-end verification is **pending** — treat a first run of those as *your*
> validation against a gold standard, not a proven BioMate result. See
> "What's not covered" and Appendix E. This is the same three-state honesty
> (wired · verified · not built) used in [II.4 Reference data & indexes](../data/II04-reference-data-and-indexes.md).

## Use cases

| Goal (researcher's words) | Workflow(s) / chain | Inputs | Outputs (artifact) | Lane |
|---|---|---|---|---|
| "Fold this protein from its sequence" | Structure prediction — **Boltz-2** / **AlphaFold2** / **OpenFold2** (BioNeMo inference) | Protein FASTA / inline sequence | PDB/mmCIF model + **pLDDT** (+ PAE where emitted) + confidence JSON | Cloud (hosted BioNeMo API / GPU) |
| "Fold a protein–ligand complex and estimate affinity" | **Boltz-2** complex prediction | Boltz YAML (protein + ligand) | mmCIF complex + `boltz_summary.json` + `qc_metrics.json` (pLDDT / PAE) | Cloud (GPU) |
| "Predict the structure, then dock this ligand into it" | `structure_prediction_docking` (**AlphaFold3 → DiffDock ‖ AutoDock Vina**) | Sequence FASTA + ligand SDF | Model (CIF/PDB) + PAE + **DiffDock poses** + **Vina poses** + score JSONs | Cloud (GPU) |
| "Dock these ligands into my receptor and rank the poses" | `docking_autodock_vina` | Receptor PDB + SMILES list (+ box) | Ranked poses (`.pdbqt`) + `docking_autodock_vina_results.json` + `qc_metrics.json` | Cloud (AWS Batch) |
| "Get the AlphaFold structure for this UniProt / read a model I have" | AlphaFold DB fetch (II.4) → in-app **structure viewer** | UniProt ID, or any `.pdb`/`.cif` | 3-D model + pLDDT chart in-app | Instant (fetch) / Instant (viewer, no run) |
| "Find proteins with a similar fold / similar sequence" | **Foldseek** (structure) / **MMseqs2** (sequence) — *wired, not yet verified* | Query structure or FASTA + target DB | Hit table (`.m8`) + summary JSON | Cloud — **unverified (T17/T18)** |
| "Run MD on this protein–ligand complex" | `gromacs_protein_md` (GROMACS + MM-GBSA) — *wired, not yet verified* | Receptor PDB + ligand SDF/MOL2 | Trajectory + ΔG_bind + RMSD/RMSF — **unverified (T19)** | Cloud (GPU) — **unverified** |

> **Pitfall — structure prediction is folding, not threading or homology
> modelling.** These models predict a structure *de novo* from sequence (and an
> MSA). If what you actually want is "find me a known homolog," that is
> **homology search** (Foldseek / MMseqs2, rows 6) — a different, and here
> *unverified*, path.

## How to ask

BioMate routes on intent. The words that matter are **"predict structure / fold /
AlphaFold / Boltz"** for prediction, and **"dock / docking / Vina / pose"** for
docking, plus a hint of your inputs (sequence vs. structure; with or without a
ligand).

Fold a protein:

> "Predict the 3-D structure of this protein sequence with Boltz-2:
> `MKTAYIAKQR…`"

> "Fold EGFR (this FASTA) and tell me the pLDDT."
> *(the verified routing probe for structure prediction, T10 — Boltz-2,
> `run_phase1.py:83-84`.)*

Fold a complex and estimate affinity:

> "Predict the structure of this protein–ligand complex and give me the binding
> confidence." *(routes to Boltz-2 complex mode; supply a Boltz YAML.)*

Predict then dock (the end-to-end chain):

> "Predict the structure for this sequence, then dock this ligand (SDF) into it —
> use both DiffDock and AutoDock Vina."

Dock into a receptor you already have:

> "Dock these SMILES into EGFR (PDB 1M17) and rank the poses by Vina score."
> *(the docking routing probe, T11 — AutoDock Vina, `run_phase1.py:64-65`.)*

Homology search (routable, but treat as unverified):

> "Find proteins with a similar fold to this PDB." → Foldseek (T17, unverified).
> "Find homologous sequences for this FASTA." → MMseqs2 (T18, unverified).

**Disambiguation to avoid:**

- **Predict vs. dock vs. search.** "Structure" alone is ambiguous. *"predict /
  fold"* → structure prediction; *"dock a ligand"* → docking; *"find similar /
  homologous"* → Foldseek/MMseqs2 (unverified). Name the verb.
- **Which folding model.** Boltz-2 (MIT-licensed, handles protein/RNA/DNA/ligand
  complexes + affinity) is the general default; AlphaFold2/OpenFold2 are the
  classic single-chain folders; AlphaFold3 (server API) is used inside the
  predict→dock chain. Name a model if you have a preference, otherwise routing
  picks one.
- **Sequence vs. structure input for search.** Foldseek can start from a 3-D
  structure *or* from sequence (it predicts the 3Di alphabet with ProstT5 —
  `foldseek_structure_search/main.nf:16-33,66-77`). Say which you have.
- **A ligand is required for docking, not for folding.** "Dock" needs a ligand
  (SMILES/SDF) *and* a receptor. If you give only a sequence, you get a fold, not
  a pose.

## Tools & workflows behind this

| Tool / workflow | Role | Where (verified) |
|---|---|---|
| **Boltz-2** structure prediction | Fold protein/RNA/DNA/ligand complexes; MIT-licensed; emits pLDDT/PAE + affinity | `.../structural_biology/boltz_structure_prediction/main.nf:59-185`; BioNeMo route `bionemo_client.py:70,107` |
| **AlphaFold2 / OpenFold2** | Classic single-chain folding via hosted BioNeMo NVCF functions | `bionemo_client.py:68,71,105-108`; catalog per [II.4](../data/II04-reference-data-and-indexes.md) |
| **AlphaFold3** structure prediction | Fold via `alphafoldserver.com` API (server mode) or local weights; emits CIF/PDB + PAE + scores | `.../drug_discovery/structure_prediction_docking/main.nf:75-231` |
| **AutoDock Vina** docking | Classical docking; ranked poses + affinities; pocket from AF3 PAE in the chain | `.../pharmacology/docking_autodock_vina/main.nf:17-48`; `structure_prediction_docking/main.nf:318-433` |
| **DiffDock** blind docking | Diffusion-model docking (no pocket needed); ranked poses by confidence | `structure_prediction_docking/main.nf:238-311`; `.../pharmacology/run_diffdock_with_smiles/main.nf` |
| BioNeMo inference dispatch | Enumerates + calls Boltz-2/AF2/OpenFold2/Evo2 (self-host or NVCF NIM) | `bionemo_client.py:65-116`; Models API `models_inference.py:77-122` |
| pLDDT extraction | Reads per-residue pLDDT from B-factor / model output for the viewer chart | `models_inference.py:999-1053` |
| **Foldseek** structure search *(wired, unverified)* | 3Di structure search vs. prebuilt AFDB/SwissProt/PDB index (ProstT5 for seq queries) | `.../structural_biology/foldseek_structure_search/main.nf`; **T17** `run_phase1.py:76-77` |
| **Foldseek/HMMER web-API search** *(wired, unverified)* | Structural + sequence search via `search.foldseek.com` / EBI HMMER — no local DB | `.../drug_discovery/alphafold_db_search/main.nf:1-45`; **T17** |
| **MMseqs2** sequence search *(wired, unverified)* | Fast sequence homology vs. a prebuilt target DB (UniRef/Swiss-Prot) | `.../proteomics/mmseqs2_sequence_search/main.nf`; **T18** `run_phase1.py:78-79` |
| **GROMACS** protein–ligand MD *(wired, unverified)* | GAFF2 param → solvate → EM → NVT → NPT → production MD → MM-GBSA ΔG_bind | `.../drug_discovery/gromacs_protein_md/main.nf:1-60`; **T19** `run_phase1.py:85-86` |
| In-app viewers | 3-D model (3Dmol) + per-residue pLDDT chart; PAE heatmap component exists | `frontend/client/src/components/step-output-preview.tsx:1032,1067,1167`; `viewers/plddt-chart.tsx`; `viewers/pae-heatmap.tsx` |

> **License** — **Boltz-2 is MIT-licensed** (`boltz_structure_prediction/main.nf:6`),
> so its predictions and complexes are yours to use freely. **AlphaFold3** runs
> through the `alphafoldserver.com` API and is governed by that service's terms
> (an `AF3_API_TOKEN` is required — `structure_prediction_docking/main.nf:105-112`);
> AlphaFold2/OpenFold2 run through the hosted BioNeMo NVCF functions. AutoDock Vina
> (Apache-2.0) and DiffDock are open-source. Predicted structures are models, not
> experimental coordinates — read the confidence before you trust the geometry.

> **Note — IDs verified against the catalog.** In `galaxy_ai_tools.db` the
> folding/docking/search tools resolve to: **boltz_structure_prediction (id
> 12853)**, **Structure Prediction Docking (id 10644)**, **Docking Autodock Vina
> (id 12824)**, **foldseek_structure_search (id 14456)**, **mmseqs2_sequence_search
> (id 14462)**, and **AlphaFold DB Search (id 12647)** — consistent with
> [II.4](../data/II04-reference-data-and-indexes.md). This chapter grounds claims
> on the workflow **source-file paths** (the stable reference), with these IDs
> confirmed by direct DB query.

## QC gates & how to read them

Structural-biology QC answers one question for a scientist: **"can I trust this
model / this pose, and where?"** The confidence numbers are the whole point of a
prediction — a fold you can't calibrate is a liability. Every threshold below is
stated **from code**, with its citation and provenance tier.

> **Pitfall — there is NO auto-loop remediation in this domain.** Unlike the
> ADMET chapter, the structure-prediction and docking QC gates are **advisory,
> surfaced-for-you** gates, not an automatic re-run loop.
> `qc_evidence.yaml:358-361` labels these explicitly as *"Unwired-but-cited
> domains … no auto-loop bridge entry yet."* The gate metrics are computed and
> shown; acting on them (deeper MSA, more recycling, wider docking box) is a
> decision you make and re-run manually.

### Structure-prediction confidence gates

| Gate | Threshold | What a fail means | Enforced / cited where |
|---|---|---|---|
| **Mean pLDDT** | **≥ 70** recommended for downstream docking | Below 70 the fold is low-confidence; whole regions may be wrong. pLDDT bands: >90 high, 70–90 well-modelled, 50–70 low, <50 often disordered. | `qc_evidence.yaml:364-376` — **GOLD** (Jumper 2021); metric emitted `boltz_structure_prediction/main.nf:137-162` |
| **Confident fraction** | **≥ 0.70** (advisory below) | Fewer than 70% of residues are confidently modelled (pLDDT > 70). | `qc_evidence.yaml:377-393` — **SILVER** (Tunyasuvunakool 2021; 0.70 is operational); wired `main.nf:173-176` |
| **Max inter-domain PAE** | **≤ 8 Å** (advisory above; skipped single-domain) | The model places domains unreliably relative to each other — the *relative* arrangement is untrustworthy even if each domain folds well. | `qc_evidence.yaml:394-412` — **SILVER** (Tunyasuvunakool 2021; ≤8 Å operational); wired `main.nf:177-180` |

### Docking gates

| Gate | Threshold | What a fail means | Enforced / cited where |
|---|---|---|---|
| **Vina binding score** | flags **> −7 kcal/mol** (advisory) | Weak predicted binding — a "hit" heuristic, not a hard line. | `qc_evidence.yaml:330-343` — **BRONZE** (Trott & Olson 2010 introduces Vina but prescribes *no* cutoff; −7 is community heuristic); Boltz/docking QC parse `qc_trace_monitor.py:1655,1673` |
| **Valid poses** | flags **< 3** poses | Too few valid poses for consensus scoring. | `qc_evidence.yaml:345-356` — **BRONZE** (community practice, no peer-reviewed minimum) |

**How to read each, as a scientist:**

- **pLDDT** — this is *the* per-residue confidence. Read it spatially, not as one
  number: a mean pLDDT of 85 with a floppy low-pLDDT loop is a good core with an
  uncertain tail; colour the model by pLDDT and believe the blue, doubt the red.
  The gate (≥ 70 mean) is the GOLD, paper-anchored part; the confident-fraction
  0.70 cutoff is BioMate's operational (SILVER) reading, not a value from the
  paper.
- **PAE** — pLDDT tells you whether a residue is placed well *locally*; PAE tells
  you whether two parts are placed well *relative to each other*. A multi-domain
  model with high inter-domain PAE means "each domain is fine, but don't trust how
  they're arranged" — critical before you dock into an inter-domain pocket.
- **Vina score** — a more-negative kcal/mol is stronger predicted binding. The
  −7 line is a **BRONZE community heuristic**, not a law (Trott & Olson 2010 gives
  no cutoff). Rank your poses by it; don't treat −6.8 as a hard fail.
- **Valid poses** — fewer than 3 poses undermines consensus. The remedy is a wider
  box or lower energy cutoff, not a looser score threshold.

> **QC gate — trust the confidence, not the pretty cartoon.** A rendered model
> always *looks* like a structure. The only thing that tells you whether it *is*
> one is the pLDDT/PAE. Read the confidence chart before you build a hypothesis on
> the geometry — a smooth cartoon over a red-pLDDT region is confident-looking
> nonsense.

### What "fixing" a low-confidence result looks like here

The remediation notes are emitted for you to act on (no auto-loop):

- **Low pLDDT / confident fraction** → increase `recycling_steps` (e.g. 3 → 6) or
  supply a deeper MSA (ColabFold MSA server) — `qc_evidence.yaml:374-376,391-393`;
  Boltz `--recycling_steps` / `--use_msa_server` (`boltz_structure_prediction/main.nf:75-85`).
- **High inter-domain PAE** → deepen the MSA, increase recycling, or treat the
  domains independently (`qc_evidence.yaml:410-412`).
- **Weak docking / few poses** → raise Vina `exhaustiveness` (8 → 32), widen the
  search box (`qc_evidence.yaml:341-343,354-356`;
  `docking_autodock_vina/main.nf:12-13`).

## Worked example (gold standard)

**Goal.** Fold a well-characterised target from sequence, then dock a known ligand
into it, and read the artifacts as a structural biologist / chemist would.

**Target.** **EGFR kinase domain**, whose experimental structure with the
inhibitor **erlotinib** is **PDB 1M17** — the reference used by the evaluation
harness (structure-prediction task **T10**: EGFR sequence → PDB 1M17; docking task
**T11**: EGFR PDB 1M17 + ligands; `run_phase1.py:64-65,83-84`). 1M17 is the natural
sanity anchor: a good fold should recover the kinase geometry, and a good dock
should place erlotinib in the ATP pocket.

> **Note (verification tier).** Structure prediction (Boltz-2, T10) and docking
> (AutoDock Vina, T11) are the **code-verified (C)** supported paths of this
> chapter. Both are **GPU/Batch** runs; a fresh live run to reproduce exact
> numeric outputs (RMSD-to-1M17, Vina kcal/mol) is **pending (L / ⏳)** and is not
> fired speculatively — GPU runs cost real money and the plan forbids speculative
> execution. EGFR/1M17 is the harness's intended target; a machine-readable gold
> entry in `evaluation/tutorial_demos/gold_standards.yaml` for structural biology
> is a **registry gap** to close (as with cryo-EM).

**Prompt:**

> "Predict the structure of this EGFR kinase-domain sequence with Boltz-2, then
> dock erlotinib into it with AutoDock Vina and rank the poses."

**What comes back and how to read it:**

- **The model + pLDDT.** Boltz-2 returns the mmCIF/PDB model and
  `qc_metrics.json` with `mean_plddt`, `confident_fraction` and (for multi-domain
  cases) `max_pae` (`boltz_structure_prediction/main.nf:137-182`). Open the model
  in the in-app viewer, colour by pLDDT: the kinase core should be high-confidence
  (blue), and mean pLDDT ≥ 70 clears the recommended gate. *This is your first
  decision point — a low-pLDDT core means stop and deepen the MSA before docking.*
- **The docked poses.** AutoDock Vina writes ranked poses (`.pdbqt`) and a summary
  with `best_affinity_kcal_mol` and per-mode affinities
  (`structure_prediction_docking/main.nf:409-422`;
  `docking_autodock_vina/main.nf`). DiffDock, running in parallel, contributes
  blind-docking poses ranked by confidence (`main.nf:290-301`). Interpretation:
  the top Vina pose should sit in the ATP pocket with a strong (more-negative)
  score; ≥ 3 valid poses clears the pose-count gate.
- **The honest reads.** pLDDT/PAE calibrate the *model*; the Vina score calibrates
  the *pose*. You end on a decision — *this fold (mean pLDDT ≥ 70, confident core),
  this pose (Vina best-affinity, in-pocket) — proceed* — which is the
  "gold-standard-comparable artifact" the tutorial-demo plan mandates, not a
  process tree.

**The artifact.** A predicted model (`.mmcif`/`.pdb`) + `boltz_summary.json` +
`qc_metrics.json` (pLDDT / confident-fraction / PAE) + ranked docked poses
(`.pdbqt`) + Vina/DiffDock score JSONs.

## Outputs & visualization

Structure and docking outputs render in the after-run panel's Outputs tab through
the in-app viewer taxonomy (`frontend/client/src/components/step-output-preview.tsx`);
the mapping below is by file type. Cross-referenced from
[I.8 Outputs, viewers & interactive panels](../modules/I08-outputs-viewers-interactive.md),
which is where the **structure viewer has a real screenshot-capture pattern**.

| Output | File | In-app viewer | When to go interactive |
|---|---|---|---|
| Predicted model | `*.pdb` / `*.mmcif` / `*.cif` | **InlineStructureViewer** — 3Dmol cartoon/stick/sphere/line; renders the **pLDDT chart** beside the model when the B-factor column holds confidence (`step-output-preview.tsx:98,1032,1067,1167`) | Open in ChimeraX/PyMOL for figures, mutagenesis, or model building |
| Per-residue confidence | pLDDT in the model's B-factor / `qc_metrics.json` | **PlddtChart** — per-residue bars, 4-band colouring, click-to-centre the 3-D view (`viewers/plddt-chart.tsx`; `centreOnResidue` `step-output-preview.tsx:1119`) | Read the confident vs. disordered spans inline — no export |
| Pairwise aligned error | `*_pae.json` | **PaeHeatmap** component exists (`viewers/pae-heatmap.tsx`) **but is not wired into the .pdb/.cif routing today** — see pitfall below | Read PAE from the raw JSON / plot externally until wired |
| Docked poses | `*_vina_poses.pdbqt`, DiffDock `rank*.sdf` | Load the receptor + pose in the structure viewer; scores in the summary table | Open poses in PyMOL for interaction analysis |
| Score summaries | `*_vina_summary.json`, `*_diffdock_summary.json`, `docking_autodock_vina_results.json` | **Table viewer** — per-mode affinities / confidences | Export CSV for SAR triage |
| Fold/dock QC | `qc_metrics.json`, `boltz_summary.json` | **Findings** section (pLDDT / confident-fraction / PAE / best-affinity verdicts) | — |

> **Tip — the structure viewer needs no plugin.** InlineStructureViewer renders
> the model and its pLDDT chart in-browser (3Dmol.js, dynamically imported) the
> moment the run finishes (`step-output-preview.tsx:1067`). Colour by pLDDT and
> eyeball the confident core before you export anything to ChimeraX/PyMOL. The I.8
> chapter documents this viewer's live capture pattern.

> **Pitfall — the PAE heatmap is built but not wired to structure files yet.** The
> `PaeHeatmap` component exists (`viewers/pae-heatmap.tsx`), but
> `step-output-preview.tsx` does **not** currently detect a `*_pae.json` sidecar
> next to a `.pdb`/`.cif` and pair it — so today you get the **pLDDT chart, not an
> in-app PAE heatmap**. The PAE data is still produced by the workflow
> (`*_pae.json`); read it from the JSON until the sidecar routing lands. (Roadmap
> — Appendix E.)

## Pitfalls & tips

> **Pitfall — a confident-looking cartoon is not a confident model.** Always read
> pLDDT (and PAE for multi-domain) before you trust the geometry. The gate is mean
> pLDDT ≥ 70 (GOLD, Jumper 2021, `qc_evidence.yaml:364-376`); low-pLDDT regions
> are the model guessing.

> **Tip — pick the folding model for the job.** Boltz-2 (MIT) handles
> protein/RNA/DNA/ligand complexes *and* gives an affinity estimate; AlphaFold2 /
> OpenFold2 are the classic single-chain folders; AlphaFold3 (server API) drives
> the predict→dock chain. Name a model if you care; otherwise routing defaults to
> a general folder.

> **Pitfall — deeper MSA and more recycling are your levers, not a lower gate.**
> When pLDDT/PAE disappoint, the fix is more signal (deeper MSA, more recycling
> steps), not moving the threshold. Boltz exposes `--use_msa_server` and
> `--recycling_steps` (`boltz_structure_prediction/main.nf:75-85`).

> **Tip — widen the box / raise exhaustiveness for docking.** A weak Vina score or
> too-few poses usually means the search was too tight. Raise `exhaustiveness`
> (8 → 32) and widen the box (`docking_autodock_vina/main.nf:12-13`;
> `qc_evidence.yaml:341-343`). The −7 kcal/mol line is a BRONZE heuristic, not a
> hard cutoff.

> **Pitfall — Foldseek/MMseqs2/GROMACS are callable but unproven here.** They
> route and launch, but their benchmarks (T17/T18/T19) are **pending**. Don't cite
> "a Foldseek/MD result on BioMate" as validated — run it against a gold standard
> first. (Appendix E.)

## What's not covered

Honest scope — these are **not** claimed as verified-and-present in this chapter;
they live in **Appendix E (Coverage & roadmap)**:

- **End-to-end-verified Foldseek structure search (T17).** The
  `foldseek_structure_search` and `alphafold_db_search` workflows are wired and
  routable (3Di / ProstT5 / web-API), but the SCOPe40 benchmark is
  **`unverified=True`** (`run_phase1.py:76-77`). Wired, not proven.
- **End-to-end-verified MMseqs2 sequence search (T18).** The
  `mmseqs2_sequence_search` workflow is wired, but the Pfam/UniRef50 recall
  benchmark is **`unverified=True`** (`run_phase1.py:78-79`).
- **Molecular dynamics (GROMACS, T19).** The `gromacs_protein_md` pipeline
  (GAFF2 → solvate → EM/NVT/NPT → production MD → MM-GBSA) exists as code, but
  MD is **`unverified=True`** (`run_phase1.py:85-86`). Do **not** claim MD "works"
  end-to-end. (No AMBER-only MD pipeline is documented here.)
- **Multimer / complex-interface prediction (T20).** AlphaFold-Multimer
  (`bionemo_client.py:69`) and Boltz-multimer paths exist, but interface accuracy
  (DockQ vs. 1IVO) is **`unverified=True`** (`run_phase1.py:87-88`).
- **An auto-remediation loop.** There is **no** auto-loop wired for structure
  prediction or docking — `qc_evidence.yaml:358-361` labels these
  "Unwired-but-cited domains … no auto-loop bridge entry yet." Gates are advisory,
  surfaced for you to act on and re-run manually.
- **In-app PAE heatmap for predicted structures.** The `PaeHeatmap` component
  exists but is **not** wired to `.pdb`/`.cif` sidecar routing in
  `step-output-preview.tsx`; today the in-app view is pLDDT only. Roadmap.
- **MolProbity / experimental validation.** No MolProbity, Ramachandran, or
  clash-score validation step is wired into these pipelines; confidence here is
  the model's own pLDDT/PAE (and Vina score), not experimental-structure
  validation.
- **A machine-readable structural-biology gold-standard entry.** EGFR/1M17 is the
  harness's intended target (T10/T11), but a row is **missing from**
  `evaluation/tutorial_demos/gold_standards.yaml` (registry gap), and numeric
  outputs have **not** been re-confirmed by a fresh live GPU/Batch run.
- **Stable numeric workflow IDs.** Integer tool IDs differ between the local DB
  snapshot and the deployed routable catalog; this chapter grounds on workflow
  source-file paths, which are stable. (Recorded as a mismatch.)
- **Batch (many-target) runs.** This chapter documents single-target fold/dock
  runs; fan-out over many targets in one submission is not documented here.

---
_Verification: this page depends on the coverage-ledger rows under
**"## Structural biology"** — structure prediction Boltz-2/AF2/OpenFold2 via
BioNeMo (`bionemo_client.py:65-116`, `models_inference.py:77-122`) + Boltz
workflow (`boltz_structure_prediction/main.nf:59-185`) (C); AlphaFold3 +
DiffDock ‖ AutoDock Vina chain (`structure_prediction_docking/main.nf:75-433`)
(C); standalone AutoDock Vina docking (`docking_autodock_vina/main.nf`) (C);
struct-pred pLDDT ≥70 GOLD / confident-fraction ≥0.70 SILVER / max-PAE ≤8Å SILVER
(`qc_evidence.yaml:364-412`, wired `boltz…/main.nf:137-182`) (C); docking Vina
>-7 kcal/mol + <3 poses BRONZE (`qc_evidence.yaml:330-356`,
`qc_trace_monitor.py:1655,1673`) (C); NO auto-loop for this domain
(`qc_evidence.yaml:358-361`) (C); pLDDT viewer + PlddtChart real capture pattern,
PAE heatmap component present-but-unwired (`step-output-preview.tsx:1032,1067,1167`,
`viewers/plddt-chart.tsx`, `viewers/pae-heatmap.tsx`) (C 🔧); EGFR/1M17 gold target
T10/T11 (registry gap 🔧, numeric live-run L / ⏳); and the wired-but-unverified /
roadmap rows — Foldseek T17, MMseqs2 T18, GROMACS-MD T19, AF-Multimer/Boltz-multimer
T20 all `unverified=True` (`run_phase1.py:76-88`) (🗺️), MolProbity absent (🗺️).
Tool IDs verified by direct DB query and consistent with II.4 (boltz 12853,
structure-prediction-docking 10644, vina 12824, foldseek 14456, mmseqs2 14462,
AlphaFold DB Search 12647)._
