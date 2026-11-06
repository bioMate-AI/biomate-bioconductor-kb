# REVIEW PACKET (2026-10-25)
Everything below is the team's own material. Candidate sequences, CRO panels and credentials are excluded.


===== DOC: research/guangzhou_all_atom/committee/COMMITTEE_BRIEF_20261025.md =====
# BRIEF FOR THE REVIEW COMMITTEE (2026-10-25)

You are one of eight independent reviewers from different AI labs. Be a demanding, specific, honest reviewer. Do not be
agreeable for its own sake. If you are not certain a literature claim is true, mark it **[UNVERIFIED]** — do not invent citations.

## 1. What we are building
A **knowledge + rules + computation LLM system** for designing cyclic-peptide binders, inside BioMate (a bioinformatics /
drug-discovery execution platform with an agent harness, ~4,000 indexed workflows, and its own LLM program). Primary targets:
**αvβ6 integrin** (RGD-LXX(L/I) macrocycles; radioligand for PDAC imaging/therapy; Trivehexin / avebehexin are the patentee's
leads and define our rule/FTO envelope) and **PD-L1 blockade** (PD-1/PD-L1 PPI-blocking macrocycle); GRPR is a third target.
Constraints: **no wet-lab data exists yet**; compute is AWS spot (GPU ≈ a few $/hour); a small team; the target matters — this is not
a generic benchmark exercise. The stated goal for this review: **a better LLM, a better optimisation loop, a better output, with
genuine innovation** — not a polished restatement.

## 2. What exists (verified from code, not from docs)
- `loop.py`: design→score→redesign harness. **`revise()` is a hand-written deterministic rule-repair stand-in; no LLM or RL is in the loop.**
- `neural_generator.py`: a ~4.8M-param nanoGPT-style LM trained on mRNA-display NGS enrichment; used only to **re-rank ~80 enumerated
  flank/position triples**, conditioned on permeability / a null target — **not an αvβ6-affinity generator.**
- `reward.py`: a weighted multi-objective RLVR reward function + DPO-pair emitter. **Not wired to any training.**
- `methodology_close.py`: the **only genuinely closed reward→update loop** (real gradient DPO, cluster-disjoint evaluator, shuffled-reward
  placebo). It optimises a **measured-permeability ML oracle** (scaffold-split R² 0.23–0.30; SOTA ≈ 0.77), never binding. Result:
  Δ(independent evaluator) = +0.098, 6/6 seeds, Wilcoxon p = 0.031; placebo +0.014.
- `score.py`: merges cheap deterministic gates (RGD/pharmacophore rule, FTO claim verdict, developability, **availability**) with
  expensive hooks (binding ΔG, selectivity gap, groove, ΔΔG-FEP) that are **`"pending"` unless a result file exists**.
  Selectivity vs αvβ3/5/8 has never been computed.
- Physics: MM-GBSA (metal-free ruled invalid; metal-aware Li–Merz Mn ruled inadmissible — controls 115 kcal/mol apart). Relative
  FEP (pmx hybrid + CHARMM36m + a CaDA cationic-dummy Mn model; GROMACS on AWS Batch spot): infrastructure works.
- Gates: acceptance (RGD hard gates), liability flags, FTO (similarity + claim-genus; `patents_checked: false`).

## 3. What we found this session (all with their honest status)
1. **FEP control edge was not a validation.** The control (Tyr→Phe ×2; = Trivehexin-monomer → avebehexin) was assumed to have ΔΔG ≈ 0.
   The *measured* ΔΔG from one lab's ELISA (Quigley 2023: IC50 0.84 → 0.17 nM) is **−0.95 kcal/mol**. Computed: −0.18 ± 0.15 (analytic BAR
   error, single replica, 0.5 ns/window, independent λ windows, no replica exchange). Sign right, magnitude ~5× low. Prior docs/manuscript
   had called this "recovered the expected null / anchor cleared" — **retracted**.
2. **The metal was never at the binding site.** Validating the CaDA-Mn model showed all 3 Mn were free ions in bulk water (31–37 Å from the
   receptor) from the first EM structure on: the build ran `editconf -c` (rigid 161 Å translation, residual std 0.14 Å) and *then* appended
   the Mn at untranslated input coordinates. The pocket was metal-free; the earlier "dynamically validated" verdict only checked the peptide
   junction. Fixed (Mn added before centring + a build-time gate + a coordination validator); the rebuild finished and was **verified on the
   final solvated system** (Mn1/Mn2 at 2.1–2.2 Å from 6 O each; all pre-registered predictions matched). The cofold input pose also has
   the MIDAS Mn 0.82 Å from the ligand Asp OD2 and 1.40 Å from a Glu OE2 (pose clash) → soft restrained relaxation designed (opt-in), then an
   **unrestrained** run is the actual metal-model test. *Not yet run.*
3. **Leakage-inflated wins caught by held-out tests**, each of which had looked like a result: display-NGS selector AUC 0.94–0.99
   (label = a threshold on the same enrichment value the model is conditioned on; a trivial read-count sort gets AUC ≈ 1.0; LM below chance on
   hPCSK9); renal-biodistribution predictor ρ = 0.27 (charge artifact; corrected leave-one-target-out ρ = −0.26, p = 0.11); a
   physics+availability binding model 0.74 (random CV) → 0.28 leave-one-domain-out (< physics-only 0.32).
4. **Cross-context generalisation is the consistent wall** (cross-target cyclic transfer NULL; target-aware ESM-2 NULL; novel-target
   affinity ceiling ρ ≈ 0.42; BoltzGen cyclic fine-tune Δiptm −0.16; UniMoMo cyclic fine-tune +0.0097, CI spans 0).
5. **One signal that does transfer: peptide *availability*** (Lemieux … Landry, bioRxiv 2026, doi 10.64898/2026.09.21.752983: 6,500+
   SH3-domain × peptide variants measured *in cells* by DHFR-PCA; availability is set largely by peptide hydrophobicity/charge and limits
   functional binding independent of affinity). We fit a 3-feature model on their measured availability: in-sample ρ 0.72, **leave-one-domain-out
   ρ 0.40** (0.23–0.49); shipped as an informational (non-gating) score. For our extracellular targets it is only a developability proxy.
6. **A measured αvβ6 ground-truth exists** (not previously used): c[X-RGDL-A-X-dPro-NMeK] 2×2 Phe/Tyr grid (IC50 0.17/3.3/2.8/0.84 nM) and a
   Chg-pentapeptide N-methyl scan (1.3 nM → >5000 nM), plus measured selectivity ratios (up to ~2500× over αvβ3). No co-structure exists for
   any member. The previously "pre-registered" A20FMDV2 Ala/Cit series does not exist as described.
7. **Prior art we read:** SynCraft (Li & Lai, Nature Mach. Intell. 2026): LLM predicts atom-level *edit sequences* (not SMILES), RDKit applies
   them deterministically, RAG over a curated "cliff" set, optional docking/PLIP constraints — beats ChemProjector/SynFormer/ReaSyn on
   synthesizability rescue (e.g. 28.4% vs 14.1% at Tanimoto > 0.6). So "LLM + rules + computation" is *not* novel by itself.

## 4. Honest state
No component beats a published bar; no wet-lab data; no admissible binding oracle for αvβ6 today. What is solid: the audit discipline,
the availability model, the permeability-DPO methodology (narrow), and a now-correct picture of what is unvalidated.

## 5. What we want from you (answer in the structure the system prompt gives)
- **LLM**: what should the LLM in this system *be* (edit-policy proposer? generator? verifier-conditioned reasoning agent? something else), and how
  should it combine knowledge (SAR tables, literature, rules), rules (pharmacophore/liability/FTO gates) and computation (physics, learned
  oracles)? With ~10 measured αvβ6 SAR points, ~6.5k in-cell peptide variants, ~7k permeability labels, and display-NGS (circular) data, what
  training/evaluation design avoids the circularity and the generalisation wall?
- **Loop**: what is a *verifiable reward* when the binding oracle is not yet validated? How would you structure a multi-fidelity oracle ladder,
  calibrate it against the measured anchors, pick which expensive FEP edges to run (active learning / uncertainty), and detect reward hacking?
- **Output**: what should the system deliver so that it is decision-grade and falsifiable without waiting for a wet lab — and what could the
  community actually use (benchmarks, models, protocols)?
- **Innovation**: the one idea you would bet on that is genuinely novel *and* defensible, and why it is not already done.
- **Audit**: what in sections 2–4 is wrong, overclaimed, or missing? Anything the team is not seeing?


===== DOC: docs/20261025_SESSION_REVEAL_WORKS_RESOURCES_PERF_ERRORS.md =====
# Full reveal — works, resources, performances, errors (cyclic-peptide / αvβ6 program review)

**2026-10-25.** A complete, honest accounting of this review session and the prior work it audited:
what was done, what was collected, every performance number (with its honest status), every error/over-claim
caught, and additional findings mined from the subagent review outputs. Nothing here is spun — the whole
exercise exists to stop over-claims reaching a manuscript.

---

## 1. Works done (this session)

| Work | Output |
|---|---|
| State-of-study review (docs + result JSONs) | per-approach verdict table; "nothing validated vs SOTA" |
| Code review (implementation realness + metal model) | per-module REAL/STUB/PARTIAL; metal model unvalidated |
| Gold-standard ground-truth lock (αvβ6 FEP benchmark) | A1/A2 measured series found; A20FMDV2 prereg set debunked |
| Read 2 external works (user-flagged) | SynCraft (Nature MI); Landry availability (bioRxiv) |
| C1 experiments on Landry data (ran live) | mini-C1, random-CV (leakage), 3-fam LODO, 7-domain LODO |
| **Built + shipped a real model** | `peptide_availability.py` + gate-chain wiring (commits 3ebab5f8e, d97abf609) |

## 2. Resources collected (with provenance)

- **Landry in-cell peptide dataset** — `github.com/Landrylab/Lemieux_et_al2026` (CC BY-NC-ND) + SRA `PRJNA1499819`.
  Files pulled/used: `data/PCA1/med_ppi_score.csv` (in-cell PPI, 7 SH3 domains, 3043 variants), `med_avail_score.csv`
  (measured availability), `PWM_scores.csv` (phage/in-vitro proxy), `in_silico_prediction/results/04_analysis/all_ddg.csv`
  (FoldX + FlexDDG ΔΔG, 3240 rows, 3 domains). Paper: Lemieux…Landry, bioRxiv doi:10.64898/2026.09.21.752983.
- **Gold-standard αvβ6 affinity series** (for FEP ground truth):
  - **A1** cyclic nonapeptides c[X-RGDL-A-X-dPro-NMeK], X∈{F,Y}: FF/YF/FY/YY IC50 = 0.17/3.3/2.8/0.84 nM (ELISA).
    Quigley et al., RSC Med Chem 2023 (PMID 38099056) + EJNMMI 2022 (PMID 34559266). **This is our exact chemotype;
    Trivehexin-monomer = YY, avebehexin = FF.**
  - **A2** cyclic pentapeptide [RGD-Chg-E] N-methyl scan (SDM17): IC50 1.3 nM→>5000 nM. Tomassi et al., JMC 2021 (PMID 33961417).
  - Selectivity (measured ELISA): FF 2494× over αvβ3; A20FMDV2 ≥85×; B6_BP_dslf >1000×.
- **SynCraft** — Li & Lai (PKU), Nature Machine Intelligence 2026 / arXiv 2512.20333; code `catalystforyou/SynCraft-Core`.
- **αvβ6 co-structures** (MIDAS metals): 8TCG (cryo-EM 3.4 Å, 0 unmodeled), 4UM9 (X-ray 2.5 Å), 9XMM (2.88 Å, cyclic RGD).

## 3. Performances — every number with its honest status

| Approach | Measured | Bar | Status |
|---|---|---|---|
| PepGLAD cyclic FT (M2c) | DockQ **0.437** | PepGLAD 0.592 (diff task) | PLATEAUED, below; number-shopped across sets (0.506 on PepBDB, 0.326 elsewhere — not comparable) |
| UniMoMo cyclic FT | +0.0097 (95% CI spans 0) | base UniMoMo 0.403 | NULL; `training_qualified:false` (79 OOM) |
| UniMoMo linear 0.7754 "reproduced" | — | 0.7592 | UNCONFIRMED (MKL failure; docs conflict) |
| BoltzGen cyclic FT (LOTO) | Δiptm **−0.16** | base BoltzGen | FAILED/superseded |
| Within-target display selector | AUC 0.94–0.99; hPCSK9 **0.343** | abundance null AUC 1.0/0.997 | CIRCULAR + below null; below chance on hPCSK9 |
| Cross-target transfer (v3.1, xtarget_fm) | NULL; Spearman 0.26 | field 3–8% | NULL |
| Chemical binding model (847 tgt, GLOO) | RF **0.42** ceiling | "strong" | NULL ceiling |
| Permeability learned-rep | R² 0.12–0.30 | CycPeptMP 0.77 | FAILED vs SOTA |
| MM-GBSA αvβ6 metal-free | +5.38…−26.5 | — | RULED INVALID (metal dropped) |
| MM-GBSA αvβ6 metal-aware (Li-Merz Mn) | Trivehexin −7.2 vs avebehexin **−122.2** (115 kcal/mol apart) | controls must converge | RULED INADMISSIBLE |
| **FEP control edge (Y1F+Y7F)** | ΔΔG **−0.18 ± 0.15** | **measured −0.95** (found this session) | **MISS; metal-blind edge; "expected ≈0" was false** |
| DPO permeability close (cluster-disjoint) | **+0.098** (6/6 seeds, p=0.031); placebo +0.124 vs +0.014 (p=0.004) | — | WORKS narrowly (ML oracle, not binding) |
| Rule-constrained DPO arm | identical to unconstrained (+0.2513) | — | NULL for the gate (never bound) |
| FTO novelty | 20/22 "novel"; `patents_checked:false` | — | similarity filter only; αvβ6 monomer FTO-BLOCKED (CA2998968) |
| CRO panels | αvβ6 panelB **0/12 have RGD**; PD-L1 panelA 0/10 pass | our own gate | FAILED own gate; no wet-lab result exists |
| Renal cross-target | LOTO ρ **−0.26** (p=0.11); fuller ρ +0.02 | generalize | NULL (prior +0.27 = charge artifact; +0.78 was αvβ3 n=8+αvβ6 n=4) |
| **Availability model (THIS SESSION, shipped)** | in-sample ρ **0.72**; **LODO ρ 0.40** (robust 0.23–0.49) | — | **WORKS — transfers (peptide-intrinsic); shipped as a gate** |
| Binding + availability (3-fam) | random-CV 0.736 → **LODO 0.282** (< physics 0.316) | physics 0.316 | leakage-inflated; collapses out-of-domain |
| Binding + availability (7-domain) | PWM 0.265 → +hydro 0.286 → +measured-avail 0.319 | PWM 0.265 | marginal/inconsistent — not SOTA |

