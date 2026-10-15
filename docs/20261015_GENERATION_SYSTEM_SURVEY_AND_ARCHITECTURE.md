# Lead-generation system — survey, architecture (LLM vs closed-loop), and build plan

**Date:** 2026-10-15 · Answers: what knowledge goes *inside* the LLM vs *outside* in a closed loop; generative
LLM vs rules (the hybrid answer); a literature + open-source survey (incl. the generative+rules-in-one-model
paper); and a concrete build plan. Premise (user): the hard part is **collecting the knowledge first** — target
biology, structures, patents — before any loop can work. Builds on `20261015_LESSONS_AND_GENERATION_SYSTEM_UPGRADE.md`.

## 1. The core architecture question: what goes IN the LLM vs OUTSIDE (closed loop)
A clean split, confirmed by the surveyed work:

**Inside the LLM (parametric + context):** the *fuzzy, generative, language* parts.
- Proposing candidates in the free design space (the generator / proposer).
- Interpreting intent + free-text target knowledge (prose → design); multi-param reasoning.
- Domain priors: via continued pretraining / SFT on sequence–chemistry data (our HELM-LLM thesis), and via
  RAG at inference for factual grounding. The LLM is the PROPOSER and the natural-language reasoner — NOT the
  source of truth for facts, arithmetic, or constraints.

**Outside the LLM (tools / databases / verifiers in a closed loop):** anything needing *correctness,
determinism, freshness, or arithmetic*.
- **Knowledge bases:** target structures (PDB/AlphaFold), patents (SureChEMBL / Google Patents), sequences +
  assays (UniProt/ChEMBL), prior SAR. These are the "collect-first" foundation the user is right about.
- **Hard constraints / rules:** pharmacophore, FTO claim-scope, developability, mechanism (metal cofactor,
  epitope type) — deterministic, testable, cheap.
- **Scoring / physics verifier:** docking, MM-GBSA (mechanism-matched: add the MIDAS metal), counter-target
  selectivity, groove occupancy, geometry triage. This is the REWARD signal.

**The loop that ties them:** LLM proposes → verifier scores against all hard objectives → LLM revises. That
design→score→redesign loop is exactly where we turned a failure into a win (lactam SL-01 → SL-v3). It is the
product, not the raw generator.

## 2. Generative LLM vs rules → use BOTH, in the neurosymbolic / SNG pattern
Our rounds already showed rules are a **good filter, poor generator** (a rule fixing the whole scaffold only
emits molecules inside the patented genus). The literature's answer is the same and now formalized:
- **Symbolic Neural Generation (SNG)** — `arXiv:2510.23379`, Srinivasan et al., *Machine Learning* 115:210 (2026).
  Inductive Logic Programming learns symbolic rules from *very few* instances; those rules **constrain a neural
  generator, which rejects any candidate violating the rule**; output is (rules H, molecules X). Claims: binding
  "on par with leading clinical candidates" on poorly-understood targets, with interpretable rules experts use as
  "preliminary filters." This is literally "generative + rules in one model." (No OSS released as of the paper.)
- **Neurosymbolic representations in LLMs** — `arXiv:2502.01657` (EMNLP 2025): encode symbolic computation inside
  neural hidden states (demonstrated on math, not molecules) — the deeper "fuse, don't just chain" idea.

**Takeaway for us:** rules (outside, deterministic: pharmacophore + FTO claims + developability + mechanism) act
as *constraints and rejection filters* on the LLM generator (inside), which explores the free space. That's the
SNG pattern and it matches our empirical finding exactly.

## 3. FTO/novelty-aware generation (the αvβ6 genus lesson) — precedent exists
- **Molecular Optimization with Patentability Constraint** — AAAI 2024 (Turutov et al.). Trains generation to
  *jointly* optimize properties AND dissimilarity from patented compounds, using **SureChEMBL / Google Patents
  Public Datasets** as the reference DB (InChIKey exact-structure search). Directly the "generate outside the
  claimed estate" capability we need. Also: "AI-driven molecular generation of not-patented compounds" (Keio).
- Industrial FTO-in-the-loop agents now exist (patent check + prune alongside design).
⇒ The patent KB is a solved-enough pattern to adopt: structure a claim/compound DB and make dissimilarity a
generation objective. (For αvβ6 we did this manually via the CA2998968 claim read; this generalizes it.)

