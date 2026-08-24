# M6 Tool Reconnaissance — Cryo-EM-Anchored Protein Transition-Path / Kinetics Generator

**Date:** 2026-08-18
**Goal (M6):** Anchor a *generated* protein transition PATH + KINETICS (rates, committors, transition ordering) on an experimental cryo-EM density map, by injecting a cryo-EM density log-likelihood as a guidance/conditioning term (classifier-guidance / reconstruction-guidance style) into a generative model's sampling loop.
**Decision axis:** (a) external-guidance injection point, (b) produces PATH *or* KINETICS (not just static ensembles), (c) buildable on AWS Batch GPU without a dependency swamp, (d) permissive license + public weights.

> **Verification status:** All repo URLs, arXiv IDs, and licenses below were fetched directly. Items I could not confirm are explicitly flagged **[UNVERIFIED]**. No URLs or IDs were fabricated.

---

## TL;DR — Ranked shortlist (best → worst for M6)

| Rank | Tool | Guidance injection? | Path/Kinetics? | Dep. swamp risk | License / weights | Verdict |
|---|---|---|---|---|---|---|
| **1** | **OM-TPS** (Onsager-Machlup TPS) | ✅ **Explicit, cleanest** — action is a differentiable PyTorch sum of scalar terms; add one more additive term | Endpoint-conditioned PATH (max-likelihood path) | Low–med (torch + OpenMM in separate env) | **MIT**, code public; uses *your* pretrained score model | **Build M6 here.** |
| **2** | **MDGen** | ✅ Plausible — stochastic-interpolant sampler w/ per-step velocity; needs a guidance hook added | PATH (interpolation/TPS mode) + forward sim; reproduces MSM fluxes | Low (pure PyTorch; ESM, MDTraj, pyEMMA) | **MIT**, **weights on HF** | Strong #2 / the *score model* OM-TPS can wrap. |
| **3** | **DeepPath** | ⚠️ Guidance = MM force-field oracle (add cryo-EM term there, not in a diffusion loop) | Endpoint-conditioned atomistic PATH; no explicit rates | Med–high (OpenMM oracle + builder) | CC-BY article; **code availability [UNVERIFIED]** | Viable but guidance is oracle-side, not sampler-side. |
| **4** | **MarS-FM** | ✅ Flow-matching ODE sampler (`transport.py`) — injectable in principle | MSM-state transitions / trajectory stats; **not** endpoint path | Low–med (torch, vendored OpenFold+ESM) | **MIT**, **weights on HF** | Emulates MSM, not a two-endpoint path; kinetics via MSM. |
| **5** | **DeepJump** | ✅ Euclidean-equivariant flow-matching (injectable in principle) | Single-state autoregressive "jumps"; folding pathways, MSM/TICA kinetics | **[UNVERIFIED]** — code/weights not found public | **No public repo found** | Great science; **blocked on availability**. |
| **6** | **DeepTICA** | N/A (not a generator) | Learns slow CVs / committor; **no structure generation** | Low (shallow NN + PLUMED) | MIT (mlcolvar) | **Not a path generator** — use as a *kinetics/committor scorer* on M6 output. |
| **7** | **TS-DAR** | ❌ No sampler; discriminative | Detects transition-state *frames* in existing MD; no generation | Low (torch, CPU-ok) | **MIT** | Analysis tool, not a generator. Useful as an evaluator. |
| **8** | **TPS-Flow** | ⚠️ Flow-matching + "structure-aware constraints" hook exists | Endpoint-conditioned PATH; damped fluctuations | Unknown | **Paywalled (ACS)**; code/weights **[UNVERIFIED]** | Conceptually ideal but availability unconfirmed. |

**Recommended build:** **OM-TPS as the M6 scaffold, wrapping MDGen (or MarS-FM) as the pretrained score/velocity model.** OM-TPS gives the cleanest, verified injection point; MDGen gives MIT-licensed public weights and native transition-path support.

---

## Prior-art check — "has anyone conditioned a path/kinetics generator on cryo-EM density?"

**Verdict: The narrow claim survives, but with an important caveat — the *mechanism* has been demonstrated for STATIC states (CryoBoltz), just not for a PATH with kinetics/ordering/committors.**

- **The survey exists and is real:** arXiv:**2604.25244**, *"Learning Structure, Energy, and Dynamics: A Survey of Artificial Intelligence for Protein Dynamics"* (Tang, Shi, Zhang, Liu, Tang, Lu). It does **NOT** explicitly name cryo-EM density as an open anchoring target. Its future-work items are "sparse experimental constraints" (it names **NMR chemical shifts / SAXS**, from BMRB/SASBDB — *not* cryo-EM) plus "kinetic fidelity." **⚠️ Do not cite this survey as saying "cryo-EM anchoring is open future work" — it says NMR/SAXS. The cryo-EM framing is our extrapolation.**