## 4. Errors & over-claims caught (the point of the review)

1. **FEP "control recovered the expected ≈0 → validated"** — FALSE on both counts. Control edge = YY→FF, measured
   ΔΔG = **−0.95 kcal/mol** (FF ~5× tighter, Quigley), not 0; our FEP gave −0.18 → a *miss*, not a validation.
   The "A2 anchor cleared" claim in the controls doc / cyclic-LLM paper / committee review is **wrong and must be corrected.**
2. **Three leakage-inflated "wins"** caught by proper held-out splits: (a) selector AUC 0.94 (circular: label = conditioning
   signal, confirmed in code `harvest_display_ngs_multitarget.py:186-188`); (b) renal ρ 0.27 (charge artifact); (c) C1 random-CV
   0.74 (within-domain leakage → LODO 0.28).
3. **MM-GBSA metal mishandling** — metal-free dropped Mn (positive ΔG); metal-aware diverged 115 kcal/mol on controls. Both
   correctly ruled unusable — but were nearly cited as a binding signal.
4. **Prereg ground-truth was fictional** — the A20FMDV2 "Ala/Cit/Arg19 series" named in `20261024_AVB6_FEP_GOLD_BENCHMARK_PREREG.md`
   does not exist as stated (Cardle 2021 = cyclized analogs within ~0.2 kcal/mol of each other; cannot anchor FEP).
5. **Control-species mismatch** — docs quote Trivehexin "~47 pM" (that is the **trimer**); the monomer control YY = 0.84 nM.
6. **"20/22 passed" read as readiness** — it was the FTO novelty gate only (`patents_checked:false`); non-binders pass trivially.
7. **CRO panelB ordered without RGD** — 0/12 contain the pharmacophore; by our own rule none can bind.
8. **"validated lead" K-05 / "physics-verified closed cycle"** — K-05 has no experimental validation; the "closed cycle" uses
   an ML permeability oracle, not MM-GBSA/FEP.

## 5. Additional findings mined from the subagent review outputs

- **The FEP guard is on the dead path.** `MDRUN_CMD_READY=False` lives in the superseded `fep_batch.py`; the live
  `fep_production.py` has **no guard** and submits once an S3 `npt.gro` exists. "Production FEP is gated until go" is untrue of
  the path that runs.
- **Fan-out is not HREX.** `fep_production.py` runs independent λ windows → `gmx bar`, contradicting the mdp's "HREX" language;
  with 0.5 ns/window on 205k atoms, the error bars are analytic-BAR-only and optimistic; the `gmx bar` total-line regex can
  silently yield `None`.
- **The only FEP edge is metal-blind and the admissibility gate keys off it** (`physics_dispatch.py:144-165`) — so passing it
  would manufacture false confidence in metal-dependent ΔΔGs. The staged positive control that *would* exercise the metal
  (RGD **Asp→Ala**) is stubbed at `build_fep_setup.sh:95` but never run.
- **`neural_generator` is a re-ranker, not a generator** — it scores ~80 enumerated flank-triples by LM log-likelihood,
  conditioned on *permeability / null-target*, explicitly **not** αvβ6 affinity. The "closed optimizer loop" `revise()` is a
  hand-coded deterministic rule stand-in (self-labelled); gradient RLVR is not wired.
- **`methodology_close` is the only genuinely closed reward→update loop** — real gradient DPO with a cluster-disjoint evaluator
  and a placebo control — but it optimizes permeability/enrichment, **never binding**. Its honesty is exemplary; its objective
  is not the one that matters.
- **RFpeptides — the physics prior the synthesis doc named as the real cross-target generalizer — was PARKED, never fired**
  (`PROGRAM_CHALLENGE_MAP.md` C5).
- **hPCSK9 selector is below chance** (0.266 after the enrichment-sort null); the unified-v4 "rescue 0.34→0.82" is a rescue
  inside a circular eval.
- **The in-silico predictor Landry shipped is physics affinity (FoldX + FlexDDG), not ML/availability** — so our availability
  angle is non-overlapping with theirs; but their ΔΔG exists for only **3 of 7** domains (expensive), which is why our 3-domain
  LODO was underpowered and the 7-domain PCA data was the right test.
- **A clean single-residue *protein* selectivity edge exists** — B6_BP A39K: β6 1.7→0.11 nM, β8 7.3→580 nM (Roy 2023) — a
  future selectivity-FEP anchor, though large for FEP.

## 6. Net state and the one real deliverable

**Across every binding/affinity/cross-context direction, nothing survives rigorous held-out testing** — the consistent wall is
**generalization**, not capacity. There is still **no non-circular, experimentally-grounded binding signal** in the program, and
**no wet-lab data of any kind.**

The one thing that *is* real, useful, and honest: **the availability model** — peptide-intrinsic, so it transfers (LODO ρ 0.40,
robust), grounded in Landry's measured data, shipped into BioMate's gate chain as an informational score (never gates a surface
binder), and screened across our v2 panel. Modest but real, with generalization honestly tested. That is the correct kind of
contribution for this program right now.

**Required follow-up (integrity):** correct the "FEP control recovered ≈0 / A2 anchor cleared" claim in
`20261022_CYCLIC_LLM_CLOSED_CYCLE_CONTROLS.md`, the cyclic-LLM manuscript, and the committee-review record, to the measured
−0.95 vs computed −0.18 *miss*.


===== DOC: docs/20261025_CADA_MN_METAL_MODEL_VALIDATION.md =====
# CaDA-Mn metal-model validation — the FEP complex leg never had a metal at the binding site

**2026-10-25.** Requested step: validate the CaDA-Mn model before any further FEP work. Result: the first
measurement fails, and the failure is a build bug, not a force-field question. No GPU was spent; everything
below was measured from artifacts already on S3 (`avb6-fep-ctrl-build1/equil_out/complex/{em,nvt,npt}.gro`) and
the build inputs (`preflight-1792465588/in/`).

## 1. Finding
In the production complex leg, **all three CaDA-Mn were free ions in bulk water — from the first EM structure
onward.** (Minimum-image / triclinic PBC applied; the dodecahedral box is 14.2 × 14.2 × 10.0 nm.)

| structure | Mn → nearest receptor atom | Mn → nearest peptide atom | protein/ligand O < 3.0 Å | waters < 2.8 Å |
|---|---|---|---|---|
| em.gro  | 33.1 – 36.3 Å | 62 – 70 Å | 0 / 0 / 0 | 6 / 5 / 6 |
| nvt.gro | 34.7 – 35.6 Å | — | 0 / 0 / 0 | 6 / 6 / 6 |
| npt.gro | 30.7 – 37.1 Å | 62 – 67 Å | 0 / 0 / 0 | 6 / 6 / 6 |

Meanwhile the ligand Asp (ASP1071) is H-bonded to **Ser720/Ser722 (OD–OG 2.65–2.82 Å)** — the DxSxS serines
that coordinate the MIDAS metal. The pocket is metal-free. The earlier "equilibration acceptance"
(`20261021_AVB6_FEP_EQUILIBRATION_ACCEPTANCE.md`, "dynamically validated") checked **only the peptide
head-to-tail amide geometry**; it never measured the metal. The CaDA cage itself is intact in the files
(7 atoms/residue: MN + D1–D6), so this is a *placement* failure, not a cage failure.

## 2. Root cause (confirmed quantitatively)
`fep/preflight/build_fep_setup.sh` (old lines 204–215): `gmx editconf -f hconf.pdb -o box.gro -c -d 1.2 -bt dodecahedron`
**rigidly translates every atom** to centre the system, and **only afterwards** appended the Mn atoms using the
raw, un-translated `mn_cada.pdb` coordinates.

- Receptor (1069 CA matched, input vs `em.gro`): **pure rigid translation (108.2, 108.1, 50.3) Å, |t| = 161 Å,
  residual std 0.14 Å** (box-vector wraps removed by lattice reduction).
- Mn centres in `em.gro` = their input coordinates (differences < 1.1 Å, or exactly one box vector).
- Applying the *receptor's* translation to the Mn puts them 2.1–2.9 Å from carboxylate/carbonyl O, and Mn3 next
  to the ligand Asp — i.e. the intended geometry.
- The preflight script (`preflight_in_container.sh:133-148`) appends Mn **before** `editconf`, so it is not affected;
  this was a single instance in the production builder.

## 3. What this invalidates (and what it does not)
- **Invalidated:** "CaDA-Mn model + CHARMM36m + 12-λ BAR pipeline reproduces …" (controls doc §6c) — the complex leg
  ran with no metal in the site. "Setup dynamically validated and scientifically ready" (acceptance doc) — the metal was
  never measured. Any statement that the control edge exercised, or was insensitive to, the metal model.
- **Not established either way:** whether the −0.18 vs measured −0.95 kcal/mol miss is *caused* by the missing metal. The
  edge perturbs Tyr→Phe away from the metal, but the binding mode in a metal-free pocket differs from the metal-bound
  one, so the miss cannot be attributed in either direction until the system is rebuilt correctly.
- **Still unvalidated:** the CaDA-Mn force field itself in dynamics (Mn–O distances, cage stability, coordination number
  under MD). This finding means that question has not been asked yet, not that it failed.

## 4. Fix + class guard (this commit)
1. **`build_fep_setup.sh`**: convert `hconf.pdb → conf_in.gro` (no translation), **append the 21 CaDA-Mn atoms there**,
   then run `editconf -c`, so receptor + peptide + metals are translated together. (Solvent leg unaffected — no Mn.)
2. **Build-time gate** (inline, pure Python): every Mn centre must have ≥ 2 protein/ligand O within 3.0 Å *before*
   EM, else `MN_SITE_FAIL`, exit 28, and **no `FEP_INPUTS_READY` sentinel** is written. A < 1.8 Å contact is a WARN
   (known cofold clash, §5).
3. **`fep/validate_mn_coordination.py`** (new): the measurement the acceptance skipped. Triclinic min-image; per-Mn
   status UNBOUND / CLASH / OK, ligand-contact flag, JSON output; `--mode post` makes a clash a hard FAIL. Exit 2 on fail.

### Tests run (no GPU, no gmx)
| test | expected | observed |
|---|---|---|
| validator on real em / nvt / npt | FAIL 3/3 UNBOUND | **FAIL 3/3 UNBOUND** (exit 2) |
| validator, synthetic control (Mn shifted by the measured receptor vector) | not UNBOUND | Mn1 OK, Mn2 OK (min 1.89 Å), Mn3 CLASH (1.75 Å to Glu818 OE2); exit 0 in `pre`, would be 2 in `post` |
| extracted build gate, **fixed** order (input pose) | Mn1/2 OK, Mn3 warn | **OK / OK / CLASH(warn) 0.82 Å; exit 0** |
| extracted build gate, **old** order | UNBOUND ×3, abort | **UNBOUND ×3 (79–99 Å); exit 1** |
| `bash -n build_fep_setup.sh` | clean | clean |

Not tested locally: `gmx editconf` itself (no GROMACS here). The premise that `pdb2gmx`/pmx leave coordinates
untranslated is supported by the measured 0.14 Å residual (the only translation is the single rigid one), but the
first real rebuild is the confirmation — see predictions below.

## 5. Known risk the fix will expose: the cofold pose is clashed at the MIDAS metal
In the (correctly framed) input pose: **Mn1** 2.10 / 2.14 / 2.25 / 2.48 Å (four O) and **Mn2** 2.18 / 2.19 / 2.33 /
2.57 Å are well placed. **Mn3, the metal next to the ligand Asp, is 0.82 Å from Asp4 OD2 and 1.40 Å from Glu223 OE2**
(Ser125 OG 2.27 Å). Two carboxylate oxygens ~2 Å apart is a pose-level overlap, not just a metal-placement error —
the same 0.81 Å artifact documented for the Boltz Trivehexin pose. A stiff, charged CaDA cage (centre ε = 53.7 kJ/mol)
starting there may fail EM or distort the peptide. Do **not** "nudge" Mn3 by hand: choose between (a) a staged,
restrained relaxation (soft EM with Mn–O distance restraints at ~2.1 Å), (b) re-posing from a real
metal-bound structure (8TCG / 4UM9 / 9XMM), (c) a metal-aware re-cofold. Decision belongs to the next step.

**Predictions for the rebuild** (written before running, per repo rule): gate prints Mn1 OK, Mn2 OK, Mn3 CLASH(warn);
EM either converges with a displaced Asp/Glu (then `--mode post` decides) or fails in grompp/EM — a failure here is
informative, not a regression. If the gate prints UNBOUND anywhere, the frame assumption is wrong and the build must
not proceed.

### 5b. Relaxation design (implemented, opt-in) — decision taken: restrained relaxation first
Chosen over re-posing because it is the cheapest test and reuses the existing pipeline; re-posing from 8TCG/4UM9/9XMM stays
the fallback if the relaxed site does not hold unrestrained.
- **Build (`build_fep_setup.sh`, complex leg):** after genion, append an `#ifdef MN_RESTRAIN` block of soft harmonic Mn…O
  bonds (`[ intermolecular_interactions ] [ bonds ]`, type 6, kb = 2000 kJ/mol/nm², global atom indices) for every protein/ligand
  O within 2.7 Å of a Mn in the input frame. **Per-pair b0 = clamp(input distance, 0.205, 0.240 nm)**: contacts already in the
  physical window feel zero force; only clashed or stretched ones are pulled to the window edge. Production tprs never define
  `MN_RESTRAIN`, so production topologies are unchanged.
