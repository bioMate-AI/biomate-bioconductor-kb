# Proposed BioMate training trace and annotation contract

**Status:** design for implementation, not telemetry already collected. All examples below are synthetic. The schema supports the task IDs in the [task catalog](/Users/kky/biomate-review/docs/20260912_onprem_llm/TASK_CATALOG.md).

## Units of collection

- **Episode:** one user objective across turns, including follow-ups, failed attempts, tool calls and final artifacts.
- **Task invocation:** one logical model responsibility, e.g. T06 parameter extraction. Retries/fallback attempts remain separate records linked to it.
- **Transition:** state/context → assistant output or tool action → validator/tool observation → next state. This is the primary supervision unit.
- **Preference pair:** the same exact input context with a reviewed chosen and rejected response plus reasons. Different contexts are not interchangeable preference pairs.

Store an immutable local raw event stream separately from the sanitized annotation view and curated training exports. A user edit, a click, a successful HTTP response or absence of complaints is not sufficient proof that the response is correct.

## Required fields

| Group | Fields | Purpose |
|---|---|---|
| Identity | schema_version, record_id, episode_id, task_invocation_id, task_id, turn_index, attempt_index, parent_record_id | Reconstruct the sequence and distinguish fallback attempts. |
| Ownership | tenant_scope, project_group_id, consent/training-rights status, retention policy | Prevent accidental cross-tenant use and unauthorized export. Use pseudonyms in the annotation/training view. |
| Versioning | application_commit, prompt_id, prompt_sha256, template version, tool_catalog_version, schema hashes, retrieval/index version, base/adapter/tokenizer revisions | Reproduce the request and invalidate stale labels. |
| Input | rendered_messages, available_tools, response_schema, retrieved_evidence, state_before, capability_manifest | Capture what the model actually knew. Raw prompts alone omit tool/schema/context differences. |
| Generation | provider, actual_model, adapter, endpoint_class, temperature, max_tokens, reasoning_mode, token counts, stop_reason, latency, error, fallback_from | Identify the true answering model, truncation and outside-boundary rescues. Never record credentials. |
| Result | raw_output, parsed_output, tool_calls, tool_observations, validator_results, state_after, terminal_outcome, artifact references/hashes | Separate plausible text from executed outcomes. |
| Review | gold_output/actions, correctness labels, defect tags, reviewer role/pseudonym, review status, source spans, accepted/rejected reason | Make the target explainable and auditable. |
| Splitting | source_document_group, study_group, entity/scaffold group where relevant, augmentation_parent, near_duplicate_cluster, split, split_manifest_hash | Keep correlated examples and augmentations out of opposing splits. |

A trace may contain material that must remain in a restricted artifact store. Record content hashes and local references in the index, with the corresponding content included only in authorized training jobs. A hash without access to the evidence is not a self-contained training example.

## Synthetic example: T06 parameter extraction

```json
{
  "schema_version": "biomate-trace-v1-proposed",
  "record_id": "synthetic-record-001",
  "episode_id": "synthetic-episode-001",
  "task_invocation_id": "synthetic-invocation-001",
  "task_id": "T06",
  "turn_index": 2,
  "attempt_index": 0,
  "parent_record_id": null,
  "tenant_scope": "synthetic",
  "project_group_id": "fixture-project-a",
  "training_rights": "synthetic-owned",
  "application_commit": "record-real-commit-at-capture",
  "prompt_id": "schema-parameter-resolver",
  "prompt_sha256": "compute-from-exact-rendered-input-at-capture",
  "versions": {
    "workflow_schema": "synthetic-schema-v1",
    "tool_catalog": "fixture-catalog-v1"
  },
  "input": {
    "rendered_messages": [
      {"role": "system", "content": "Extract only canonical keys named in the supplied schema. Return JSON."},
      {"role": "user", "content": "Synthetic workflow schema: genome is one of hg38, mm10; padj_threshold is numeric. Request: Use mouse mm10 and set padj to 0.01."}
    ],
    "available_tools": [],
    "response_schema": {
      "type": "object",
      "properties": {
        "genome": {"type": "string", "enum": ["hg38", "mm10"]},
        "padj_threshold": {"type": "string"}
      },
      "additionalProperties": false
    },
    "retrieved_evidence": [],
    "state_before": {"rule_params": {}, "user_overridden_keys": []},
    "capability_manifest": {"local_inference": true, "execution_requested": false}
  },
  "generation": {
    "provider": "synthetic-placeholder",
    "actual_model": "not-executed",
    "endpoint_class": "local-only",
    "temperature": 0,
    "max_tokens": 256,
    "stop_reason": null,
    "input_tokens": null,
    "output_tokens": null,
    "latency_ms": null,
    "fallback_from": null
  },
  "result": {
    "raw_output": "{\"genome\":\"mm10\",\"padj_threshold\":\"0.01\"}",
    "parsed_output": {"genome": "mm10", "padj_threshold": "0.01"},
    "tool_calls": [],
    "tool_observations": [],
    "validator_results": [{"check": "example-only", "status": "not-run"}],
    "terminal_outcome": "synthetic-label-only"
  },
  "review": {
    "gold_output": {"genome": "mm10", "padj_threshold": "0.01"},
    "status": "synthetic-example-not-reviewed",
    "evidence_spans": ["mouse mm10", "padj to 0.01"],
    "defect_tags": []
  },
  "split_lineage": {
    "source_document_group": "fixture-family-a",
    "augmentation_parent": "fixture-parent-a",
    "near_duplicate_cluster": "fixture-family-a",
    "split": "unassigned"
  }
}
```

