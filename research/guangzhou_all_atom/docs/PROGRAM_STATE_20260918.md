# Cyclic-peptide program — consolidated state (2026-09-18)

Single-source-of-truth after the generate–verify–select engine was built and characterized. Honest
throughout: separates what's built/demonstrated, what's adopted, and what's genuinely novel vs unbuilt.

## The engine (built, demonstrated end-to-end)
```
GENERATE  BoltzGen (adopted)                          -> cyclic designs + iptm/pTM/filters
VERIFY    MM-GBSA  (psfgen cyclic build -> OpenMM GBn2, automated, our-S3 FF cache)  -> physics ΔG  [non-circular]
          Permeability GBM (CycPeptMPDB, R²0.45)        -> predicted logPapp                         [ranking]
SELECT    3-objective Pareto/combined (bind × physics × permeability)  -> ranked "advance these"
LEARN     tested — cheap surrogate on generator features does NOT pre-screen (see findings)
```
Scripts: `peptide_mmgbsa_run.sh` (verify), `permeability_baseline.sh` / `perm3_select.sh` (permeability),
`conformer_permeability.sh` (differentiator test). Build recipe: `peptide_psfgen_smoke.sh`.

## Findings (real results, with honest caveats)
| # | Finding | Evidence | Caveat |
|---|---|---|---|
| 1 | **Physics reorders the generator on ALL 4 targets** | BoltzGen #1 (iptm) → 5th–7th of 8 by MM-GBSA on kallikrein/Fab/toxin/cathepsin | MM-GBSA size bias (phys-#1 skew longer) |
| 2 | **iptm ⟂ physics ΔG** | Spearman(iptm, within-target ΔG_z) = −0.04 | strongest non-circular-oracle evidence |
| 3 | **Cheap-surrogate pre-screen fails** | LEARN surrogate LOTO-CV R²≈0 on 28 designs | generator features don't carry ΔG; 28 too few → run MM-GBSA directly |
| 4 | **Permeability changes selection** | 3-obj ties GSGLLKS↔FSRNVGDPY (better binder less permeable) | perm model ranking-only (R²0.45) |
| 5 | **Designs are permeability-poor** | all predicted logPapp −7.5..−8.4 | ⇒ permeability must be a GENERATION objective, not a filter |
| 6 | **2D permeability plateaus ~0.45–0.55; cheap chameleon-span fails** | rich-desc R²0.45; conformer-span adds nothing | real lift needs 2-environment MD (expensive, uncertain) |
| 7 | **Automated cyclic MM-GBSA works** | 32/32 designs' rings closed incl. Pro-containing | psfgen `first none last none` + unique CYCP patch |

## What's genuinely new vs adopted (honest)
- **New:** the automated headless cyclic-peptide MM-GBSA (engineering artifact the field says is hard); the
  empirical findings above (esp. iptm⟂ΔG across 4 targets); the strategic insight that permeability belongs
  in generation; honest negatives (cheap conformer-span, cheap surrogate) that de-risk future effort.
- **Adopted (not new):** BoltzGen, MM-GBSA/gmx_MMPBSA, CHARMM36m, permeability GBM, Pareto selection, DMTA concept.
- **Unbuilt (the real differentiator, still ahead):** conformation-aware permeability (2-env MD) and
  permeability-driven **generation**.

## Assets (S3 bucket knowledge-datasets-1759951976, cyclic_peptide/)
- FF cache: `datasets/charmm36_toppar/` (top_all36_prot.rtf + par_all36m_prot.prm) — runs no longer depend on MacKerell.
- Data: `raw/CycPeptMPDB_Peptide_All.csv` (perm), `datasets/cremp_partial/` (43GB conformers), PepBDB, HELM,
  BindingDB peptide subset, `datasets/approved_cyclic_peptide_drugs/` (54-drug positive-control set).
- Code refs: `code_refs/` (MDML_PeptPerm, CycPeptMP, HELM-GPT, GenMol, RINGER…).
- Runs: `runs/mmgbsa-*`, `runs/perm*`, `runs/conf-perm-*` (results JSONs).
- Infra: AutoimmuneCorpusProfile, DL Base GPU AMI, spot GPU capacity tight (use g6.2xl/4xl fallback).

## Docs (all committed to integration/dev-test)
MMGBSA_RESULTS · PERMEABILITY_BASELINE_RESULTS · CLOSED_LOOP_ENGINE · PEPTIDE_MMGBSA_TOOLING ·
BIOMATE_CLOSED_LOOP_INTEGRATION · BOLTZGEN_OURTARGETS_RESULTS · CYCLIC_PEPTIDE_DRUGS · SMALL_MOLECULE_TRANSFER.

