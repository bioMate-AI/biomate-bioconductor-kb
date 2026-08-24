# CryoDynamics M6 — Concrete Design + Ablation Protocol (2026-08-18)

**Purpose.** Convert the vague "M6 conditioning step" into a specific, buildable module and — most
importantly — a **falsifiable ablation gate**. Per the honesty reckoning in
`20260811_RECENT_LITERATURE_NOTES_AND_INSIGHTS.md` §6 and the strategic call in
`20260804_CRYODYNAMICS_EXPERIMENT_LOG.md` §5k: **M6 (experiment-anchored path + kinetics) is the project's
only defensible novelty.** M4 (converged GltPh PMF) is HPC-scale and deferred; do not grind it. This doc is the
go-forward plan.

**Honesty contract (carried from the experiment log):** every claim traces to a read source; tool choices are
pending the 2026-08-18 recon (two background agents) and are marked `[RECON]` until filled from ground truth.

> **⚠️ RECONCILIATION (2026-08-18) — this doc is an ADDENDUM, not the authoritative M6 method.** After writing the
> above I found the M6 method was already specified on 2026-08-02, in stronger form:
> `20260802_SNAT2_CRYODYNAMICS_METHODS_NATURE_METHODS.md` §M6 formalizes it as a **maximum-caliber constraint**
> (single cryo-EM state in → rates out; the inversion of CoPE-MaxCal), with the **same ablation gate** ("removing
> the likelihood must move ordering/rate/committor beyond its CI, else it's re-invented CryoPhold and FAILS"), the
> **same reduction trap** (CryoPhold guard), and the data-needs list (`20260802_SNAT2_MASTER.md` §6). **That doc is
> authoritative for the method.** What THIS doc genuinely adds over 2026-08-02:
> 1. **OM-TPS as a concrete, code-verified path-level injection route** (`actions.py` = differentiable additive-
>    scalar OM-action) — a specific *implementation* of "likelihood into the path," complementary to the MaxCal-
>    reweighting formulation, not a new method.
> 2. **Base-model scale ceiling** (MDGen ≤~80 aa → Boltz-2 for AdK/SNAT2) and the **fast-folder-first** cheap
>    ablation rung.
> 3. **CryoBoltz (2506.04490)** added to the prior-art guard set alongside the pre-existing CryoPhold guard.
> 4. A fresh verified S3/asset inventory (`.mrc` confirmed absent).
> Treat §2–§6 below as the OM-TPS *implementation route* + de-risking; treat the MaxCal formulation in the 08-02
> METHODS doc as the canonical statement of the contribution.

---

## 1. What M6 is (one sentence)

Given **one** experimental cryo-EM density `D` of a transporter/protein, produce a **transition path and its
kinetics** (rates, committors, intermediate ordering) between conformational states such that the generated
*dynamics* are **anchored to `D`** — and prove, by ablation, that the anchor **materially changes the path/kinetics
result**, not merely the endpoint states.

## 1b. "Is it just a pipeline?" — the honest innovation floor

Yes, by default. States (Boltz-2), path (OM-TPS), density-guidance-into-a-sampler (CryoBoltz, **already exists**),
and kinetics-from-paths (MSM) are all commodities. "Generate a path, pull each frame toward a cryo-EM map, read
off a rate" = OM-TPS + CryoBoltz-style guidance + MSM = **a pipeline**, incremental, CryoBoltz-adjacent. That is
the honest floor, and if the work stops there it is *integration, not innovation.*

It rises above a pipeline **only if both** hold (neither is met today):
1. **New objective, not per-frame map-fitting.** Constrain the **path ensemble's occupancy** to a cryo-EM
   **heterogeneity landscape** (3DVA/cryoDRGN) so the density shapes the **committor / populations along the
   transition** (the *kinetics*). No existing method does this (state-gens stop at states; endpoint-path methods
   fix endpoints; CryoBoltz fits per-structure). A **single static map cannot** do it → collapses to the thin
   per-frame case. This needs heterogeneity data (Appendix A.2).
2. **Empirical result.** The §4 ablation must show anchor-ON moves *kinetics toward the known answer*. ON≈OFF, or
   states-only re-weighting → no innovation. The gate is built to falsify exactly this; it has not run.

SNAT2 is *application* novelty (new protein/structure), **not** a method claim — do not conflate. Until the public
ablation passes with objective #1, label this **integration**, not innovation.

**No model training (by design).** OM-TPS is zero-shot (optimizes the *path*, not weights); the guidance is
inference-time; base models (MDGen/Boltz-2) are pretrained, used as-is. No new weights, no dataset, no learned
artifact → contribution ceiling = *new inference objective + empirical finding*, not "we trained a model" (cf.
CryoBoltz, also zero-shot, NeurIPS). **Heavier alternative (a real trained artifact): amortize** into a cryo-EM-
density-conditioned path/kinetics *generator* (learn density→dynamics directly). That needs paired (MD path,
density) training data at scale — **we don't have it**, it's a large build, and per the no-tiny-dataset rule a toy
run is worthless. **Decision rule:** the zero-shot ablation IS the feasibility test for the trained version — do
not train until zero-shot proves the density→kinetics signal is real (ON≠OFF toward truth); otherwise you'd pay to
reproduce a null.

## 2. The novelty line — and the trap that kills it

From the verified full-text reading (§6b, 4/4 papers + 2026 survey) **plus the 2026-08-18 tool recon**:

- **Claimed / commodity (do NOT claim):** generating alternate *states/ensembles* conditioned on cryo-EM density
  (CryoBoltz, Boltz-2-on-density, Exp-Guided AF3); generating *endpoint-conditioned* paths (TPS-Flow, MARS-FM,
  DeepPath, OM-TPS); generating trajectories/kinetics unconditioned (MDGen, DeepJump, TS-DAR).
- **The precise open gap — differentiate on the KINETICS/PATH axis, not the survey wording:**
  - **CryoBoltz** (arXiv:2506.04490, NeurIPS 2025, `ml-struct-bio/cryoboltz`) **already** guides a diffusion
    sampler with a cryo-EM density term → but outputs **static alternate states: no ordering, no committors, no
    rates.** Boltz-2 test-time cryo-EM supervision (arXiv:2605.09832) and cryoDRGN/3DFlex (continuous landscape,
    no time axis) are the same class. **So the density-guidance *mechanism* is precedented; the PATH-with-kinetics
    is not.** This is the primary, model-independent differentiator.
  - **Survey support (use precisely — do NOT overstate):** the 2026 survey *"Learning Structure, Energy, and
    Dynamics"* (arXiv:2604.25244, Tang et al., 28 Apr 2026) names, in its future-directions §, *"incorporating
    heterogeneous, sparse experimental data—such as **NMR chemical shifts, SAXS profiles, and cryo-EM equilibrium
    densities**—… to calibrate generated ensembles … correct localized kinetic inaccuracies"* (survey.txt L1528–9;
    "cryo-EM" appears exactly once, here). ⚠️ Cryo-EM is **one of three** co-named modalities, framed as
    *equilibrium-density calibration of ensembles* — cite it as "anchoring generated dynamics on sparse
    experimental data is named as open," **not** as "the survey singles out cryo-EM." The kinetics/path
    differentiator above is what carries the claim.