- **CLOSEST SCOOP — mechanism precedent (static states, NOT path/kinetics):**
  - **CryoBoltz** — *"Multiscale guidance of protein structure prediction with heterogeneous cryo-EM data"*, arXiv:**2506.04490**, **NeurIPS 2025**, code `github.com/ml-struct-bio/cryoboltz`. **This is the key one.** It guides the diffusion sampling trajectory of Boltz-1 with global+local cryo-EM density constraints to recover *multiple conformational states*. → This proves density-guidance-into-a-diffusion-loop works, but it outputs **static alternative states, with no transition ordering, no committors, no rates.** M6's differentiation = *kinetics on the path*, not multi-state fitting.
  - **Boltz-2 test-time cryo-EM supervision** — arXiv:**2605.09832** (2026), *"Modeling Atomic Conformational Ensembles… via Test-Time Supervision of Boltz-2 on Cryo-EM Density Maps."* Same family: density-guided *ensemble*, still static.
  - **"Modeling cryo-EM structures in alternative states with generative AI and density-guided simulations"** — bioRxiv 2025.02.06.636862. Density-guided sampling of *alternative states*; not a kinetics-ordered path.
  - **CryoFM** — bioRxiv 2025.12.29.696802, a generative *prior over densities* with flow-posterior sampling; about density restoration, not protein kinetics.

- **cryoDRGN / 3DFlex / RECOVAR family:** produce a *continuous conformational landscape / latent* from particle images — **no time axis, no rates, no committors.** They give you states, not kinetics. (Corroboration of this specific point pending from parallel prior-art fork; my direct searches are consistent with it.)

**Bottom line for the pitch:** Reframe the novelty precisely. It is **NOT** "first to condition any generator on cryo-EM density" (CryoBoltz did the *static* version at NeurIPS 2025). It **IS** "first to anchor a *transition PATH with kinetics — ordering / committors / rates* — on a cryo-EM map." Lead with that honest, narrower claim.

---

## Per-tool detail

### 1. OM-TPS — **top pick for the M6 scaffold**
- **Paper:** *"Action-Minimization Meets Generative Modeling: Efficient Transition Path Sampling with the Onsager-Machlup Functional"* — Raja, Šípka, Psenka, Kreiman, Pavelka, Krishnapriyan. **ICML 2025.** arXiv:**2504.18506**.
- **Repo:** `github.com/ASK-Berkeley/OM-TPS` — **MIT**, active.
- **What it does:** Given a *pretrained* diffusion/flow generative model, interprets its learned score as the drift of an SDE and finds the **maximum-likelihood transition PATH** between two endpoints by minimizing the **Onsager–Machlup action** over an explicit sequence of frames. Endpoint-conditioned. Demonstrated on Müller-Brown, alanine dipeptide, tetrapeptides, and D.E. Shaw fast-folding proteins.
- **★ Injection point (verified by reading source):** `two-for-one-diffusion/actions.py` defines the OM action as a **differentiable `torch.nn.Module`** returning a **sum of independent scalar terms** — a path/kinetic term `(x_{t+1}-x_t)²/(2dt)`, a force term `F²·dt/(2γ²)`, and (Hutchinson variant) a divergence term. The optimizer is a plain gradient descent in `sample.py` (`--optimizer sgd --lr 1e-5 --steps 5000`). **Adding a cryo-EM density log-likelihood is literally one more additive term in `forward()`'s return** — its gradient flows to every frame of the path automatically. This is the cleanest guidance hook of all candidates.
- **Kinetics:** OM action = path *likelihood*; committors/rates come from evaluating the action-weighted path ensemble (couple with DeepTICA/MSM downstream).
- **Footprint:** Python 3.9, PyTorch 1.12.1/cu113, MDTraj, `flow_matching`, `torchdiffeq`; **OpenMM in a separate conda env** (their note — plan two envs on Batch). Low-to-moderate; no JAX, no ColabFold. Model size = whatever score model you plug in.
- **Caveat:** README doesn't name the exact pretrained score model used for proteins (the `two-for-one-diffusion` dir implies a "Two-for-One" diffusion model). **Confirm which checkpoint drives the protein demo before committing** — you may need to supply MDGen as the score model.

