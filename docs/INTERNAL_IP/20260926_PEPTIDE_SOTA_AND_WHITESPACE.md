# Peptide-Generation SOTA + the Real White Space (internal)

**Date:** 2026-09-26 · **Updated 2026-09-27** with a verified 5-agent competitor pass (latest-LLM cross-check +
web verification). internal (NOT client-facing). Numbers are each paper's *self-reported* values on *its own*
split unless noted — cross-method rankings are **directional, not head-to-head** (no shared benchmark).

> ⚠️ **MAJOR UPDATE 2026-09-27 — the intersection we called "unbuilt" is now PARTLY OCCUPIED.**
> Two 2025–2026 methods (**APCyc, KDD 2026**; **CP-Composer, ICML 2025**), *both PepGLAD-derived*, now do
> **target-conditioned, full-atom, de-novo cyclic co-design.** The old claim ("no one combines structure +
> target + cyclic co-design") is **false as of KDD 2026.** The surviving, defensible white space is narrower
> and precise — see §3. This is exactly the kind of over-claim the competitive-pass discipline exists to catch;
> lead with the honest gap.

---

## 1. The structure-based co-design field (canonical, mostly LINEAR)
Self-reported, each on its own split:
- **PepGLAD** (NeurIPS 2024, MIT): Diversity 0.506 / Consistency 0.789 / Success 55.97% / DockQ 0.592 / ΔG −21.94; RMSD-Cα 4.09 Å (PepBench). **Linear only.** Re-runnable.
- **PepFlow** (ICML 2024, MIT): AAR 51.25% / RMSD-Cα 2.07 Å / Designability 65%. **Linear only.** Re-runnable.
- **D-Flow** (IEEE JBHI 2026, license unconfirmed): AAR 58.69% / RMSD 1.63 Å / Designability 75%. **Linear D-peptides (mirror-image), not cyclization.** Re-runnable with effort.
- **MultiFlow** (ICML 2024, MIT): co-designability PMPNN@8 81.4%. **Linear backbones, no sidechains.** Re-runnable.
- **RFdiffusion+ProteinMPNN** (Nature 2023 / Science 2022; BSD/MIT): ProteinMPNN seq-recovery 52.4%. Base RFdiffusion **now supports macrocycles** (`inference.cyclic=True`).
- **Newer successors (verify before citing):** **SurfFlow** (AAR 54.07% / 1.96 Å), **PepBFN** (AAAI 2026, THU PepGLAD-successor), **A-CODE** (81.2% co-designability), **FoldFlow-2** (~4× MultiFlow). Field is moving fast.

**Takeaway:** PepGLAD/PepFlow/D-Flow/MultiFlow are all **linear** — the macrocycle gap is real *for them*, but it is now filled by APCyc/CP-Composer (§3).

## 2. Cyclic / macrocycle-specific methods (the actual competitors)

**Structure + target + cyclic CO-DESIGN (the core we no longer own):**
- **APCyc** (KDD 2026, public code) — **pocket-conditioned full-atom joint seq+structure latent-diffusion co-design of cyclic peptides**, automated cyclization-topology inference, Bayesian multi-property guidance (affinity/permeability/protease/solubility/immunogenicity). **Same PepGLAD+AM-EGNN lineage as us. THE head-to-head.** ncAA scope = *cyclization linkages* (disulfide/amide/isopeptide), NOT sidechain N-Me/D-AA/staples.
- **CP-Composer** (ICML 2025) — zero-shot cyclic generation via composable geometric constraints on PepGLAD; full-atom, target-binding, stapled/head-to-tail/disulfide/bicycle *topologies*. Staple = geometric constraint, not sidechain chemistry.
- **Vilya-1/2** (2026, commercial, closed) — macrocycle **foundation model**, ncAA + full-atom; primary mode prediction, generative mode property-conditioned (receptor-conditioning unclear). Biggest resourced "foundation-model" threat.

**Experimental cyclic binders (the wet-lab bar):**
- **RFpeptides** (Nat Chem Biol 2025, BSD): **6 nM (GABARAP), 9.4 nM (RbtA)**, µM on MCL1/MDM2; hit rate 21–37%; 4 targets; ~6–14 synth/target; crystal Cα-RMSD 0.7–1.4 Å. **All-canonical L-AA** (explicitly needs no D-AA). Re-runnable.
- **EvoBind2** (Commun Chem 2025, CC-BY-**NC**): 19 nM best, 46% sub-µM, 75% cyclic success, sequence-only. NC license blocks commercial.
- **HFGuidedDesign** (Chem Sci 2026, code open): target-conditioned cyclic *sequence* generator + wet-lab (MDM2 75%/~1.2 µM). Canonical-only, sequence-only.
- **HighPlay2** (2026), **CycleRFdiffusion/TREM2** (2025): target+cyclic search pipelines with wet-lab hits; generate-then-predict, not co-design.
- **AlphaProteo / BindCraft** = **protein-binder** methods, **NOT cyclic peptides** → context, not competitors.

**Non-canonical generators (chemistry axis):**
- **NS-Pep** (arXiv Oct 2025) — de-novo, pocket-conditioned, full-atom, "non-standard AAs" → **but ncAAs are PTM-dominated (phospho-Ser/Tyr), not synthetic N-Me/D-AA/staples; not cyclic-primary; code unreleased.** Primary ncAA+full-atom+target prior art.
- **NCFlow** (bioRxiv Jul 2025) — arbitrary ncAA + full-atom + receptor-aware, **but mutation/DMS, not de-novo.**
- **PepINVENT** (Chem Sci 2025, Apache-2.0), **PepTune** (ICML 2025, CC-BY-NC-ND), **PepALD** (arXiv 2026), **PepEVOLVE** (2025): ncAA chemistry but **SMILES/HELM, no full-atom 3D, no receptor-structure conditioning** (and PepINVENT/PepEVOLVE are edit/mutation, not de-novo).
- **UNAAGI / GeoCycler / FuncBind (NeurIPS 2025)**: 2–3.5 legs; GeoCycler/HFGuidedDesign canonical-only; FuncBind lists ncAA but doesn't demonstrate it on peptides.

**Conformer generation (AE bar):**
- **RINGER** (ICML 2023-WCB, MIT): macrocycle-peptide SOTA — coverage-recall 79.7% vs ETKDG 35.8% / OMEGA 32.3%; needs SLSQP ring-closure post-processing; 4/5/6-mer canonical sidechains. Re-runnable.
- **RDKit ETKDGv3** (JCIM 2020, BSD): the free default baseline. **OMEGA-macrocycle** (JCIM 2020, proprietary — **academic-only, excludes CRO/commercial**).
- **PuckerFlow** (2026): fixes RINGER's post-hoc closure but on 5–8-membered rings, not peptide macrocycles — not like-for-like yet.

**Closed-loop / agentic (moat axis):**
- **GALILEO** — embodied AI-scientist, real wet-lab in the loop → the closest analogue to our DMTA loop; pressures loop-novelty.
- **PEGASUS** (J Med Chem 2026) — massively parallel biological assays (billions of cyclic peptides via NGS) + de-novo → attacks the **data-scarcity moat** with a high-throughput-assay flywheel. Most strategically important data-side threat.
- **FAR-DPO / CYC_BUILDER** — optimizer/assembly, not generators.
- **Supporting our thesis:** a 2026 J Med Chem position paper confirms *data scarcity, not architecture, is the field's bottleneck* → validates "the moat is the wet-lab flywheel + proprietary data."

## 3. The white space — VERIFIED and NARROWED (2026-09-27)

- **FALSE (refuted):** "no one generates non-canonical peptides" (PepINVENT). **Also now FALSE:** "no one does target-conditioned full-atom de-novo cyclic co-design" (**APCyc, CP-Composer**).
- **The ONE cell still unoccupied (write the claim at exactly this resolution):**
  > **Full-atom cyclic-peptide co-design *at a receptor pocket* with *native sidechain* non-canonical chemistry — N-methylation / D-amino acids / staples as first-class residues — not as cyclization-linkage tokens or geometric constraints, and de-novo (not mutation).**
- Why it survives, cell-by-cell: APCyc/CP-Composer = linkage chemistry, not sidechain ncAA · NS-Pep = ncAA+full-atom+target but PTM-dominated + not cyclic-primary · NCFlow = ncAA+full-atom+target but mutation not de-novo · PepALD/PepINVENT = ncAA but no 3D/no pocket · RFpeptides = cyclic+experimental but canonical-only.
- **Reviewers WILL cite APCyc & CP-Composer (co-design frame) and NS-Pep (ncAA+full-atom+target frame).** The paper must name and distinguish all three head-on.
- **Honest caveat on the ncAA axis:** RFpeptides reaches nM with all-canonical chemistry → native ncAA is **not an affinity advantage**. It is only a win if it delivers **developability (permeability / oral / protease-stability)** that canonical binders can't — so the ncAA claim must be tied to a developability result, not a DockQ delta.

## 4. Targets to beat (verified SOTA per metric, for the eval protocol)
- **Co-design (canonical):** AAR ≥ 59% (D-Flow) · RMSD-Cα ≤ 1.6 Å (D-Flow) · DockQ ≥ 0.592 / Success ≥ 56% / Consistency ≥ 0.79 / Diversity ≥ 0.51 (PepGLAD).
- **Cyclic co-design (the head-to-head):** **APCyc** on its full-atom + multi-property panel — *the* primary comparator (public code).
- **Cyclic conformer (AE):** **RINGER** coverage-recall 79.7% / ring-closure validity.
- **Cyclic permeability (developability):** **HELM-BERT** scaffold-split R² 0.483 (random 0.668); honest scaffold ceiling ~0.48–0.50; RF-ECFP4 floor.
- **Experimental cyclic binder:** **RFpeptides** 6–9.4 nM, 21–37% hit, ~6–14 synth/target, canonical.

## 5. Positioning recommendation (2026-09-27)
Given APCyc occupies the co-design core, **lead with the composite, not the backbone** (consistent with the IP doc posture):
1. **Headline = the narrow cell (§3):** native-sidechain-ncAA full-atom cyclic co-design at a pocket, **tied to a developability win** (the RFpeptides-canonical caveat forces this).
2. **Co-design parity vs APCyc = a REQUIRED gating experiment**, not the headline. We must show we match APCyc on the shared panel *and* add the ncAA axis it lacks. If we can't match APCyc, the co-design contribution collapses and the paper rests on ncAA + loop + proprietary data.
3. **Moat = the closed loop on proprietary wet-lab data** (differentiate from GALILEO = general agent; from PEGASUS = HT-assay, not learned-generator-on-proprietary-pharma-data).
4. **Do NOT claim:** "first non-canonical" (PepINVENT), "first cyclic co-design" (APCyc), the backbone, or in-sampling guidance (prior art). Claim the *composite* + the narrow cell + the proprietary loop.

## Change log
- **2026-09-27:** verified 5-agent competitor pass. Corrected the central white-space claim (intersection partly occupied by APCyc/CP-Composer); added APCyc/CP-Composer/Vilya/NS-Pep/NCFlow/HFGuidedDesign/HighPlay2/CycleRFdiffusion/PepALD/PepBFN/SurfFlow/A-CODE/FoldFlow-2/GALILEO/PEGASUS/HELM-BERT; verified numbers, licenses, re-runnability; narrowed the claim to native-sidechain-ncAA + tied it to a developability result; made APCyc the primary co-design comparator; added the honest RFpeptides-canonical caveat.
- **2026-09-26:** initial SOTA/white-space survey.