## Prioritized roadmap (the big focused builds — each a fresh effort)
1. **Permeability-driven generation** — the differentiator gap finding #5 exposed. Steer generation toward
   permeable designs (PepTune-style MCTG guidance / permeability-conditioned redesign). Highest strategic value.
2. **FEP finalist tier** — ATM/FEP+ (~1 kcal/mol) on the Pareto set, length-controlled, to arbitrate MM-GBSA + size bias.
3. **Productionize on BioMate** — register the validated MM-GBSA workflow in the DB (per BIOMATE_CLOSED_LOOP_INTEGRATION).
4. **Real LEARN loop** — only after physics-informed cheap features + hundreds of scored designs (finding #3).
5. **Conformation-aware permeability** — 2-environment MD ensembles on CREMP; do only if a milestone justifies the cost.

## 2026-09-20 — committee review (3 flagship models) + fixes
`docs/COMMITTEE_REVIEW.md`: independent review by claude-opus-5 + gpt-6-astra-pro + gemini-3.1-pro-preview
(all MAJOR REVISION). Strong cross-model consensus. **P0 fixes applied + numbers recomputed:** (1) `cyclic_mol`
deleted the carbonyl O not the hydroxyl → spurious +1 donor/+2 Da on EVERY design (verified constant offset;
ΔHBD headroom & relative rankings unaffected; absolutes corrected — GPFVPGL now 0 donors after redesign);
(2) v3 scored the LINEAR peptide → now cyclized; (3) removed the auto "binding PRESERVED" verdict.
**P1 INVESTIGATED (`perm_size_correction.py`, `results/perm_size_correction.json`):**
- §3.9 "9 kcal/mol binding lost" = **SIZE ARTIFACT, OVERTURNED.** Raw dG is size-dominated (spearman rawdG~LE
  +0.78); by ligand efficiency the perm-aware picks bind BETTER per atom on both targets (1yf4 −0.62 vs −0.577;
  1u8p −0.49 vs −0.37). Permeability-aware selection picks smaller, more ligand-efficient, more permeable
  designs — it does NOT sacrifice per-atom binding. (LE is a heuristic; FEP still the absolute arbiter.)
- §3.2 iptm⟂physics = **DOWNGRADED, not robust.** −0.04 (within-target-z, n=32) vs −0.40 (pooled union, n=27);
  survives size correction (iptm–LE −0.46). Strong "orthogonal" claim unsupported (CI ≈ ±0.35); keep only the
  operational "verify with physics is prudent."
- 1u8p receptor truncation = **MOOT.** Design complexes have only 2 chains (peptide + chain B); nothing
  truncated. `split()` hardened for future multi-chain receptors anyway.
**P2 OPEN:** CIs/replicates on small-n; proper N-methyl FF with CMAP; full-pool scoring + matched baselines;
reproducibility artifacts. Engineering + honest-negatives praised by all three reviewers.

## Honest bottom line
A disciplined, demonstrated, non-circular generate–verify–select engine exists and every layer produced a
real finding. The differentiating *science* (permeability-aware generation) is scoped and evidence-backed
but not yet built — that's the frontier. Wet lab remains the ultimate gate.

## 2026-09-19 addendum
- **Manuscript written** — `docs/MANUSCRIPT.md` consolidates the engine + findings in publication form
  (honest, computational-only, no wet-lab).
- **Track A (2-env permeability proxy): attempted but toolchain-blocked, NOT a result.** Root-caused and
  hardened the runner (`perm_2env.sh`): per-item SIGALRM timeout, per-iteration budget check (the original
  run died to an `i%25`-gated budget check + hard deadline), row checkpointing, `libgomp.so.1` OpenMP-runtime
  fix (system `libgomp1` + conda `libgomp/llvm-openmp` + `LD_LIBRARY_PATH` + fail-fast preflight), and
  worker-level error capture (`worker_errors.txt`). After all fixes the per-peptide GAFF/AM1-BCC (`sqm`)
  parametrization still fails inside the worker on ephemeral spot instances (`kept=0`). **Stopped after 3
  attempts** — expected payoff is low (cheap conformer-span + N-methylation already negative; survey <2%
  variance) so it doesn't justify a 4th diagnostic launch this session. The next session can read
  `worker_errors.txt` to see the exact `sqm` failure without re-deriving it. Launcher saved as
  `launch_perm_2env.sh` (CPU spot).
- **Spot lesson applied** — all these CPU runs used spot; `peptide-aws-launch-infra` memory updated.
- **Permeability-driven redesign STARTED (v1, the differentiator)** — `perm_redesign_v1.py`,
  `docs/PERMEABILITY_DRIVEN_GENERATION.md`, `results/perm_redesign_v1_result.json`. Structure-grounded,
  mechanistic (backbone-NHD lever, NOT the GBM which is blind to N-methylation), local/no-GPU. Finding: all
  32 designs carry binding-safe permeability headroom (ΔHBD 2–14 backbone donors N-methylatable without
  touching interface H-bonds); strong binders keep it (1yf4 FSRNVGDPY ΔG−52.7, HBD16→11). Supplies the
  `binding × ΔHBD × MW` objective for generation.
- **v2 capability BUILT; v2b done across 4 targets; honest result = MM-GBSA can't score this** —
  `peptide_nmethyl_smoke.sh`/`peptide_nmethyl_mmgbsa.sh`, `results/nmethyl_mmgbsa_{1yf4_FSRNVGDPY,1csb,1kc4,1u8p}.json`.
  The hard part (backbone N-methyl parametrization) is SOLVED: NMET psfgen patch + supplementary CHARMM36
  params (mirror amide-H terms onto CT3) — builds, parametrizes (GBn2), minimizes. ΔΔG for each target's top
  candidate (methylate v1 non-interface positions): 1yf4 −4.6, 1csb −12.6, 1kc4 −6.1, 1u8p −2.6 kcal/mol —
  all nominally "preserved", BUT **not reliable**: each ΔΔG is a 1–4% residual of large (+150..+320 kcal/mol)
  near-cancelling complex/ligand intramolecular changes and tracks methyl COUNT, not binding mode (single-traj
  never relaxes the free ligand → strain inflates apparent binding). **Defensible: no binding degradation;
  sign/magnitude untrustworthy; single-traj MM-GBSA is the wrong tool → needs FEP.** Binding-safe claim rests
  on v1 structure; v2 also gives independent motivation for the FEP finalist tier. Corrected an initially
  over-optimistic "binding preserved" framing after reading the decomposition.
- **v3 STARTED (oversample + perm-aware select) — first result POSITIVE** — `launch_boltzgen_oversample.sh`
  (GPU spot, AZ-fallback), `perm_generation_v3.py`, `results/perm_generation_v3_1yf4.json`. Oversampled
  BoltzGen 1yf4 to 32 designs; selected on iptm + END-STATE permeability (low HBD-after-redesign + low MW;
  NOT ΔHBD — that favors big peptides). Perm-aware top-8 vs BoltzGen default top-8: iptm 0.65 vs 0.675 (small
  cost), HBD-after-redesign 5.75 vs 9.0 (−36%), MW 694 vs 997 (−30%). Surfaces small low-donor binders
  (GGPLLGR, YSGGGPG) the permeability-blind ranking buried. Loop works end-to-end. Caveats: iptm ⟂ physics
  (picks need MM-GBSA/FEP); selection not sampling-guidance; 1 target; iptm dip may be real.
- **v3 physics-verified (DONE)** — `peptide_mmgbsa_v3verify.sh`, `results/v3verify_mmgbsa_1yf4.json`. MM-GBSA'd
  the perm-aware top-8 ∪ default top-8. **iptm-based perm selection sacrificed binding: mean ΔG −29.6 vs default
  −38.9** (iptm ⟂ physics, 3rd confirmation — small Gly-rich permeable designs had OK iptm, weak MM-GBSA). BUT
  ranking on PHYSICS ΔG × permeability finds true dual-optimal: **FVVGNPIA (ΔG −42.4, MW 816, 3 donors after
  redesign), GGPLLGR (ΔG −42.2, MW 669)** — strong AND permeable, beating BoltzGen's polar top picks on both
  axes. **Engine fix: selection objective must use PHYSICS, not iptm.**
- **v3 GENERALIZED to 2nd target class (1u8p antibody Fab, DONE)** — `results/{perm_generation_v3,v3verify_mmgbsa}_1u8p.json`.
  Binding cost of perm-selection is TARGET-DEPENDENT: 1u8p perm-aware top-8 did NOT lose binding (physics ΔG
  −23.7 vs default −22.4) while improving permeability; vs 1yf4's −29.6 vs −38.9 (~9 lost). Reason: 1yf4 deep
  pocket/strong binders vs 1u8p shallow Fab/weak-comparable binders. Universal rule confirmed: iptm ⟂ physics
  → physics-verify the perm-aware picks always. Dual-optimal both targets: 1yf4 FVVGNPIA (−42.4/MW816),
  1u8p GPFVPGL (−27.6/MW686/1 donor after redesign).
- **Remaining:** FEP on dual-optimal finalists (FVVGNPIA/GGPLLGR/GPFVPGL) + N-methyl ΔΔG (both need FEP);
  v3b = physics-in-the-loop selection scaled to remaining 2 targets (1csb/1kc4); then true sampling-time guided generation.