### 2. MDGen — **best pretrained score model to wrap / strong standalone #2**
- **Paper:** *"Generative Modeling of Molecular Dynamics Trajectories"* — Jing, Stärk, Jaakkola, Berger. **NeurIPS 2024.** (proceedings PDF + OpenReview `yRRCH1OsGW`).
- **Repo:** `github.com/bjing2016/mdgen` — **MIT**. **Weights: HuggingFace `bjing-mit/mdgen`.**
- **What it does:** SE(3)-invariant tokenized trajectory generation. Modes: forward simulation (`sim_inference.py`, single-state), **transition-path sampling / interpolation (`tps_inference.py`, endpoint-conditioned, `--tps_condition`)**, upsampling, inpainting. Reproduces free-energy surfaces, torsional relaxation, and **Markov-state fluxes** → genuine dynamical content, on *transferable* (unseen) peptides.
- **Injection point:** Stochastic-interpolant/flow sampler with a per-step velocity field — a guidance term can be added to the velocity at each integration step (need to add the hook; not exposed out-of-box). Cleaner still: **use MDGen as the score model *inside* OM-TPS**, so the injection happens in OM-TPS's action rather than MDGen's loop.
- **Footprint:** PyTorch 1.12.1, PyTorch-Lightning, MDTraj, BioPython, `torchdiffeq`, fair-ESM, pyEMMA. **No JAX/OpenMM/ColabFold.** Trained/demoed at tetrapeptide scale — verify it scales to your protein of interest.