- **Defensible one-line claim:** *"First to anchor a transition **path with kinetics** (ordering / committors /
  rates) on an experimental cryo-EM density."* Cite CryoBoltz as the density-guidance precedent; differentiate
  strictly on kinetics/path.

**The reduction trap (must be defused in the design, not just the paper):** if M1 supplies the 2nd endpoint and the
density only pins an *endpoint*, M6 collapses into existing endpoint-conditioned path generation. To be distinct,
the density must constrain the **path/kinetics** — i.e. *which intermediates the path traverses* and/or *the
relative populations / committor along the path* — **not just the terminal state.**

**Design consequence:** the anchor must exploit information a single static endpoint cannot supply. Three admissible
sources of that information (pick per system, all real cryo-EM products):
1. **Heterogeneity density** — a 3D-variability / cryoDRGN latent or multi-class reconstruction gives an
   **occupancy landscape** over conformations → constrains relative populations / committor, i.e. the *dynamics*.
2. **Intermediate/occluded-state density** — a map of a metastable intermediate constrains a *waypoint the path
   must pass through* (interior of the CV space, not an endpoint).
3. **Ensemble/blurred density of a mobile region** — local map heterogeneity flags which sub-domains are mobile →
   constrains the *ordering* of sub-motions along the path.

If the ablation shows anchor-ON ≈ anchor-OFF on path/kinetics observables, **M6 is not novel** and we say so.

