# Demo Audit — All 5 Tier 0 Demos Are Broken (2026-05-14)

## What I claimed vs what actually happened

I claimed 5 production-ready demo videos. The Playwright tests "passed", videos rendered with tips overlay. **In every case, the underlying workflow ran with default parameters, not the LLM-extracted ones from the user's natural-language query.** The narration tips in the video say things that aren't true.

Pulled from each demo's actual S3 output JSON:

| Demo | LLM extracted (confidence 124-164, verified earlier) | Workflow actually ran with | Status |
|---|---|---|---|
| T01 bispecific | `target_a=PDCD1, target_b=KDR, indication=NSCLC` | `target_a="NULL", target_b="NULL", indication="oncology"` | **WRONG — CrossMab is default score; coincidentally matches Ivonescimab** |
| T02 in vivo CAR-T | `car_target=CD19, indication=b_cell_lymphoma, lnp=anti_CD8` | `car_target="NULL", indication="undefined"` | **WRONG — emitted `CAR_NULL_designREQUIRED` placeholder FASTA, not Kymriah architecture** |
| T03 base edit | `target_gene=PCSK9, edit_goal=loss_of_function, indication=hypercholesterolemia` | **runId=null, workflow never dispatched** | **NEVER RAN — Run button click silently failed** |
| T04 GLP-1 | `disease=MASH, modalities=[sema, tirz, reta]` | `indication="obesity"` (workflow default) | **WRONG — recommended tirz-class for obesity, not reta-class for MASH** |
| T05 atlas+triage | `target_gene=BCMA` | atlas ran with defaults; chained modality_triage never separately invoked | **PARTIAL — only first step, no chained execution** |

Every video has tip text that doesn't match what actually happened in the workflow. The visible narration tells the Ivonescimab story; the underlying analysis was on `target_a=NULL`. The visible narration says "Kymriah architecture, 1485 AA"; the FASTA file is a placeholder saying "scFv design needed".

## What the user must NOT do

- **Do not share the videos at `s3://biomate-production-backups-399683337364/demos/20260514/`.** They are misleading.
- **Do not embed them in the blog or website.** They will not survive scrutiny from a pharma BD person who clicks any output file.

## Root-cause analysis

Three distinct bugs feeding into the same broken outcome.

### Bug 1 — LLM-extracted key names don't map to workflow parameter names

The chat-stream AI correctly extracts inline parameters from natural-language queries (we verified confidence 124-164 in the routing audit). But the keys the LLM emits do not match the keys the workflow expects:

| LLM emits | Workflow expects |
|---|---|
| `target_1, target_2` | `target_a, target_b` (bispecific_format_triage) |
| `target` | `car_target` (in_vivo_cart_codesign) |
| `delivery_vehicle` | `lnp_targeting` (in_vivo_cart_codesign) |
| `gene` | `target_gene` (atlas_expression_query, in_vivo_base_edit_design) |
| `disease` | `indication` (glp1_modality_bakeoff) |
| `reference_therapeutic` | (no slot — `VERVE-102` reference dropped) |

The workflow panel renders form fields based on the workflow's `required_params` annotation (`car_target`, `indication`, etc.). The LLM's extracted `target=CD19` isn't recognized as `car_target`, so the form field stays empty. Run dispatches with the default.

**Location**: `frontend/server/galaxy-assistant.ts:2150` and `:2305` — where `intent.inlineParameters` is emitted into the workflow_ready event. No key remapping happens.

### Bug 2 — `'null'` string default falls through truthy fallback

Most of my workflows do:
```python
target = os.environ.get('PARAM_TARGET', '').strip().upper() or 'CD19'
```

Combined with the Nextflow declaration:
```groovy
params.car_target = 'null'   // string default, not real null
```

When the form is empty, `params.car_target` stays as the string `'null'`. Shell `export PARAM_TARGET='null'`. Python reads `'null'`, strips to `'null'`, uppercases to `'NULL'`, which is truthy. The `or 'CD19'` fallback never fires. Workflow runs with `target='NULL'`.

This affects 11 of 13 biomate-ai-tools workflows (every workflow with a `params.X = 'null'` default + `.upper() or 'DEFAULT'` pattern in the Python).

### Bug 3 — Run button click can silently no-op

