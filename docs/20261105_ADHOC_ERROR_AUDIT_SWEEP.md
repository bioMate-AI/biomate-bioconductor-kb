# Ad-hoc-error audit sweep (2026-11-05)

Multi-agent audit for the class of silent logic/data bug found earlier today (DILI asymmetric
override, BOIN dose-above-MTD, GEO nonsense contrasts, echoed-array findings, shape-blind sidecar
trust, zero metrics, starved step outputs). Six parallel agents, each on a distinct surface,
audit-only (trace real logic + verify; no edits). Findings recorded here as they report; I verify
the high-severity ones before fixing. Each finding marked CONFIRMED (verified wrong behavior) or
PLAUSIBLE. Agent reports are leads, not authority — I re-check before acting.

Surfaces: (1) workflow .nf reduce logic · (2) QC gate + auto-loop · (3) findings parsers +
descriptors · (4) chat + workflow card · (5) run-record consumers + billing · (6) sidebar/nav/dialogs.

---

## Surface 6 — sidebar / nav / dialogs (dead-control / mock-as-real) — REPORTED
Headline: the earlier #7 fix held — data services (`projects.ts`, `starred-workflows.ts`,
`recent-tools.ts`) return honest empty arrays; Projects page has real states; dead dialog buttons
removed; Billing/CRO routes+nav commented out; settings stub tabs gated behind `{false &&}`. **No
live fabricated-data-as-real bug survives.** Remaining = built-but-unwired cluster (all
frontend-safe; all OUTSIDE the `wiring-contracts.test.ts` guard, which doesn't cover app-sidebar):

1. **"Workflows" sidebar nav → permanently-empty, dead-ended dialog** — CONFIRMED (act on this).
   `app-sidebar.tsx:275-280/490`, `starred-workflows-dialog.tsx:55-58/236-246`. Two compounding
   defects: (a) nothing in the app ever calls `starWorkflow`/`toggleStar` → `getAllStarred()`
   always `[]` → the top-level nav always opens to "No starred workflows"; (b) the dialog is
   mounted with no `onWorkflowSelect`, so clicking a workflow's "Open" is a silent no-op (just
   closes). Axis: UX-misleading (first-class nav entry, permanently empty + dead-ended).
   Fix: wire a real star affordance + pass `onWorkflowSelect`, OR repoint "Workflows" at the real
   workflow browser/history and drop the dead dialog. Min: pass `onWorkflowSelect`.
2. **"Recent Tools" never populated** — CONFIRMED (lower). `app-sidebar.tsx:425/493-495`,
   `recent-tools.ts`. `addRecentTool()` is never called from live code → always empty. BUT
   `onToolSelect` IS wired and the empty state is honest → "honest dead feature," not deception.
   Fix: call `addRecentTool()` at the real tool-launch site (App `handleToolSelect`), or remove
   the entry.
3. **`ConnectorsDialog` dead-mounted** — CONFIRMED (cleanup). `app-sidebar.tsx:133/492`. No code
   ever sets `showConnectorsDialog` true (the Connectors nav goes to `/settings/connections`
   correctly). Unreachable dialog shipped. Fix: remove import/state/mount.
4. **`recentProjects` dead variable** — CONFIRMED (cleanup). `app-sidebar.tsx:175` computes it
   from legacy `biomate-projects` localStorage, never rendered (sidebar uses API `apiProjects`).
   Fix: delete; consider retiring the localStorage project path.

Guard suggestion: extend `wiring-contracts.test.ts` with contracts that `app-sidebar` passes
`onWorkflowSelect` and that `starWorkflow`/`addRecentTool` each have ≥1 live caller — exactly the
"built but silently un-wired" class.

---

## Surface 4 — chat + workflow card presentation / chat→panel wiring — REPORTED
(Real prop distribution is in `chat-interface.tsx`, rendered via `<ChatInterface>` from
chat-with-artifacts.tsx — the two worst bugs are there, not chat-message.tsx.) Verified-safe:
workflow-name "undefined" now guarded at both sites; card-after-text ordering correct;
`parseActions` not a mis-render path; no brittle alert-variant string check found.

