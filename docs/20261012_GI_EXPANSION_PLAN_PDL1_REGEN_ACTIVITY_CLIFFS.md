# GI-cancer expansion plan + PD-L1 regeneration + activity-cliff handling

**Date:** 2026-10-12 · Follows the sequence audit (`sequence_audit.json`) and the knowledge-grounding
reframe. Three parts: (A) the pan-cold-GI expansion plan + ranked indication table, (B) a knowledge/
structure-templated PD-L1 regeneration, (C) how to handle the activity-cliff nuance (small key changes →
opposite function). Honesty: αvβ6/PD-L1 radioligand facts cited from the review; per-indication αvβ6
prevalence marked "verify" where no specific number is cited; the candidate sets are DESIGN HYPOTHESES
requiring docking + FTO + wet-lab, not validated binders.

## A. GI-cancer expansion — "αvβ6-RLT + checkpoint for the checkpoint-COLD GI carcinomas"

**Thesis:** αvβ6 is a pan-epithelial-carcinoma target (validated across GI by multiple clinical ADCs —
SGN-B6A / sigvotatug vedotin, STRO-006, PF-08046876; and αvβ6-ADC+pembrolizumab is already clinical in
NSCLC, NCT06758401). The program's *open* slot is **radioligand-therapy (RLT) + checkpoint**, and its
mechanism (tumor-cell αvβ6 radiation → antigen release → checkpoint priming) is decisive specifically in
**checkpoint-COLD** GI tumors — not in checkpoint-responsive ones. RLT's edge over the existing αvβ6 ADCs:
crossfire/bystander kill of antigen-low cells + immune priming an ADC payload doesn't give.

**Ranked indication table** (lead → fast-follow; cite = sourced, verify = source before quoting):

| Rank | GI indication | αvβ6 expression | Checkpoint status | Existing αvβ6 RLT competition | Fit for RLT+checkpoint |
|---|---|---|---|---|---|
| 1 | **PDAC (pancreatic)** | ~88% of primaries (cite: review ref 3) | **COLD** (checkpoint-refractory) | Trivehexin/Therahexin imaging+first RLT (cite) | **LEAD** — hardest cold GI; αvβ6 on tumor cells vs FAP on stroma → more direct priming |
| 2 | **MSS colorectal** | high (verify %) | **COLD** (MSS = non-responder; MSI-high excluded) | none RLT (αvβ6 ADCs only) | **fast-follow** — large population + cold; big unmet need; white space for RLT |
| 3 | **Cholangiocarcinoma** | high (verify %) | cold/modest | none RLT (white space) | fast-follow — desmoplastic, cold, αvβ6+; clean competitive white space |
| 4 | Gastric / GEJ | high (verify %) | **MIXED** (PD-L1 CPS-dependent, partly responsive) | αvβ6 ADCs active | lower differentiation — checkpoint partly works |
| 5 | Esophageal (SCC/adeno) | high (verify %) | responsive-ish | αvβ6 ADCs active | lower differentiation |
| — | **MSI-high CRC** | — | **HOT** (checkpoint already works) | — | **NOT a target** — no differentiation |
| — | HCC | variable/lower (verify) | moderate | — | deprioritize (αvβ6 less consistent) |

**Is it "more significant"?** Yes in *reach* (pan-cold-GI >> PDAC-only) AND the differentiation is
*preserved* by staying in the cold indications (PDAC → MSS-CRC → cholangio). Expanding into
checkpoint-hot GI (MSI-CRC) would dilute the thesis. **Gate:** this is positioning downstream of a
working, novel, FTO-clean αvβ6 ligand — which the audit showed we don't yet have. Expansion is a reason to
fix the ligand (knowledge-grounding), not a substitute.

**To source next** (web budget / primary lit): per-indication αvβ6 IHC prevalence (MSS-CRC, cholangio,
gastric, esophageal); checkpoint-cold confirmation per indication; a per-indication αvβ6-radioligand
competitive scan (vs the ADC landscape).

## B. PD-L1 regeneration — structure/scaffold-templated (honest)