## 4. Open-source projects to leverage or build on
| project | what it gives us | license / repo |
|---|---|---|
| **REINVENT4** (AstraZeneca/MolecularAI) | mature RL multi-objective molecular generation; scoring-guided loop; the workhorse scaffold for design-score-redesign | Apache-2.0, github.com/MolecularAI/REINVENT4 |
| **Saturn** (Schwaller group) | sample-efficient generation (Augmented Memory, Mamba); multi-parameter optimization; beats 22 models | github.com/schwallergroup/saturn |
| **Mozi** (`arXiv:2603.03655`) | governed-autonomy agent pattern: dual-layer (generative flexibility + deterministic rigor), *verifiable stages*, hard constraints/role permissions — the "closed-loop governance" blueprint | paper (pattern to implement) |
| **AgentD** (`bioRxiv 2025.07`) | RAG drug-discovery agent: retrieves UniProt/ChEMBL/web, closed-loop molecular refinement — the knowledge-retrieval pattern | paper |
| **SNG** (`arXiv:2510.23379`) | the symbolic-rules-constrain-neural-generator method | paper (no code yet) |
| patent-constraint model (AAAI'24) | patentability/FTO as a generation objective; SureChEMBL/Google Patents DB | paper + public patent datasets |

**Critical caveat — these are SMALL-MOLECULE (SMILES).** REINVENT/Saturn/SNG/patent-constraint all operate on
small-molecule SMILES. **Our target is cyclic peptides / macrocycles**, where the generation substrate is
different (HELM/sequence; structure-based binder design via BoltzGen/RFdiffusion). So we **borrow the loop
architecture, the patent/scoring KBs, and the SNG constraint pattern — NOT the generators themselves.** The
peptide generator stays ours (HELM-LLM / BoltzGen). This gap (mature OSS is small-molecule; peptide/macrocycle
generation is less tooled) is also an opportunity: the loop + peptide generator is less crowded.

## 5. Build plan for BioMate (prioritized, knowledge-first)
**Phase 0 — collect + structure the knowledge (the user's point; prerequisite to everything):**
- Target KB: structures (PDB incl. cofactors/metals), mechanism annotation (metal? linear vs discontinuous
  epitope), counter-targets (e.g. PD-L2, αvβ8), known SAR/controls.
- Patent/FTO KB: claim-level representations of the relevant estate (SureChEMBL + Google Patents; our CA2998968
  read as the template) → dissimilarity/claim-scope as a queryable constraint.
- Scoring/verifier stack: mechanism-matched physics (metal-aware cofold/MM-GBSA), counter-target, developability,
  groove/geometry — control-anchored (A2) every batch.

**Phase 1 — close the loop (highest leverage):** adopt the REINVENT/Saturn-style design-score-redesign loop with
OUR peptide generator + the verifier stack as the reward (SNG pattern: rules constrain + reject; LLM proposes in
the free space). Make selectivity, developability, FTO, geometry IN-LOOP objectives, not post-hoc filters.

**Phase 2 — governance (Mozi pattern):** discretize the loop into verifiable stages with hard constraints, so
the agent can't silently produce invalid/unverified candidates — the trust layer for high-stakes output.

## 6. Honest framing
Most of the hard pieces (RL generation loop, patent-constraint generation, agent governance, RAG retrieval) have
published precedent and some OSS — but all small-molecule. BioMate's defensible build is the **peptide/macrocycle
version of this loop**: our HELM/structure generator + a knowledge-first verifier stack (mechanism-matched
physics, FTO claim DB, selectivity/developability/geometry) in a governed design-score-redesign loop. That is the
moat — not the generator alone — and it is exactly what the rounds showed is missing today.

## Sources
- SNG: https://arxiv.org/abs/2510.23379 · Neurosymbolic-in-LLMs: https://arxiv.org/abs/2502.01657
- Patentability-constrained generation (AAAI'24): https://ojs.aaai.org/index.php/AAAI/article/view/27778
- REINVENT4: https://github.com/MolecularAI/REINVENT4 · Saturn: https://github.com/schwallergroup/saturn
- Mozi: https://www.themoonlight.io/review/mozi-governed-autonomy-for-drug-discovery-llm-agents
- AgentD: https://www.biorxiv.org/content/10.1101/2025.07.02.662875.full.pdf
