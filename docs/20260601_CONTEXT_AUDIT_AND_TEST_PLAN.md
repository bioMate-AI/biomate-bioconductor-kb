# Context Architecture Audit — Three Questions

**Date:** 2026-06-01
**Branch:** `integration/next-phase`
**Method:** code review (storage layer, chat agent tools, session DB) + one live API test against dev

This doc answers three questions about BioMate's "context" handling — output reuse, dataset/workflow reusability, and what to test next. Conclusions are grounded in actual code paths and one end-to-end test of the chat agent, not speculation.

---

## Q1: Once I get outputs from a workflow, can I refer to them and ask questions or do further computation?

**Honest answer: PARTIAL.** The data is preserved; the chat agent's access to it is not.

### What works ✓

- **Outputs persist** in S3 (`s3://biomate-nextflow-work/nextflow/outputs/<…>/`) indefinitely.
- **Run metadata persists** in Postgres `execution_runs` table (253+ rows verified). Survives container restart.
- **Public API endpoint** `GET /api/runs/:anyId/outputs` returns the list with presigned download URLs. Also has `publishDir-gap` fallback that recovers files from `work/` if `outputs/` is empty.
- **OutputAnalyzer** (`backend/lib/galaxy/ai/output_analyzer.py`) can parse VCF, CSV rankings, FASTQ QC, RNA DEG, and MRC maps into a structured summary (`summary`, `key_results`, `search_queries`, `caveats`, `next_steps`).
- **Endpoint** `POST /api/internal/analyze-outputs` exposes the analyzer.

### What doesn't work ✗

The **chat agent has only 3 tools registered** (`frontend/server/galaxy-assistant.ts:53,84,102`):

1. `run_code` — execute Python/bash on user-uploaded files
2. `read_file` — read a file from the data dir
3. `query_domain_knowledge` — RAG over curated bio knowledge

There is **no `get_run_outputs(run_id)` tool**. So when a user asks "What were the CYP IC50 values from my last cyp_ddi run?", the agent literally cannot reach the persisted data.

### Live test result (this turn)

I fired the cyp_ddi_panel workflow with `mock_mode: true` (run `75da05a8-2d0a-41b0-bdd4-079466d6bdcd`), which produced `validated_compound.json` with real aspirin chemistry. Then I sent this to `/api/chat/stream`:

> *"What were the CYP IC50 values from my last cyp_ddi run? Reference run id 75da05a8-…"*

Agent's response (paraphrased):
> *"No output files from run `75da05a8…` are currently staged in the data environment. Please upload the output file(s) … and I can immediately parse and display."*

It tried `run_code` (`find $DATA_DIR`) and `query_domain_knowledge` (`CYP DDI IC50 values output format`). Neither found the data because neither has direct access to S3 outputs.

### The fix shape (not blocking, just to make this work)

Add a fourth tool: `get_run_outputs(run_id, format?)` that wraps the existing `runs-outputs-service.list()` and optionally `OutputAnalyzer`. About 20 lines in `galaxy-assistant.ts`. Then the same prompt would get the actual `pk_summary.json` content fed to the LLM and the IC50 values would come back directly.

---

## Q2: Does BioMate make previous datasets, previous workflows, and previous outputs reusable?

**Honest answer: PARTIAL — depends on what level you mean.**

### Per-session reusability ✓

Three DB tables track everything within a chat session:

| Table | What it tracks |
|---|---|
| `session_datasets` | All datasets uploaded or referenced in this session (input + output + intermediate). Storage type + path + format + size. |
| `session_workflows` | Workflows discussed/executed in this session, with success/failure flag. |
| `chat_messages` | Full message history. |
| `session_summary` (view) | Per-session rollup: counts of workflows, datasets, success rate. |
| `session_compressions` | Compressed conversation history for long sessions. |

### Cross-session at the data layer ✓

- **Outputs**: persist in S3 indefinitely; queryable via `/api/runs/:id/outputs` from any future session.
- **Runs**: persist in Postgres `execution_runs` table. 253+ rows verified covering today's + yesterday's + last week's runs.
- **Workflow catalog**: 2,455 workflows in `workflows` table (`backend/database/galaxy_ai_tools.db`). Searchable by name, domain, input_types, etc. The recipe doc `docs/20260529_WORKFLOW_INPUT_RECIPE.md` is built from this.

### Cross-session in the chat agent ⚠

The `_buildCrossSessionContextBlock` (`galaxy-assistant.ts:1618`) DOES pull up to 5 recent past sessions when relevant, scored by token overlap with current message. But what it carries is THIN:

```
[Past session context — use to inform your response but don't mention unless relevant]
- 2026-05-28: workflow CYP-DDI run on aspirin succeeded with 4 outputs
- 2026-05-27: pharmacophore filtering on 3 SMILES
- ...
```

Just titles/summaries — **NOT** the actual output contents. So the agent knows "I ran a cyp_ddi workflow before" but doesn't know what the IC50 values were unless you re-upload.

### Verdict per asset type