## 3. Method — density likelihood as guidance on a path/kinetics generator

M6 = a **guidance term** injected into the sampling loop of a diffusion/flow-matching path/kinetics generator
(the generator itself is a 2026 commodity; the *guidance on dynamics* is the contribution).

**Chosen scaffold (recon 2026-08-18): OM-TPS** (`ASK-Berkeley/OM-TPS`, MIT, ICML 2025, arXiv:2504.18506, Raja et
al.). It is a **model-agnostic, zero-shot** transition-path layer: it represents a path as a trajectory under a
pretrained model's learned score and finds the **max-likelihood path by minimizing the Onsager–Machlup (OM)
action** — a differentiable `torch.nn.Module` returning a **sum of independent scalar terms** over an explicit
atomic path. **Adding the cryo-EM density log-likelihood is literally one more additive term in `action.forward()`**;
autograd propagates it to every frame. This is the cleanest verified injection point of any 2026 tool. OM-TPS is
endpoint-conditioned (needs metastable A and B) — which is *why* the density term must act on the interior/path
(§2 trap): with A,B fixed, the OM action's minimum path is what the cryo-EM term reshapes.

**Cryo-EM forward model.** For a conformation `x` (atomic coords), simulate a density `ρ(x)` = sum of per-atom
Gaussians convolved to the experimental map resolution (standard rigid-atom map simulation, as in
molmap/`gmconvert`/EMAN `pdb2mrc`). Likelihood of the experimental map `D`:

```
log p(D | x) = (1/σ²) · CC(ρ(x), D)          # real-space cross-correlation form
             = -(1/2σ²) · ‖ D − s·ρ(x) − b ‖²  # equivalent Gaussian form (s scale, b offset)
```

**Guidance on the generator.** At each denoising/flow step `t` on the latent path/trajectory `X_t`
(a sequence of conformations, not one), add the density gradient to the model score:

```
score_guided(X_t) = score_θ(X_t)  +  λ(t) · Σ_k w_k · ∇_{x_k} log p(D | x_k)
```

- The sum runs over the frames `x_k` of the path. **The choice of `w_k` is where novelty lives:**
  - Anchoring `w_k` on **endpoints only** → the reducible/claimed case (our negative control).
  - Anchoring `w_k` via the **occupancy landscape** (source 1/2/3 above) → constrains the *dynamics* → the novel
    case. E.g. `w_k ∝` target occupancy at frame `k`, or a hard waypoint constraint at the intermediate.
- `λ(t)` is a guidance schedule (strong early/structure-forming steps, annealed late) — standard
  reconstruction-guidance practice; tune on the AdK control.

This is "reconstruction guidance" (à la CryoBoltz) **lifted from states to the whole path**, which is exactly the
survey's open problem. `[RECON]` will confirm the chosen generator exposes a per-step score/gradient hook to make
this injection possible (the single most important tool-selection criterion).

## 4. The ablation gate — AdK first (cheap, known-answer)

**Why AdK, not GltPh:** soluble (no membrane → far cheaper), small (214 aa), M1 already validated it spans
open(4AKE)↔closed(1AKE), and it has a **kinetics gold standard** — NMR opening/closing rates **≈286 s⁻¹ / 44 s⁻¹**
(Wolf-Watz/Kern). GltPh membrane systems are 5× the atom count and the PMF is HPC-scale — wrong place to prototype.

