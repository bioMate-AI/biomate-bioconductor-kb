# Evidence System ↔ LLM Training — Status & Integration Plan

Date: 2026-10-15
Scope: factual status of BioMate's evidence/grounding/multi-agent infrastructure, and
how it can better serve LLM training (both the on-prem *target* LLM and the *immune* FM).
Reference framing (user): "evidence system surrounding the LLM, complementing each other,
taking the virtual-pharma multi-agent evidence collection as a reference."

Sources: three parallel code surveys (evidence system / multi-agent orchestration /
training↔evidence wiring) + program record. Nothing was edited during the survey.

---

## 0. Thesis (the "complementing each other")

The LLM and the evidence system are two halves of one loop, and the program discipline
already names the division of labour (`project_immune_system_of_record`):
**the LLM structures messy inputs into features / plans / hypotheses and explains; it does
NOT emit the numbers.** The evidence system's job is to **ground, verify, score, and —
the part that is underused — to GENERATE the training signal.**

Today the evidence system mostly *decorates answers at inference*. Its highest-value use —
**producing grounded, execution-verified training data and an un-gameable reward** — is the
gap. That is the one sentence answer to "how can it better help LLM training": turn the
evidence system from an inference-time annotator into a **training-data generator + verifiable
reward**, and use it as the **inference-time context** that the KB-dividend result proves is the
small model's biggest lever.

---

## 1. What exists — the evidence system in three layers

### Layer A — Grounded Standards Assistant (the new, formal provenance layer)
- Design: `docs/20261014_GROUNDED_STANDARDS_ASSISTANT.md`.
- Trust lattice `SourceTier` A/B/C/D (normative / peer-reviewed / org-validated /
  unverified-personal); a Tier-D note can never ground a confirmed claim
  (`backend/lib/galaxy/ai/grounded/models.py:29-70,126-141`).
- Returns a provenance chain + explicit `Boundary` (where the record stops) + GRADE
  confidence capped at MODERATE when a boundary exists + per-tenant `IsolationAudit`.
- Standalone prototype `grounded-prototype/` (~2,900 LOC) + production mirror
  `backend/lib/galaxy/ai/grounded/` with `live.py` (regulatory + literature retrievers)
  and `_ich_bundle.py` (16 ICH guidelines pre-extracted, rides the .py-only backend sync).
- STATUS: **engine + `POST /api/grounded/answer` built and LIVE on dev** (11/11 e2e;
  returns `reg_sources=['reg:ICH M7(R2)']` Tier-A + live DOIs + isolation audit). Node
  proxy wired (`frontend/server/routes.ts:4877-4912`). **Unwired: the user-facing React
  panel (no route/sidebar import) and the MCP connector tool.**

### Layer B — Multi-agent evidence collection (the "virtual pharma" analog)
- `agents/agent_orchestrator.py` — parallel `DomainSpecialistPool`
  (`ThreadPoolExecutor max_workers=3`) → `WorkflowAssembler`. Reachable only via
  `/api/ai_assistant/generate_workflow_multi_agent`; **proxy has ZERO callers → DORMANT.**
- `pattern_router.py` (589 lines) — capability-gated chooser
  (SINGLE/MULTI_SPECIALIST/PIPELINE/PARALLEL_FANOUT), NMI saturation threshold, `fanout()`
  map-reduce. Flag `BIOMATE_PATTERN_ROUTER_ENABLED` (OFF) AND its only hook sits in the dead
  `route_and_handle` → **built + tested but cannot fire in prod.**
- `agents/research_agent.py` — **LIVE** deep-research/evidence agent (lit fan-out, PaperQA2
  grounding, `_ground_citations` rejects uncited prose). Confabulation guards present + fixed.
- `federated_query.py` — **LIVE** parallel source fan-out, but FLAT `_merge_results`
  (source-priority ranking, **no provenance tiers**).
- `agents/context_gatherer.py` — the solicit flow (`need_more_context` + ≤3 questions);
  `_extract_from_query` still MOCKED/TODO.
- `verification_layer.py` — majority_vote / self_consistent / consensus / verified_sample /
  grounded_pick. **ZERO non-test callers → DORMANT** (findings path is a single deterministic
  rule pass, `output_analyzer.py`).