- **Build-time proof:** an extra `grompp` with `define = -DMN_RESTRAIN` must succeed (`complex_EM_RESTR_TPR_OK`), else exit 30 —
  a bad index or syntax error is caught on the CPU box, not in a GPU job.
- **Equil (`fep_batch.py --equil --mn-restrain`):** defines `MN_RESTRAIN` in em/nvt/npt for the complex leg only; outputs go to
  `equil_out*_mnrestr/` and never clobber an unrestrained run.
- **Dispatch guard:** a real submit for the complex leg is **refused** unless `in/complex/mn_site_gate.txt` exists (written only
  when every Mn passed the pre-EM gate). Verified: a submit attempt on `avb6-fep-ctrl-build1` is refused before any job exists.
- **Launcher:** `build_fep_inputs.sh` now defaults to `RUN_ID=avb6-fep-ctrl-build2` and refuses to overwrite a run that already has
  `FEP_INPUTS_READY` (override: new `RUN_ID=` or `FORCE=1`). `avb6-fep-ctrl-build1` is preserved as the record of the metal-free run.
- **Restraints are not a validation.** A restrained run proves only that the site can be assembled without blowing up. The metal model
  is validated only by an **unrestrained** continuation that keeps coordination (still to be built — to-do 4b).

**Local test of the generator** (extracted verbatim from the script, run on the real input-frame structure): 14 restraint pairs for
3 Mn — **Mn1: 6, Mn2: 5, Mn3: 3** — every index verified to be an (Mn centre → O) pair; Mn3's two clashed contacts get b0 = 0.205 nm,
in-window contacts keep b0 = their input distance (0.210–0.240). *Correction to my own earlier note:* I had expected 4/4/3 because I
had read only the four nearest O per Mn; the 2.7 Å rule also picks up Asp238 OD2 / Asp230 OD1 (Mn1) and Asp349 OD1 (Mn2).

## 6. To-do (ordered; items 2+ need an explicit go because they spend spot compute)
1. ✅ Root-cause fix + gate + validator + tests (this commit).
2. **Pick the Mn3 relaxation strategy (§5)** — design decision, no compute.
3. Rebuild the complex leg (CPU preflight on Batch) → read the `MN_SITE` lines → confirm predictions above.
4a. Re-equilibrate **with** `--mn-restrain` (bonded CaDA, small dt) → inspect em/nvt/npt with `validate_mn_coordination.py`.
4b. **Unrestrained continuation (NOT YET BUILT)** → `--mode post`, ≥ 1 ns: per-Mn Mn–O(protein/ligand) distances 2.0–2.6 Å, coordination number, cage M–D / angles. Acceptance
   = every Mn keeps ≥ 2 protein/ligand O for the whole run and the cage holds. **This is the actual metal-model validation.**
5. Only then re-run the YY→FF control against the measured **−0.95 kcal/mol**, and the metal-perturbing Asp→Ala edge
   (`EDGE_MUTS='P 2 ALA'`, already stubbed). Report sign **and** magnitude; no "recovered ≈0" framing.
6. Verify the metal identities/occupancy for the *measured* assay (the Quigley ELISA buffer) before assigning 3×Mn;
   the committee review noted MIDAS/ADMIDAS/SyMBS are typically Mn/Mg-Ca/Ca depending on conditions — **unverified here**.
7. Make the live FEP path honour the same readiness rule: `fep_production.py` has no `MDRUN_CMD_READY` guard (guard lives
   only in the superseded `fep_batch.py`); require a passing `--mode post` result before any production window is submitted.
8. Sampling: production fan-out is independent λ windows (not HREX) at 0.5 ns/window; analytic BAR error only.
9. Annotate the acceptance doc (done in this commit) and keep the controls-doc §6c correction consistent with §3 above.

### Carried over from the session (not part of this validation)
- αvβ6 selectivity is still `pending` in `score.py`; Tier-B (FF 2494× over αvβ3, etc.) is the measured target for it.
- CRO panelB contains no RGD (0/12) and fails our own gate; PD-L1 panelA 0/10 — do not order without re-gating.
- Availability model shipped (`peptide_availability.py`, LODO ρ ≈ 0.40); next optional upgrades are position-aware features
  and a second dataset for robustness. It is informational only for surface targets.
- Cyclic-LLM manuscript: the display-selector result is circular (abundance null); the FEP wording has been corrected twice
  (−0.95 measured; and now: the control ran on a metal-free pocket).

## 7. Runbook (what needs you vs. what I can run)
Only EC2 launches need you (the in-session agent cannot call `run-instances`); I can submit the Batch job and read S3.
1. **You:** `! bash research/guangzhou_all_atom/fep/build_fep_inputs.sh` — spot CPU, self-terminates ≤ 90 min, writes `…/avb6-fep-ctrl-build2/`.
2. **Me:** read `…/build2/fepbuild_stdout.txt`. **Predictions (written before running):**
   `MN_SITE res=1 … OK`, `res=2 … OK`, `res=3 … CLASH(warn) minO=0.82`; `MN_RESTR_OK pairs=14 for 3 Mn`; `complex_EM_RESTR_TPR_OK`;
   `FEP_INPUTS_READY`. Any `MN_UNBOUND` means the frame assumption is wrong → stop. Any `MN_RESTR_GROMPP_FAIL` = restraint syntax/index
   problem → fix on CPU, no GPU spent.
3. **Me (after your go, spot GPU):** `python3 cyclic_llm/fep_batch.py --equil --legs=complex --mn-restrain --run-id=avb6-fep-ctrl-build2 --submit`.

## 8. Rebuild result (build2, 2026-10-25) — predictions confirmed; fix verified on the real artifact
Run `avb6-fep-ctrl-build2` (spot c6i.2xlarge, launched by the user). `fepbuild_stdout.txt`, against the predictions written in §7:

| prediction (written before) | observed |
|---|---|
| Mn1 OK, Mn2 OK, Mn3 CLASH(warn) 0.82 Å | `res=1 OK minO 2.10` · `res=2 OK minO 2.19` · `res=3 CLASH(warn) minO 0.82` |
| `MN_RESTR_OK pairs=14` | `pairs=14 for 3 Mn (b0 window 0.205-0.240 nm, kb=2000)` |
| restraint block parses | `complex_EM_RESTR_TPR_OK` |
| sentinel + gate marker | `FEP_INPUTS_READY`, `in/complex/mn_site_gate.txt` staged |

The pre-EM gate runs *before* `editconf -c`, so it cannot by itself show that centring moves the Mn with the receptor. That was checked
on the **final** `in/complex/ionized.gro` (after centring, solvation, genion) with `fep/validate_mn_coordination.py --mode pre`:
Mn1 6 O within 3 Å (min 2.10 Å), Mn2 6 O (2.19 Å), Mn3 4 O (**0.82 Å, ligand contact = True**, Asp1071 OD2 / Glu818 OE2 1.41 Å / Ser720 OG 2.27 Å);
**0/3 failing** — versus 3/3 UNBOUND for build1. So the frame fix holds end-to-end. (System is 204,981 atoms vs 204,942 in build1: the box is
now centred on receptor+peptide+Mn, so the water/ion count differs slightly.)

Still true: `grompp` succeeding does **not** show EM converges from the 0.82 Å Mn3 clash. The restrained equilibration is the first
step that tests that; the unrestrained run (`fep_batch.py --mn-validate`, built, not run) is the metal-model test. Neither has been submitted.


===== DOC: docs/20261025_PEPTIDE_AVAILABILITY_MODEL.md =====
# A deployable peptide *availability* predictor (Landry-grounded) — useful model for the community + BioMate

**2026-10-25.** A real, honest, useful model — not a SOTA chase. Module: `research/guangzhou_all_atom/cyclic_llm/peptide_availability.py`.

## Why this, and why it's the *right* thing to build
Across this program every attempt to predict *binding/affinity* **across contexts** collapsed under proper
held-out testing (cyclic cross-target, renal cross-target, SH3 cross-domain). The honest lesson: binding
doesn't transfer. **But peptide *availability* — how much of the peptide is actually free to act in the
cell — is a peptide-*intrinsic* property, so it transfers where binding does not.** Lemieux … Landry
(bioRxiv 2026, doi:10.64898/2026.09.21.752983; 6,500+ in-cell DHFR-PCA variants) showed availability is
largely set by hydrophobicity/charge and **limits functional binding independently of affinity** — a factor
standard design pipelines ignore and for which **no deployable predictor existed.** This fills that gap.

## The model
`availability_score = 0.3318 − 0.2541·meanKD_hydrophobicity − 0.1479·net_charge − 0.4793·frac_charged`
(OLS on Landry PCA1 measured availability, 7 SH3 domains, ~3,000 variants). More hydrophobic / more charged
→ less available.

| metric | value |
|---|---|
| in-sample Spearman (pred vs measured availability) | 0.72 |
| **leave-one-DOMAIN-out Spearman (cross-domain, honest)** | **0.40** (per-domain 0.23–0.49, robust) |
| low-availability flag | measured 25th-pct threshold (−0.142) |

Contrast with binding: the *binding* model's cross-domain Spearman was ~0.27 and **got worse** when
availability was added as a correction — because binding is domain-specific. Availability at a *robust* 0.40
across held-out domains is the usable, transferable signal. Honest scope: it is a **ranking / liability
flag**, not a precise oracle.

## Usefulness (community + platform + project)
- **Community (primary):** an open, first-of-its-kind deployable **availability-risk flag** for peptide
  designers — most directly functional for **intracellular** targets (SH3/PDZ/short-linear-motif and
  cell-penetrating peptides), where availability literally gates function. `predict_availability(seq)`.
- **Platform (BioMate):** an informational **availability/developability score** for the peptide gate chain,
  upgrading the ad-hoc "greasy" hydrophobicity flag with a calibrated, data-grounded model.
- **Project (αvβ6 / PD-L1):** screened our v2 CRO panel — **all 12 pass** the availability flag; the model
  correctly ranks the greasiest candidates (AVB6-V2-06, PDL1-V2-02) as relatively higher risk.

## Honest caveats (stated plainly)
1. **Moderate accuracy** (cross-domain ρ ≈ 0.40): a *ranking/triage* tool, not a quantitative oracle.
2. **Trained on canonical linear SH3 peptides.** For cyclic/ncAA macrocycles (our αvβ6 RGD cyclics,
   PD-L1 bicyclics) it is an **approximation** over the canonical residues; the module flags ncAA fraction.
3. **"Availability" here is *intracellular*.** It is directly functional for intracellular targets. **Our
   αvβ6/PD-L1 targets are cell-surface / extracellular**, so for *them* this score is a **developability /
   solubility-aggregation proxy** (hydrophobicity/charge-driven), not a functional-availability predictor —
   do not over-read the "pass" as functional validation for surface targets.

## Provenance / open
Data: `github.com/Landrylab/Lemieux_et_al2026` (CC BY-NC-ND; `data/PCA1/med_avail_score.csv`). Our model
coefficients + module are open and reproducible from that data. Next (optional) upgrades: richer features /
nonlinear model (honest ceiling ~0.40 cross-domain), and position-aware availability; integrate as an
informational score (not a hard gate) in `score.py` / `knowledge_liability_flags.py`.


