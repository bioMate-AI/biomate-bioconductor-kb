# Capability Demos — Information-Flow Handoff for Claude Design

**Date:** 2026-10-23 (rev. 2 — reframed to "harness routes → existing category; no custom UI")
**For:** Claude Design — tutorial generation on **data-centroid v2**.
**Companion to:** `docs/20261023_DRUGDEV_TUTORIAL_INFOFLOW_FOR_CLAUDE_DESIGN.md`
(the 9 workflow use cases) and `docs/20261023_ML_DL_CAPABILITY_MAP_FOR_UI_ENRICHMENT.md`.

**What this is:** the input→intermediate→output information flow for the **four
capability demos** — **(1) the dry loop**, **(2) the dry→wet loop**, **(3) multi-agent
target-ID evidence search**, **(4) adaptive intelligence (context disambiguation +
memory + RSI)** — worked on the real **αvβ6 PDAC / PD-L1 / GRPR cyclic-peptide**
program.

### Governing principle — NO custom UI per capability (read first)

BioMate is a **small fixed set of categories + run-cards-by-domain**; the **harness
decides what a request is and routes it into an existing category**, which renders on
its existing canonical surface. **Design does not build a bespoke surface for any of
these demos.** Each demo below is specified as *category → surface → info-flow*, not
as a new screen. The only shared build that drug-discovery needs is the **evidence-
class viewers** (Structure / Figure / Table) that *every* molecular task reuses — a
shared primitive, never per-task.

| Capability | Harness routes to (category) | Renders on (existing surface) | Custom UI? |
|---|---|---|---|
| Dry loop | Cloud · workflow | Workflow panel **auto-loop** (Spec 07) | No |
| Dry→wet loop | Cloud · models | **Models → Rounds** *campaign object* (Spec 03 §3.7; see §2) | No |
| Target-ID | Instant · search | **Search & evidence** answer (Spec 01/09) — ranked-entity variant | No |
| Adaptive: disambiguation | (any) | Chat **clarification card** (existing, v1 live) | No |
| Adaptive: memory | (any) | Cold-start + chat injection (existing) | No |
| Adaptive: RSI | n/a | **No user surface** — background mechanism; effect = better routing | No |

The same applies to the 9 workflow use cases: d1–d7 are **Nextflow workflows** → the
standard workflow panel / run-card-by-domain; **b1** is a **Model training run** →
the Models Train surface. None get a bespoke deck/screen.

---

## 1. The worked-example program (shared across all four)

- **Modality:** head-to-tail backbone-cyclized **cyclic peptides / macrocycles**.
- **Three targets:** **αvβ6 integrin** (PDAC, lead; our metal-complete receptor from
  PDB **9XMM**); **PD-L1** (IO; SYSUCC anchor; control macrocycle PDB **5O45**);
  **GRPR** (GPCR; radioligand/renal line).
- **Artifacts to populate screens:** BoltzGen **10-peptide (PD-L1)** / **12-peptide
  (αvβ6)** panels; in-house dataset `binding_affinity_v1` (**136,730 rows; 36,102
  cyclic; 434 PD-L1; 227 αvβ6**); multi-objective **qNEHVI +37.6%** vs composite on
  PD-L1; assays — αvβ6 **FP competition**, GRPR **whole-cell flow** (IC50→Ki); a
  send-ready **GenScript RFQ** for the PD-L1 round-1 order.