| Asset | Per-session reusable | Cross-session reusable | Notes |
|---|---|---|---|
| **Past datasets** | ✓ (session_datasets table) | ⚠ (path stored, but agent can't auto-attach) | Need a `find_dataset(name_pattern)` tool to bridge |
| **Past workflows** | ✓ | ✓ (workflow catalog used in routing) | Best-supported area |
| **Past output values** | ⚠ (re-fetchable via API) | ⚠ (NOT in agent's reach) | The biggest gap (Q1) |
| **Past parameters** | ✓ (in session_workflows) | ⚠ (not searched in agent prompts) | Could be added |

---

## Q3: Common context issues to test

Concrete test cases, written so they can be run by E2E playwright tests or by hand against `/api/chat/stream`. Each has a clear pass/fail criterion.

### Test 1 — Same-session output recall (will fail today)
1. Fire workflow X (e.g. ADMET on aspirin SMILES) → wait for completion → outputs include `admet_results.json` with `hERG_prob: 0.021`.
2. In the SAME chat session, ask: *"What was the hERG probability for aspirin?"*
3. **Pass:** agent answers `0.021` directly.
4. **Fail (expected today):** agent says "please upload your output file" or fabricates a number.

### Test 2 — Cross-session workflow recall (partial today)
1. Session A: discuss / run RNA-seq DE workflow on samples S1/S2.
2. Session B (later, same user): ask *"Do I have RNA-seq runs in my history?"*
3. **Pass:** agent lists the prior run with date + sample IDs.
4. **Today:** likely surfaces session summary but not run-level detail.

### Test 3 — Output-driven follow-up workflow (will fail today)
1. Run pocket_detection_druggability on PDB 1IEP → gets pocket coords.
2. Ask: *"Dock this top pocket against the aspirin SMILES from my earlier cyp_ddi run."*
3. **Pass:** agent picks up BOTH the pocket coords (from outputs of prior run) AND the SMILES (from history), constructs docking workflow.
4. **Today:** agent can't reach either; asks user to provide both.

### Test 4 — Dataset reuse (partial today)
1. Upload `samples.fastq.gz` in session A.
2. In session B: *"Run differential abundance on those samples I uploaded last week."*
3. **Pass:** agent finds the dataset via `session_datasets`, reuses its S3 path.
4. **Today:** `session_datasets` table has it but no tool surfaces it back; agent asks for re-upload.

### Test 5 — Parameter inheritance (will fail today)
1. Session A: run PBPK with `dose_mg=325, fu_plasma=0.05`.
2. Session B: *"Re-run my PBPK with the same parameters but change dose to 500."*
3. **Pass:** agent retrieves prior params, only diffs `dose_mg`, fires.
4. **Today:** agent asks for all parameters again.

### Test 6 — Long-conversation forgetting
1. In one session, have 30+ message turns about CryoEM.
2. At turn 35, ask: *"What movie set did we choose at turn 5?"*
3. **Pass:** agent recalls correctly (via session_compressions or full history).
4. **Today:** depends on conversation-state pre-compaction flush. Likely partial.

### Test 7 — Concurrent session leakage
1. User has session A and session B open simultaneously.
2. In B, ask about something from A.
3. **Pass:** cross-session block surfaces the A reference.
4. **Pass (security):** but only if B is the same user as A — never leak across users.
5. **Test failure modes:** non-authed user; admin viewing as user.

### Test 8 — Stale-reference handling
1. Reference a `run_id` that was deleted or that the user doesn't own.
2. **Pass:** clean error message ("run not found or not accessible"), not 500.
3. **Test failure modes:** UUID typo; expired presigned URL.

### Test 9 — Output type → automatic visualization
1. Run a workflow that produces a CSV with rankings.
2. Ask: *"Show me the top 10."*
3. **Pass:** agent uses OutputAnalyzer's `csv_rankings` path; returns top 10 with column names.
4. **Today:** agent uses `run_code` which works ONLY if user uploads. With the missing tool, can't auto-fetch.

### Test 10 — Mock-mode boundary
1. Fire a workflow with `parameters: {mock_mode: true}`.
2. Ask agent about outputs.
3. **Pass:** agent flags that mock mode was used and warns interpretation should be qualified.
4. **Pass (security):** mock-mode flag MUST be visible to user and never silently activated.

### Test 11 — Pre-run parameter validation
1. Send a workflow request with `parameters: {}` (no required inputs).
2. **Pass:** API returns a clear `400 missing required: smiles, dose_mg` BEFORE submitting to AWS Batch.
3. **Today:** agent fires, AWS Batch task fails 21s later with cryptic Python ValueError. Wastes ~$0.05 + 2-3 min per attempt.

### Test 12 — DB-vs-actual drift detection
1. Compare each row in `workflows.input_types` against the actual `.nf` file's `params.X` declarations.
2. **Pass:** zero diffs after `python3 backend/scripts/refresh_workflow_input_types.py` runs.
3. **Make it CI:** add a test that fails if any row drifts > 1 day from .nf file content.

---

## Summary recommendations

If I had to pick the 3 highest-impact context improvements to ship next:

1. **Add `get_run_outputs(run_id)` tool to the chat agent** (~20 lines). Unblocks Q1 (output recall) and indirectly fixes Tests 1, 3, 9. The data is already there; the agent just needs a tool to reach it.
2. **Add `find_dataset(name_pattern)` tool** (~30 lines). Unblocks Test 4 (cross-session dataset reuse). Reads `session_datasets` filtered by user.
3. **Add pre-run validator endpoint** (~50 lines). Unblocks Test 11. Saves money on every silent-failure.

After those three, BioMate's context handling would close the user-visible "amnesia" gaps without requiring any new infrastructure — all 3 read from data that's already persisted.

## Test execution shape

These can be turned into Playwright E2E tests using the existing infrastructure under `frontend/e2e/`. Pattern:

```typescript
test('context-test-1: same-session output recall', async ({ page }) => {
  await fireWorkflow(page, 'predict_admet', { smiles: 'CC(=O)Oc1ccccc1C(=O)O' });
  await waitForCompletion(page);
  const reply = await chat(page, 'What was the hERG probability for aspirin?');
  expect(reply).toMatch(/0\.0?2[0-5]/);   // accept range due to model nondeterminism
});
```

About 30-60 min per test to author. The 12 above would cost ~6-12 hours total to add to the E2E suite.
