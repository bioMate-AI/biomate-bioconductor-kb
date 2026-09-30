# ACT Application — Working Protocol (Cyclic-Peptide Immuno-Oncology)

**Date:** 2026-09-30
**Owner (this doc):** the three technical/strategy lines of the ACT task —
(1) accelerator landscape, (2) top-3 target directions for cyclic-peptide
generation + wet-lab validation, (3) cyclic-peptide generation using existing
models + our own model. The remaining two lines of the ACT task (validation
**quota/cost-as-therapy**, and the **MD Anderson / Texas clinical-collaborator**
map) are owned by a parallel session — referenced here, not duplicated.

**What "ACT" is:** TMC Innovation's **Accelerator for Cancer Therapeutics**
(Texas Medical Center, Houston). Cancer-therapeutics-focused → our submission is
**immuno-oncology only** (the broader immune-LLM covers all axes; for ACT we lead
with the IO cyclic-peptide therapy program). This scope was already fixed in
`20260926_IO_MULTITARGET_MARKET_LANDSCAPE.md` ("ACT / cancer, immuno-oncology only").

**Honesty contract:** demonstrated (approved/failed trials, filed deals, PDB
structures) vs reasoned (mechanistic/topological) vs our forward capability
(not-yet-built) are kept distinct. Deadlines/terms are VERIFY-on-web and dated;
anything unverified is flagged, never asserted.

---

## 0 · The one-paragraph thesis (what we pitch to ACT)

An AI-driven, **immune-mechanism-aware** discovery platform that nominates
non-redundant immuno-oncology targets/pairs and generates **cyclic-peptide**
therapeutics against them through a **dry→wet closed loop** (compute design →
CRO validation → model update). First-in-class shape (from the market landscape):
**not** another checkpoint×checkpoint pair (dead) and **not** "our PD-1×VEGF"
(crowded, >$20B committed) — but a **differentiated macrocycle format** on a
peptide-druggable IO target, with a staged path to an **LLM-nominated novel-axis /
multi-target, tumor-conditional macrocycle** — the sub-niche only Bicycle occupies
(and it is retrenching). Round-1 wet-lab proves the loop on a de-risked target;
the differentiated asset is staged on that proof.

---

## 1 · Accelerator landscape (Task 1) — *being filled by parallel research*

> Research agent running (web-verified: focus, stage, cohort size, terms,
> location, next 2026 deadline, fit). Anchor = TMCi ACT; "similar" = comparable
> early-stage cancer/therapeutics accelerators this startup could apply to.
> Table + ranked shortlist + "must-have application elements" land here.

_(placeholder — do not cite until filled)_

---

## 2 · Top-3 target directions for cyclic-peptide generation + wet-lab validation (Task 2)

**Ranking axis:** we optimize jointly for (a) **generatability** — is there a
structure/epitope our design models can condition on?; (b) **validatability** —
is there a cheap, fast, unambiguous wet-lab assay for round 1?; (c) **strategic
fit** — does it advance the first-in-class thesis without walking into a known
graveyard?; (d) **IP cleanliness** — can we claim novel composition, not a me-too.
Grounded in `20260926_IO_MULTITARGET_MARKET_LANDSCAPE.md` §4–§6.

### Direction 1 — **PD-L1 single-target macrocycle** — *the de-risking anchor / platform proof* ✅ round-1
- **Generatability: HIGHEST.** PD-L1 IgV domain; multiple co-crystal macrocycle
  structures (WL12 / pAC65-class; BMS-986189 series) → a well-defined binding
  groove our generator (PepGLAD / RFpeptides) can condition on.
- **Validatability: cheapest + fastest.** Off-the-shelf Promega PD-1/PD-L1
  blockade reporter bioassay + SPR/BLI affinity; co-crystal feasible. Orderable
  in round 1.
- **Precedent = de-risk, not crowding-out:** BMS-986189 reached the clinic then
  **suspended for PK/half-life** — the *chemistry* works; the open problem is
  **developability/PK**, which our permeability scorer + a tumor-conditional
  format directly attack. That is the wedge, not a me-too.
- **Role:** prove the dry→wet loop end-to-end on a target where success is
  unambiguous; produces the traction data ACT wants. **Not** the first-in-class
  story alone.
- **IP:** must design **around** BMS/PeptiDream scaffolds — novelty from a new
  macrocyclic scaffold + conditional gating, not a WL12 analog.
- **Risk:** crowded single-target field → win on format/PK, and keep it as the
  platform-validation vehicle, not the headline asset.

### Direction 2 — **CD47 / SIRPα macrocycle** — *the innate-axis complement, format-differentiated* ⚠️ round-1 stretch
- **Generatability: MODERATE–STRONG.** SIRPα/CD47 interface has structures + an
  existing **macrocyclic SIRPα blocker** (PMID 32640189) and D-peptide binders
  (D4-2, PDB 6LYC-class) → conditionable, but existing affinities are **µM**
  (needs affinity maturation).
- **Validatability:** phagocytosis / blockade reporter assays — established but
  more involved than PD-L1.
- **Strategic role:** opens the **adaptive + innate** combination story (the one
  non-redundant axis class that is mechanistically complementary).