**Controlled anchor for the AdK dry-run:** AdK has no cryo-EM map, so synthesize one — simulate a density from a
**known intermediate** (or the closed state / a heterogeneity landscape from an MD-derived occupancy) at a chosen
resolution `r`. This makes the ground truth exact and the ablation clean. (For the *real* claim we later use a
genuine cryo-EM product; see §5 SNAT2.)

**The gate (pass/fail, decided before running):**

| Condition | Anchor `w_k` | Expected if M6 is real |
|---|---|---|
| **OFF (control)** | none / endpoints-only | path & rate reflect the bare generator; committor generic |
| **ON (treatment)** | occupancy/intermediate-weighted | path traverses the anchored intermediate; committor & rate shift **toward the known answer** |

**M6 PASSES only if** anchor-ON changes a **dynamics** observable (committor profile, intermediate ordering, or
rate) by more than run-to-run noise, **in the direction of the known answer**, while anchor-OFF does not. A shift
in *endpoint* structure only = **FAIL** (that's the reducible case). Quantify:
- Rate: compare generated MFPT/rate to NMR 286/44 s⁻¹ (order-of-magnitude + ratio).
- Committor: does the anchored intermediate sit near committor ≈ 0.5 as expected?
- Path: RMSD of the intermediate ensemble to the anchor's state vs. to the endpoints.
- **Noise floor:** ≥3 seeds each arm; report the ON−OFF effect against the seed spread.

**Second known-answer case (if AdK passes):** GltPh path (not the converged PMF) vs the PNAS-2025 landscape's
*qualitative* intermediate ordering — reuses the equilibrated endpoints/CV/steered path already on S3. This uses
the string-method assets **only as an MD-truth reference**, not as the deliverable.

**REFINEMENT (from reading OM-TPS source, 2026-08-18) — do the *first* method-proof on a within-regime system, not
AdK.** OM-TPS's bundled MDGen base model is demonstrated on alanine dipeptide, tetrapeptides, and **DESRES
fast-folding proteins (≤~80 aa)** — AdK (214 aa) is beyond it, so an AdK-first ablation confounds "method fails"
with "base model out of regime." Better first proof: a **DESRES fast-folder** (villin/trp-cage/WW/BBA/NTL9 — all
handled by MDGen) because its DESRES long trajectory supplies *both* (a) an **on-pathway intermediate** → build the
synthetic anchor density on the *intermediate* (not the folded endpoint → stays out of the §2 reduction trap) and
(b) **gold-standard committors + folding/unfolding rates** → the exact ON/OFF gate observable. This proves the
*method* (density anchoring materially moves path/kinetics toward truth) with **zero base-model scale risk**.
Escalation ladder: fast-folder (method proof, MDGen) → AdK (transporter-class hinge, Boltz-2 as `force_func`) →
SNAT2 (application, her map). The gate logic (§4 table) is unchanged at every rung.

## 5. SNAT2 application (the real target — after AdK gate passes)

- SNAT2 / SLC38A2 (UniProt Q96QD8), the sister's protein; she has a ~3.0 Å cryo-EM of **one** state. Elevator
  transporter (GltPh is the closest validated analog — deliberate benchmark choice).
- M1 generates the alternate elevator endpoint from sequence; **M6 anchors the transport-cycle path/kinetics on
  her one experimental density.** This is the application-novelty that is safe regardless of the method-novelty
  outcome (novel protein, her map, her paper).
- **Asset readiness (verified 2026-08-18, `s3://…/projects/snat2_dynamics/`):**
  - ✅ `inputs/structures/SNAT2_cryoEM_stateA_3.0A.pdb` — 3.0 Å PHENIX-refined **fitted model** (CC_mask 0.79,
    401 residues 67→470, **apo, single state**; N82/T384 = canonical Na⁺ site confirmed).
  - ✅ `inputs/SNAT2_Q96QD8.fasta` (full) + modeled-span FASTA. ✅ ortholog refs `6C08`/`7KGV` (SLC38A9
    inward/outward) for state-ID. State-ID prototype (Batch `777168ad`) → **leans inward, ΔTM=0.01 (within
    noise)** → needs a gate/HOLE call.
  - ❌ **No cryo-EM density `.mrc` on S3** — only the fitted PDB. **No heterogeneity/3D-variability data.**
- **Design consequence for the anchor (important):** with only a *single-state fitted model* and no map or
  heterogeneity, the only §2 novel-anchor source currently available is **#2 (single intermediate/state as a path
  waypoint)** — and even that needs the actual `.mrc` (or a simulated density from the fitted coords) to form a
  real likelihood. **#1 (occupancy landscape) and #3 (mobile-region ordering) require the raw map or
  variability data we do not have.** → **Action item to the sister/collaborator: obtain the `.mrc` map and, if it
  exists, the 3D-variability / multi-class output** (cryoDRGN/3DVA). Until then, the SNAT2 real-data claim is
  bounded to waypoint-anchoring; the *method* claim is proven on AdK regardless (§4).

