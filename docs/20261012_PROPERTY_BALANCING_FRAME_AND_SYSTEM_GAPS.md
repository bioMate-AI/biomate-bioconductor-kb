# Property balancing — the frame, and the gaps from it

**Date:** 2026-10-12 · Captures the design principle argued through this session (you cannot fold all
properties into one model; PK/PD must be *tuned*, not optimized) and then does the honest thing the frame
demands: names where BioMate + this program fall SHORT of the frame — both architecturally and in the live
execution path tested today. Companion to `20261012_NEXT_STEPS_PLAN_AND_MULTITARGET_CONSTRUCT.md` and
`20261012_GI_EXPANSION_PLAN_PDL1_REGEN_ACTIVITY_CLIFFS.md`.

## 1. The frame — a decomposed property ladder, not a monolithic optimizer

**Claim:** "optimize all properties of a molecule in one model" is a category error. Toxicity and PK/PD are
not properties of a structure; they are outcomes of *structure × exposure × biology*. The defensible system
is a three-layer ladder with human judgment at defined points:

**Layer A — hard constraints (no trade-off).** Pharmacophore (RGD/Asp for αvβ6), hard CMC liabilities
(Asp-Gly isomerisation), FTO, dose-limiting-organ vetoes. These are feasibility gates: a candidate that
fails is removed, never "balanced." Shrinks the space to the feasible region. *(Implemented:
`pharmacophore_knowledge.py`, `knowledge_liability_flags.py`, `drug_novelty_fto.py`.)*

**Layer B — multi-objective selection (Pareto, not scalarization).** Within the feasible set, keep the
competing intrinsic objectives (affinity, permeability, SA, selectivity, developability) as a VECTOR; compute
the Pareto front; defer weighting. Human judgment is spent *on the front* (novelty strategy, synthesis, IP),
not on loss weights. *(Implemented: `peptide_select.py` Pareto+HVI; `mo_select_qnehvi.py` for the next-batch
Bayesian acquisition.)*

**Layer C — exposure / PK-PD (where dose lives, and where tuning is irreducible).** Dose enters here, not in
the molecular model. Clinical tox/efficacy are *derived* as dose-aware margins (liability ÷ expected
exposure), treated as constraints feeding Layer A — never predicted as a molecular label. **PK/PD cannot be
automated to an output** because it is (i) emergent from several independent mechanisms (CYP + proteolysis +
renal/biliary clearance, tissue/plasma binding), (ii) *coupled* to the binding levers (lipophilicity ↑perm
but ↑clearance/↑PPB/↑hERG/↓solubility; N-methyl ↑perm+protease-resistance but can ↓affinity and flip
conformation — an activity cliff; ↓charge ↓renal dose but ↓perm), (iii) a design-*to-a-profile* problem
(half-life matched to regimen; Cmax/trough window), and (iv) empirical/translational (in vitro → rodent PK →
allometry → human PBPK, refit each round). It is a human-steered DMTA/DMPK loop.