This illustrates data shape only; it is not a captured current BioMate request. The actual T06 prompt and schema representation must be captured from the running extractor rather than replaced with the short synthetic system message above.

## How to turn traces into training data

1. **Validate capture completeness.** Reject or quarantine missing prompt/tool/evidence versions, unknown actual providers, truncated outputs, absent tool observations and incomplete episodes. Retain them for debugging, but do not silently label them successful.
2. **Sanitize within the tenant boundary.** Remove credentials, access tokens, irrelevant identifiers and free-text personal information. Replace identifiers consistently throughout an episode; preserve exact scientific structures and input/output relationships. Keep deletion/retention lineage so a removed source can be traced to derived datasets and adapters.
3. **Annotate by task.** Record raw correctness before application repair and final correctness after repair. Label whether a clarification was necessary, whether a tool should have been called and whether the observed results support the final claim.
4. **Check with tools.** Parse JSON, validate schemas, resolve IDs against the frozen catalog, run code/workflow fixtures, compare units/values, verify referenced artifacts and evidence spans. For a clinical/regulatory assertion, route to the appropriate expert review; the application’s own checker is evidence, not an infallible gold label.
5. **Deduplicate and split.** Canonicalize rendered message content and outputs; exact-hash deduplication first, similarity clustering second, then group by source study/project/template parent. Keep base documents and all synthetic variants together. Compute train/dev/test overlap reports on both prompts and full conversations.
6. **Export SFT.** Preserve role-aware conversations, real tool-call IDs/arguments and available tool definitions. Keep tool observations as context and use explicit loss masks. Do not flatten an agent trajectory into “user question → final answer.”
7. **Export DPO.** Use the identical prompt/evidence/tool context for chosen and rejected responses. Reject pairs where both answers are wrong or quality is unresolvable. Preserve error-type metadata for balanced sampling.
8. **Freeze and evaluate.** Publish local manifests with hashes, annotation guidelines, task/domain distributions, token-length distributions and contamination checks. Train only from the train export; development data selects settings; test data supports release decisions.

## Task-specific gold labels

| Task family | Required gold | Reject examples that… |
|---|---|---|
| T01–T03 understanding | intent/domain, source spans, justified clarification decision | infer absent data or treat discussion as authorization to execute. |
| T04/T24 memory/notes | source-grounded updated state/summary and supersession links | preserve contradicted facts or invent completed work. |
| T05–T11 workflows/parameters | valid IDs, canonical parameters, I/O bindings, expected validation outcome | select unavailable tools or make missing inputs look satisfied. |
| T12–T17 reasoning/evidence/vision | action sequence, verified tool results, supporting passages/panels, final claim labels | cite nonexistent sources, invent tool observations or rely on unavailable visual content. |
| T18–T19 diagnosis/repair | true root cause, minimal justified change, observed recovery result | merely hide errors, bypass checks or alter unrelated data. |
| T20–T23 findings/regulatory | exact numerical/source references, supported conclusions, defect labels | invent metrics/studies, overstate prediction as observation or hide failed execution. |
| T25 auxiliary | relevant short title or independently established binary answer | embed unreviewed model judgments as scientific ground truth. |

Suggested shared defect tags: `wrong_intent`, `wrong_workflow`, `unknown_id`, `missing_input`, `wrong_unit`, `override_lost`, `unnecessary_question`, `missing_tool_call`, `invalid_tool_args`, `fabricated_tool_result`, `unsupported_claim`, `citation_mismatch`, `numeric_mismatch`, `stale_memory`, `truncated_context`, `truncated_output`, `provider_bypass`, `unsafe_fix`, `unavailable_capability`, `cross_tenant_context`.

## Evaluation manifest contract

Each release evaluation manifest should specify:

- Frozen example IDs, group IDs and hashes; sources/rights; task/domain/language/difficulty; untouched holdout status.
- Application commit; prompt/skill/catalog/schema/index versions; exact model/adapter/tokenizer/template and quantization; serving image and configuration.
- Fixture containers, reference-data snapshots, artifact checks, numeric tolerances and allowed tool budgets.
- Which tests are component replay, real local execution, full trajectories, human-reviewed scientific tasks or adversarial boundary cases.
- Allowed egress policy; actual attempted external destinations; fallback provider identities; normal/outage cases.
- Primary metric and gate per task, non-inferiority margin, sample-size justification, paired statistical method and stopping rules.
- Latency/memory/concurrency measurements; missing/failed/skipped counts and reasons. Mark skips explicitly, never as passing tasks.
- Blinded reviewer assignments/rubric, disagreements, adjudication and generator/judge independence.

Report the pass/fail decision **per enabled capability** as well as an aggregate. Publish enough local evidence to reproduce the decision: request/response hashes, validator outputs, execution logs and final artifact hashes. Do not ship raw customer prompts in a broadly accessible report.