## 5b. Existing infra inventory (verified 2026-08-18) — reuse vs. build

**Reusable now:** `gromacs_umbrella_pmf/main.nf` (24-window fan-out + `gmx wham` bootstrap-200, M4 baseline);
`amber_pmemd_md/` (M2 membrane equil); local `research/string-method/` package (steered + string + a
`postprocessing/transition_count_calculation.py` transition-matrix + `free_energy_calculation.py` FES-from-CV —
though FES is manual histogram reweighting, no WHAM); AdK/GltPh/SNAT2 S3 assets above; tool DB (12,301 tools) has
the full classical-GROMACS stack (grompp/mdrun/genion/…, dcTMD, fastpca, TI/FEP).

**Missing → must build (these gate M5/M6):**
- 🔴 **MSM + committor/TPT wrapper** (M5) — deeptime/PyEMMA exist as libs, not wrapped as a Nextflow module/image.
- 🔴 **String-method `.nf` wrapper** (M3 alt) — local Python is ~production-ready; no `.nf` + container yet.
- 🔴 **WESTPA cross-check** (M5, optional but the "Nature Methods bar") — not integrated.
- 🔴 **The M6 density-guidance layer itself** — novel, unbuilt.

**Two implementation routes for M6 (recon 2026-08-18 resolved: Route A is viable):**
- **Route A — OM-TPS guidance layer** (§3): inject the cryo-EM density term into OM-TPS's OM-action. Verified clean
  injection point, MIT, no dependency swamp. **This is the primary route.** Open sub-decision = the *base score
  model* OM-TPS wraps (below).
- **Route B — MD-native density-biased path/kinetics** (fallback, buildable on existing infra **now**): bias the
  string-method path search / umbrella seeding / MSM reweighting by the same cryo-EM density likelihood. Reuses the
  verified GROMACS stack; no ML-scale risk. Kept as fallback if Route A's base model can't scale to AdK/SNAT2.
- The **ablation gate (§4) is identical** either way — anchor ON vs OFF on AdK — so the *contribution* does not
  depend on which route wins.

**⚠️ TOP PRE-BUILD VERIFICATION GATE — the base score model for OM-TPS.** OM-TPS needs a pretrained model whose
score ∇log p(x) is available over full-protein conformations. Two candidates, each with a real risk:
- **MDGen** (`bjing2016/mdgen`, MIT, HF weights `bjing-mit/mdgen`) — light, native TPS mode, reproduces MSM
  fluxes. **RISK: its TPS/dynamics mode was validated mainly on tetrapeptides + ATLAS monomers — AdK (214 aa) and
  SNAT2 (~500 aa membrane) likely exceed its trained regime.** Must verify the largest system MDGen-TPS actually
  runs on before committing.