- **The landmine, turned into the pitch:** PD-L1+CD47 is exactly the
  **magrolimab graveyard** (systemic tox + RBC antigen-sink, ~$4.9B write-off).
  A **macrocycle** (short half-life, tunable, tumor-conditional) is a credible
  answer to the *specific* failure mode that killed the antibody — this must be
  argued head-on, not hidden.
- **Risk:** µM starting affinity + the CD47-tox narrative are real headwinds;
  only pursue in round 1 if capacity allows, else stage to round 2.

### Direction 3 — **LLM-nominated novel-axis / multi-target tumor-conditional macrocycle** — *the first-in-class wedge* 🔜 round-2, gated
- **Candidates (partner to be chosen by our pair-nominator, not pre-guessed):**
  CCR8 (Treg depletion — hottest non-redundant axis, BMS-986340 furthest),
  CD73/adenosine (metabolic axis), or a **bivalent PD-L1 × novel-axis** tumor-
  conditional macrocycle — the format "**never built**" per the landscape.
- **Generatability: LOWER / variable.** CCR8 is a GPCR (7-TM → harder peptide
  epitope, fewer clean groove structures); CD73 is enzymatic (has a druggable
  pocket); a bivalent needs scaffold + linker design beyond single-binder
  generation. **Blocked on** running the immune-LLM **pair-nominator** to pick
  the partner with a broken-down evidence rationale (landscape Open Decision #1).
- **Strategic role:** THE differentiated, defensible asset (LLM-nominated novel
  axis + multi-target macrocycle + tumor-conditional gating) — solves the
  systemic-tox / PK failure modes that sank the incumbents.
- **Recommendation:** **do not** spend round-1 generation budget here. Run the
  pair-nominator **in parallel** during round 1; commit Direction-3 generation
  in round 2 once (a) the loop is proven on Direction 1 and (b) the nominator has
  produced a ranked, evidence-broken-down partner menu.

### Recommendation (what to actually generate)
| Round | Generate | Rationale |
|---|---|---|
| **Round 1** | **PD-L1** (Direction 1), + CD47 as stretch | Fastest unambiguous dry→wet proof; cheap assay; de-risks the platform for the ACT pitch |
| **Parallel** | *(no wet-lab)* run LLM pair-nominator | Selects the Direction-3 partner on evidence, not guess |
| **Round 2** | Direction-3 differentiated asset | First-in-class; gated on round-1 proof + nominator output |

---

## 3 · Cyclic-peptide generation protocol (Task 3) — *being filled by parallel research*

> Capability-inventory agent running: reads our macrocycle/closed-loop docs +
> locates the **PepGLAD harness** (commit 68df05ba9), inventories existing models
> (PepGLAD, RFpeptides/RFdiffusion+ProteinMPNN, AfCycDesign, HighFold, ADCP) +
> our own macrocycle permeability scorer/optimizer, and writes the concrete
> generate→fold→dock→filter→rank→select pipeline (inputs per target, spot compute,
> cost/wall-clock, IP-clean licensing flags). Lands here.

_(placeholder — do not cite until filled)_

---

## 4 · The ACT application working protocol (assembly)

**A. Narrative** (from §0 thesis + §2 ranking): platform + de-risked round-1
target + staged first-in-class asset; lead with the closed-loop moat.

**B. Traction to show** (the point of round-1 generation): a generated,
folded, docked, developability-filtered PD-L1 macrocycle panel → the wet-lab
validation result (affinity + blockade) → model-update = a *demonstrated* loop,
not a slide.

**C. Milestones (proposed, to be timeboxed to ACT's cycle in §1):**
1. Generate + in-silico rank PD-L1 macrocycle panel (compute; per §3).
2. Order top-N from an IP-clean CRO; run blockade + affinity (per the parallel
   session's **quota/cost** line).
3. Feed results back → model update → round-2 candidate set (Direction 3).
4. Pair-nominator output → chosen novel axis for the differentiated asset.

**D. Must-have application elements:** _(from Task-1 agent — pending)_ team, IP
position, validation data, defensible milestones, the ask.

**E. Cross-references:** target thesis =
`20260926_IO_MULTITARGET_MARKET_LANDSCAPE.md`; closed-loop mechanics =
`20260721_MACROCYCLE_CLOSEDLOOP_MASTER.md`, `20260730_DRY_WET_CLOSED_LOOP_PROTOCOL.md`;
cost model = `20260721_WETLAB_CLOSEDLOOP_FIRST_ROUND_COST_MODEL.md`;
validation quota + clinical-collaborator map = **parallel session**.

---

## 5 · Caveats
- Accelerator deadlines/terms (§1) are web-verified + dated; treat any unverified
  item as flagged, not fact.
- ACT = TMCi Accelerator for Cancer Therapeutics is inferred from the Texas/TMC/
  cancer context + the landscape doc's usage; confirm against the actual program
  the founder is targeting.
- §2 generatability/validatability calls rest on the landscape doc's peptide-
  druggability findings (PD-L1 strong, CD47 moderate, TIGIT none) — Direction-3
  partner peptide-druggability is explicitly TBD pending the nominator + a
  structure check.
- "First-in-class" claims are the *reasoned* strategic thesis, not a filed/proven
  position.