1. **Un-run workflow card inherits ANOTHER run's live status + findings** — CONFIRMED (top).
   `chat-interface.tsx:2229-2231`. The prop guard `currentExecutionRun && message.invocationId && …`
   short-circuits: a generated-but-never-executed card (no `invocationId`) is handed the GLOBAL
   `currentExecutionRun`. Scenario: run ADMET (completed) → ask RNA-seq → the new RNA-seq card
   shows ADMET's "COMPLETED" badge/spinner AND a FindingsCard with ADMET's results under it.
   Axis: **data-integrity** (wrong run's findings under a different workflow) + UX. Fix: positive
   match — pass `currentExecutionRun` only when its id/galaxyInvocationId == message.invocationId,
   else null. Frontend-safe.
2. **"In panel" badge / card-collapse fires on ALL workflow cards** — CONFIRMED.
   `chat-interface.tsx:2236` `isInPanel={panelWorkflowMessageId ? (message.id===panelWorkflowMessageId) : isPanelOpen}`
   → when the panel is opened with no message id (run-restore on refresh `chat-with-artifacts.tsx:680-683`;
   `biomate:open-personal-workflow` `:691-693`; file-attach pre-open `:2391-2395`), EVERY workflow
   card gets isInPanel=true → all collapse to an invisible anchor + all show "In panel". Axis:
   UX-misleading. Fix: resolve the owning message id on every open, or gate the fallback to the
   latest workflow message. Frontend-safe.
3. **Param-hallucination guard skipped when schema is empty** — CONFIRMED (conditional gap).
   `galaxy-assistant.ts:9040-9060`, gated `if (_schemaNames.size > 0)`. For lazily-fetched/empty
   schemas (fresh/steps-lazy workflows) the guard is bypassed → an LLM-invented inline param key
   survives as a phantom "Recommended" row. Axis: data-integrity. Fix: when schema empty, don't
   prefill inline_parameters (or defer the drop until hydrated). Server-side, additive.
4. **SSE phase pills fall back to a progress heuristic when process names don't map** — PLAUSIBLE.
   `nextflow-workflow-viewer.tsx:1657-1719`. Live lookup keys on `phase.id/phase.name` but nf-core
   emits FQ names (`NFCORE_RNASEQ:RNASEQ:FASTQC`) → lookup null → drops to a workflow-%% heuristic
   that marks one phase running at a time; if `progress` isn't updated, later running phases stay
   `pending`. Axis: UX-misleading (live pills stuck). Fix: normalize both sides (strip nf-core
   prefixes / match trailing segment). Frontend-safe.
5. **wf-chip shows blank label for `queued`/unknown status** — CONFIRMED (minor). `chat-message.tsx:728`
   chipLabel map lacks `queued` → colored dot + blank text. Fix: add `queued` + default label.
6. **Disambiguation card degrades to a generic "Workflow" chip** — CONFIRMED (consequence of #2).
   `chat-message.tsx:724/842/900`. When #2 forces everInPanel=true on a disambiguation message,
   the candidate-picker path is skipped → generic chip; the routing disambiguation UI is lost.
   Axis: core-deliverable. Fix: fixing #2 resolves it; defensively exclude disambiguation from the
   everInPanel-collapse path. Frontend-safe.

## Surface 1 — executed workflow `.nf` reduce/selection logic — REPORTED (all CONFIRMED; all human-applied `.nf`)
**Six findings — FOUR new beyond the known BOIN/DILI.** This is the highest-harm surface.

1. **BOIN Phase-2 dose 2× MTD** — patient-safety. `clinical_trial_simulation/main.nf:304-328`.
   Confirmed **still live**: the `max_dose*1.1` guard caps at the dose-range max, NOT the MTD, and
   `max(P_success)` + Emax-monotone efficacy picks `p2_base*2.0`. = my existing #2 patch
   (`docs/20261105_BOIN_PHASE2_DOSE_FIX_PATCH.md`) — confirms it's unfixed and the patch is needed.
2. **phase2_dose_justification: "no safe dose" → HIGHEST candidate** — patient-safety. NEW.
   `pharmacology/phase2_dose_justification/main.nf:394-401`. `primary_dose = recommended_doses[0] if
   recommended_doses else candidate_doses[-1]` → when no dose is safe+efficacious it recommends the
   highest (most toxic) candidate; also `safety_margin is None` is treated as SAFE (`:395`).
   Fix: fallback to LOWEST / explicit "do not advance"; unknown margin = not-safe.
3. **repeated_dose_tox: PASS when margin is 0 or missing** — patient-safety. NEW.
   `pharmacology/repeated_dose_tox_prediction/main.nf:183-187`. `'PASS' if (safety_margin or 999)>=10`
   — a margin rounding to `0.0` is falsy → `0.0 or 999 → PASS`; `None or 999 → PASS`. The classic
   `(x or default)` trap where 0 is a valid, dangerous value. Fix: `is not None and >=10`.
4. **ADMET DILI asymmetric override → stale "high"; aggregate≠per-compound** — scientific/integrity.
   `predict_admet_properties/main.nf:480-486` vs `:500-521`. Confirmed **still live** and the
   per-compound "consistency fix" reintroduced the mismatch in the aggregate direction. = my
   existing #1 patch (`docs/20261105_ADMET_DILI_FIX_PATCH.md`).
5. **docking_autodock_vina: fabricated affinity vs a fake 1-ALA receptor reported as success** —
   data-integrity. NEW. `pharmacology/docking_autodock_vina/main.nf:305-317` vs `:438-513`. No-receptor
   path builds a single-alanine placeholder, docks, emits `success=True` + `best_affinity` + gate —
   directly contradicting the `:468-470` comment that claims `status='not_computed'` without a fake
   verdict. Fix: no-receptor → success=False/not_computed, null the score; ALA only behind a smoke-test flag.
6. **accelerated_stability: "most stable formulation" is always the first-listed** —
   scientific-correctness. NEW. `pharmacology/analyze_accelerated_stability_.../main.nf:135-152,227-237`.
   `chemical_stability` depends only on storage condition + time, NOT on the formulation, so all
   formulations tie and strict `>` keeps the first. Fix: formulation-dependent degradation rate, or
   stop emitting the ranking.

Judged clean (this class): herg_cardiac_safety_qsar, dart_toxicity, genotoxicity_ames,
exposure_response_modeling, allometric_scaling, hts_plate_qc, adaptive_trial_design.

## Surface 5 — run-record consumers + billing — REPORTED
Cross-check: this agent independently verified **#6 metrics + #8 steps are correctly wired AND
persisted** on both the read path and the completion/poller paths (routes.ts:12777/12864) — my
work holds. `resources.*` staying zero is intentional (no Node-side per-task trace). Live probes
were blocked by the credential guard, so the two PLAUSIBLE ones want a live GET.

1. **Billing usage reads wrong field names → tokens/compute-hrs/storage-GB always ZERO** —
   CONFIRMED, Node-safe. `pages/billing.tsx:78-95,555,696-745` vs producer
   `realtime_cost_service.py:501-525`. UI reads `tokens_in/tokens_out/mem_usd/total_hours/size_gb/
   put_count`; API emits `input_tokens/output_tokens/memory_usd/total_seconds/storage_usd/puts`.
   Dollar amounts match (masking it), but all usage QUANTITIES + the token-quota % render 0.
   Fix: rename UI fields to the API's (or alias backend-side).
2. **`float('inf')` quota → JSON `Infinity` → invalid JSON → billing page DEAD for team/
   enterprise/test tiers** — CONFIRMED, backend-py. `quota_enforcer.py:46-48,112-115` →
   `realtime_cost_service.py:531,538` → `billing_router.py:234,278`. `JSON.parse(Infinity)` throws.
   Fix: serialize unlimited as `null`/omit, never `inf`.
3. **Progress fields never written to Postgres → DB-loaded run shows `totalSteps=0`/`0%`** —
   CONFIRMED, Node-safe. `schema.ts:1294-1298` has the columns; `storage.ts:388-413` INSERT omits
   total_steps/percent/currentStepIndex; `:583-599` UPDATE sets only completedSteps. Under multi-
   worker / after MemStorage eviction a completed run's card reads "N of 0 steps / 0%". Fix: add
   the 3 fields to INSERT + UPDATE `.set()`.
4. **Redis-down billing fallback returns a flat shape missing `month`+`breakdown` → page throws** —
   CONFIRMED, backend-py. `billing_router.py:213-219` vs `billing.tsx:578,551-553`
   (`cycleLabel(undefined).split('-')` throws). Fix: return the canonical zeroed shape.
5. **Month-rollover un-quota'd (fail-open)** — PLAUSIBLE, backend-py. `realtime_cost_service.py:535-538`
   month-keyed limit, only (re)set on login/plan-change/webhook; a continuously-authed user crossing
   a month boundary gets `quota_usd=None` → enforcer allows unlimited, `/quota` `over_quota=false`.
   Fix: lazily re-derive from plan on read-miss. (live-verify)
6. **`used_usd`/`quota_pct` fold in in-flight running ESTIMATES not just committed** — PLAUSIBLE
   (semantics). `realtime_cost_service.py:530-532`. Gating (402) on a polled estimate that may over/
   under-shoot the final cost. Confirm intended; `committed_usd` exists if "used" should be committed.
7. **Reproducibility `completedAt` fallback tests `run.status` which is never set** — CONFIRMED minor,
   Node-safe. `reproducibility-record.ts:148,157`; status lives at `run.execution.status`. Fix:
   test `run?.execution?.status ?? run?.status`.

## Surface 2 — QC gate engine + auto-loop — REPORTED
Spot-checks clean: per-domain comparison directions (≥/≤) correct; GateRow value/threshold columns
not swapped; GOLD-lockout/red-line clamp sound.

1. **DILI gate HALTs on categorical `dili_risk` label, ignoring numeric probability** — CONFIRMED,
   patient-safety. `qc_trace_monitor.py:5493-5509` (gate = `dili_risk=="high" OR dili_prob>=0.8`);
   reads a single top-level `toxicity` block (worst-of-set label) so per-compound 0.041 never reaches
   it. The gate-side half of the DILI incident. Fix: gate on numeric `dili_probability` as primary,
   categorical advisory-only. Backend + `.nf` provenance (emit per-compound).
2. **hERG probability-only predictions bypass the cardiotox gate on the S3/Batch path** — CONFIRMED,
   patient-safety. `nextflow_executor.py:4744-4748` `_extract` allow-list DROPS `herg_inhibition_prob`
   (live path `:2008-2011` keeps it) → gate `herg_prob>=0.9` never evaluated on Batch runs → silent
   clean pass; the two paths disagree. Fix: add `herg_inhibition_prob` (+ any live-parser keys) to
   `_extract`. Backend-only.
3. **`FASTP` registered with `"*.json"` → any JSON mis-attributed to a sequencing gate on clinical/
   chem runs** — CONFIRMED, data-integrity. `qc_trace_monitor.py:1714`. The reference FASTP-on-clinical
   incident, root-caused. Fix: use real fastp basename or exclude `"*.json"` from process-inference.
   Backend-only.
4. **`build_gate_event` reports GOLD/passed=True when ZERO gates evaluated (`all([])==True`)** —
   CONFIRMED, scientific-correctness. `qc_gate_reader.py:541-558`; reachable via
   `nextflow_executor.py:4506-4508`. No readable metrics → "perfect pass." Violates "a gate that
   can't be read must never read as pass." Fix: empty → `NOT_EVALUATED`/passed=None. Backend-only.
5. **Degraded/unevaluable QC invisible in after-run summary** — CONFIRMED, UX/integrity, frontend-safe.
   `AfterRunReport.tsx:486,491` only render `fail`/`advisory`; backend deliberately writes
   `unavailable`/`unknown` sentinels (the degraded-sidecar work) which then show as empty → reads as
   all-clear. Fix: include unavailable/unknown/not_evaluated with distinct "could not evaluate" styling.
6. **`read_bioc_harness_gates` signature-incompatible with `build_gate_event`** — CONFIRMED latent.
   `qc_gate_reader.py:773` registers a list-returning fn in a single-6-tuple registry → bioc QC never
   surfaces (unreachable today; would ValueError if wired). Fix: flatten list-returning gate fns.
   Backend-only.
7. **Fail and advisory render identical amber** — CONFIRMED, UX, frontend-safe. `AfterRunReport.tsx:2304,2313-2316`
   (`isPassedStatus` true only for "pass"). A hERG/DILI HALT looks as benign as an advisory. Fix:
   fail/halt→red, advisory→amber, pass→green, unavailable/unknown→gray. (Also: summary vs full table use
   opposite measured/threshold column order — internally consistent, mutually inconsistent.)
8. **Manual-remediation input reads the wrong state key → typed value never displays** — CONFIRMED,
   UX, frontend-safe. `auto-loop-panel.tsx:294` reads bare `manualValues?.[k]` but store/merge use
   `` `${gate}.${key}` `` (`:432,450`). UI echo diverges from the applied value. Fix: read the
   prefixed key.

## Surface 3 — findings parsers + descriptors — REPORTED (schemas verified against real outputs)
1. **`reconcileFindingsDocument` clobbers the CORRECT entity-aware summary with the LLM flat summary
   → re-creates #4** — CONFIRMED, Node-safe. `findings-extract.ts:296-340`, wired `routes.ts:16238,16279`.
   `flatLiabilities` only recognizes a liability via the exact phrase `/potential liability/i` (emitted
   by the now-dead deterministic ADMET path, #6) → ∅ on every LLM flat → `flatSet≠docSet` → reconcile
   OVERWRITES the correct `doc.summary` with the LLM's "no liabilities" text. Fix: reconcile on a
   common basis, or treat the document as PRIMARY when flat is LLM-sourced; never let empty flatSet
   override non-empty docSet.
2. **DESeq2 parser hard-codes comma; real `de_results.tsv` is TAB → null / EMPTY findings on a
   parseable file** — CONFIRMED, Node-safe, core-deliverable. `routes.ts:15434`, descriptor
   `findings-descriptors.ts:123` (parse:'csv'). Fix: autodelim (tab-if-present else comma), as
   raredisease/VARIANT already do.
3. **DESeq2 gene column lost on `write.csv(row.names=TRUE)` → headline genes relabeled `gene_N`/`row_N`**
   — CONFIRMED, Node-safe, integrity. `routes.ts:15435,15446`, `findings-extract.ts:79`. nf-core emits
   gene IDs as the unlabeled row-name column; regex misses `""` → synthetic names, real symbols
   discarded. Fix: fall back to first (row-name) column, treat empty-named first col as id.
4. **Rare-disease `/moderate|mod/i` matches MODIFIER → MODERATE count massively inflated** — CONFIRMED,
   Node-safe, scientific. `routes.ts:15532`. `/mod/` is a substring of MODIFIER (usually the majority).
   Fix: `/moderate|^mod$/i` + a MODIFIER bucket (the VARIANT descriptor already did this).
5. **Variant parsers cap at first 200 rows with NO impact-sort → pathogenic HIGH variants dropped** —
   CONFIRMED, Node-safe, scientific. `routes.ts:15527`, `findings-descriptors.ts:165`. Position-sorted
   tables → HIGH-impact candidate causal variant beyond row 200 is invisible; counts undercount. Fix:
   sort by IMPACT severity before slicing, or count over all rows.
6. **Deterministic ADMET flat parser expects `Drug:/Compound:` blocks no workflow emits → dead on real
   output** — CONFIRMED, Node-safe, core-deliverable. `routes.ts:15328-15358`. Real output is
   `key:value` / `toxicity_report.json`. So the ADMET "flat primary verdict" the reconciler (#1) defers
   to is actually LLM text, not the deterministic gate. Fix: route ADMET through the JSON descriptor
   as primary, or teach the parser the real shapes.
7. **VARIANT descriptor has `fileRegex` but no `contentIncludes` → cross-fires on "filtered"/"annotated"**
   — PLAUSIBLE, Node-safe, integrity. `findings-descriptors.ts:153,178-180`. scRNA `filtered_feature_bc_matrix`
   / "annotated" tables can select VARIANT and get a spurious impact document. Fix: add `contentIncludes`
   (IMPACT token) / tighten fileRegex.
8. **ADMET_REPORT double-flags DILI + propagates the panel-worst aggregation; `assess` has no `band`
   branch** — CONFIRMED minor + .nf-part. `findings-descriptors.ts:75,87,93`; `findings-extract.ts:144-147`.
   Emits two DILI liability records (prob + risk) → inflated liability list; faithfully reports the
   per-compound = panel-worst DILI (aspirin 0.675). Node-safe part: dedupe DILI metrics + add `band`
   branch. .nf part: fix the per-compound=panel-worst aggregation in the ADMET workflow (same root as #1/DILI).
   enrichGO note: comma-only too but its real output IS csv, so not currently broken; autodelim everywhere is the safe general fix.

---

# CONSOLIDATED TRIAGE — 39 findings across 6 surfaces

**Validates the concern: this is a systemic class.** Split by who applies the fix:

### A. Frontend/Node-safe — I can apply + gate + ship (≈18)
- Billing field-name mismatch (S5#1), progress-field persistence (S5#3), reproducibility status field (S5#7)
- Chat-card run scoping (S4#1 ⚠️ data-integrity), In-panel mis-fire (S4#2), empty-schema param guard (S4#3, server), SSE pill normalize (S4#4), queued chip label (S4#5), disambiguation chip (S4#6)
- QC: degraded-QC invisible (S2#5), fail/advisory color (S2#7), manual-remediation key (S2#8)
- Findings parsers: reconcile clobber (S3#1), DESeq2 delimiter (S3#2), gene column (S3#3), MODIFIER count (S3#4), variant top-N sort (S3#5), dead ADMET kvBlock→JSON primary (S3#6), VARIANT contentIncludes (S3#7), DILI dedupe + `band` (S3#8 Node part)

### B. Backend-Python — review patches for human (≈6)
- QC: hERG prob bypass in `_extract` (S2#2 ⚠️ safety), FASTP `*.json` mis-attribution (S2#3), empty-gates→GOLD (S2#4), bioc gate signature (S2#6), DILI gate numeric-primary (S2#1 ⚠️ safety)
- Billing: `inf`→`Infinity` JSON (S5#2), Redis-down fallback shape (S5#4), month-rollover fail-open (S5#5), estimate-vs-committed (S5#6)

### C. Production `.nf` / workflow logic — review patches for human (≈6, highest harm)
- BOIN dose>MTD (S1#1=existing #2 patch), phase2_dose highest-when-unsafe (S1#2 NEW), repeated_dose_tox `(x or 999)` PASS (S1#3 NEW), ADMET DILI asymmetric override (S1#4=existing #1 patch), docking fake-receptor success (S1#5 NEW), accelerated-stability degenerate ranking (S1#6 NEW), ADMET per-compound=panel-worst aggregation (S3#8 .nf part)

### Already-fixed, re-verified clean: #4, #5a, #5b, #6, #7(data layer), #8.