**Where manual intervention belongs (minimised, relocated):** the human sets the **TPP** (per program, once)
and the **anchors** (permeability ≥ cyclosporine-class, ΔG ≥ round-1 median ~−35, HBD ≤ 6 post-N-methylation),
and makes the go/no-go on the Pareto front. The machine does hard gates, Pareto bookkeeping, HVI batch
proposal, and physics scoring. **Human-steered, machine-accelerated.** The moat is the closed loop (each
round's PK/PD data refits the priors), not full automation.

**Program-specific:** the αvβ6 radioligand's PK/PD *is* the program — biodistribution + dosimetry
(tumor:kidney ratio, residence time, radionuclide half-life ↔ peptide clearance), tuned via
chelator/linker/charge/albumin-binder and read from imaging, not predicted from sequence. The
heterobivalent-linker option is itself a PK-tuning lever (linker length ↔ avidity vs clearance).

## 2. Gaps from this frame

### 2a. Architectural gaps (what is missing to realise the ladder)
- **Layer C barely exists.** There is no wired PBPK/exposure model and no dose-margin computation feeding the
  gates. Renal charge is handled as a *rule* (good first cut) but not as a dosimetry calculation. No TPP
  object exists as data — the anchors live in prose, not a machine-readable profile the selector reads.
- **Layer B is not wired to live predictors.** `peptide_select.py` expects a `PeptideProperties` vector, but
  the affinity/permeability/stability predictors are not yet connected to the knowledge-grounded K-sets as a
  live feed — selection would run on stale/absent axes.
- **Property predictors are weak and OOD for macrocycles.** Permeability R²~0.45; stability ranking-grade
  AUROC~0.84 on *linear* SMILES; affinity DTA models are small-molecule-trained (see 2b). These are priors
  with wide error bars, correctly, but the system does not yet propagate that uncertainty into selection.
- **The "learn" seam is unbuilt.** The DMTA loop's retrain step (DPO on verify-layer + wet-lab preferences)
  is designed but not implemented — so the closed loop that is the actual moat is open.
- **Physics discriminator needs a pose it does not have.** The trusted scorer is MM-GBSA (OpenMM/GBn2,
  EC2 spot), which requires a bound COMPLEX. The K-sets are sequence-only → a cofold/dock pose stage
  (BoltzGen/Boltz-2) must precede MM-GBSA, and that stage is not yet runnable through the MCP surface (2b).

### 2b. Execution gaps hit LIVE today (concrete BioMate capability gaps)
- **`biomate_session` is not exposed on this MCP server** ("Unknown tool") — the documented primary entry
  point is unavailable, forcing `run_workflow` with explicit params.
- **The Boltz-2 module has no parameter schema** (file-driven: FASTA in) — `run_workflow` cannot target it
  without an `upload_file` + unknown param wiring, so the cofold pose stage is blocked through the MCP.
- **`predict_binding_affinity_protein_1d_sequence` is a STUB.** Run `08705d65…` returned
  status=completed / returncode 0 but the result was: *"DeepPurpose package is not available in this
  environment … in production with a DeepPurpose Docker image, this would predict binding affinities."* →
  **green success, zero real scores.** This is a false-positive completion (the "exit code is not a
  diagnosis" trap) and a real capability gap: the container lacks DeepPurpose. Also DTA here is
  small-molecule-trained and single-sequence, so even when fixed it is only a weak PD-L1 triage and is
  ill-posed for the 2-chain αvβ6 RGD interface.
- **Transient backend instability** — repeated HTTP 500 "fetch failed" on search/spec during the session.

### 2c. The honest consequence
The frame says physics scores one axis of a multi-objective, human-steered loop. Today BioMate can *route*
and *execute* a workflow end-to-end (path verified, 154 s), but the affinity tool no-ops without its
dependency, and the trusted MM-GBSA path needs a pose stage that the MCP can't yet launch. So the K-sets
remain **liability- and FTO-gated but not yet physics-scored** — Layers A done, B partial, C absent.

## 3. Progress on the new sequences
- αvβ6 K-set: 8 PASS / 2 WATCH / 1 DROP after liability+FTO (lead **AVB6-K-08 `YRGDLIWPA`**); 3D conformers
  prepared; NOT physics-scored (needs cofold→MM-GBSA on 9xmm).
- PD-L1 K-set: 3 PASS / 4 WATCH / 1 HOLD; SMILES + receptor (5O45 chain A) staged; a first-pass DTA run was
  launched on BioMate and **completed but returned a stub (no scores)** — gap logged above.
- **Next, to actually score:** fix the DeepPurpose container (or route affinity via a working model), and
  stand up the cofold pose stage (BoltzGen/Boltz-2 on 9xmm/5O45) → MM-GBSA rescore (EC2 spot) → feed the ΔG
  axis into `peptide_select.py` alongside permeability/SA/developability → Pareto front → human review.