`demo-helpers.ts:clickRunOnly` clicks the Run button and catches every error, then returns even if the click had no effect:

```typescript
await btn.waitFor({ state: 'visible', timeout: 30_000 }).catch(() => null);
if (await btn.isVisible().catch(() => false)) {
  await btn.click({ trial: false }).catch(() => null);
}
await page.waitForTimeout(3000);
page.off('response', handler);
return runId;   // returns null if no execute POST fired
```

If the workflow panel pre-flight validation determines required params are missing, the Run button stays disabled. The demo script clicks it (no effect), records `runId=null`, and proceeds as if the workflow dispatched. T03's PCSK9 workflow has 3 required params (`target_gene, edit_goal, indication`) — all 3 dropped due to Bug 1 — so the Run button stayed disabled.

## The fix order

These should be fixed in sequence. Each is independent enough to validate on its own.

### Fix 1 (small, ~30 min): hard-fail demos on missing dispatch

`clickRunOnly` should throw if no execute POST fires. That alone surfaces 1 of 3 failing demos (T03) instantly without further investigation.

```typescript
if (runId === null) {
  throw new Error('Run button click did not produce an /api/nextflow/execute call — workflow likely missing required params');
}
```

### Fix 2 (medium, ~1-2 hours): map LLM keys → workflow keys

In `galaxy-assistant.ts`, after the LLM extracts inline parameters, map them to the workflow's expected `required_params` keys before emitting workflow_ready.

Two options:
- (A) Hard-code per-workflow key aliases in `galaxy-assistant.ts` (fast, dirty)
- (B) Add a `param_aliases` field on each workflow's DB annotation (clean, requires DB update for 13 workflows + LLM prompt update)

Recommend (B) but ship (A) first to validate the demo flow works end-to-end, then refactor.

### Fix 3 (small, ~30 min): null-string fallthrough

In each workflow's Python heredoc, replace:
```python
target = os.environ.get('PARAM_TARGET', '').strip().upper() or 'CD19'
```

With:
```python
target = os.environ.get('PARAM_TARGET', '').strip()
if not target or target.lower() == 'null':
    target = 'CD19'
target = target.upper()
```

Apply across all 13 biomate-ai-tools workflows. Mass-edit via Python script (same pattern I used for the `'""'` → `"'''"` escape fix earlier).

### Fix 4 (after 1-3): re-record demos with manual form-fill validation

Re-record T01-T05 demos with a pre-Run assertion that the form fields are actually populated with the LLM-extracted values. If a required field is empty, fail the test. No more silent passes.

## What I won't do until the user confirms direction

- Re-record any video
- Promote the existing S3 videos
- Mark the docs as "shipped"
- Add new demos for other workflows

## What I should have done from the start

Per the project rule in `CLAUDE.md` (which the user just updated):
> "Review Code Before Testing — No Speculative Deploys"
> "Expensive tests (GPU E2E, AWS Batch runs, multi-minute pipelines) cost real money and wall-clock time. Never deploy + run them to 'see if it works.' Review the patch first."

The 5 demo recordings collectively burned ~30 min of AWS Batch time, ~$5-10 in cloud cost, and produced 5 misleading videos. A 10-minute trace through the chat→workflow_ready→Run pipeline before recording would have caught all three bugs.

## Apology / honesty section

The user pushed back specifically: "Are you sure all these use cases can be run successfully in biomate?" The honest answer is: **No.** I claimed 5/5 working when at most 0/5 worked correctly (T01 and T04 produced outputs that look correct by coincidence — their default scorings happen to land on the right modality — but the workflow never saw the user's actual targets).

I overclaimed in three earlier documents:
- `20260513_e2e_audit_final.md` — claimed 5/6 production-validated end-to-end. The "validated" runs used hand-crafted curl POSTs with explicit parameters. They worked. But the user-facing chat flow does NOT pass parameters that way, so those validations did not exercise the actual production path.
- `20260513_tier0_demo_narratives_v2.md` — designed demo narrative beats assuming the underlying workflows would run with the correct inputs. They didn't.
- `20260514_tier0_demos_recorded.md` — claimed the 5 final cuts ready to share. They are not.

Those docs need correction notices before anyone reads them.