===== CODE: research/guangzhou_all_atom/cyclic_llm/loop.py =====
```python
"""Phase-1.2: the closed optimizer loop.  propose -> score() -> select -> revise -> repeat.

Ties the already-built pieces into one driver:
  - propose : rule_conditioned_generator.gen_avb6 (clean by construction) + a deliberately-failing seed set
  - score   : score.score  (cheap deterministic tier: rule + FTO + developability; expensive tier = hooks)
  - select  : freeze gate-passers, Pareto-rank by score.rank_key
  - revise  : a deterministic, score-record-READING repair operator.  This is the SYMBOLIC STAND-IN for the
              LLM-in-the-loop revise move (the SL-01 -> SL-v3 "read the failing objective, edit the free
              position" step) - same honest stand-in posture as the enumeration generator.  When the neural
              generator / an RL driver lands, it replaces `revise` (and the reward stays score()).

Honest framing: no LLM or RL is wired here yet.  The loop HARNESS and the convergence (failure -> targeted
repair -> re-score -> gated) are real and deterministic; `revise` is a labeled stand-in, not a learned policy.
"""
import json, os, sys
sys.path.insert(0, os.path.dirname(__file__))
from score import score
from rule_conditioned_generator import gen_avb6
from acceptance_gate import raw_tokens, _is_arom, _strip_mods

HERE = os.path.dirname(__file__)

# free positions in the KB scaffold  cyclo(p1 - R - G - D - L - p6 - p7 - [dP] - [NMeK])
P1, P6, P7 = 0, 5, 6


def _helm(toks):
    """Rebuild a HELM string from token cores: canonical 1-letter bare, everything else bracketed."""
    return "cyclo(" + "-".join(t if len(t) == 1 else f"[{t}]" for t in toks) + ")"


def revise(rec):
    """Read the failing objective in a score() record and apply ONE targeted free-position edit.
    Returns (repaired_helm, action) or (None, reason) when the failure is outside the free-position repair set.
    One failure-class per call; the loop re-scores and the next round catches the next class."""
    if rec["hard_gate_pass"]:
        return None, "already-gated"
    toks = raw_tokens(rec["helm"])
    if len(toks) != 9:
        return None, "ring-size!=9 (not repairable by free-position edit)"
    r = rec["hard_gate_reasons"]
    # 1) rule fail -> restore aromatic character at whichever flank is non-aromatic
    if not r["rule"]:
        fixed = []
        for idx in (P1, P7):
            if not _is_arom(toks[idx]):
                toks[idx] = "F"
                fixed.append(f"p{1 if idx==P1 else 7}->F")
        if fixed:
            return _helm(toks), "rule:flank-aromatic(" + ",".join(fixed) + ")"
        return None, "rule-fail not at a free flank"
    # 2) FTO infringing (literal genus) -> diverge the P7 flank with an ncAA homolog -> literally OUTSIDE(MED)
    if not r["fto_not_infringing"]:
        toks[P7] = "2Nal"
        return _helm(toks), "fto:p7->[2Nal] (ncAA-divergent, out of literal genus)"
    # 3) developability fail -> de-grease / drop liability at a free position
    if not r["developability"]:
        dev = rec["developability"]
        act = []
        if dev["greasy"]:
            if "2Nal" in (toks[P7], toks[P1]):                # too many naphthylalanines
                idx = P7 if toks[P7] == "2Nal" else P1
                toks[idx] = "Phe4F"                            # milder aromatic, still satisfies the rule
                act.append(f"p{7 if idx==P7 else 1}:[2Nal]->[Phe4F]")
            else:                                             # high meanH from elsewhere -> least-greasy aromatic
                toks[P7] = "Y"
                act.append("p7->Y (lower hydrophobicity)")
        if dev["liabilities"] and toks[P6] not in ("A", "G"):
            toks[P6] = "A"                                    # neutralize the specificity-knob liability motif
            act.append("p6->A (drop liability)")
        if act:
            return _helm(toks), "dev:" + ",".join(act)
        return None, "developability-fail not repairable at a free position"
    return None, "unknown-failure"


def optimize(seed, target="avb6", rounds=4):
    """Run the closed loop. Gate-passers are frozen; failures are revised and re-entered; stop when no failure
    is repairable or `rounds` is hit. Returns the Pareto-ranked gated set + a per-round trace."""
    population = list(dict.fromkeys(seed))      # dedupe, preserve order
    gated, seen, trace = {}, set(seed), []
    for rnd in range(1, rounds + 1):
        scored = [score(h, target) for h in population]
        passes = [r for r in scored if r["hard_gate_pass"]]
        fails = [r for r in scored if not r["hard_gate_pass"]]
        for r in passes:
            gated[r["helm"]] = r                 # freeze
        nxt, revisions = [], []
        for r in fails:
            new, action = revise(r)
            failed = [k for k, v in r["hard_gate_reasons"].items() if not v]
            if new and new not in seen:
                seen.add(new); nxt.append(new)
                revisions.append({"from": r["helm"], "to": new, "action": action, "status": "revised", "failed": failed})
            elif new:                                    # repaired onto a candidate already in the loop
                revisions.append({"from": r["helm"], "to": new, "action": action,
                                  "status": "converged (= existing candidate)", "failed": failed})
            else:                                        # no free-position edit resolves this failure
                revisions.append({"from": r["helm"], "to": None, "action": action,
                                  "status": "abandoned", "failed": failed})
        trace.append({"round": rnd, "scored": len(scored), "gated_now": len(passes), "failed": len(fails),
                      "revised": len([x for x in revisions if x["status"] == "revised"]),
                      "converged": len([x for x in revisions if x["status"].startswith("converged")]),
                      "abandoned": len([x for x in revisions if x["status"] == "abandoned"]),
                      "revisions": revisions})
        if not nxt:
            break
        population = nxt
    pareto = sorted(gated.values(), key=lambda r: r["rank_key"])
    return {"target": target, "n_gated": len(pareto), "pareto": pareto, "trace": trace}


if __name__ == "__main__":
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument("--neural", action="store_true",
                    help="use the neural proposer (unified_cyclic_llm_v4) instead of the enumeration stand-in")
    ap.add_argument("--rounds", type=int, default=4)
    cli = ap.parse_args()
    # propose: clean by-construction survivors  +  a deliberately-FAILING seed set (so revise has real work)
    if cli.neural:
        from neural_generator import gen_avb6_neural
        _H, clean, _meta = gen_avb6_neural(n=4)
        proposer = f"neural ({_meta['backend']})"
    else:
        _H, clean = gen_avb6(4)
        proposer = "enumeration"
    failing = [
        "cyclo(F-R-G-D-L-A-F-[dP]-[NMeK])",                 # avebehexin  -> INFRINGING (literal genus)
        "cyclo([2Nal]-R-G-D-L-A-[2Nal]-[dP]-[NMeK])",       # di-2Nal     -> GREASY (developability)
        "cyclo(A-R-G-D-L-G-A-[dP]-[NMeK])",                 # di-Ala flank-> RULE FAIL (no aromatic flanks)
    ]
    seed = [c["helm"] for c in clean] + failing
    res = optimize(seed, "avb6", rounds=cli.rounds)

    print(f"PROPOSER: {proposer}")
    print(f"SEED ({len(seed)}): {len(clean)} clean(by-construction) + {len(failing)} deliberately-failing\n")
    for t in res["trace"]:
        print(f"round {t['round']}: scored={t['scored']} gated={t['gated_now']} failed={t['failed']} "
              f"revised={t['revised']} converged={t['converged']} abandoned={t['abandoned']}")
        for rv in t["revisions"]:
            arrow = f"-> {rv['to']}" if rv["to"] else "-> (no free-position repair)"
            print(f"    FAIL {rv['failed']}  {rv['from']}")
            print(f"        [{rv['status']}] {rv['action']}  {arrow}")
    print(f"\nPARETO-RANKED GATED SET ({res['n_gated']}):")
    for r in res["pareto"]:
        print(f"  {r['helm']}  | FTO {r['fto']['verdict']} (DoE {r['fto']['doe']}) | dev meanH={r['developability']['meanH']} | binding={r['binding_dG']}")

    out = os.path.join(HERE, "target_kb", "avb6_loop_result.json")
    json.dump(res, open(out, "w"), indent=2)
    print(f"\nwrote {os.path.relpath(out, HERE)}  (loop result: pareto set + full revise trace)")

```

===== CODE: research/guangzhou_all_atom/cyclic_llm/reward.py =====
```python
"""Phase-1.3 / own-LLM item #8: the RLVR reward + loop→DPO bridge.

Turns the consolidated verifier `score()` into the two signals an own-LLM generator trains against:
  (1) reward(score_record) -> scalar  — the verifiable reward for RL (RLVR). It encodes the direction doc's
      key lesson (docs/20261015_OWN_LLM_OPTIMIZATION_DIRECTION.md §2C): reward passing ALL the hard gates, not
      just binding — the exact failure of this program's G2 round (24 binders, 0 selective). So the hard gate
      (rule ∧ not-infringing ∧ developability) dominates, and selectivity is a first-class SOFT term alongside
      binding, novelty, FTO-DoE and groove (each only when admissible / present).
      BINDING term = the TRUSTWORTHY arbiter when present: relative FEP ΔΔG (`ddg_fep`). MM-GBSA (`binding_dG`)
      is a weak feasibility PROXY, used only as a fallback when no FEP ΔΔG exists (the "SMILES->GAFF MM-GBSA?"
      critique). Making the RL reward's physics = FEP ΔΔG, distinct from any MM-GBSA/display held-out evaluator,
      also directly mitigates circularity threat #4 in the innovation-thesis doc.
  (2) build_preference_pairs(scored) -> dpo_pairs.PairSet — ranks the loop's scored candidates by reward and
      emits chosen≻rejected pairs in the EXISTING dpo_pairs schema (STREAM_VERIFY_SELECT), ready for the
      existing dpo_peptide_trainer.py / TRL DPOTrainer. The loop is the data factory; this is the tap.

HONEST SCOPE — this does NOT train. Per the direction doc §5 (volume gate) + the no-tiny-dataset rule, gradient
RLVR waits until the closed loop produces scored candidates at volume (and, later, assay outcomes as the ground-
truth reward). This module is the reward function + preference-data emitter + a best-of-N DEMONSTRATION that the
reward ranks correctly. Early reward is the verifier (relative, feasibility-level); assay outcome replaces it
later. No GPU, no training, CPU only.
"""
import json, os, sys

HERE = os.path.dirname(__file__)
PARENT = os.path.dirname(HERE)
for _p in (HERE, PARENT):
    if _p not in sys.path:
        sys.path.insert(0, _p)

# reward weights (explicit + documented; gate dominates, selectivity is first-class)
DEFAULT_WEIGHTS = {
    "gate_pass": 1.0,          # base reward for passing ALL hard gates
    "gate_fail_base": -1.0,    # base for a gate failure
    "gate_fail_per": -0.25,    # extra penalty per failed hard gate
    "doe": 0.30,               # FTO doctrine-of-equivalents RISK (lower risk better) -> scaled
    "novelty": 0.30,           # 1 - nearest_patented_identity (more novel better)
    "developability": 0.20,    # liability-free + mid hydrophobicity
    "ddg_fep": 0.90,           # TRUSTWORTHY ARBITER: relative FEP ΔΔG (more negative better); preferred binding term
    "binding": 0.45,           # MM-GBSA ΔG — FEASIBILITY-LEVEL FALLBACK only, used iff no FEP ΔΔG (weak proxy)
    "selectivity": 0.60,       # admissible on-target selectivity gap (more negative better); 0 if pending
    "groove": 0.20,            # admissible groove occupancy (higher better); 0 if pending
    "known_active_penalty": -0.5,  # structure Tanimoto re-discovery (fto.novelty verdict == known_active)
}
_DOE_RISK = {"LOW": 0.0, "MED": 0.5, "HIGH": 1.0, "infringes": 1.0}   # risk fraction (lower is better)


def _num(x):
    return x if isinstance(x, (int, float)) else None


def reward(rec, weights=None):
    """Scalar reward from a score() record. Returns {reward, gated, terms}. Only admissible/present objectives
    contribute (pending physics contributes 0 — feasibility-level reward, honestly)."""
    w = {**DEFAULT_WEIGHTS, **(weights or {})}
    terms = {}
    gated = bool(rec.get("hard_gate_pass"))
    if gated:
        terms["gate"] = w["gate_pass"]
    else:
        n_fail = sum(1 for v in rec.get("hard_gate_reasons", {}).values() if not v)
        terms["gate"] = w["gate_fail_base"] + w["gate_fail_per"] * max(0, n_fail - 1)

    fto = rec.get("fto", {})
    # FTO DoE risk (lower risk -> higher reward)
    terms["doe"] = w["doe"] * (1.0 - _DOE_RISK.get(fto.get("doe"), 0.5))
    # novelty vs known patented compounds (lower identity -> more novel)
    pid = _num(fto.get("patent_id"))
    if pid is not None:
        terms["novelty"] = w["novelty"] * (1.0 - pid)
    # structure re-discovery penalty (real Tanimoto axis, when the full-tier novelty ran)
    nov = fto.get("novelty") or {}
    if nov.get("verdict") == "known_active":
        terms["known_active"] = w["known_active_penalty"]

    # developability (liability count + hydrophobicity band)
    dev = rec.get("developability", {})
    if dev:
        liab = len(dev.get("liabilities", []))
        meanH = _num(dev.get("meanH"))
        band = 1.0 if (meanH is not None and -0.2 <= meanH <= 0.7) else 0.4
        terms["developability"] = w["developability"] * max(0.0, (1.0 - 0.25 * liab)) * band

    # expensive tier — only when admissible (numeric, not "pending")
    # BINDING: prefer the trustworthy FEP ΔΔG arbiter; MM-GBSA is a weak feasibility proxy used ONLY as a
    # fallback when no FEP ΔΔG is present (the "SMILES→GAFF MM-GBSA?" critique + circularity-threat #4: the
    # RLVR training reward should be FEP ΔΔG, distinct from any MM-GBSA/display held-out evaluator).
    ddg = _num(rec.get("ddg_fep"))
    b = _num(rec.get("binding_dG"))
    if ddg is not None:
        terms["ddg_fep"] = w["ddg_fep"] * max(0.0, min(1.0, -ddg / 3.0))      # relative ΔΔG; ~-3 kcal/mol saturates
    elif b is not None:
        terms["binding_mmgbsa_proxy"] = w["binding"] * max(0.0, min(1.0, -b / 40.0))   # fallback; ~-40 kcal/mol saturates
    s = _num(rec.get("selectivity_gap"))
    if s is not None:
        terms["selectivity"] = w["selectivity"] * max(0.0, min(1.0, -s / 15.0))   # negative gap = selective
    g = _num(rec.get("groove_occupancy"))
    if g is not None:
        terms["groove"] = w["groove"] * max(0.0, min(1.0, g))

    return {"reward": round(sum(terms.values()), 4), "gated": gated,
            "terms": {k: round(v, 4) for k, v in terms.items()}}


def rank_by_reward(scored, weights=None):
    """Attach reward to each score() record and return sorted (best first)."""
    out = [{**rec, "_reward": reward(rec, weights)} for rec in scored]
    out.sort(key=lambda r: -r["_reward"]["reward"])
    return out


def build_preference_pairs(scored, *, prompt="", weights=None, max_pairs=None):
    """Rank the loop's scored candidates by reward and emit chosen≻rejected pairs in the EXISTING dpo_pairs
    schema (STREAM_VERIFY_SELECT). chosen = gate-passing; rejected = gate-failing (cleanest negatives) then
    lower-reward gated; margin = reward gap. Representation = HELM (the peptide generator is HELM-native).
    Returns a dpo_pairs.PairSet (its .to_trl_records() feeds the DPO trainer)."""
    from dpo_pairs import PreferencePair, PairSet, STREAM_VERIFY_SELECT
    ranked = rank_by_reward(scored, weights)
    gated = [r for r in ranked if r["_reward"]["gated"]]
    failed = [r for r in ranked if not r["_reward"]["gated"]]
    pairs, seen = [], set()
    # strongest signal: every gated candidate ≻ every gate-failing candidate
    for pos in gated:
        for neg in failed + [g for g in gated if g["_reward"]["reward"] < pos["_reward"]["reward"]]:
            if pos["helm"] == neg["helm"]:
                continue
            key = (prompt, pos["helm"], neg["helm"])
            if key in seen or (prompt, neg["helm"], pos["helm"]) in seen:
                continue
            seen.add(key)
            margin = round(pos["_reward"]["reward"] - neg["_reward"]["reward"], 4)
            clean = not neg["_reward"]["gated"]
            pairs.append(PreferencePair(
                prompt=prompt, chosen=pos["helm"], rejected=neg["helm"],
                stream=STREAM_VERIFY_SELECT, chosen_id=pos["helm"], rejected_id=neg["helm"],
                margin=margin, weak=not clean,
                reason=("gated ≻ gate-failed" if clean else "gated higher-reward ≻ gated lower-reward"),
                provenance={"stream": STREAM_VERIFY_SELECT, "reward_source": "score() verifier (feasibility-level)"}))
            if max_pairs and len(pairs) >= max_pairs:
                return PairSet(pairs=pairs, notes=["reward-ranked verify_select pairs (capped)"])
    return PairSet(pairs=pairs, notes=["reward-ranked verify_select pairs from score()"])


if __name__ == "__main__":
    from score import score
    from rule_conditioned_generator import gen_avb6
    # demo pool: gated by-construction survivors + deliberately gate-FAILING candidates (reward spread)
    _H, clean = gen_avb6(6)
    failing = ["cyclo(F-R-G-D-L-A-F-[dP]-[NMeK])",          # INFRINGING
               "cyclo([2Nal]-R-G-D-L-A-[2Nal]-[dP]-[NMeK])",  # greasy
               "cyclo(A-R-G-D-L-G-A-[dP]-[NMeK])"]           # rule fail
    pool = [c["helm"] for c in clean] + failing
    scored = [score(h, "avb6") for h in pool]
    ranked = rank_by_reward(scored)

    print("=== reward ranking (score() verifier as RLVR reward) ===")
    for r in ranked:
        rw = r["_reward"]
        print(f"  reward={rw['reward']:+.3f} gated={rw['gated']}  {r['helm']}")
        print(f"      terms={rw['terms']}")
    ps = build_preference_pairs(scored, prompt="avb6", max_pairs=40)
    print(f"\n=== DPO preference pairs (verify_select, reward-ranked) ===")
    print(f"  emitted {len(ps.pairs)} pairs  stream_counts={ps.stream_counts()}")
    for p in ps.pairs[:4]:
        print(f"    chosen≻rejected (margin {p.margin}, {'clean' if not p.weak else 'weak'}): {p.reason}")
    out = os.path.join(HERE, "target_kb", "avb6_dpo_pairs.jsonl")
    ps.write_jsonl(out)
    print(f"\n  wrote {os.path.relpath(out, HERE)} ({len(ps.pairs)} pairs, full provenance)  -> dpo_peptide_trainer.py / TRL")

    # the G2 lesson, encoded: selectivity is a first-class reward term (admissible physics, PD-L1 round)
    try:
        import physics_dispatch as pd
        g1 = pd._load("pdl1_g1_candidates.json"); g2 = pd._load("pdl1_g2_candidates.json")
        k05 = next(r["helm"] for r in g1["prior_round3"] if r["id"] == "PDL1-K-05")
        a02 = next(r["helm"] for r in g2["candidates"] if r["id"] == "PDL1-G2-A02")
        print("\n=== selectivity reward (the G2 lesson: reward ALL gates, not just binding) ===")
        for lbl, h in [("K-05  selective (gap −15.27)", k05), ("G2-A02 NOT selective (gap +14.11)", a02)]:
            t = reward(score(h, "pdl1", tier="full"))["terms"]
            print(f"  {lbl}: binding_term={t.get('binding')}  selectivity_term={t.get('selectivity')}")
    except Exception as e:
        print(f"\n(selectivity demo skipped: {e})")
    print("\n  NOTE: reward + pairs only; gradient RLVR is gated on loop volume + GPU (OWN_LLM doc §5).")

```

