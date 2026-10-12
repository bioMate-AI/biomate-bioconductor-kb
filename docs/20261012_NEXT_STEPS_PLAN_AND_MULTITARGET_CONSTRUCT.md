# Next-steps plan + the multi-target linked-construct question (αvβ6 × PD-L1)

**Date:** 2026-10-12 · Consolidates the knowledge-grounding reframe into a forward plan, and answers the
new question: *should the αvβ6 and PD-L1 ligands be LINKED into one medicine, and how?* Honest throughout:
candidate sets are design hypotheses; the linked-construct analysis surfaces a real PK conflict.

## 1. Where we are (one paragraph)
The sequence audit showed pure-LLM output was mechanism-dead for αvβ6 (0/12 RGD / 0/12 Asp). We reframed
to **knowledge-grounded design**: knowledge fixes the pharmacophore (hard), the LLM samples the free
space, physics/structure verifies. Built: `pharmacophore_knowledge.py` (gate + generation-constraint
contract), a new αvβ6 set (`knowledge_grounded_candidates_v1.json`, RGD+Asp+RGDL+lock, flanks diversified)
and a structure/scaffold-templated PD-L1 set (`knowledge_grounded_pdl1_v1.json`, docking-gate-required),
the pan-cold-GI expansion plan (`20261012_GI_EXPANSION...md`), and the activity-cliff handling.

## 2. The multi-target linked-construct question (αvβ6 × PD-L1 in one molecule?)

**Short answer:** for the program's actual thesis (αvβ6-radioligand-therapy **+** checkpoint blockade),
the two should **stay SEPARATE agents given together — NOT linked** — because of a fundamental PK
conflict. Linking makes sense in exactly one narrower scenario (avidity/selectivity), described below.

### 2a. Why NOT link them for the RLT + checkpoint combination
- **Opposite PK requirements.** A radioligand must be **small (~1–2 kDa) and FAST-clearing** (hours) so it
  penetrates tumor and spares the kidney (the dose-limiting organ, per the review). Checkpoint blockade
  needs **sustained occupancy** (antibody-like, days–weeks). One molecule cannot be both fast-clearing for
  clean dosimetry and long-residence for checkpoint coverage. Linking a PD-L1-blocking moiety onto the
  αvβ6 radioligand would wreck the radioligand's PK/dosimetry and raise kidney dose.
- **The mechanism doesn't need linking.** The combination works by *radiation (αvβ6-RLT) → tumor-antigen
  release → checkpoint (separate anti-PD-L1) priming* — the two act in different compartments/timescales.
  Separate dosing is how every radioligand+ICB precedent in the review runs (FAP-RLT + anti-PD-L1, etc.).
- **Regulatory/CMC.** Two well-characterized agents (a radioligand + an approved checkpoint antibody) is a
  far cleaner path than a novel bifunctional radio-immunoconjugate.

→ **Default: αvβ6-RLT and PD-L1/PD-1 blockade are co-administered, not linked.** This is also the review's
framing and the competitive precedent.

### 2b. The ONE scenario where linking IS sensible — heterobivalent AVIDITY targeting
If the goal is **tumor SELECTIVITY of the radioligand** (not checkpoint function), a **heterobivalent
αvβ6×PD-L1 peptide** is legitimate: both antigens are on the tumor, so a bivalent binder engages
**double-positive cells** with avidity → higher tumor selectivity and lower on-target-off-tumor dose
(directly mitigating the αvβ6 pituitary/kidney liabilities the review flags). Here **PD-L1 is a second
ANCHOR, not a checkpoint-blocker** — the construct is a more-selective radioligand, not a checkpoint drug.
Still bigger/slower than a monomer (a real cost), but both arms serve the same fast-delivery goal, so the
PK conflict of 2a does not apply.

### 2c. How to build a heterobivalent construct (if pursued)
1. **Two pharmacophore-locked arms**: the αvβ6 arm (RGD+RGDL+D-Pro/NMe) and a PD-L1-binding arm
   (docking-validated from the PD-L1-K set), each kept intact (knowledge-grounded).
2. **Tuned linker**: a flexible spacer (PEG_n or (Gly-Ser)_n) whose LENGTH is the critical variable —
   long enough for both arms to engage (same cell, two antigens within reach, or sequential), short enough
   to avoid entropy/PK penalty. **Linker length is itself an activity cliff** (small change → avidity
   gained or lost) — optimize by modeling, don't guess.
3. **One chelator** (e.g., DOTA) for the radionuclide, positioned to not occlude either arm.
4. **Validate simultaneous engagement + PK**: dock/model whether both arms can bind at once; model size vs
   renal clearance; then SPR (each arm + the bivalent) and cell binding on double-positive vs single-
   positive lines.
5. **LLM + knowledge role**: knowledge fixes both pharmacophores; the LLM/optimizer tunes the linker and
   the non-pharmacophore positions; physics checks co-engagement and PK.

### 2d. Am I considering it? (honest)
Not until now — the program (memory, review) treated αvβ6-RLT and checkpoint as **separate** arms, which
is correct for the combination thesis. The linked bispecific was out of scope. Flagging it explicitly:
**recommend separate agents for the RLT+checkpoint mechanism; evaluate a heterobivalent αvβ6×PD-L1
*anchor* only as a radioligand-SELECTIVITY play**, with the honest caveat that any linked peptide pays a
size/PK cost against the small-fast-radioligand ideal. Decision needs the single-agent ligands validated
first.

## 3. Next steps (ranked)
1. **Stand up the docking gate** (αvβ6 MIDAS pocket; PD-L1 IgV cleft) → score the αvβ6-K and PD-L1-K sets
   → convert hypotheses into ranked, pose-bearing, rationale-attached candidates. *This is the top lever*
   (turns both sets from "carry the pharmacophore" into "predicted to bind").
2. **FTO vs the Trivehexin/avebehexin genus** on the αvβ6-K set (run the novelty/FTO gate) — the
   mechanism-vs-novelty squeeze; drop or redesign ones too close to patented matter.
3. **Pull the real WL12 / dmp10 / BMS macrocycle sequences** from the primary refs → proper PD-L1 scaffold
   templating + a validated-binder similarity prior (no memory-fabrication).
4. **Source the GI-table "verify" cells** (per-indication αvβ6 IHC prevalence; checkpoint-cold confirmation;
   per-indication radioligand competition) → finalize the PDAC→MSS-CRC→cholangio expansion ranking.
5. **Cliff-aware training data**: assemble single-substitution / deep-mutational-scan display pairs → a
   contrastive objective so the selector learns the decisive positions (RGD vs RGE class).
6. **Multi-target construct decision**: keep separate for RLT+checkpoint; prototype a heterobivalent
   αvβ6×PD-L1 *anchor* (linker-length scan) only if the selectivity play is wanted — after step 1 validates
   both single-agent arms.

## 4. Honest gate (unchanged)
Every candidate set needs docking + FTO-vs-genus + wet-lab SPR before it means "binder." Indication
expansion and any linked construct are downstream of validated single-agent ligands. The value delivered
here is the *method* (knowledge-grounded generation + gates + cliff handling) and mechanism-carrying
hypotheses — not validated drugs.
