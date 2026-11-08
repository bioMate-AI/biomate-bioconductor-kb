# Our Peptide LLM — Architecture & IP (challenge → resolution → claim)

**Date:** 2026-09-26 · **Status:** internal IP spec (NOT for client materials — see `README.md`)
**Frame:** *Stand on the giant's shoulders to go fast; the IP is in the challenges we resolve + our proprietary data + the composite system.* Not from-scratch, not a derivative — a **leveraged foundation with owned solutions**.

---

## 1. Posture (settled)
- **Leverage (speed):** a latent-diffusion-over-autoencoder all-atom co-design backbone (PepGLAD-class) + physics scorers + pocket detection + public data. Proven, adopted in weeks, gave us a real baseline (epoch-221, DockQ 0.557) and a working verify→select loop. Don't reinvent the backbone.
- **Own (IP):** the defensible value is the **hard problems the field leaves open**, solved on **our proprietary data**, as a **composite system**. The moat is *not* "we wrote our own diffusion model."
- **PepGLAD's role going forward:** a **reference baseline to beat** on its own 7-metric panel — *and* to exceed on capabilities it structurally can't do. (It is **one of several**, not uncontested SOTA — beaten on AAR/RMSD/hard-ΔG; target the SOTA-per-metric set, not PepGLAD. See `20260926_PEPTIDE_SOTA_AND_WHITESPACE.md`.)
- **Design north-star — ALL-IN-ONE:** scope the model as **one chemistry-native generative foundation across modalities** (small molecule + peptide + macrocycle + non-canonical), **target-conditioned + full-atom 3D** — not peptide-only. This is the market's unification direction.
- **⚠️ White-space claim NARROWED (2026-09-27, verified competitor pass — see `20260926_PEPTIDE_SOTA_AND_WHITESPACE.md` §3).** The old "no one has built the intersection" is **now FALSE**: **APCyc (KDD 2026)** and **CP-Composer (ICML 2025)**, both PepGLAD-derived, do target-conditioned full-atom de-novo **cyclic co-design**. The **surviving, defensible cell** is precise: *full-atom cyclic co-design **at a receptor pocket** with **native sidechain** non-canonical chemistry (N-Me/D-AA/staples as first-class residues — not cyclization-linkage tokens (APCyc/CP-Composer), not PTM residues (NS-Pep)), de-novo (not mutation, cf. NCFlow).* **Claim that cell + the composite + the proprietary loop — NOT "first cyclic co-design" (APCyc) or "first non-canonical" (PepINVENT).** **Honest caveat:** RFpeptides hits nM canonical → native ncAA must be tied to a **developability** win, not affinity. APCyc is the primary co-design comparator (must match + add the ncAA axis).
- **Per-modality caveat (honest):** a unified representation must NOT collapse to a lowest-common-denominator — a dedicated small-molecule model can beat a generalist on small molecules. Keep **per-modality heads + per-modality eval**; all-in-one wins only if the shared chemistry representation stays genuinely strong *per modality*.

---

## 2. Challenge → resolution → IP-claim map (the core)

| # | Challenge the foundation/prior-art leaves open | Our resolution (the "how") | IP strength (honest) |
|---|---|---|---|
| **1** | **Representation can't express non-canonical chemistry.** The AE hard-codes 20 canonical AAs + 14 atoms/residue (TRP saturates; N-Me-TRP → 15, forcing a retrain). | A **chemistry-native representation** that treats N-Me / D-AA / staples / non-standard residues as first-class — general (any modification), not the brittle 14→15 one-off. Candidate: atom/graph-level or HELM-aware encoding decoupled from a fixed residue vocab. **This general solution is the crown technical IP.** | **STRONG — the biggest gap; lead claim** |
| **2** | Developability is silent in the model (post-hoc filter). | **Developability-conditioned generation** with learned heads (permeability ΔPSA3D, SA, ΔG surrogate) — DCG P1. | **Held capability, NOT a novelty claim** — in-sampling multi-objective guidance is prior art. Present as capability we own, not invention. |
| **3** | Ring closure over **non-canonical** rings during sampling. | **Hard cyclic-manifold closure** formulated for the non-canonical setting (a specific, non-obvious gradient/constraint formulation; gradient-scale lessons already encoded in `ph_closure_guidance.py`). | **DEFENSIBLE — a concrete non-obvious claim can live here** |
| **4** | "High score ≠ drug"; no learning from outcomes. | **Closed-loop preference optimization (DPO) on proprietary wet-lab data** — verify-layer + assay-ranked (chosen, rejected) pairs. | **Method not novel; moat = the accumulating proprietary DATA + the composite system** |
| **5** | Data-bound ceiling (0.557 plateau; only ~1,233 structured N-Me examples). | **Foundation pretraining** on the broad peptide + small-molecule + physicochemical corpus (the 3-pillar data recipe: negatives / expert / physchem) → specialize; RAG for the data-starved cyclic case. | **System + data recipe** (execution moat, not a single-algorithm claim) |