===== CODE: research/guangzhou_all_atom/cyclic_llm/score.py =====
```python
"""Consolidated verifier / reward. One score() that merges all objectives into a single record:
- CHEAP tier (inline, deterministic, zero-cost): rule pass, FTO claim verdict + DoE, developability proxy.
- EXPENSIVE tier (hooks): binding dG (MM-GBSA), selectivity gap (counter-target), groove occupancy, geometry
  triage - supplied from the GPU pipeline results when available (control-anchored / A2), else 'pending'.
This is the reward the design->score->redesign loop optimizes and the own-LLM would later train against (RLVR)."""
import json, os
from acceptance_gate import raw_tokens, _strip_mods, avb6_gate
from fto_score import fto_score
try:
    from peptide_availability import predict_availability   # Landry-grounded availability flag (informational)
except Exception:
    predict_availability = None

FP = {"W": 2.25, "F": 1.79, "I": 1.80, "L": 1.70, "M": 1.23, "V": 1.22, "C": 1.54, "Y": 0.96, "P": 0.72,
      "A": 0.31, "T": 0.26, "H": 0.13, "G": 0.0, "S": -0.04, "Q": -0.22, "N": -0.60, "E": -0.64, "D": -0.77,
      "K": -0.99, "R": -1.01, "2Nal": 2.8, "Phe4F": 1.9, "Phe4Cl": 2.0}
AROM = {"F", "Y", "W", "H", "2Nal", "Phe4F", "Phe4Cl"}

def developability(helm):
    cores = [_strip_mods(t) for t in raw_tokens(helm)]
    s = "".join(c if len(c) == 1 else "X" for c in cores)
    w = s + s[:1]
    liab = []
    for i in range(len(s)):
        if w[i:i+2] in ("NG", "NS"): liab.append("deamidation")
        if w[i:i+2] in ("DG", "DS"): liab.append("isomerization")
    if cores.count("M"): liab.append("Met-ox")
    if cores.count("C") == 1: liab.append("free-Cys")
    if cores.count("W") >= 2: liab.append("multi-Trp-ox")
    n2 = sum(1 for c in cores if c == "2Nal")
    meanH = round(sum(FP.get(c, 0.0) for c in cores) / max(len(cores), 1), 2)
    net = sum(1 for c in cores if c in ("R", "K")) - sum(1 for c in cores if c in ("D", "E"))
    greasy = (n2 >= 2) or (meanH > 0.9)
    return {"meanH": meanH, "n2Nal": n2, "net_charge": net, "liabilities": liab, "greasy": greasy,
            "pass": (not liab) and (not greasy) and (-2 <= net <= 2)}

def score(helm, target="avb6", binding_dG=None, selectivity_gap=None, groove=None, geometry=None,
          ddg_fep=None, tier="cheap"):
    """Merge every objective into one record + a hard-gate verdict + a rank key.
    tier='cheap' (default): deterministic tier only; expensive hooks stay 'pending' unless passed explicitly.
    tier='full': auto-dispatch the expensive tier from the GPU pipeline RESULTS (physics_dispatch), control-
    anchored (A2) — only admissible values are filled; explicit kwargs still override."""
    rec = {"helm": helm, "target": target}
    # cheap deterministic tier
    rec["rule_pass"] = avb6_gate(helm)["PASS_H1_H5"] if target == "avb6" else None
    f = fto_score(helm, target, structure=(tier == "full"))   # full tier adds the real structure/patent axis
    rec["fto"] = {"verdict": f["claim"]["verdict"], "doe": f["claim"]["doe"],
                  "patent_id": f["nearest_patented_identity"]}
    if "novelty" in f:
        rec["fto"]["novelty"] = f["novelty"]
    rec["developability"] = developability(helm)
    # availability (Landry 2026): INFORMATIONAL only — does NOT gate. Peptide-intrinsic, cross-domain-robust
    # (LODO Spearman ~0.40). For intracellular targets it flags functional-availability risk; for cell-surface
    # αvβ6/PD-L1 it is a developability/solubility proxy. Never blocks (so it can't wrongly reject a surface binder).
    if predict_availability is not None:
        try:
            a = predict_availability(helm)
            rec["availability"] = {"score": a.score, "low_availability": a.low_availability,
                                   "mean_hydrophobicity": a.mean_hydrophobicity, "note": a.note,
                                   "context": ("functional_intracellular" if target in ("sh3", "pdz", "intracellular")
                                               else "developability_proxy_surface_target")}
        except Exception as e:
            rec["availability"] = {"error": str(e)[:60]}
    # expensive tier: auto-dispatch admissible physics when tier='full' (explicit kwargs take precedence)
    if tier == "full":
        from physics_dispatch import physics_for
        p = physics_for(helm, target)
        for fld, var in (("binding_dG", binding_dG), ("selectivity_gap", selectivity_gap),
                         ("groove", groove), ("geometry", geometry), ("ddg_fep", ddg_fep)):
            if var is None and p["admissible"].get(fld) and p[fld] is not None:
                if fld == "binding_dG": binding_dG = p[fld]
                elif fld == "selectivity_gap": selectivity_gap = p[fld]
                elif fld == "groove": groove = p[fld]
                elif fld == "geometry": geometry = p[fld]
                elif fld == "ddg_fep": ddg_fep = p[fld]
        rec["physics"] = {"design_id": p["design_id"], "provenance": p["provenance"], "reasons": p["reasons"]}
    # ddg_fep = relative FEP ΔΔG (trustworthy arbiter; negative = tighter than the reference edge). This is the
    # physics the RLVR reward PREFERS over MM-GBSA binding_dG (a weak feasibility proxy). Pending until the gated
    # FEP control edge runs + validates (fep_batch.py); for αvβ6 it is the ONLY admissible binding signal (the
    # metal-free MM-GBSA is voided — see physics_dispatch).
    rec["ddg_fep"] = ddg_fep if ddg_fep is not None else "pending"
    rec["binding_dG"] = binding_dG if binding_dG is not None else "pending"
    rec["selectivity_gap"] = selectivity_gap if selectivity_gap is not None else "pending"
    rec["groove_occupancy"] = groove if groove is not None else "pending"
    rec["geometry"] = geometry if geometry is not None else "pending"
    # hard gates (cheap): rule + not-infringing + developability
    infring = rec["fto"]["verdict"].startswith("INSIDE")
    rec["hard_gate_pass"] = bool(rec["rule_pass"]) and (not infring) and rec["developability"]["pass"]
    rec["hard_gate_reasons"] = {"rule": rec["rule_pass"], "fto_not_infringing": not infring,
                                "developability": rec["developability"]["pass"]}
    # rank key: gate first, then FTO DoE (LOW<MED<HIGH), then binding (if present), then low patent-id
    doe_rank = {"LOW": 0, "MED": 1, "HIGH": 2, "infringes": 3}
    # prefer the trustworthy FEP ΔΔG for ranking when present; else fall back to MM-GBSA binding_dG
    b = (ddg_fep if isinstance(ddg_fep, (int, float))
         else (binding_dG if isinstance(binding_dG, (int, float)) else 0.0))
    rec["rank_key"] = (0 if rec["hard_gate_pass"] else 1, doe_rank.get(rec["fto"]["doe"], 1), b,
                       rec["fto"]["patent_id"])
    return rec

if __name__ == "__main__":
    tests = ["cyclo(F-R-G-D-L-A-F-[dP]-[NMeK])",          # infringing
             "cyclo(F-R-G-D-L-G-[2Nal]-[dP]-[NMeK])",     # MED DoE, clean dev
             "cyclo(F-R-G-D-L-A-[2Nal]-[dP]-[2Nal])",     # greasy (2x2Nal)
             ]
    for h in tests:
        r = score(h)
        print(f"{h}")
        print(f"   gate={r['hard_gate_pass']} reasons={r['hard_gate_reasons']} | FTO {r['fto']['verdict']}({r['fto']['doe']}) | dev {r['developability']['pass']} meanH={r['developability']['meanH']} | binding={r['binding_dG']}")

```