PD-L1 is a discontinuous PPI surface (no linear motif), so — unlike αvβ6 — I do **not** hand-write a
decisive sequence rule, and I will **not** recite WL12/dmp10/BMS sequences from memory (fabrication risk).
Instead I design toward the **structural pharmacophore** I can state confidently: the PD-L1 IgV front
β-sheet face / hydrophobic cleft that antagonists engage, and the **validated macrocyclic-peptide
chemotype** (cyclic ~11–14-mer, amphipathic with a hydrophobic/aromatic face into the cleft, D-AA +
N-methyl conformational lock). These are **design hypotheses that MUST be docking-gated** against the
PD-L1 structure before they mean anything — they are a step up from the old protein-fragment-like
L-cyclic set, not validated binders. Candidate set: `results/knowledge_grounded_pdl1_v1.json`.

**Required gates before PD-L1 synthesis:** (1) dock vs PD-L1 IgV cleft (rank by pose/ΔG); (2) similarity
to the validated PD-L1 binder set (WL12/dmp10/BMS — pulled from primary refs, not memory) as a scaffold
prior; (3) FTO; (4) wet-lab (SPR / cell PD-1:PD-L1 blockade).

## C. Handling activity cliffs — small key change → opposite function (the deepest point)

The failure the question names is the **activity cliff**: near-identical sequences with opposite
function. αvβ6 makes it vivid — **RGD binds, RGE does not** (Asp→Glu, one methylene) because only Asp's
carboxylate geometry coordinates the MIDAS metal; **L-Pro vs D-Pro** flips the macrocycle conformation;
**N-methyl on/off** changes membrane permeability and the bound pose. Global sequence/fingerprint
similarity (Tanimoto, a plain selector LLR) **smooths over exactly these decisive differences** — two
peptides 95% identical can be binder vs non-binder. How we handle it:

1. **Key positions are HARD constraints, not similarity features.** The pharmacophore gate treats Asp as
   *required*, not "similar to Asp." Mechanistically decisive positions are weighted ≫ bulk similarity —
   knowledge tells us *which* positions are the cliff.
2. **Stereo- and modification-aware representation.** The HELM/monomer vocab distinguishes D-Asp vs
   L-Asp, N-methyl vs not, Nle vs Leu — the char-LM cannot. A cliff that is invisible to a canonical-AA
   model is a distinct token to the monomer model. (This is a second reason the ncAA representation
   matters, beyond coverage.)
3. **Physics/structure is the arbiter at the cliff.** Docking / MM-GBSA / FEP "see" that RGE loses the
   MIDAS coordination while RGD keeps it — the single-atom difference the sequence model smooths. So the
   verification layer is not optional polish; it is *how* cliffs are resolved. Rank the final go/no-go by
   structure+physics, never by sequence similarity.
4. **Cliff-aware / contrastive training on matched pairs.** Train on matched-molecular-pairs (near-
   identical, opposite activity) — deep-mutational-scan / single-substitution display data — with a
   contrastive loss, so the model learns the decisive positions rather than averaging them. Our selector's
   LLR (logP(hi)−logP(lo)) is a first step; it needs explicit cliff pairs to sharpen.
5. **Per-position attribution + uncertainty flagging.** Flag any candidate that is high-similarity to a
   known binder BUT differs at a decisive position as HIGH-RISK (likely on a cliff) — do not trust the
   smoothed score there; route it to physics/wet-lab first.
6. **Do not use global Tanimoto for go/no-go.** Our FTO/novelty Tanimoto is valid for *re-discovery* (is
   this a known compound) but NOT for *activity* near cliffs — keep those two jobs separate.

**Net:** activity cliffs are precisely why pure-LLM/similarity fails and why the knowledge + stereo-aware
representation + physics-verification stack is necessary. The cliff lives at the key position; knowledge
names it, the monomer representation encodes it, physics scores it.

## Status / next
- A: plan documented; ranked table (source the "verify" cells next).
- B: PD-L1 regenerated as structure/scaffold-templated hypotheses (docking-gate-required).
- C: activity-cliff handling specified; reflected in the method (pharmacophore hard positions + HELM
  stereo-rep + physics verify + cliff-aware training).
- Honest gate (unchanged): all candidate sets need docking + FTO-vs-genus + wet-lab; indication expansion
  is downstream of a validated ligand.