- **⚠️ Program honesty caveat (demos 1–2):** at *platform* level the campaign/loop API
  is **small-molecule (SMILES) only**. The αvβ6/PD-L1/GRPR **peptide loop lives in
  research scripts** (`research/guangzhou_all_atom/`) + an **external `sdl-macrocycle`
  repo**; close-back has run only on **synthetic KD** ("the real loop turns when the
  GenScript round-1 KD returns"). So use a **small-molecule campaign** for platform-
  native loop mechanics, and the **αvβ6/PD-L1 peptide program as the scientific worked
  example**, shown honestly as the research-script loop the platform is extending to.

---

## 2. Architecture note — the continuous loop as a *campaign object* (the one thing that needs attention)

Every other category is **request → run → result**: a **bounded run object**. The
continuous design + optimisation loop is **not** — and that's why it, specifically,
deserves design attention (while still using no bespoke per-task UI).

**Why it's special.** A loop is a **long-lived campaign** that: owns **many runs** over
weeks–months; **waits on the physical world** (the bench), not just compute;
**accumulates state across rounds** (surrogate version, measured data, proposal
history); is **re-entered over time, not re-initiated**; and has **humans at gates**
(approve / order / intake). A run-centric surface can't hold that — it's
program-centric.

**How to make it smooth (the model to build toward):**

1. **One home, already defined: the Models → Rounds *campaign object*.** Make the
   campaign a **first-class persistent object** (like a project/dataset), with rounds
   as its timeline. The harness routes "optimise / design in rounds" there. No new
   surface — the Rounds track *is* the home; it just needs to behave like a durable
   object, not a run page.
2. **A continuous thread, not a run page.** Stage bar **Proposed → Ordered → At the
   bench → Results in → Refit**, persisting across sessions; the user re-opens the
   *same* campaign; memory recalls where it stands.
3. **"Waiting on the world" as a first-class state.** Weeks-long bench stages shown as
   **day-count + expected return + a notification when results land** — never a hung
   spinner. This is the one state the run model lacks.
4. **Two cadences under one object.** The **dry loop is the fast inner loop**
   (design → predict → QC → remediate) that produces clean proposals *within* a round;
   the **wet loop is the slow outer loop** (make → test → learn) *across* rounds. Show
   the inner loop as the "propose" phase, the outer as the round timeline.
5. **Built entirely from existing primitives.** Each proposal = a Design run; each
   prediction = a workflow; each refit = a training run; the results = a dataset
   version; the order = a file (order sheet + plate map). The loop is **only the
   orchestration that chains these over time** — the harness constructs it.
6. **Seamless re-entry.** Campaign object + memory make it always resumable: drop in,
   see the current round + the next decision, act, leave.

**The design attention is the state model + the continuous timeline + the "waiting on
the world" state + round-to-round coherence — not a widget.** Get those right and the
loop feels like one living program assembled from the same parts as everything else.

---

## 3. The four demos (category → surface → info-flow)

### Demo 1 — THE DRY LOOP (design → predict → QC gate → remediate → re-design)
- **Category → surface:** Cloud · workflow → the **workflow panel auto-loop** (Spec 07
  Self-correct toggle + remediation card). **No custom UI** — the auto-loop panel
  appears when a gate-wired phase halts.
- **Input:** any autoloop-wired drug-dev run on a candidate set (e.g. an **ADMET
  liability screen** on the αvβ6/PD-L1 panel).
- **Flow (input → intermediate → output):** run → QC evaluator scores each gate
  (`PASS / ADVISORY / HALT` with value/threshold/cited rationale from the public QC KB
  `qc_evidence.yaml`, GOLD/SILVER/BRONZE) → on **HALT** of a risk-stratification gate,
  a **before→after param diff** built from the *actual failing run values* (e.g.
  `logp_max 5.0→4.0`, `mw_max_da 500→400`) with rationale + citation → expert may
  **edit** the proposed params → **Apply & Re-run** (capped 3 attempts, review window,
  on by default) → gate passes → converged set + full gate/remediation trail in the
  **QC audit** (Reproducibility record).
- **compute × knowledge × wet-lab:** predictors (compute) + cited public thresholds +
  in-house data (knowledge) + wet-lab *avoided* until convergence.
- **Maturity:** **BUILT** for admet/docking/pbpk/cyp_ddi/nca_pk/cryo_em. **PROCEED +
  RETRY live; the third branch PIVOT (switch-workflow) is future work.** Fail-open.
- **Hero beat:** fixes a real liability cheaply, in silico, with a cited reason and a
  human in control — never a silent pass, never an autonomous restart.
- **Scenes:** run panel → **gate HALT** card (measured vs threshold, cited) →
  remediation before→after diff → expert edits one value → Apply & Re-run (1 of 3) →
  pass → QC-audit trail. *(Label PIVOT "planned," not shown firing.)*

### Demo 2 — THE DRY→WET LOOP (DMTA: design → make → test → learn)
- **Category → surface:** Cloud · models → **Models → Rounds campaign object** (Spec 03
  §3.2.3/§3.7; the **campaign model of §2**). Existing starting deck:
  `tutorials_v2_after_resequence/t2-models-and-the-closed-loop-walkthrough.html`. **No
  custom UI** — this is the Rounds track behaving as a durable campaign.
- **Input:** a campaign with a **surrogate model** + **virtual library**. Platform-native
  = small-molecule (SMILES); scientific example = PD-L1 10-peptide panel (research-script).
- **Flow (input → intermediate → output):** Round 1 baseline scored from **literature
  only** → **propose** via GP + **EHVI/qNEHVI** (multi-objective, never blended) →
  **order** = order sheet + plate map (the real GenScript RFQ) → **At the bench**
  (owns *weeks*; day-count stage bar, not a spinner) → **Results in** (3 intake routes;
  one dataset object, a version per pull; provenance-tagged measured vs predicted;
  **partial returns first-class** incl. no-data-with-reason; **censored `IC50 > 30 µM`
  kept as inequality**) → **Refit** (partial at 50% returned, full on close; the refit
  **is a tracked training run** → a **new model version** that scores nothing until it
  passes; effect on **held-out** data, e.g. MAE 0.41→0.33; previous version
  **superseded, not deleted**) → next round.
- **compute × knowledge × wet-lab:** surrogate (compute) + literature + assay history
  (knowledge) + measured KD (wet-lab) — the canonical three-way loop.
- **Maturity:** **BUILT for small molecules end-to-end**; physical **Make/Test
  sim-stubbed** (no live LIMS/CRO auto-push); **peptide loop = research-script, not
  platform-wired**; measured-data → generative-policy retrain is a capability, not a
  demonstrated live round-to-round loop; `sdl-macrocycle` is an external repo.
- **Hero beat:** measured bench data — including the inconvenient rows — refits the
  model and makes the next round better; censored kept as `>`, partial returns counted,
  refit is a gated training run, not a silent overwrite.
- **Scenes:** Round-1 literature baseline → propose (multi-objective bars, qNEHVI) →
  order sheet + plate map → bench stage with day-count → intake (one `>30 µM`, one
  no-data-with-reason) → refit → held-out MAE improves → new version supersedes.
  *(Label peptide arm "scientific example — platform loop is SMILES-wired.")*

### Demo 3 — MULTI-AGENT TARGET-ID EVIDENCE SEARCH
- **Category → surface:** Instant · search → **Search & evidence answer** (Spec 01/09;
  `dataui/SearchAnswer.jsx`). Renders as a **ranked-entity evidence answer** — the same
  evidence-answer surface as `lit_evidence`, with a ranked target table + tier/conflict/
  veto badges + per-channel provenance chips + a boundary note. **A content variant of
  an existing category, not a new surface.**
- **Input:** a disease/question ("evidence for PD-L1 in IO"), optional candidate targets
  / in-house tables. API `POST /api/target-id/identify`.
- **Flow (input → intermediate → output):** optional LLM planning (seed genes) →
  **parallel fan-out across evidence channels** (OpenTargets genetics [live], STRING PPI
  [live], pathway co-membership, cached table [DepMap / frozen OT / **in-house KB** /
  genetics-eQTL], optional frozen FM) → **weighted-harmonic-sum arbiter** → ranked
  targets with **convergence tier (corroborated/nominated), conflict flag, optional
  safety veto, per-channel provenance** + boundary. Paired **clinical-responder arm**
  (ICB response; IMPRES, CYT, IFN-γ) against the field **IMPRES AUROC ≈ 0.598** bar.
- **compute × knowledge × search/reasoning:** rich public KBs (OpenTargets, STRING,
  pathways) + in-house tables, fused and made auditable.
- **Maturity (read carefully):** orchestrator + channels + arbiters + API **BUILT &
  reachable**. **Honest default = OT-primary: fusion does NOT beat OpenTargets-alone
  (benchmark-confirmed).** Value = provenance + corroboration/conflict/veto + the
  clinical-responder arm, **not a ranking win** — do not show "we beat OpenTargets."
  Learned arbiter + FM channel = **dormant/stub**. MCP `identify_targets` is **live at
  runtime but absent from the committed manifest** and **not yet in the chat agent's
  in-loop tool set**. "Multi-agent" = **one orchestrator over parallel channels**, not
  an LLM-agent hierarchy. IMPRES 0.598 = verified baseline; beating it = not demonstrated.
- **Hero beat:** every target comes with its receipts — which sources fired, where they
  agree/conflict, what vetoes it, what it's *not* evidence for — turning OpenTargets
  into an auditable, corroborated answer rather than a bare rank.
- **Scenes:** ask → lane chip (Instant·search) → channels fan out → ranked targets with
  tier/conflict/veto badges + provenance chips → boundary → (optional) clinical arm vs
  the 0.598 bar. *(Label: "ranks by OpenTargets; channels add corroboration — not a
  ranking claim.")*

### Demo 4 — ADAPTIVE INTELLIGENCE (disambiguation + memory + RSI)
- **Category → surface:** **no new surface.** Disambiguation = chat **clarification
  card** (existing, v1 live; stricter v2 `DisambigCard` built, pending swap). Memory =
  **cold-start / chat injection** (existing). RSI = **no user surface** (background;
  show the *effect*, not the mechanism).
- **One scenario, three threads on the αvβ6/PD-L1 program:**
  1. **Disambiguation — LIVE.** Ambiguous ask ("dock this peptide" with ≥2 close
     workflows, or "DESeq2 or edgeR") → BioMate **asks** via the clarification card
     (candidates + scores + recommended pill) instead of silently routing; a
     clear-from-context ask is **auto-resolved** (context used to disambiguate without
     asking). Pick captured.
  2. **Memory — LIVE.** Next session, BioMate **recalls** user profile, **project
     knowledge** (the αvβ6/PD-L1 program), recent runs, episodes, and **corrections**,
     and **prepends them to personalise routing + param auto-fill** ("use to inform,
     don't mention"). The prior correction becomes a **hard constraint**. Human-only
     notes filtered out (privacy). `recall_memory` = a **live, fully-wired MCP tool**.
  3. **RSI — OFFLINE/DORMANT in production.** Across runs, the **harness** (prompt,
     skills, router tables, budget), **catalog coverage**, and (on-prem) **weights**
     improve via **propose→probe→compose**, adopting an edit only if a grounded score
     improves on an **out-of-generator held-out set, else ZERO (leakage firewall)**,
     with **human `.approve()`**, an executes-for-real gate, a forgetting guard, and a
     fail-closed export gate. **Prototype BUILT & self-tested, but not imported by
     `backend/` — production wiring dormant** (behind flag-OFF `pattern_router`). Show
     RSI as *capability growth over time*, labelled "validated offline; production
     wiring in progress."
- **compute × knowledge:** the memory KB (in-house user/project context) + the catalog
  + the self-improving substrate.
- **Hero beat:** BioMate learns your program and gets better the more you use it —
  disambiguates from context, remembers across sessions, improves its own substrate,
  every improvement **held-out-verified and human-gated** (never a silent self-edit).
- **Scenes:** ambiguous "dock this peptide" → clarification card (pick) → *new session*
  → cold-start shows **remembered αvβ6 context** + the earlier correction auto-applied →
  (internal/eval view) **RSI capability-growth** curve on a held-out set with firewall/
  approval badges. *(Label RSI offline-validated / production-pending.)*

---

## 4. Cross-cutting honesty rules
- Mark **live vs aspirational** on every step: dry-loop PIVOT = planned; dry→wet peptide
  loop = research-script; target-ID = OT-primary (no fusion win), MCP under-wired; RSI =
  offline/dormant.
- **Never claim a benchmark win** target-ID does not have ("does not beat OpenTargets").
- Platform-native loop mechanics = small molecule; peptide program = scientific example.
- Keep the v2 vocabulary (Table/Figure/Structure/Report/Log), molecular-viewer and
  no-bare-number rules, and the "approval pauses, never times out" contract.
- **No bespoke per-task/per-capability UI** — the harness routes into an existing
  category; the only shared build is the evidence-class viewers.

## 5. Source index
- Dry loop: `backend/experiments/autoloop_bridge.py`; `backend/experiments/{admet,docking,
  pbpk,cyp_ddi,nca_pk,cryo_em}_autoloop/`; UI `frontend/client/src/components/auto-loop-panel.tsx`;
  spec `data_centroid_design_v2/spec/07 The workflow panel.html`.
- Dry→wet loop: `backend/lib/galaxy/ai/drug_discovery/{assay_ingestion,bayesian_optimizer,
  auto_retrain,cro_order_export,wetlab_report_ingester,feedback_router}.py`; UI
  `frontend/client/src/components/models/*`; spec `.../spec/03 Models.html` §3.2.3/§3.6/§3.7;
  deck `tutorials_v2_after_resequence/t2-models-and-the-closed-loop-walkthrough.html`.
- Target-ID: `backend/lib/galaxy/ai/target_id/{orchestrator,arbiter,channels,data_channels,
  network_channels,clinical_arm}.py`; `backend/lib/galaxy/webapps/galaxy/api/target_id_api.py`;
  benchmark `docs/20261021_TARGETID_FUSION_VS_OPENTARGETS_BENCHMARK.md`.
- Adaptive intelligence: disambiguation `backend/lib/galaxy/ai/ai_assistant.py:4746-4871`,
  `frontend/client/src/components/workflow-disambiguation-card.tsx`, `v2/DisambigCard.tsx`;
  memory `backend/lib/galaxy/ai/memory/agentic_memory.py`, `frontend/server/memory-integration.ts`,
  MCP `backend/lib/mcp/tools_manifest.py:501`; RSI `grounded-prototype/research/harness_improver.py`,
  `evaluation/scorers/rsi_scorer.py`; docs `docs/20261021_HARNESS2_SCIENCEBUDDY_RSI_HANDOFF.md`.
- Program: `docs/20261004_PEPTIDE_PROGRAM_PLAN.md`, `docs/20261014_AVB6_OUR_STRUCTURE.md`,
  `docs/20261007_BINDING_ASSAY_PROTOCOL.md`, `docs/20261001_GENSCRIPT_RFQ_PDL1_ROUND1.md`.
- Master loop readiness audit: `docs/20261002_BIOMATE_LOOP_INFOFLOW_READINESS.md`.