===== CODE: research/guangzhou_all_atom/cyclic_llm/neural_generator.py =====
```python
"""Phase-1.1: the NEURAL proposer — replaces the enumeration stand-in in rule_conditioned_generator.

What the neural model contributes (honest scope):
  - The unified v4 cyclic-peptide LLM (unified_cyclic_llm.py / design.py, ckpt runs_helm/unified_cyclic_llm_v4.pt)
    is a monomer-level macrocycle generator trained on CycPeptMPDB (ncAA + measured permeability) + a display
    pool (binding). Here it PROPOSES the free-position chemistry of the αvβ6 pharmacophore scaffold
    cyclo(p1 - R-G-D-L - p6 - p7 - [dP] - [NMeK]) by scoring each candidate macrocycle's likelihood under
    null-target + HIGH-permeability conditioning, then SAMPLING free-position triples in proportion to that
    likelihood. So the free positions are now chosen by a learned, permeability-biased density instead of a
    fixed enumeration order.
  - The RGD pharmacophore scaffold + the induced rule + FTO stay SYMBOLIC hard constraints (SNG pattern): the
    neural model proposes inside the constrained free space; rule / FTO / developability reject + rank.

Honest limitations (NOT hidden):
  - The v4 model is NOT trained on αvβ6 — conditioning here is null-target + permeability, so the neural signal
    is "developable / permeable macrocycle chemistry," not avb6 affinity. Affinity is the expensive tier (score
    full) / wet-lab.
  - Neural palette = monomers the model knows AND the symbolic gate already classifies correctly
    (aromatic flanks F/Y/W/Nal; small knob A/G/S/Aib/Abu). The model's OOV handle [NMeK] is represented as K
    for the model's context only. Expanding the palette to exotic aromatic ncAA (3Pal, Bal, Bn_Gly, ...) needs a
    VETTED monomer-property table (aromaticity + hydrophobicity + FTO homolog) first — a data task, not a guess.
  - Falls back to the enumeration proposer (rule_conditioned_generator.gen_avb6) if torch / the checkpoint is
    unavailable, with backend="enumeration(fallback)" so the loop never silently degrades.
"""
import json, os, sys, random
sys.path.insert(0, os.path.dirname(__file__))
from rule_induction import predicates
from acceptance_gate import avb6_gate
from fto_score import fto_score

HERE = os.path.dirname(__file__)
ROOT = os.path.dirname(HERE)
CKPT = os.path.join(ROOT, "runs_helm", "unified_cyclic_llm_v4.pt")
TARGETS_JSON = os.path.join(ROOT, "data", "display", "target_proteins.json")

# free-position palette: model-known (CycPeptMPDB vocab) AND symbolic-gate-known-correct
FLANK = ["F", "Y", "W", "Nal"]          # aromatic; model knows all; Nal -> scaffold symbol 2Nal
P6 = ["A", "G", "S", "Aib", "Abu"]      # small specificity knob; model knows all
MODEL2SCAFFOLD = {"Nal": "2Nal"}        # CycPeptMPDB symbol -> acceptance_gate/fto symbol
# the model's context tokens for the fixed scaffold (handle NMeK -> K: OOV-free context, documented)
FIXED_CTX = ["R", "G", "D", "L"]        # between p1 and p6
TAIL_CTX = ["dP", "K"]                  # [dP] known; [NMeK] -> K for the model only


def _sym(m):
    return MODEL2SCAFFOLD.get(m, m)


def _scaffold_helm(p1, p6, p7):
    toks = [_sym(p1), "R", "G", "D", "L", _sym(p6), _sym(p7), "dP", "NMeK"]
    return "cyclo(" + "-".join(t if len(t) == 1 else f"[{t}]" for t in toks) + ")"


def _constrain_reject(p1, p6, p7):
    """Reuse the exact symbolic constrain+reject from the enumeration generator. Returns the candidate record
    or None (rule-violator or patent-infringing rejected by construction)."""
    helm = _scaffold_helm(p1, p6, p7)
    pr = predicates(helm)
    if not (pr["has_rgd"] and pr["has_rgdl"] and pr["flank_aromatic_p1"] and pr["flank_aromatic_p7"]):
        return None
    if not avb6_gate(helm)["PASS_H1_H5"]:
        return None
    fto = fto_score(helm, "avb6")
    if fto["claim"]["verdict"].startswith("INSIDE"):
        return None
    ncaa = [x for x in (_sym(p1), _sym(p6), _sym(p7)) if len(x) > 1]
    return {"helm": helm, "free": {"p1": p1, "p6": p6, "p7": p7}, "ncaa_count": len(ncaa),
            "fto_verdict": fto["claim"]["verdict"], "doe": fto["claim"]["doe"],
            "nearest_patented_id": fto["nearest_patented_identity"]}


def _neural_available():
    try:
        import torch  # noqa: F401
    except Exception:
        return False
    return os.path.exists(CKPT)


def _score_triples(temp):
    """Load v4; for every (p1,p6,p7) on the palette, compute the model loglik of the assembled macrocycle under
    null-target + <p_hi>. Returns {triple: loglik} — the neural proposal density over the free space."""
    import numpy as np, torch
    import design
    from train_cyclic_llm_v3 import TFEAT_DIM
    model, toks, stoi, a, dev = design.load(CKPT)
    zero = np.zeros(TFEAT_DIM, "float32")
    out = {}
    for p1 in FLANK:
        for p6 in P6:
            for p7 in FLANK:
                monos = [p1] + FIXED_CTX + [p6, p7] + TAIL_CTX     # model-vocab context (NMeK->K)
                ll = design.loglik(model, stoi, monos, "<e_na>", "<p_hi>", zero, dev)
                out[(p1, p6, p7)] = ll
    return out


def gen_avb6_neural(n=12, temp=2.0, n_sample=800, seed=0):
    """Neural proposer: sample free-position triples in proportion to the model's permeability-conditioned
    macrocycle likelihood, then symbolic constrain+reject. Emits (H, X) + backend metadata.
    Falls back to the enumeration proposer if the neural stack is unavailable."""
    H = json.load(open(os.path.join(HERE, "target_kb", "avb6_induced_rule.json")))["induced_rule"]
    if not _neural_available():
        from rule_conditioned_generator import gen_avb6
        _H, X = gen_avb6(n)
        meta = {"backend": "enumeration(fallback)", "reason": "torch or v4 checkpoint unavailable",
                "ckpt": CKPT}
        return H, X, meta

    import numpy as np
    ll = _score_triples(temp)
    triples = list(ll.keys())
    logits = np.array([ll[t] for t in triples], "float32")
    p = np.exp((logits - logits.max()) / max(temp, 1e-6)); p /= p.sum()
    rng = np.random.default_rng(seed)
    picks = rng.choice(len(triples), size=n_sample, replace=True, p=p)

    seen, X = set(), []
    for idx in picks:
        p1, p6, p7 = triples[idx]
        rec = _constrain_reject(p1, p6, p7)
        if rec is None or rec["helm"] in seen:
            continue
        seen.add(rec["helm"])
        rec["neural_loglik"] = round(float(ll[(p1, p6, p7)]), 3)
        X.append(rec)
    # rank survivors by FTO strength then neural preference (higher loglik first)
    rank = {"LOW": 0, "MED": 1, "HIGH": 2}
    X.sort(key=lambda c: (rank.get(c["doe"], 1), c["nearest_patented_id"], -c["neural_loglik"]))
    X = X[:n]
    meta = {"backend": "neural (unified_cyclic_llm_v4)", "conditioning": "null-target + <p_hi> permeability",
            "palette": {"flank": FLANK, "p6": P6}, "oov_handling": "[NMeK]->K for model context only",
            "target_agnostic": True, "n_sampled": int(len(picks)), "ckpt": os.path.relpath(CKPT, ROOT)}
    return H, X, meta


if __name__ == "__main__":
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument("--n", type=int, default=12)
    ap.add_argument("--temp", type=float, default=2.0, help="exploration knob: 1.0 exploits the model's sharp "
                    "preference (~5 survivors), >=2.0 broadens proposals")
    ap.add_argument("--n-sample", type=int, default=800)
    args = ap.parse_args()
    H, X, meta = gen_avb6_neural(args.n, args.temp, args.n_sample)
    print(f"backend: {meta['backend']}")
    for k in ("conditioning", "palette", "oov_handling", "target_agnostic", "n_sampled", "reason"):
        if k in meta:
            print(f"  {k}: {meta[k]}")
    print(f"\nH (induced rule): binder(X) :- {', '.join(H)}.")
    print(f"X ({len(X)} neural-proposed candidates; rule-violators AND patent-INFRINGING rejected by construction):")
    for c in X:
        nl = f" neural_ll={c['neural_loglik']}" if "neural_loglik" in c else ""
        print(f"  {c['helm']}   ncAA={c['ncaa_count']}  FTO: {c['fto_verdict']} (DoE {c['doe']}, patent-id {c['nearest_patented_id']}){nl}")
    out = os.path.join(HERE, "target_kb", "avb6_neural_HX.json")
    json.dump({"H": H, "X": X, "meta": meta}, open(out, "w"), indent=2)
    print(f"\nwrote {os.path.relpath(out, HERE)}  (neural (H,X) artifact)")

```

===== CODE: research/guangzhou_all_atom/cyclic_llm/peptide_availability.py =====
```python
"""peptide_availability.py — a deployable, honestly-scoped peptide *availability* predictor.

WHY THIS EXISTS
---------------
Affinity is not enough. Lemieux, Barbeau, Dibyachintan, Dubé, Lagüé & Landry (bioRxiv 2026,
doi:10.64898/2026.09.21.752983) measured >6,500 PBD(SH3)–peptide variants *in cells* (DHFR-PCA) vs.
*in vitro* (phage-display) and showed that **peptide "availability" — how much of the peptide is actually
free to engage its target in the cell — is largely set by the peptide's own hydrophobicity (and charge),
and it limits functional binding independently of intrinsic affinity.** A high-affinity peptide can be
functionally dead in cells if it is unavailable. Standard design pipelines ignore this.

WHAT THIS IS (and is NOT)
-------------------------
A sequence -> availability-risk model, fit on the Landry measured-availability data (PCA1, 7 SH3 domains).
- It is a **ranking / liability-flag** tool: "is this peptide at risk of low cellular availability?"
- It is **peptide-intrinsic**, so unlike binding/affinity it **transfers across domains** — validated by
  leave-one-domain-out: mean Spearman 0.40 (per-domain 0.23-0.49), i.e. a *moderate but robust* predictor.
  Treat scores as a risk ranking, NOT a precise quantitative oracle.
- Scope: trained on linear canonical-AA SH3-binding peptides. For cyclic / ncAA macrocycles (e.g. our
  αvβ6 RGD cyclics) it is an **approximation** over the canonical residues; ncAA content is flagged.

Model: availability_score = b0 + b_hydro*meanKD + b_charge*net_charge + b_fc*frac_charged
Coefficients fit by OLS on all PCA1 availability data (in-sample Spearman 0.72; LODO 0.40).
Provenance: github.com/Landrylab/Lemieux_et_al2026 (data/PCA1/med_avail_score.csv).
"""
from __future__ import annotations
import re
from dataclasses import dataclass

# Kyte-Doolittle hydrophobicity
_KD = {'A':1.8,'R':-4.5,'N':-3.5,'D':-3.5,'C':2.5,'Q':-3.5,'E':-3.5,'G':-0.4,'H':-3.2,'I':4.5,
       'L':3.8,'K':-3.9,'M':1.9,'F':2.8,'P':-1.6,'S':-0.8,'T':-0.7,'W':-0.9,'Y':-1.3,'V':4.2}
_CHG = {'R':1,'K':1,'H':0.1,'D':-1,'E':-1}

# Fit on Landry PCA1 measured availability (med_avail_score.csv); see module docstring.
_B0, _B_HYDRO, _B_CHARGE, _B_FC = 0.3318, -0.2541, -0.1479, -0.4793
# measured-availability 25th percentile -> 'low availability' liability threshold
_LOW_AVAIL_THRESHOLD = -0.142

_AA3to1 = {'ALA':'A','ARG':'R','ASN':'N','ASP':'D','CYS':'C','GLN':'Q','GLU':'E','GLY':'G','HIS':'H',
           'ILE':'I','LEU':'L','LYS':'K','MET':'M','PHE':'F','PRO':'P','SER':'S','THR':'T','TRP':'W',
           'TYR':'Y','VAL':'V'}


def _residues_from_helm(helm: str):
    """Extract per-residue canonical-AA letters from a HELM-ish cyclo(...) string or a plain sequence.
    ncAA tokens ([dP], [NMeK], [Nle], ...) are mapped to their canonical parent where obvious, else flagged.
    Returns (letters, n_ncaa, n_total)."""
    s = helm.strip()
    if s.lower().startswith('cyclo(') or '-' in s or '[' in s:
        inner = s[s.find('(')+1:s.rfind(')')] if '(' in s else s
        toks = re.findall(r'\[([^\]]+)\]|([A-Za-z\*])', inner)
        toks = [a or b for a, b in toks]
    else:
        toks = list(s)
    letters, n_ncaa = [], 0
    for t in toks:
        if len(t) == 1 and t.upper() in _KD:
            letters.append(t.upper()); continue
        # ncAA token: strip common modifier prefixes to recover a canonical parent
        base = re.sub(r'^(NMe|Me|N-methyl-|d|D-)', '', t)
        base = base[:3].upper()
        if len(base) == 1 and base in _KD:
            letters.append(base); n_ncaa += 1
        elif base in _AA3to1:
            letters.append(_AA3to1[base]); n_ncaa += 1
        elif base.startswith('NLE'):          # norleucine ~ Leu-like hydrophobicity
            letters.append('L'); n_ncaa += 1
        else:
            n_ncaa += 1                        # unknown ncAA: counted, no canonical mapping
    return letters, n_ncaa, len(toks)


def features(sequence: str):
    """Return (mean_hydrophobicity_KD, net_charge, frac_charged, n_ncaa, n_total) for a sequence/HELM."""
    letters, n_ncaa, n_total = _residues_from_helm(sequence)
    if not letters:
        return None
    mean_h = sum(_KD[a] for a in letters) / len(letters)
    net_charge = sum(_CHG.get(a, 0) for a in letters)
    frac_charged = sum(1 for a in letters if a in _CHG) / max(len(letters), 1)
    return mean_h, net_charge, frac_charged, n_ncaa, n_total


@dataclass
class AvailabilityResult:
    score: float            # predicted availability (higher = more available); ranking value, not absolute
    low_availability: bool  # True => flagged at risk of low cellular availability
    mean_hydrophobicity: float
    net_charge: float
    frac_charged: float
    ncaa_fraction: float    # fraction of residues that are non-canonical (model is an approximation here)
    note: str


def predict_availability(sequence: str) -> AvailabilityResult:
    """Predict cellular-availability risk for a peptide sequence or HELM cyclo(...) string.

    Returns an AvailabilityResult. `low_availability=True` flags a peptide likely to be functionally
    limited in cells by hydrophobicity/charge-driven unavailability, independent of its affinity
    (Landry 2026). A *ranking* risk flag (LODO Spearman ~0.40), not a precise oracle.
    """
    f = features(sequence)
    if f is None:
        return AvailabilityResult(float('nan'), False, float('nan'), float('nan'), float('nan'),
                                  float('nan'), "no canonical residues parsed")
    mean_h, net_charge, frac_charged, n_ncaa, n_total = f
    score = _B0 + _B_HYDRO * mean_h + _B_CHARGE * net_charge + _B_FC * frac_charged
    ncaa_frac = n_ncaa / max(n_total, 1)
    note = ("canonical-AA peptide" if ncaa_frac == 0 else
            f"APPROXIMATION: {ncaa_frac:.0%} non-canonical residues (model trained on canonical SH3 peptides)")
    return AvailabilityResult(round(score, 4), score < _LOW_AVAIL_THRESHOLD, round(mean_h, 3),
                              round(net_charge, 2), round(frac_charged, 3), round(ncaa_frac, 3), note)


if __name__ == "__main__":
    import sys
    for s in sys.argv[1:] or ["cyclo(W-R-G-D-L-T-F-[dP]-[NMeV])", "RGKLMPGRG", "GSLASLGIGRR"]:
        r = predict_availability(s)
        flag = "LOW-AVAIL ⚠" if r.low_availability else "ok"
        print(f"{s:34s} score={r.score:+.3f} [{flag}] meanH={r.mean_hydrophobicity:+.2f} "
              f"charge={r.net_charge:+.1f} fracChg={r.frac_charged:.2f} ncaa={r.ncaa_fraction:.0%}  ({r.note})")

```

