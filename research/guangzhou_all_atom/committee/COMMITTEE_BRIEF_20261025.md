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