### Layer C — Immune-FM evidence channels (evidence as model input)
Single file `biomate-audit-fix/research/immune_llm_baseline/immune_hybrid_llm.py` (3,544 lines);
provenance written to `evidence_provenance.json`.

| Channel | Origin | Train vs Eval |
|---|---|---|
| Knowledge (MSigDB pathways + TF regulons) | per-batch transform, fused every step | **TRAIN** |
| Genetics (OpenTargets L2G/eQTL) | gated feature + target-ID prior refresh | **TRAIN** (env-gated) |
| PINNACLE KG (context PPI) | expr-weighted embedding → fusion input | **TRAIN** (env-gated) |
| Perturbation (Replogle-Nadig Perturb-seq) | bilinear KO-effect loss `perturb_ground` | **TRAIN loss — default weight 0.0 (OFF)** |
| Target-eval gold (DisGeNET) | disorder-conditioned gene-set expansion | **EVAL-ONLY** (prior zeroed during its own eval) |
| DepMap (negated-Chronos essentiality) | virtual-KO rank vs essentiality | **EVAL-ONLY** |
| STRING PPI | evidence-mining over hit list | **EVAL-ONLY** |

Honest measured payoff (run #3, 22M cells): clean split-te lift **+0.057 macroF1** (the +0.25
headline was ~78% label-memorization leakage). Real wiring, small-and-honest, data-bound.

---

## 2. How the target LLM trains today, and where evidence is / isn't in it

- **Gold is DB-derived, single-turn:** `evaluation/local_trial/build_sft_from_gold.py` →
  `build_sft_v2_decomp.py`/`build_sft_v3_real.py`/`build_clean_sft.py`, over
  `docs/20260912_onprem_llm/data_candidates_v2/manifest.json` (workflow specs 4,200; tool
  knowledge 12,312; composition rationale 9,817; run-output 1,707; git-fix 500; docs; benchmarks).
- **DPO reward = gold-string match** (`train_dpo_grounded.py`): routing=named-workflow match,
  param=fraction of gold values + schema-valid, diagnosis=category match. Cheap programmatic
  verifier — NOT execution.
- **Execution grading is EVAL-ONLY:** `execution_grader.py::grade_run` (L1 terminal +
  non-empty; L2 S3 content + per-workflow correctness contracts incl. molecular-identity MW
  check) is wired ONLY into `backend_bakeoff.py` + its test. **No SFT/DPO builder calls it.**