### 3. DeepPath
- **Paper:** *"DeepPath: overcoming data scarcity for protein transition pathway prediction using physics-based deep learning."* **RSC Chemical Science 2026**, DOI `10.1039/d5sc08253f`; bioRxiv 2025.02.27.640693; PMID 40060558. Article **CC-BY**.
- **What it does:** Physics-guided **generative active learning** — an "Explorer" proposes latent moves and a "Structure Builder" makes all-atom structures along a tentative **endpoint-conditioned** transition pathway; an **MM force-field acts as an oracle** iteratively refining the path. Validated on AdK, SHP2, CdiB, BAM.
- **Injection point:** Not a diffusion sampling loop — **guidance already enters via the force-field oracle.** A cryo-EM density term could be added to that oracle's objective (density-as-a-restraint), which is architecturally *different* from reconstruction-guidance but still principled.
- **Availability:** **[UNVERIFIED]** — could not confirm a public code repo or weights (biorxiv PDF fetch was 403; check the RSC SI's Code-availability statement). Georgia Tech group.
- **Footprint:** OpenMM oracle + a structure builder → moderate–high; verify before committing.

### 4. MarS-FM (MSM emulator)
- **Paper:** *"MarS-FM: Generative Modeling of Molecular Dynamics via Markov State Models."* **ICLR 2026.** arXiv:**2509.24779**.
- **Repo:** `github.com/valence-labs/mars-fm` — **MIT**. **Weights: HuggingFace `valencelabs/mars-fm`.**
- **What it does:** "MSM Emulator" — flow-matching model sampling transitions across discrete MSM states (not fixed-lag). ≥100× vs MD; up to 500-residue domains. Kinetics come from the emulated MSM, **not** from a two-endpoint path.
- **Injection point:** Flow matching w/ "GVP path + ODE sampler" in `transport.py`; entry `scripts/generate.py`. Injectable in principle during ODE integration.
- **Footprint:** conda `mars.yaml`; vendors OpenFold (IPA/rigids) + ESM (RoPE attention). PyTorch/Lightning. No JAX/OpenMM/ColabFold. Model size not stated.
- **Fit caveat:** It emulates the *whole* MSM, not the specific A→B path you'd anchor to a map. Less natural for "anchor THIS transition on THIS density."

### 5. DeepJump — **excellent science, blocked on availability**
- **Paper:** *"Accelerating Protein Molecular Dynamics Simulation with DeepJump"* — dos Santos Costa, Ponnapati, Rubin, Smidt, Jacobson (MIT Center for Bits and Atoms / Media Lab). arXiv:**2509.13294** (Sep 2025); NeurIPS 2025.
- **What it does:** **Euclidean-equivariant flow matching** predicting multi-timescale conformational "jumps" from **one** state (autoregressive rollout, not endpoint-conditioned). Reproduces folding pathways + TICA/MSM kinetics; ~1000× (memory "10,000×" claim overstates the paper's ~1000×). Trained on mdCATH.
- **Injection point:** Flow-matching → injectable *in principle*.
- **Availability:** **⚠️ NO public code/weights found.** The `github.com/DeepJump` org is an unrelated user's Python-101 repos, not this model. No repo/license in the paper metadata I could fetch. **Blocked until authors release** — do not plan M6 on it yet.

### 6. DeepTICA — **use as a kinetics/committor scorer, not a generator**
- **Paper:** Bonati, Piccini, Parrinello, *"Deep learning the slow modes for rare events sampling,"* **PNAS 2021.** Legacy repo `github.com/luigibonati/deep-learning-slow-modes` (frozen); **maintained in `mlcolvar`** (Bonati et al.), MIT.
- **What it does:** Learns nonlinear **slow collective variables / committor** via variational transfer-operator objective; drives OPES/metadynamics through **PLUMED**. **Does NOT generate structures.**
- **M6 role:** Ideal **evaluator** — compute committors / slow-CV ordering / rates *on the path M6 produces*, to validate the kinetics claim. Small (shallow NN); dependency = PLUMED/OPES (analysis-time only).

### 7. TS-DAR — **evaluator, not generator**
- **Paper:** Nat. Commun. 2024 (`s41467-024-55228-4`) + JPCB 2025 practical guide (`10.1021/acs.jpcb.5c06097`, PMC12670429). Repo `github.com/xuhuihuang/ts-dar` — **MIT**.
- **What it does:** **Discriminative** — maps existing MD frames to a hyperspherical latent and flags **transition-state frames as out-of-distribution.** No generation, no sampling loop, no injection point. Needs MD trajectories as input. Tiny (torch, CPU-fine, ~30 min train).
- **M6 role:** Post-hoc validator that M6's path passes through plausible transition states.

### 8. TPS-Flow — **conceptually ideal, availability unconfirmed**
- **Paper:** *"TPS-Flow: Physics-Guided Flow-Based Generative Modeling of Protein Transition Paths."* **JCIM 2026**, DOI `10.1021/acs.jcim.6c00807`. **Paywalled (ACS).**
- **What it does:** Endpoint-conditioned SE(3) flow-matching interpolation velocity from MD, with **optional energy + structure-aware constraints** and a short physics relaxation. Tested on a mycobacterial transporter, a monomer, a PPI complex, an enzyme. Preserves fluctuation patterns (damped amplitudes).
- **Injection point:** The "structure-aware constraint" hook is conceptually where a density term would go — but I **could not verify a public repo, weights, or license** (paper paywalled). **[UNVERIFIED availability]** — request code from authors before considering.

---

## Recommended M6 build plan

1. **Scaffold:** OM-TPS (`ASK-Berkeley/OM-TPS`, MIT) — extend `two-for-one-diffusion/actions.py` to add a `cryoem_density_term(path)` returning a scalar log-likelihood, summed into the total action; gradients flow to all frames via existing `sample.py` SGD loop.
2. **Score model:** MDGen (`bjing2016/mdgen`, MIT, HF weights) as the pretrained generative drift, or fall back to OM-TPS's bundled diffusion model for the pilot. Confirm the protein-scale checkpoint OM-TPS actually ships.
3. **Density likelihood:** simulate map from candidate structure (Gaussian/EM forward model), score cross-correlation / negative log-likelihood vs experimental map — same forward-model family CryoBoltz uses (borrow their formulation, `ml-struct-bio/cryoboltz`, as reference for the density term).
4. **Kinetics/committor validation:** DeepTICA (mlcolvar) + TS-DAR as independent evaluators on the anchored path.
5. **AWS Batch:** two conda envs (torch-CUDA + OpenMM), single-GPU; no JAX/ColabFold dependency swamp. Low deployment risk.

**Novelty framing (honest):** "First to anchor a transition *path with kinetics* (ordering/committors/rates) on a cryo-EM density map." CryoBoltz (NeurIPS 2025) already did density-guided *static* multi-state fitting — cite it as the mechanism precedent, differentiate on kinetics.

---

## Open items to verify before committing
- [ ] Which pretrained protein score checkpoint OM-TPS actually ships / whether MDGen must be plugged in.
- [ ] DeepPath code & license (RSC SI Code-availability statement).
- [ ] TPS-Flow code/weights/license (paywalled; email authors).
- [ ] DeepJump code release (watch `dos Santos Costa` / MIT CBA; not public as of 2026-08-18).
- [ ] ScooBDoob **[UNVERIFIED]** — appears only in the survey's citation list as an MCMC-frame-transition model; no repo/paper located. Do not rely on it.
- [ ] Confirm cryoDRGN/3DFlex/RECOVAR produce no kinetics (parallel prior-art fork corroboration pending).