**The composite IP claim:** leveraged backbone **+ non-canonical-native representation (#1) + hard closure (#3) + proprietary closed-loop (#4)**, emphasizing the non-obvious, hard-won parts. Aligns with `20260922_PROPRIETARY_PEPTIDE_IP_TECHNIQUE.md`: *claim the composite; weight #1 (representation) + #4 (data loop); do NOT claim the multi-objective guidance (#2) as novel.*

---

## 2b. The model itself — the depth IS the IP

The peptide LLM is a **conditional generative model over the joint (sequence, all-atom 3D structure, chemical modification) space of target-bound peptides.** The IP is the *technical depth* of resolving the following — not guidance, not the loop.

**A. Chemistry-agnostic representation (the crown).** *Challenge:* express canonical + non-canonical residues, backbone modification (N-Me), stereochemistry (D-AA), and macrocyclic topology (staples / head-to-tail) in ONE learnable representation — a fixed residue-vocab + fixed atom template cannot (the 14-atom wall). *Resolution:* a **hierarchical block-atom latent that decouples residue *identity* from the *atom template*** — each block carries a learned, variable-size typed-atom set + explicit modification state (N-Me flag, chirality, staple/closure bonds), so non-canonical chemistry is **in-distribution by construction**. This identity ⊥ atom-template decoupling is the lead claim (#1) **and the all-in-one enabler**: the *same* chemistry-native representation spans small molecules + peptides + macrocycles from one model. Fused with B/C/D (full-atom 3D + target conditioning + closure) it *is* the unbuilt intersection — the verified white space (native ncAA + full-atom 3D + target-conditioned + de-novo). The winning shape, per the SOTA survey, is a **structure latent (PepGLAD-style) × chemical-language ncAA vocabulary (PepINVENT-style), jointly receptor-conditioned**.

**B. Joint co-design with enforced self-consistency.** *Challenge:* the generated sequence must actually fold to the generated structure (the *Consistency* metric — which our warm-restart showed degrades when unmanaged). *Resolution:* jointly denoise the sequence / structure / modification channels with **cross-modal attention + a consistency-regularizing objective** (structure-from-sequence auxiliary + cycle-consistency), directly optimizing the metric we measure rather than hoping for it.

**C. Learned target + developability conditioning (integrated, not proxy).** *Challenge:* condition on the target pocket (binding) and developability (permeability/SA). *Resolution:* **pocket cross-attention + learned developability heads distilled from the real scorers, injected as training-time conditioning.** — **Explicitly NOT a novelty claim:** in-sampling multi-objective *guidance* (#2) is prior art; what is ours is the *learned, integrated* conditioning, and even that is presented as a **held capability, not an invention.**

**D. Hard geometric / topological constraints.** *Challenge:* guarantee valid macrocyclic closure + non-canonical valence/chirality. *Resolution:* **manifold-constrained generation** with hard ring-closure + valence/chirality constraints in the generative process, formulated for non-canonical rings (#3).

**E. Data-efficient foundation.** *Challenge:* ~1,233 structured N-Me examples is far too few to train a deep model. *Resolution:* a **foundation-pretraining curriculum** — pretrain the chemistry-agnostic representation on the large small-molecule + linear-peptide + physicochemical corpus (where non-canonical *fragments* are abundant), then specialize on peptide/non-canonical structured data + the proprietary loop. The shared chemistry representation is what makes the transfer work (#5).

**Where the depth-IP lives:** A (representation) + B (co-design consistency) + D (constraints) + the composite. **Not** C's guidance idea (prior art) and **not** the DPO recipe (prior art; moat = data). A serious, professional model — measured on the full 7-metric panel, on leakage-honest splits — where the novelty is the *resolved challenges*, not a re-skinned backbone.

## 3. What we leverage vs. own (be explicit)
- **Leverage (don't claim):** the diffusion/AE co-design backbone, pocket detection, physics scorers (MM-GBSA/FEP), the in-sampling-guidance *idea* (#2), the public data sources.
- **Own (claim / moat):** the general non-canonical representation (#1), the hard-closure formulation (#3), the proprietary-data closed loop (#4), the pretraining/data recipe (#5), and the **composite system** as one governed pipeline.

---

## 4. Eval — baseline-to-beat (multi-metric, honest)
- **PepGLAD = the reference baseline.** Our model must, on the **full 7-metric panel** (DockQ, RMSD-Cα, Consistency, AAR, Seq/Struct/Codesign Diversity):
  1. **match or beat** on canonical co-design, *and*
  2. **do what PepGLAD can't** — emit *native, valid, developable non-canonical* macrocycles (the capability differentiator, not just a DockQ delta).
- Always on **leakage-filtered / family-disjoint** splits, vs a **physics baseline** and a **simple baseline**. Never a single number (the 0.557 plateau lesson).
- The verdict is the *capability + the panel*, not raw DockQ — a model that wins DockQ by collapsing diversity is worse.

---

## 5. Build order (leverage-first, resolve-the-challenges)
1. **Keep** the leveraged backbone + the verify/select loop + the frozen 0.557 baseline. *(done)*
2. **Resolve #1 — non-canonical-native representation** *(top technical IP)*: design the general encoding (not the 14→15 patch); the CycPeptMPDB N-Me dataset (in prep) is the falsification substrate.
3. **Resolve #3 — hard closure** over non-canonical rings.
4. **#5 — foundation pretraining** on the 3-pillar corpus to break the data ceiling.
5. **Close #4 — proprietary DPO loop** (needs wet-lab data; the compounding moat).
6. **#2 — DCG P1** learned heads (held capability) folds into 2/4.

---

## 6. Honest posture (IP defensibility)
- Defensibility = **composite system + proprietary data + resolved challenges**, not a novel backbone. A reviewer will (correctly) find the backbone and the guidance idea in prior art — so we **don't** claim those; we claim the representation, the closure formulation, the data loop, and the integrated system.
- Internal only — no method/stack disclosure in any external artifact (deck/flyer/proposal).
