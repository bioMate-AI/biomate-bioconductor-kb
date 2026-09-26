# Peptide-Generation SOTA + the Real White Space (internal)

**Date:** 2026-09-26 · internal (NOT client-facing). Numbers are each paper's *self-reported* values on *its own* split — cross-method rankings are **directional, not head-to-head** (no shared benchmark).

## 1. PepGLAD is NOT uncontested SOTA — it's one of several
- **PepGLAD** (NeurIPS 2024): wins **Diversity 0.506 / Consistency 0.789 / Success 56% / DockQ 0.592 / speed 3s** on PepBench.
- **Beaten on:** **AAR** — D-Flow 58.69%, PepFlow 51.25% (PepGLAD doesn't even report AAR); **full-atom RMSD** — D-Flow 1.63 Å, PepFlow 2.07 Å; **ΔG on hard systems** — RFdiffusion −33.82.
- ProBayes (2026 Bayesian-flow) *claims* DockQ 0.74 — **unverified**.
- **So "beat PepGLAD" is the wrong target** — beat the *SOTA-per-metric set* below, and win the white space.

## 2. Targets to beat (verified SOTA per metric)
**Canonical co-design (match the field):** AAR ≥ **59%** (D-Flow) · RMSD-Cα ≤ **1.6 Å** (D-Flow) · DockQ ≥ **0.60** verified (PepGLAD 0.592) · Diversity ≥ 0.51 / Consistency ≥ 0.79 / Success ≥ 56% (PepGLAD) · ΔG ≤ −22 (note RFdiffusion −33.82 on hard systems).
**Cyclic/macrocycle (the real, experimental bar):** **RFpeptides** (Nat Chem Biol 2025) — sub-nM/sub-10-nM on 4 targets, ~20 synth/target. **EvoBind2** — 75% cyclic success, best 0.26 nM, sequence-only.
**Binder (experimental):** BindCraft ~31% real hit rate (open); AlphaProteo 9–88% (closed).

## 3. The white space — VERIFIED, and narrower than "nobody does non-canonical"
- **FALSE:** "no one generates non-canonical natively." **PepINVENT** (Chem Sci 2025, CHUCKLES chem-LM), **NCFlow**, **NS-Pep**, **PepTune** all generate ncAA/N-Me/D-AA at the *chemistry* level. **Do NOT claim "first to generate non-canonical peptides."**
- **TRUE (the real gap):** **no method combines all four** — (a) **native** ncAA/N-Me/D-AA/staple generation, (b) **full-atom 3D** structure, (c) **de-novo target-receptor conditioning**, (d) *not* mutational-scanning. The native-ncAA methods are **receptor-blind (SMILES-only)**; the structure/target methods are **canonical-only** (D-Flow's "D" is a receptor-reflection trick, not native; RFpeptides is L-canonical macrocycles). NCFlow is closest (structure-aware ncAA) but does **mutation into an existing complex**, not de-novo design.
- **Our defensible claim (frame exactly this way):** *"native non-canonical chemistry (N-Me / D-AA / staples) generated jointly with full-atom 3D structure, conditioned on a target receptor, as de-novo design"* — that intersection is genuinely unbuilt.

## 4. The winning architecture (from the survey)
**PepGLAD-style structure latent × PepINVENT-style chemical-language ncAA vocabulary, jointly conditioned on the receptor.** I.e. our **chemistry-agnostic representation** (arch doc §2b-A) fused with 3D co-design + target conditioning. Validate/oracle with **HighFold3 / HighFold-MeD** (already predict N-Me/D-AA/unnatural-AA cyclic structures) + wet-lab.
- Foundation options if not PepGLAD's VAE: **MultiFlow** (joint seq+struct flow), **Chroma** (programmable macrocycle constraints), **Proteina** (SOTA backbone), **RFpeptides** (experimental cyclic, but Baker/Vilya IP-adjacent).

## 5. "All-in-one" (small molecule + peptide + …) — the market split
- **Camp A — chemistry-language / SMILES-level** (PepINVENT, PepTune, HELM-GPT, general molecular LMs): **inherently unified across modalities** (any molecule is a string/graph) — but **receptor-blind, weaker 3D**.
- **Camp B — structure-based co-design** (PepGLAD, PepFlow, RFpeptides): **modality-specific**, strong 3D + target-conditioning — but **canonical-only, not unified with small molecules**.
- **The frontier = unify them:** a **chemistry-native (atom/graph) representation that is ALSO full-atom 3D + target-conditioned.** That is simultaneously (i) the market's direction, (ii) the verified white space (§3), and (iii) exactly our arch §2b-A. Building the chemistry-agnostic representation **is** the all-in-one enabler — it serves the peptide moat, the small-molecule program, and the unified-model trend at once.
- **Honest caveat:** generalist-vs-specialist tradeoff — a dedicated small-molecule model often beats a generalist on small molecules. "All-in-one" wins only if the shared chemistry representation doesn't sacrifice per-modality quality; keep per-modality heads/eval.

## Unverified (flagged): ProBayes DockQ 0.74; RFpeptides overall success fraction (paywalled); NS-Pep primary metrics.