- **Harness vs LLM split** (`docs/20260912_onprem_llm/20261001_LLM_HARNESS_TASK_SPLIT.md`):
  harness carries selection/rules/cheap-verifiers (don't train); LLM is the ceiling only on
  out-of-catalog composition (~0.10), findings interpretation (~0.29), clarification
  calibration (~0.36), the planning core. **Training value concentrates there.**
- **KB dividend** (`project_kb_dividend_finding`): the evidence/context layer lifts the SMALL
  model far more than frontier — routing 0.68→0.915, Bioc selection +15pp to ≈frontier parity,
  and drove scientifically-invalid answers to **zero**. The evidence system is the mechanism by
  which the small target model reaches usable behaviour.
- Roadmap `docs/20261009_INTEGRATED_HARNESS_AND_MODEL_ROADMAP.md`: Track A platform, Track B
  8 skill-packages, Track C local model (C2 targeted SFT only after stable contracts; C3
  preference/execution-feedback only if the reward can't be gamed). Execution grading is
  explicitly the central gate.

---

## 3. The five concrete gaps (evidence exists but does NOT feed training)

1. **Execution grading is eval-only.** The richest BioMate signal ("did the run produce
   correct outputs") never shapes the model. → this is roadmap C3, unbuilt.
2. **Unverified run-output gold leaks into SFT.** All 1,707 `biomate_run_output_candidates`
   are `eligible_for_training: False / needs_review`, yet the findings block
   (`build_sft_from_gold.py:347-361`) ingests up to 800 by `has_gold`/`score.passed` **without
   checking `eligible_for_training`**, and `score.passed` is a skeleton/order check, not
   execution grading. Training on unverified run narration.
3. **Perturbation-grounding loss is OFF by default** (weight 0.0) — the one causal training
   term is loaded + provenance-logged but doesn't train anything unless enabled.
4. **DepMap / STRING / DisGeNET are eval/validation only** — never a training loss.
5. **No execution-trajectory training data exists.** The roadmap's primary SFT lane
   (request→skills→plan→calls→real observations→corrections→report, multi-turn) has no builder.

---

## 4. Prioritized moves — make the evidence system serve training

Ordered by leverage / cost. All reuse owned code (`feedback_audit_biomate_capabilities_first`).

**P0 — Stop the leak (hours). SHIPPED 2026-10-15 (commit 3417e1456).** `build_sft_from_gold.py`
section 7 now ingests ONLY `has_gold AND score.passed` rows and trains on the gold `expected`
text, never unverified `produced_output` — findings 800→216 clean (1,491 unverified dropped).
`grade_run` can't retro-grade these static candidates (it needs a live run object), so promoting
more rows via real execution grading is the follow-on P1/P2 work. (Gap 2.)

**P1 — Execution grading as the DPO reward.** Full version (`grade_run` on Batch outputs) is the
un-gameable reward roadmap C3 wants, but needs live Batch spend + a graded-run store that doesn't
exist yet. **Option-1 (no-spend) SHIPPED 2026-10-15:** `train_dpo_grounded.py --phase exec`
(`mine_execution_pairs`) builds execution-GROUNDED preference pairs from the persisted
`real_exec_status` — chosen = a workflow that ran (ok/ok_warnings), rejected = a confusable
same-domain sibling that failed execution (exec_error/fixture_failed/timeout/ran_empty_output),
request synthesized from SHARED signal so executability is the only learnable distinction. 286
pairs / 15 domains, eval-leak guarded, no GPU/Batch. **Still TODO (option-2):** run the bakeoff to
persist a graded-run store, then wire `grade_run` verdicts into the reward (Batch budget required).
Keep gold-match as the cheap fallback. (Gaps 1, 5.)

**P2 — Evidence system as training-data generator (the virtual-pharma payoff, 1-2 weeks).**
Wire the dormant multi-agent layer into a *trajectory collector*, not the live chat path:
`agent_orchestrator` fan-out → `research_agent`/grounded tiered retrieval for citations →
real workflow execution → `execution_grader` verdict → `verification_layer` reviewer gate.
Successful, cited, execution-verified episodes become the roadmap's missing multi-turn SFT
lane; failures become correction pairs. This is exactly "multiple agents collecting evidence"
→ turned into grounded training data. (Gaps 1, 5; activates Layer B.)

**P3 — Grounded tier layer over the flat fan-out (days).** Replace `federated_query._merge_results`
(flat, source-priority) with the grounded `CompositeRetriever` + trust lattice, and bridge the
`Boundary → solicit` path into `context_gatherer`. This makes every retrieved citation
tier-tagged, so both inference context and generated SFT data carry provenance tiers — and the
GRADE/boundary becomes a second verifiable reward (citation faithfulness, anti-confabulation).

**P4 — Immune-FM: turn eval channels into training losses (research, gated).** Enable
`perturb_ground` at a small weight with the leave-perturbation-out control; add DepMap
essentiality / STRING PPI as auxiliary losses (not just rankers) under the linear-advantage
gate (`project_immune_system_of_record`: baselines must be beaten honestly, or keep as eval).
(Gaps 3, 4.)

**P5 — Finish wiring Layer A (days).** The grounded React panel + MCP connector tool are the
only unwired pieces; wiring them makes the provenance layer user-visible and lets the connector
expose grounded retrieval as a tool the orchestrator (and trajectory collector) can call.

---

## 5. Sequencing

P0 → P1 are immediate quality/reward fixes on the target LLM and need no new infra.
P2 is the strategic build (the evidence-collection → grounded-trajectory → verified-SFT loop) and
is where the "virtual pharma" reference actually lands in training terms. P3 raises the fidelity
of both. P4 is immune-FM research under the existing honesty gates. P5 is UI/connector polish.

The consistent meta-point across all three surveys: **BioMate already owns the primitives; the
gap is wiring the evidence signal into the training loop, not building new capability.**