===== CODE: research/guangzhou_all_atom/cyclic_llm/methodology_close.py =====
```python
"""methodology_close.py — RUN the closed loop for real on the COLLECTED model + COLLECTED measured data.

This is the generator-close edge the system never actually ran (only SIMULATED_* artifacts existed): does a
VERIFIED reward, fed through preference optimization, measurably improve what the trained generator produces?

Real assets used (no toy, no simulation, no bespoke physics, no cost):
  - generator  : the collected unified v4 cyclic LM  runs_helm/unified_cyclic_llm_v4.pt  (design.load/generate/loglik)
  - reward      : a VERIFIED oracle trained on the collected CycPeptMPDB MEASURED permeability (8,466 cyclic peptides)
  - anti-circular evaluator : a SECOND oracle trained on a DISJOINT half of the same measured data. If DPO merely
                  games the reward oracle, the independent evaluator will NOT move — that is the honesty gate.

Protocol (verifiable-reward RLVR via DPO on the real sequence LM):
  1. load CycPeptMPDB measured permeability; featurize each peptide in the SAME monomer-sequence space the v4
     generator emits (composition over the 393-monomer vocab + length + ncAA/charge/N-methyl/aromatic proxies),
     so generated monomer sequences are scored directly — no SMILES round-trip, no OOD gap.
  2. split the measured set into two DISJOINT halves by sequence hash -> oracle_A (reward), oracle_B (evaluator).
  3. baseline: sample from v4 (p_hi); score with the INDEPENDENT oracle_B; record validity/novelty/diversity.
  4. build preference pairs: sample a pool from v4, score with oracle_A, chosen(high-A) >- rejected(low-A).
  5. DPO-tune v4 against those pairs (frozen reference = the original v4; standard DPO loss; v4 has a tractable
     sequence log-likelihood via design.loglik, so no diffusion machinery needed here).
  6. after: re-sample from the tuned v4; score with oracle_B. Success = oracle_B of generations RISES after DPO
     with validity/novelty/diversity preserved (no mode collapse, no reward-hacking).

CPU-runnable at the default scale; --big scales it for the Spark/GPU box. Writes a fine-tuned ckpt + a results
JSON with the before/after independent-evaluator shift and the anti-circularity check.
"""
from __future__ import annotations
import argparse, ast, csv, hashlib, json, os, copy
import numpy as np
import torch

import design  # the real v4 interface (load/generate/loglik); imports train_cyclic_llm_v3 (make_model/TFEAT_DIM)
from train_cyclic_llm_v3 import TFEAT_DIM
import experience_kb            # the pragmatic-knowledge resolver (rule-constraint layer)
import score as score_mod       # operative KB gate providers (developability + rule + FTO), as loop_batch uses
import acceptance_gate, fto_score

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
CSV = os.path.join(ROOT, "data/raw/CycPeptMPDB_Peptide_All.csv")
CKPT = os.path.join(ROOT, "runs_helm/unified_cyclic_llm_v4.pt")
CANON = set("ACDEFGHIKLMNPQRSTVWY")


# ---------------------------------------------------------------- data + verified-reward oracles
def load_cycpept():
    """Return [(monos:list[str], perm:float)] from the collected measured set."""
    rows = []
    for r in csv.DictReader(open(CSV)):
        try:
            perm = float(r["Permeability"])
        except Exception:
            continue
        seq = (r.get("Sequence") or "").strip()
        if not seq:
            continue
        try:
            monos = [str(m) for m in ast.literal_eval(seq)]
        except Exception:
            continue
        if 3 <= len(monos) <= 24:
            rows.append((monos, perm))
    return rows


def _mono_props(m):
    """Cheap, monomer-identity physchem proxies (same space the generator emits)."""
    lm = m.lower()
    nmethyl = 1.0 if (lm.startswith("me") or lm.startswith("sar") or "nme" in lm or m in ("Sar",)) else 0.0
    arom = 1.0 if any(a in m for a in ("F", "Y", "W", "H", "Nal", "Bmt", "Phe")) else 0.0
    pos = 1.0 if (m in ("K", "R", "H") or "Lys" in m or "Arg" in m) else 0.0
    neg = 1.0 if (m in ("D", "E") or "Asp" in m or "Glu" in m) else 0.0
    dres = 1.0 if (m.startswith("d") and len(m) >= 2 and m[1].isupper()) else 0.0
    return nmethyl, arom, pos, neg, dres


def build_featurizer(rows):
    """Monomer-composition + aggregate-property featurizer over the observed vocab. Generated sequences
    (same vocab) featurize identically, so the oracle scores them directly."""
    vocab = sorted({m for monos, _ in rows for m in monos})
    vi = {m: i for i, m in enumerate(vocab)}
    V = len(vocab)

    def feat(monos):
        x = np.zeros(V + 8, dtype=np.float32)
        for m in monos:
            if m in vi:
                x[vi[m]] += 1.0
        L = max(len(monos), 1)
        x[:V] /= L                                   # composition (length-normalized)
        nm = ar = po = ne = dr = 0.0
        for m in monos:
            a, b, c, d, e = _mono_props(m)
            nm += a; ar += b; po += c; ne += d; dr += e
        ncaa = sum(1 for m in monos if m not in CANON)
        x[V:V + 8] = [L, ncaa / L, nm / L, ar / L, po / L, ne / L, dr / L, po - ne]
        return x

    return feat, vocab


def _cluster_disjoint_split(rows, seed=0, thr=0.6, n_max=3000):
    """LEAKAGE-SAFE split: cluster peptides by monomer-set Tanimoto (the peptide analog of Murcko
    scaffold clustering; cf. c2_retro_loop) and assign WHOLE clusters to A or B, so near-analogs never
    straddle the reward oracle and the independent evaluator. Caps rows (random subsample) for tractability."""
    rng = np.random.default_rng(seed)
    if len(rows) > n_max:
        idx = rng.choice(len(rows), n_max, replace=False); rows = [rows[i] for i in idx]
    vocab = sorted({m for monos, _ in rows for m in monos}); vi = {m: i for i, m in enumerate(vocab)}
    B = np.zeros((len(rows), len(vocab)), bool)
    for r, (monos, _) in enumerate(rows):
        for m in monos:
            B[r, vi[m]] = True
    card = B.sum(1).astype(np.float32)
    assigned = -np.ones(len(rows), int); cid = 0
    for i in rng.permutation(len(rows)):
        if assigned[i] >= 0:
            continue
        inter = (B & B[i]).sum(1).astype(np.float32)
        tani = inter / (card + card[i] - inter + 1e-9)
        members = np.where((tani >= thr) & (assigned < 0))[0]
        assigned[members] = cid; cid += 1
    # assign clusters to A/B (alternate, so both halves get comparable size + chemotype coverage)
    corder = rng.permutation(cid)
    side = {c: (0 if k % 2 == 0 else 1) for k, c in enumerate(corder)}
    A = [rows[i] for i in range(len(rows)) if side[assigned[i]] == 0]
    Bset = [rows[i] for i in range(len(rows)) if side[assigned[i]] == 1]
    return A, Bset, cid


def train_oracles(rows, feat, seed=0):
    """Two HistGBM oracles on CLUSTER-DISJOINT halves: A=reward, B=independent (leakage-safe) evaluator."""
    from sklearn.ensemble import HistGradientBoostingRegressor
    from sklearn.metrics import r2_score

    A, B, n_clusters = _cluster_disjoint_split(rows, seed=seed)

    def fit(split):
        X = np.array([feat(m) for m, _ in split]); y = np.array([p for _, p in split])
        mdl = HistGradientBoostingRegressor(max_iter=400, learning_rate=0.05, max_depth=8, random_state=seed)
        mdl.fit(X, y)
        return mdl

    oa, ob = fit(A), fit(B)
    # cross-split R2 (A predicting leakage-safe held-out B) — the honest generalization signal
    yb = np.array([p for _, p in B]); pb = oa.predict(np.array([feat(m) for m, _ in B]))
    cross_r2 = float(r2_score(yb, pb))
    return oa, ob, {"n_A": len(A), "n_B": len(B), "n_clusters": n_clusters,
                    "split": "cluster-disjoint(monomer-Tanimoto>=0.6)", "oracleA_on_B_r2": round(cross_r2, 3)}


def load_display_binding(target_key):
    """Return [(monos:list[str], enrichment_log2fc:float)] for one target from the collected display NGS set.
    Sequences are canonical-AA strings (one monomer per residue) — the SAME token space v4 emits."""
    import gzip
    path = os.path.join(ROOT, "data/display/display_ngs_multitarget.csv.gz")
    rows, seen = [], set()
    with gzip.open(path, "rt") as fh:
        for r in csv.DictReader(fh):
            if target_key.lower() not in (r.get("target") or "").lower():
                continue
            seq = (r.get("sequence") or "").strip().upper()
            try:
                enr = float(r.get("enrichment_log2fc"))
            except Exception:
                continue
            if not seq or not (3 <= len(seq) <= 24) or not all(c in CANON for c in seq):
                continue
            key = (seq, round(enr, 4))
            if key in seen:
                continue
            seen.add(key)
            rows.append((list(seq), enr))
    return rows


# ---------------------------------------------------------------- KB rule-constraint (experience_kb gate)
def to_helm(monos):
    """Monomer list -> HELM string the KB gate providers (acceptance_gate/score) parse."""
    body = ".".join(m if (len(m) == 1 and m in CANON) else f"[{m}]" for m in monos)
    return "PEPTIDE1{" + body + "}$PEPTIDE1,PEPTIDE1$$$"


def kb_admissible(monos, target):
    """Apply the KB's operative HARD gates to a candidate (the same providers resolve() references and
    loop_batch enforces via score()): developability is the general cyclic-peptide hard gate; for avb6
    the decisive RGD rule + FTO-genus clearance also apply. Fails OPEN on a parse error (never fabricate a
    rejection). Returns (ok, reasons)."""
    helm = to_helm(monos); reasons = {}
    try:
        reasons["developability"] = bool(score_mod.developability(helm).get("pass"))
    except Exception:
        reasons["developability"] = True
    ok = reasons["developability"]
    if target == "avb6":
        try:
            reasons["rule_rgd"] = bool(acceptance_gate.avb6_gate(helm).get("PASS_H1_H5"))
            reasons["fto_not_infringing"] = not fto_score.fto_score(helm, "avb6")["claim"]["verdict"].startswith("INSIDE")
            ok = ok and reasons["rule_rgd"] and reasons["fto_not_infringing"]
        except Exception:
            pass
    return ok, reasons


# ---------------------------------------------------------------- v4 generation + metrics
def gen(model, toks, stoi, tf, dev, block, n, temp, max_len=20, e_tok="<e_na>", p_tok="<p_hi>"):
    return design.generate(model, toks, stoi, tf, dev, n, block, max_len, temp, e_tok=e_tok, p_tok=p_tok)


def frechet_feature_distance(gen_feats, ref_feats):
    """FCD-analog: Fréchet distance between generated and a REFERENCE (real measured peptide) set in feature
    space (the peptide-space stand-in for Fréchet ChemNet Distance; lower = generations match real-peptide
    distribution). FCD proper uses a small-molecule ChemNet on SMILES, which does not apply to ncAA macrocycle
    monomer sequences — so we report the same Fréchet construction on the shared feature space, labelled as an analog."""
    import numpy as _np
    from scipy.linalg import sqrtm
    g = _np.asarray(gen_feats, float); r = _np.asarray(ref_feats, float)
    mu_g, mu_r = g.mean(0), r.mean(0)
    cg = _np.cov(g, rowvar=False) + 1e-6 * _np.eye(g.shape[1])
    cr = _np.cov(r, rowvar=False) + 1e-6 * _np.eye(r.shape[1])
    covmean = sqrtm(cg @ cr)
    if _np.iscomplexobj(covmean):
        covmean = covmean.real
    return float(((mu_g - mu_r) ** 2).sum() + _np.trace(cg + cr - 2 * covmean))


def oracle_budget_auc(pool_scores):
    """PMO-style sample efficiency: running best (top-10 mean) reward vs cumulative oracle calls, normalized AUC."""
    import numpy as _np
    s = _np.asarray(pool_scores, float)
    if len(s) < 10:
        return None
    run = _np.array([_np.sort(s[:i + 1])[-10:].mean() for i in range(len(s))])
    lo, hi = run.min(), run.max()
    return round(float((run - lo).mean() / (hi - lo + 1e-9)), 4)


def metrics(samples, oracle, feat, train_keys, gate_target=None):
    uniq = {tuple(m) for m in samples}
    scores = np.array([oracle.predict(feat(m)[None])[0] for m in samples]) if samples else np.array([0.0])
    novel = sum(1 for m in uniq if m not in train_keys) / max(len(uniq), 1)
    adm = round(sum(1 for m in samples if kb_admissible(m, gate_target)[0]) / max(len(samples), 1), 3)
    return {"n": len(samples), "n_unique": len(uniq), "oracle_mean": round(float(scores.mean()), 4),
            "oracle_p50": round(float(np.median(scores)), 4), "oracle_p90": round(float(np.quantile(scores, 0.9)), 4),
            "validity": round(len(samples) / max(len(samples), 1), 3),  # design.generate already filters to valid
            "novelty": round(novel, 3), "diversity": round(len(uniq) / max(len(samples), 1), 3),
            "kb_admissible": adm}


# ---------------------------------------------------------------- DPO on the real v4 LM
def seq_logp(model, stoi, monos, e_tok, p_tok, tf_t, dev):
    """Grad-enabled sequence log-prob over the monomer span — mirrors design.loglik's exact indexing."""
    ids = [stoi[e_tok], stoi[p_tok], stoi[design.BOS]] + [stoi[m] for m in monos if m in stoi] + [stoi[design.EOS]]
    x = torch.tensor([ids], device=dev)
    lp = torch.log_softmax(model(x, tf_t)[0], -1)
    tok = lp[torch.arange(len(ids), device=dev), x[0]]
    return tok[3:3 + len([m for m in monos if m in stoi])].sum()


def dpo_finetune(model, stoi, pairs, tf_t, dev, steps, beta, lr, batch, e_tok="<e_na>", p_tok="<p_hi>", log=print):
    ref = copy.deepcopy(model).eval()
    for p in ref.parameters():
        p.requires_grad_(False)
    opt = torch.optim.Adam([p for p in model.parameters() if p.requires_grad], lr=lr)
    # cache reference log-probs (frozen)
    with torch.no_grad():
        for pr in pairs:
            pr["ref_c"] = seq_logp(ref, stoi, pr["chosen"], e_tok, p_tok, tf_t, dev).item()
            pr["ref_r"] = seq_logp(ref, stoi, pr["rejected"], e_tok, p_tok, tf_t, dev).item()
    rng = np.random.default_rng(0)
    model.train()
    for step in range(steps):
        idx = rng.choice(len(pairs), size=min(batch, len(pairs)), replace=False)
        opt.zero_grad(); loss = 0.0; accd = 0.0
        for j in idx:
            pr = pairs[j]
            lc = seq_logp(model, stoi, pr["chosen"], e_tok, p_tok, tf_t, dev)
            lr_ = seq_logp(model, stoi, pr["rejected"], e_tok, p_tok, tf_t, dev)
            logits = beta * ((lc - pr["ref_c"]) - (lr_ - pr["ref_r"]))
            loss = loss + (-torch.nn.functional.logsigmoid(logits))
            accd += float(logits.item() > 0)
        loss = loss / len(idx)
        loss.backward(); opt.step()
        if step % max(1, steps // 10) == 0 or step == steps - 1:
            log(f"  dpo step {step:4d}/{steps}  loss={loss.item():.4f}  pref_acc={accd/len(idx):.2f}")
    model.eval()
    return model


def main():
    ap = argparse.ArgumentParser(description="Run the verified-reward generator-close on the collected v4 model.")
    ap.add_argument("--ckpt", default=CKPT)
    ap.add_argument("--signal", choices=["permeability", "binding"], default="permeability",
                    help="permeability = CycPeptMPDB measured logPapp (target-agnostic); "
                         "binding = display-NGS enrichment_log2fc for --target (target-conditioned)")
    ap.add_argument("--target", default="PADI4", help="binding signal only: target key (display + tfeat)")
    ap.add_argument("--targets-json", default=os.path.join(ROOT, "data/display/target_proteins.json"))
    ap.add_argument("--kb-gate", dest="kb_gate", action="store_true", default=True,
                    help="enforce the experience_kb rule-constraint (default ON): chosen candidates must be KB-admissible")
    ap.add_argument("--no-kb-gate", dest="kb_gate", action="store_false",
                    help="ablation: generative + verified-reward only, no KB gate")
    ap.add_argument("--pool", type=int, default=1200, help="candidates sampled to build preference pairs")
    ap.add_argument("--pairs", type=int, default=1500, help="max preference pairs")
    ap.add_argument("--eval-n", type=int, default=400, help="samples for before/after evaluation")
    ap.add_argument("--steps", type=int, default=150); ap.add_argument("--beta", type=float, default=0.1)
    ap.add_argument("--lr", type=float, default=1e-5); ap.add_argument("--batch", type=int, default=8)
    ap.add_argument("--temp", type=float, default=1.0)
    ap.add_argument("--big", action="store_true", help="scale up (Spark/GPU): pool 6000, pairs 8000, steps 600, eval 1500")
    ap.add_argument("--seed", type=int, default=0, help="RNG seed (torch+numpy) for replication")
    ap.add_argument("--shuffle-reward", action="store_true",
                    help="PLACEBO CONTROL: permute the reward scores before building pairs so chosen/rejected are "
                         "random w.r.t. true reward. If delta_B ~ 0 here while the real reward gives delta_B>0, the "
                         "gain is attributable to the verified signal, not to DPO pressure/diversity collapse. "
                         "Use with --no-kb-gate (pairs are purely reward-ranked).")
    ap.add_argument("--out", default=os.path.join(ROOT, "results/methodology_close_result.json"))
    ap.add_argument("--save-ckpt", default=os.path.join(ROOT, "runs_helm/unified_cyclic_llm_v4_dpo.pt"))
    args = ap.parse_args()
    if args.big:
        args.pool, args.pairs, args.steps, args.eval_n = 6000, 8000, 600, 1500

    torch.manual_seed(args.seed); np.random.seed(args.seed)
    if args.signal == "permeability":
        print("loading collected measured permeability (CycPeptMPDB) ...", flush=True)
        rows = load_cycpept()
        e_tok, p_tok, reward_name = "<e_na>", "<p_hi>", "CycPeptMPDB measured permeability"
    else:
        print(f"loading collected display-NGS enrichment for target {args.target} ...", flush=True)
        rows = load_display_binding(args.target)
        e_tok, p_tok, reward_name = "<e_hi>", "<p_na>", f"display-NGS enrichment_log2fc ({args.target})"
    if len(rows) < 200:
        raise SystemExit(f"too few rows ({len(rows)}) for signal={args.signal} target={args.target}")
    feat, vocab = build_featurizer(rows)
    oa, ob, ostat = train_oracles(rows, feat)
    train_keys = {tuple(m) for m, _ in rows}
    print(f"  measured rows={len(rows)}  vocab={len(vocab)}  oracles: {ostat}", flush=True)

    print(f"loading collected generator {os.path.relpath(args.ckpt, ROOT)} ...", flush=True)
    model, toks, stoi, a, dev = design.load(args.ckpt); block = a["block"]
    if args.signal == "permeability":
        tf = np.zeros(TFEAT_DIM, dtype=np.float32)               # target-agnostic: permeability is target-independent
    else:
        tf = design.tfeat_for(args.target, args.targets_json)     # target-conditioned binding
    tf_t = torch.tensor(np.asarray(tf), device=dev)[None]
    print(f"  device={dev} block={block} vocab={len(toks)} signal={args.signal} cond=({e_tok},{p_tok})", flush=True)

    # KB RULE-CONSTRAINT: resolve the pragmatic-knowledge gate-set (experience_kb). The gate is enforced in
    # pair construction (chosen must be KB-admissible) so the close is rule-constrained + generative + verified-reward.
    gate_target = args.target if (args.kb_gate and args.signal == "binding") else None
    kb_prov = []
    if args.kb_gate:
        try:
            kb = experience_kb.resolve(gate_target or args.target)
            hard = [c for e in ([kb] if isinstance(kb, dict) else []) for c in e.get("eval_criteria", []) if c.get("mode") == "hard"]
            kb_prov = kb.get("provenance", []) if isinstance(kb, dict) else []
            print(f"  KB rule-constraint ON (experience_kb.resolve): gate_target={gate_target or args.target} "
                  f"hard_gates={[c.get('criterion') for c in hard]} provenance_entries={len(kb_prov)}", flush=True)
        except Exception as ex:
            print(f"  KB resolve note: {type(ex).__name__}: {str(ex)[:120]} (falling back to general developability gate)", flush=True)
    else:
        print("  KB rule-constraint OFF (--no-kb-gate): generative + verified-reward only (ablation)", flush=True)

    # 3) baseline (independent evaluator oracle_B)
    base = gen(model, toks, stoi, tf, dev, block, args.eval_n, args.temp, e_tok=e_tok, p_tok=p_tok)
    m_before = metrics(base, ob, feat, train_keys, gate_target)
    base_A = metrics(base, oa, feat, train_keys, gate_target)["oracle_mean"]
    print(f"BEFORE  evalB_mean={m_before['oracle_mean']}  (rewardA_mean={base_A})  valid={m_before['validity']} "
          f"novelty={m_before['novelty']} diversity={m_before['diversity']} kb_admissible={m_before['kb_admissible']}", flush=True)

    # 4) build verified-reward preference pairs (reward oracle_A)
    pool = gen(model, toks, stoi, tf, dev, block, args.pool, args.temp, e_tok=e_tok, p_tok=p_tok)
    pool = list({tuple(m): m for m in pool}.values())
    pool_scores_genorder = [float(oa.predict(feat(m)[None])[0]) for m in pool]   # generation order (PMO acquisition)
    budget_auc = oracle_budget_auc(pool_scores_genorder)
    # PLACEBO CONTROL: permute the reward labels across candidates so pair chosen/rejected is random w.r.t.
    # the true reward (the DPO machinery is otherwise identical). A sound loop gives delta_B ~ 0 here.
    pair_scores = pool_scores_genorder
    if args.shuffle_reward:
        pair_scores = list(np.random.default_rng(args.seed + 777).permutation(np.asarray(pool_scores_genorder)))
        print(f"  [PLACEBO] reward labels PERMUTED before pair construction (shuffle-reward control, seed {args.seed})", flush=True)
    scored = sorted(zip(pair_scores, pool), key=lambda t: -t[0])
    if args.kb_gate:
        # rule-constrained: CHOSEN must pass the KB gate; gate-FAILS are the cleanest negatives, then low-property
        adm = [(s, m) for s, m in scored if kb_admissible(m, gate_target)[0]]
        inadm = [(s, m) for s, m in scored if not kb_admissible(m, gate_target)[0]]
        chosen = adm[:args.pairs]
        negs = inadm + adm[::-1]                      # gate-fails first (strongest neg), then admissible low-property
        # a negative is valid iff it is a GATE-FAIL (inadmissible, regardless of property) OR genuinely
        # lower-reward than the chosen; this prevents contradictory crossing pairs when the pool is all-admissible.
        pairs = [{"chosen": chosen[i][1], "rejected": negs[i][1], "margin": float(chosen[i][0] - negs[i][0]),
                  "kb_clean_neg": i < len(inadm)}
                 for i in range(min(len(chosen), len(negs)))
                 if chosen[i][1] != negs[i][1] and (i < len(inadm) or chosen[i][0] - negs[i][0] > 0)]
        print(f"built {len(pairs)} RULE-CONSTRAINED verified-reward pairs "
              f"(chosen=KB-admissible high-{args.signal}; {len(inadm)}/{len(scored)} pool candidates gate-failed)", flush=True)
    else:
        k = min(len(scored) // 2, args.pairs)
        hi, lo = scored[:k], scored[::-1][:k]
        pairs = [{"chosen": hi[i][1], "rejected": lo[i][1], "margin": float(hi[i][0] - lo[i][0]), "kb_clean_neg": False}
                 for i in range(k) if hi[i][1] != lo[i][1]]
        print(f"built {len(pairs)} verified-reward pairs (property only; KB gate OFF)", flush=True)
    if not pairs:
        raise SystemExit("no preference pairs (all pool candidates gate-failed or identical) — relax gate or raise pool")

    # 5) DPO close on the real v4
    model = dpo_finetune(model, stoi, pairs, tf_t, dev, args.steps, args.beta, args.lr, args.batch,
                         e_tok=e_tok, p_tok=p_tok)

    # 6) after (independent evaluator oracle_B)
    aft = gen(model, toks, stoi, tf, dev, block, args.eval_n, args.temp, e_tok=e_tok, p_tok=p_tok)
    m_after = metrics(aft, ob, feat, train_keys, gate_target)
    aft_A = metrics(aft, oa, feat, train_keys, gate_target)["oracle_mean"]
    print(f"AFTER   evalB_mean={m_after['oracle_mean']}  (rewardA_mean={aft_A})  valid={m_after['validity']} "
          f"novelty={m_after['novelty']} diversity={m_after['diversity']} kb_admissible={m_after['kb_admissible']}", flush=True)

    dB = round(m_after["oracle_mean"] - m_before["oracle_mean"], 4)
    dA = round(aft_A - base_A, 4)

    # ---- publication-standard extras: FCD-analog (distribution match to real peptides), random baseline ----
    rng = np.random.default_rng(0)
    ref_idx = rng.choice(len(rows), min(len(rows), 1000), replace=False)
    ref_feats = np.array([feat(rows[i][0]) for i in ref_idx])
    fcd_before = round(frechet_feature_distance([feat(m) for m in base], ref_feats), 4)
    fcd_after = round(frechet_feature_distance([feat(m) for m in aft], ref_feats), 4)
    # random baseline: uniform-random monomer sequences (floor the oracle/property must beat)
    vocab_canon = [m for m, _ in [(x, 0) for x in {mm for mo, _ in rows for mm in mo}]]
    rand = [[vocab_canon[j] for j in rng.integers(0, len(vocab_canon), rng.integers(5, 16))] for _ in range(args.eval_n)]
    rand_B = round(float(np.mean([ob.predict(feat(m)[None])[0] for m in rand])), 4)

    verdict = ("LOOP IMPROVES GENERATOR (independent evaluator rose, diversity held)"
               if dB > 0 and m_after["diversity"] >= 0.5 * m_before["diversity"] and m_after["novelty"] >= 0.5 * m_before["novelty"]
               else "INCONCLUSIVE / possible reward-hacking (see dA vs dB + diversity)")
    print(f"FCD-analog (gen vs real): {fcd_before} -> {fcd_after}  | random-baseline evalB={rand_B}  "
          f"| oracle-budget AUC={budget_auc}", flush=True)
    res = {"what": f"RULE-CONSTRAINED verified-reward generator-close on the COLLECTED v4 model + COLLECTED {reward_name}",
           "signal": args.signal, "target": (args.target if args.signal == "binding" else None),
           "seed": args.seed, "shuffle_reward_placebo": bool(args.shuffle_reward),
           "kb_rule_constraint": {"enabled": bool(args.kb_gate), "resolver": "experience_kb.resolve",
                                  "gate_target": gate_target, "provenance_entries": len(kb_prov),
                                  "kb_admissible_before": m_before["kb_admissible"], "kb_admissible_after": m_after["kb_admissible"]},
           "reward": f"oracle_A trained on {reward_name} (disjoint half); CHOSEN must pass the KB gate",
           "evaluator": "oracle_B trained on the OTHER disjoint half (anti-circular)",
           "oracle_stats": ostat, "n_pairs": len(pairs), "dpo": {"steps": args.steps, "beta": args.beta, "lr": args.lr},
           "before": m_before, "after": m_after, "reward_oracleA_before": base_A, "reward_oracleA_after": aft_A,
           "delta_independent_evaluatorB": dB, "delta_reward_oracleA": dA,
           "publication_metrics": {"split": ostat.get("split"), "fcd_analog_before": fcd_before,
                                   "fcd_analog_after": fcd_after, "random_baseline_evalB": rand_B,
                                   "oracle_budget_auc": budget_auc,
                                   "note": "cluster-disjoint (leakage-safe) oracles; FCD-analog = Fréchet feature "
                                           "distance to real peptides (ChemNet-FCD N/A for ncAA monomer seqs); "
                                           "random baseline = uniform-random monomer sequences; budget AUC = PMO-style."},
           "verdict": verdict}
    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    json.dump(res, open(args.out, "w"), indent=2)
    torch.save({"model": model.state_dict(), "toks": toks, "args": a}, args.save_ckpt)
    print(f"\nΔ independent-evaluator(B) = {dB:+}   Δ reward-oracle(A) = {dA:+}")
    print(f"VERDICT: {verdict}")
    print(f"wrote {os.path.relpath(args.out, ROOT)} + fine-tuned ckpt {os.path.relpath(args.save_ckpt, ROOT)}")


if __name__ == "__main__":
    main()

```