# Innovation Thesis — Our Own Cyclic-Peptide LLM (from two deep critical surveys)

**Date:** 2026-10-05 · Forward-looking thesis (describes work to BUILD, not done). Synthesizes two
deep, limitation-focused surveys of the SOTA — structure/co-folding lineage and generative-design
lineage — read against each tool's OWN error-analysis/discussion/future-work + independent critiques.
Replaces the earlier shallow "reuse existing tools" framing: the innovation is in the tools' *cracks*,
which you only see by reading their admitted failures, not by treating them as ideal black boxes.

## The convergence (both surveys land here independently)
Every model in both lineages DEFERS the same cluster of problems — named in their own papers:
1. **No calibrated binding energetics.** Boltz-2 is triage-grade, *excludes peptides + protein–protein*;
   no cyclic method predicts ΔG. Independent FEP comparisons: negative OOD; "right answers for wrong reasons."
2. **Single static pose, no conformational ensemble.** AF3 (verbatim): "predict static structures… not
   the dynamical behaviour." Fatal for macrocycle chameleon (permeable vs aqueous), cis/trans, ring strain.
3. **"Zero-shot" novel-target generalization is largely illusion.** BoltzGen: models "succeed by reusing
   interaction motifs… we do not make the zero-shot claim"; true per-design confirmed hit rate **~3.3%**
   (BoltzProt-1), 3/10 novel targets. RFdiffusion needs human hotspots; independent replication ~7%.
4. **Circular self-consistency oracle.** Generate with an AF/Boltz prior → filter by its confidence →
   "validate" by refolding with the same family. Independently shown verifier-biased; only 43% of de-novo
   designs actually succeed experimentally; swapping the verifier changes the measured success rate.
5. **No joint multi-objective** (binding + permeability + selectivity + stability). Universally
   single-objective; permeability surrogates cap at R²≈0.3–0.65.
6. **Canonical-L, head-to-tail-only chemistry.** ncAA/N-methyl/cyclization — what *makes* macrocycle
   drugs — is exactly what the best generators can't produce. RFpeptides canonical-only (future work);
   UniMoMo linear-only; RareFold reaches only µM.

**Root cause (both surveys):** the structural **data wall** — ~hundreds of real cyclic co-structures
(~19 de-novo cyclic:target co-crystals total); everyone trains on linear peptides or AF2-*predicted*
structures (propagating predictor error). Meanwhile **display/selection data is abundant** (10¹²–10¹⁴
library members, enrichment-labeled), natively includes ncAAs/N-methylation (mRNA-display/RaPID), and
DL on 15.7k mRNA-display ligands already found pM binders.

## The genealogy (research trace)
Each generation folded the previous blind spot into the architecture — folding (AF2) → complexes
(AF-Multimer) → all-atom co-folding (AF3/Boltz/RFAA) → affinity head (Boltz-2) → ensemble attempts
(BioEmu) → ncAA/cyclic adapters (HighFold/CyclicBoltz/RFpeptides) — but **repeatedly deferred
energetics, dynamics, OOD generalization, and calibrated confidence**. The cyclic thread forks off
*because* structure data is absent, and splits into a structure-native branch (data-starved, circular)
and a sequence→property branch (abundant assay/display data, but no 3D mechanism). **Both branches
converge on the same unmet needs** — that convergence point is the frontier.

## The thesis — our own model, where an LLM actually wins
**Invert the field's data dependency.** Instead of a 3D generator trained on scarce co-structures and
graded by a circular oracle:

> An **LLM over cyclic-peptide chemistry** (HELM/monomer sequence), conditioned on target + selection-
> round enrichment, **trained primarily on abundant display/assay data** (structure as a weak prior),
> **jointly optimizing binding + permeability + developability**, **conformational-ensemble-aware**, with
> **native ncAA/cyclization chemistry**, and **graded by orthogonal experimental readouts through our
> closed loop** — not a self-consistency refold.

Why it's ours and defensible:
- **It's the regime where a chemistry-language model beats structure-first diffusion** — abundant
  sequence/HELM + enrichment + ncAA chemistry is where 3D diffusion is data-starved and circular.
- **Our assets become the moat:** the closed-loop DBTL machinery *is* the orthogonal-verification
  flywheel (#6); CycPeptMPDB + 136k affinities are the supervised seed; permeability's R²≈0.3 ceiling is
  *why* the value is the loop, not a static predictor.
- **Reframes the BoltzGen fine-tune correctly:** that is the *reuse* path (in-distribution
  specialization, expected to plateau on novel targets); it becomes a **structure-prior component**, not
  the headline. The headline is this LLM.

## Honest dependency
The one real blocker is **display/selection-scale data**: harvest public display-NGS (SRA/ENA — the
data-wall strategy's free-but-heterogeneous step 1), seed with what we hold, and/or commission a
proprietary campaign (long-term moat). The 10¹² data is NOT in hand.

## MVP — trainable on our GPU NOW, novel, no new data
A **property-conditioned cyclic-peptide HELM/sequence LLM** trained on **CycPeptMPDB (8.5k permeability)
+ binding_affinity_v1 (136k; 36k cyclic)** that **jointly generates for binding AND permeability** over
an ncAA/HELM vocabulary. No surveyed tool does joint binding+permeability generation over non-canonical
chemistry with real data (PepALD/PepTune are closest, docking-oracle-only). It is: genuinely novel
(open problems #5-multi-objective + #6-ncAA chemistry), immediately trainable on the GB10/AWS GPU
(sequence LLM, not a co-fold), and directly extensible to display data (#1), ensembles (#3), and the
closed loop (#6).

## Ranked open problems (the white-space, both surveys)
1. Display/assay data as the PRIMARY training signal (break the structural data wall + the AF2-as-data trap).
2. Joint multi-objective in one generative loop (binding + permeability + stability + selectivity).
3. Conformational-ensemble-aware design (the molecular chameleon).
4. Native non-canonical / cyclization chemistry generation (beyond a fixed library).
5. Sample-efficient novel-target generalization + honest per-synthesized metrics (not per-shortlist %).
6. Escape the self-consistency oracle with orthogonal experimental verification.
7. Physical validity + developability as in-loop constraints, reported at population scale.

## Next steps
- (a) Scope + train the **MVP cyclic HELM-LLM** (binding+permeability joint, ncAA vocab) on our GPU — novel + immediate.
- (b) Harvest **public display-NGS** (SRA/ENA) — the dependency for the full inverted-data-dependency model.
- The BoltzGen fine-tune (in flight) continues as the structure-prior component + its LOTO eval is the honest novel-target datapoint for the structure path.

Source surveys (this session, deep + critical, cite primary limitations/SI + independent benchmarks):
structure/co-folding lineage + generative-design lineage. Key frontier references incl. BoltzProt-1
(3.3%→8.0% confirmed hit rate), RFpeptides (Nat Chem Biol 2025, canonical-only), PepALD/RareFold
(ncAA/cyclic, µM), CycPeptMPDB, mRNA-display ML (pM binders from 15.7k ligands).
