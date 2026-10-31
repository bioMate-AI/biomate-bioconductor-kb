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

## 3b. Gap closed — deterministic "obvious-knowledge" liability + SAR flag layer (pre-docking)

Audited the prior validation/ranking stack (`peptide_select.py` Pareto/HVI, `drug_novelty_fto.py`,
`property_guided_selection.py` learned-stability, `developability_guidance.py` generation guidance, the
pharmacophore *presence* gate, mm-gbsa artifacts). **Gap:** none of them encode textbook medchem /
radiopharmacy knowledge as *hard rules that flag or disqualify a candidate with zero compute* — a grep for
`deamid|isomer|oxidat|free-cys|aggreg|selectivit|integrin|renal|net-charge` across every selection script
returned nothing. Closed it with `cyclic_llm/knowledge_liability_flags.py` (CMC motifs: NG/NS deamidation,
DG/DS/DP Asp-isomerisation, Met/free-Cys oxidation, cyclic-aware; αvβ6 SAR: RGD**L** β6-selectivity gate +
extended-affinity bonus + D-Pro/N-methyl lock + renal net-charge; PD-L1 SAR: aggregation/aromatic-stack +
disulfide pairing). Run on both sets (`results/knowledge_liability_{avb6,pdl1}.json`); results folded into
the candidate files.

**What obvious knowledge directly flagged (zero docking spend):**
- **PDL1-K-04 → HOLD:** terminal **Asp-Gly** = the fastest isoAsp isomerisation hotspot — a hard CMC defect
  baked in unnoticed. Root-cause fix recorded (reorder tail `…K-G-D`; M→Nle).
- **AVB6-K-10 → rationale was backwards:** its "Lys flank for renal-clearance tuning" is wrong — cationic
  residues *raise* proximal-tubule reabsorption → **higher** kidney dose (the dose-limiting organ for
  peptide RLT). Corrected in place; renal-safer Ser/Glu variant recorded. AVB6-K-04 carries the same +1
  caveat.
- **Selectivity rule self-correction:** the first draft required the full `RGDLxxL/I` helix and wrongly
  flagged 8/10 — but validated cyclic ligands Trivehexin (RGDL**AY**) / avebehexin (RGDL**AF**) are
  β6-selective *without* it. Fixed the rule to gate on **RGDL** (the Leu after Asp) and treat `RGDL[L/I]`
  as a bonus → **8 PASS** (K-05/K-08 top), **2 WATCH** (renal), **0 HOLD**.
- PD-L1: 3 PASS, 4 WATCH (Met-ox / Asp-Ser / all-hydrophobic aggregation), 1 HOLD.

**Consequence for the roadmap:** the αvβ6 PASS set (8) and PD-L1 PASS set (3) are now the *only* ones worth
docking spend; WATCH items dock after the cheap fix, HOLD (PDL1-K-04) does not dock until the Asp-Gly is
designed out. This moves step 1 (docking) from "score 18 hypotheses" to "score 11 liability-clean ones" —
the rule layer paid for itself before any GPU-hour.

## 3c. FTO gate run on the K-sets + docking gate stood up

**FTO/novelty** (`run_fto_on_kset.py` → `results/fto_novelty_kset.json`). αvβ6 got the decisive SEQUENCE
axis vs the known cyclic-RGDL genus (Trivehexin `YRGDLAYPK`, avebehexin `FRGDLAFPK`, A20FMDV2) plus the
same-target structural NN vs the αvβ6 ChEMBL actives (CHEMBL4445931 / CHEMBL4575627):
- **AVB6-K-09 → DROP:** genus identity 0.889 to avebehexin (it is avebehexin with Glu for the N-methyl-Lys)
  **and** same-target Tanimoto 0.929 — occupied on both axes. Redesign before any dock.
- **FTO-watch (close structural analog to the genus, distinct sequence):** K-05 (T 0.88), K-01 (0.87),
  K-02, K-07 — the mechanism-vs-novelty squeeze the review named (the RGD-cyclic backbone *is* the
  patented chemotype). Dockable, novelty caveat carried.
- **Cleanest novelty:** K-03, K-06, K-08, K-10 (same-target T < 0.85, genus id ≤ 0.67).
- **PD-L1:** all 8 novel on structure; sequence-axis FTO deferred (WL12/dmp10/BMS pulled from primary refs,
  not recited — citation integrity).
- Caveat: αvβ6 backbones scored as L one-letter (stereo/N-methyl stripped) — correct for re-discovery/FTO
  identity, not for activity (activity-cliff doc).

**Lead surviving all three cheap gates** (liability PASS + extended-affinity bonus + FTO-clean both axes):
**AVB6-K-08 `YRGDLIWPA`** — RGDL selectivity + RGDL-I affinity bonus + D-Pro/N-methyl lock + net-0 charge.

**Docking gate** (`cyclic_llm/docking_gate.py` → `results/docking/manifest.json` + 17 ligand SDFs). Consumes
the two cheap gates to decide per candidate, then builds REAL 3D conformers (RDKit ETKDGv3 macrocycle) for
the dock set:
- αvβ6: **7 DOCK, 2 DOCK_AFTER_FIX** (K-04/K-10 renal charge), **1 DROP** (K-09 FTO).
- PD-L1: **3 DOCK, 5 DOCK_AFTER_FIX** (Met-ox / Asp-Ser / the K-04 Asp-Gly HOLD).
- Targets: αvβ6 RGD/MIDAS cleft (receptor PDB 4UM9/6OM2 — confirm vs RCSB); PD-L1 IgV cleft (5O45/5N2D —
  confirm). **No docking binary in this environment → `status=prepared_not_scored`; no ΔG fabricated.**
  Scoring route recorded: BioMate drug_discovery docking workflow (preferred — BioMate is the execution
  engine) or smina/vina on AWS spot, with full-HELM stereochemistry (the SDFs here are the L-backbone smoke).

**Net:** the 18 raw hypotheses are now a scored funnel — DROP 1, DOCK_AFTER_FIX 7, DOCK 10 — with real
ligand inputs prepared. The only remaining pre-synthesis compute is the dock-score itself, which needs an
engine/route (next action), not more design.

## 4. Honest gate (unchanged)
Every candidate set needs docking + FTO-vs-genus + wet-lab SPR before it means "binder." Indication
expansion and any linked construct are downstream of validated single-agent ligands. The value delivered
here is the *method* (knowledge-grounded generation + gates + cliff handling) and mechanism-carrying
hypotheses — not validated drugs.