- **Boltz-2** — already in our M1 stack, generates full-protein conformations, is a diffusion model (score
  available). **RISK: must confirm OM-TPS can wrap it** (OM-TPS is advertised model-agnostic for "any diffusion/
  flow model producing i.i.d. conformational samples," but this pairing is unproven by us).
- **Decision rule:** do a cheap OM-TPS smoke on the *published* MDGen tetrapeptide example first (confirms the
  scaffold runs), then test scale — if MDGen can't reach AdK, wire Boltz-2 as the base model; if neither wraps
  cleanly, fall back to Route B. **Do not launch AdK production until the base-model scale question is answered on
  a cheap example** (mistakes-log rule #1: preflight cheaply before scaling).

## 6. Build plan (cheap-first, per the mistakes-log discipline)

1. ✅ **Generator chosen: OM-TPS scaffold** — repos cloned to `research/OM-TPS` + `research/mdgen`; OM-action
   injection point verified in `two-for-one-diffusion/actions.py` (additive scalar `torch.nn.Module`); base model
   is model-agnostic (`force_func`). **Turnkey smoke recipe (verified):** pretrained diffusion+flow weights are
   **bundled** in `saved_models/{bba,villin,trp_cage,chignolin,protein_g,alanine_dipeptide,tetrapeptides_all_atom}`
   (real 15–22 MB `.pt`, no download). Endpoint tensors need a one-time Google-Drive/`gsutil` pull (see
   `two-for-one-diffusion/README.md`). Two conda envs (`om-tps`, `openmm-env`). Command (BBA, 32 paths):
   `python sample.py --model_path saved_models/bba --gen_mode om_interpolate --atom_selection c-alpha
   --num_samples_eval 32 --action hutch --optimizer sgd --path_length 200 --steps 5000 …`. Needs a CUDA GPU →
   AWS Batch (Mac has none). **Run this unmodified first** — confirms the scaffold before adding the cryo-EM term.
   - **Representation caveat (design-relevant):** the fast-folder bundled models are **C-alpha coarse-grained**
     (`--atom_selection c-alpha`); only `tetrapeptides_all_atom` is all-atom. So for the fast-folder *method-proof*,
     keep the density term in **CA space** (synthetic CA density from the intermediate — anchor and model in the
     same space, fully self-consistent for proving "anchor moves kinetics"). All-atom cryo-EM realism only matters
     at the AdK/SNAT2 rung, which uses the all-atom Boltz-2 `force_func`. This keeps the method-proof honest and
     cheap without conflating CG-density approximation error with the ablation signal.
2. **First method-proof on a within-regime fast-folder** (§4 refinement), not AdK: reproduce a bare path/rate
   unconditioned, then add the density term anchored on a DESRES on-pathway *intermediate*. Only escalate to AdK
   (via Boltz-2 as `force_func`) after the method is proven. (Preflight-cheap; base model out-of-regime must not be
   confounded with method failure.)
3. ✅ **DONE (2026-08-18) — density forward model + gradient implemented and validated** against the *real*
   OM-TPS `actions.py`, torch-only/CPU/$0 (`research/m6_density_guidance/`). Gaussian rigid-atom map sim +
   cross-correlation nll + soft-min-over-frames waypoint term. Tests: gradient finite-diff vs autograd
   **1.2e-10**; composes with real `TruncatedAction`/`HutchinsonAction` (caught a real double-backward
   integration bug for free); at λ scaled to OM magnitude the informative anchor moves the path toward the
   observed state and MORE than an agreeing anchor (ablation logic in miniature). **Finding: λ must scale to the
   OM-action magnitude** (OM ~1e4 vs nll ~O(1) here). Scope: validates the CODE, not the science.
4. **Wire guidance in; run the ON/OFF ablation on AdK** (synthetic anchor, ≥3 seeds/arm).
5. **Gate:** only if §4 passes do we (a) claim the method and (b) move to SNAT2 with the real map.
6. Everything on AWS Batch GPU; `set -eo pipefail`, grompp/forward-model validated cheaply, no hidden output, no
   `|| true` on required steps (the three rules from the mistakes log).

## 7. Open decisions still to resolve (verify cheaply — do NOT launch production until closed)
1. **Base score model for OM-TPS** (§5b ⚠ gate) — MDGen (scale risk) vs Boltz-2 (pairing unproven). Resolve on a
   cheap example first. **This is the #1 unknown.**
2. **AdK anchor construction** — synthetic-density-from-intermediate vs an MD-occupancy landscape; pick the one
   that gives the cleanest known-answer without reducing to endpoint-anchoring.
3. **SNAT2 map form** — the raw `.mrc` (and any 3D-variability output) determines which of §2's three anchor
   sources is available for the real application. **GATED — do NOT request until the method passes the public-data
   ablation (§4).** The method is *unproven* (zero M6 runs to date); asking the collaborator for proprietary data
   before a public known-answer proof is out of order. Appendix A is *prepared, not to send yet.* A lightweight
   heads-up (long export lead time) may run in parallel, but no commitment either side until the gate passes.

## 8. Provenance
- Tool recon (2026-08-18): authoritative synthesis in the completing agent's report; a machine-generated
  companion table is at `docs/20260818_M6_PATH_KINETICS_GENERATOR_RECON.md` (verified URLs; kept as a reference
  artifact, cross-checked against this doc's §2/§3).
- Asset inventory (2026-08-18): `s3://biomate-nextflow-work/projects/{adk_goldstd,gltph_md,snat2_dynamics}/`,
  `research/string-method/`, `research/cryodynamics_papers/`, tool DB (12,301 tools).
- Key papers: OM-TPS arXiv:2504.18506 (MIT, `ASK-Berkeley/OM-TPS`); MDGen NeurIPS 2024 (MIT, `bjing2016/mdgen`,
  HF `bjing-mit/mdgen`); CryoBoltz arXiv:2506.04490 (`ml-struct-bio/cryoboltz`); survey arXiv:2604.25244
  (Tang et al.). AdK NMR rates: cross-check against primary source before publication (see literature note).

---

## Appendix A — SNAT2: what SHE must provide vs. what WE do

Split by the only axis that matters: **experimental data that physically exists only in her lab** (she must send)
vs. **computation** (ours — no ask). The whole M6/M1–M5 pipeline is ours; from her we need only the irreducible
experimental products.

> **⛔ GATE (do not skip):** this request is **prepared, not to send.** The M6 method is unproven (zero ablation
> runs). Send nothing to the collaborator until the method passes the **public-data** ablation (§4, DESRES
> fast-folders + AdK). Proprietary data is earned *after* a public known-answer proof, never before.

### A.1 — What ONLY she can provide (experimental; can't be reproduced computationally)

**Required minimum to start the SNAT2 rung:**
| # | Item | Why | Size |
|---|------|-----|------|
| 1 | **Final sharpened map** (`.mrc`/`.map`) | the density M6 anchors on | ~67–256 MB |
| 2 | **The two unfiltered half-maps** | proper likelihood weighting / local resolution | ~2× the map |
| 3 | **FSC / solvent mask** | refinement mask | small |
| 4 | **Map metadata** — pixel size (Å/vox), box size, global resolution + FSC curve, sharpening B-factor | scale/units for the forward model | trivial |
| 5 | **Construct + sample conditions** (text) — human Q96QD8 vs ortholog/mutant; tags/fusions (BRIL, Fab, GFP); apo vs substrate-bound (**which** substrate); **Na⁺**, **pH**, lipid/detergent; oligomeric state | defines *which state* we're anchoring and what to build/simulate | text |
| 6 | Her **state assignment** (inward/outward/occluded) + confirm the S3 model `SNAT2_cryoEM_stateA_3.0A.pdb` is current | overrides our TM-score guess (inward-leaning, ΔTM=0.01 = noise) | text + 0.25 MB |

**Optional but high-value (still only she has the underlying data):**
| # | Item | Why | Size |
|---|------|-----|------|
| 7 | **Any second-state map** (different condition — inward vs outward/occluded) | *jackpot:* real transition endpoints instead of M1-generated ones | ~Tier-1 per map |
| 8 | **Functional/transport data** — turnover, K_m (substrate/Na⁺), pH dependence, electrophysiology | experimental **kinetics** to validate M6's predicted rates (the gate) | small |
| 9 | **Deposition status** — EMDB/PDB IDs, or embargo / data-sharing / authorship terms | logistics | text |

### A.2 — Heterogeneity (cryoDRGN/3DVA): the ONE either/or — because the *analysis* is ours but the *input* is hers

Heterogeneity is what upgrades a single-state waypoint into a **kinetics-constraining occupancy landscape** (the
version that carries the novelty). It is computed from the **particle stack + consensus poses** — **not recoverable
from the final map.** So exactly one of two paths, decided by a single yes/no to her:

- **She already ran it (3D-class / 3DVA / cryoDRGN / 3DFlex)?** → **she sends the small output**: volume series /
  class maps (~10–50), per-class **occupancies**, latents + model. **~1–5 GB.** We touch no raw data. *(This is the
  cheap, preferred path — 3D-class/3DVA are routine in cryoSPARC, so she may already have it.)*
- **She didn't, but we want it?** → **WE run cryoDRGN** (open-source, our GPU/Batch — compute is not the issue),
  but then **she must ship the particle stack + poses** — **tens–hundreds of GB.** 3DVA lives inside cryoSPARC
  (proprietary), so our DIY route is cryoDRGN/RELION. Only request this big transfer if we decide the upgrade
  earns it.
- **Not a blocker either way:** item 1 alone starts SNAT2 (waypoint anchor); heterogeneity is a later upgrade.

### A.3 — What WE do ourselves (do NOT ask her for these)
- **All of M1–M6:** alternate-state generation (Boltz-2), membrane build + equilibration (M2), transition path
  (OM-TPS/M3), kinetics/committors (M5), and the cryo-EM density-guidance (M6).
- **Fitting/refining** an atomic model into her map, **simulating a density** from coordinates, backmapping.
- **Heterogeneity analysis itself** (cryoDRGN) — *given* her particles (see A.2).
- **State classification** (TM-align vs orthologs 6C08/7KGV) — already done.

**One-line ask to forward:** *"For a modeling project on SNAT2's transport cycle, could you share the final map +
the two half-maps + the FSC mask + the current model, plus a note on the construct and buffer (substrate/Na⁺/pH/
lipid) and any transport-assay numbers? And one question: did you run 3D-classification / 3DVA / cryoDRGN? If so
the small volume-series output (a few GB) would be gold — if not, no worries, the single map is enough to start.
No need for the raw particle stack or micrographs unless we later decide to run heterogeneity ourselves."*

## Change log
- **2026-08-18** — created. Method core (density-guidance on a path generator) + ablation gate; folded in
  both recon streams: **OM-TPS+MDGen/Boltz-2 tool decision**, verified AdK/GltPh/SNAT2 assets (SNAT2 `.mrc`
  missing — flagged as external dependency), corrected the novelty framing (CryoBoltz is the primary
  differentiator; survey names cryo-EM as one of three sparse modalities — do not overstate).
- **2026-08-18 (same session, source-verified)** — cloned `research/OM-TPS` + `research/mdgen`; **verified the
  OM-action injection point in `actions.py`** (additive scalar `torch.nn.Module`, model-agnostic `force_func`).
  Confirmed base-model scale ceiling (MDGen demonstrated ≤~80 aa DESRES fast-folders) → **refined the plan: first
  method-proof on a within-regime fast-folder** (DESRES intermediate density anchor + gold-standard rates, no
  scale risk), then escalate AdK (Boltz-2 `force_func`) → SNAT2. Added `research/{OM-TPS,mdgen,string-method}/`
  to `.gitignore`.
