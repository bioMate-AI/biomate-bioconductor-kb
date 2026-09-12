# Transfer: BioMate reasoning and collaboration workflow testing

## Destination and user correction

Destination worktree: `/Users/kky/biomate-review`, branch `integration/dev-test`. Git worktree inspection confirmed this path; there is no separate registered `biomate_review` checkout. This document and the BioMate audit are already in the destination worktree, so no checkout copying or branch switching is required.

User direction: “not this. It can be found through the biomate_review worktree. You'd better transfer the work there. Write a transfer document.”

**The previous mapping to broad hospital/pharma categories was not the collaboration scope the user meant.** Locate the actual faculty collaboration material through this worktree and its task history. Do not substitute the general China partnership brief, Zhejiang hospital pilot, or UTHealth/BCM faculty plans without verifying the intended source. Do not ask the user to reconstruct the list before investigating the existing material. The prior twelve tests remain useful generic baseline tests; they are not validation of the intended faculty workflows.

## Task to continue

The user wants BioMate-wide reasoning audited with real use cases, including drug development and the specific faculty collaboration workflows already identified. Reasoning is a shared backend system component using existing LLMs, retrieval and tools—not a separately trained reasoning LLM. Inspect both findings generation and follow-up responses. Finish representative end-to-end tests and document actual outcomes, not just generated workflow cards or HTTP success.

First locate and cite the intended collaboration source, with faculty/project names, workflow IDs, required input data and expected outputs. Then map existing coverage and add the missing cases. Discovery remains unfinished; the prior broad category mapping was rejected by the user.

## Completed work in this worktree

- `docs/20260911_REASONING_INTERFACE_CURRENT_STATE.md`: source audit and tracked task `BIOMATE-REASONING-INTERFACE`. Existing scientific retrieval is implemented, but evidence handling differs across chat/findings paths. Shared evidence service implementation remains TODO.
- `docs/20260911_biomate_cross_domain_audit/PLAN.md`: audit plan.
- `docs/20260911_biomate_cross_domain_audit/RESULTS.md`: findings and remediation order.
- `docs/20260911_biomate_cross_domain_audit/cases.json`: twelve live prompts with prespecified checks.
- `docs/20260911_biomate_cross_domain_audit/assessment.json`: manual case assessments.
- `docs/20260911_biomate_cross_domain_audit/raw/`: actual SSE/final responses, execution request/response, status, output inventory, findings and sanitized download errors.
- Reproduction scripts in that directory: `run_live.py`, `run_admet_execution.py`, `check_admet_run.py`, `fetch_admet_outputs.py`. The dispatch script refuses to duplicate the recorded run. Do not bypass that guard merely to recheck outputs.

Commits: `cb86cf803` documented the reasoning task; `99c7b2157` saved the cross-domain audit. This handoff is additional to those commits. Preserve unrelated changes in this shared checkout; do not stage or revert the whole repository.

## Verified live baseline

Endpoint: `https://dev-public.biomate.ai`. Used the repository's dedicated E2E fixture account, with credentials loaded in memory from existing test configuration. No collaborator/patient data or messages to collaborators were used. Twelve single live chat requests covered ADMET, docking, PK arithmetic, bulk DE, GWAS/single-cell, rare-disease interpretation, cryo-EM, primary literature retrieval, ADMET/bulk workflow generation, batch-confounded biomarkers and peptide/HLA target interpretation.

Key failures:

1. PK unit conversion was routed into a request for SMILES to run PBPK despite an explicit interpretation-only instruction.
2. Some correct core conclusions were followed by unsupported numerical/methodological elaborations. Primary-source retrieval failed in the explicit literature case; other answers had irrelevant sources or unresolved citation placeholders.
3. ADMET chat prerequisite validation reported missing datasets although the definition contained the three supplied SMILES and the execute API accepted it.
4. Bulk DE generation selected the appropriate workflow but left matrix/sample metadata unbound. No DESeq2 computation was launched. An explicit upload/binding continuation is still needed.
5. The real ADMET compute job completed, but all six application download links returned storage HTTP 403 `InvalidAccessKeyId`. Findings reported `ready` with empty `key_results` and an unreadable-output message. This is a failed end-to-end output/findings path, not successful scientific validation.

These are backend API tests, not browser UI coverage or population-level accuracy estimates. `datasetRAGUsed=false` does not mean all scientific retrieval is absent. No new shared evidence service was deployed by this audit.

## Exact completed ADMET run — reuse before launching more compute

- BioMate run: `47381c6c-7a32-4d7c-b8a6-59f10a12912a`
- Nextflow run: `a1422bd1-d864-45d3-9584-db1697f6acbe`
- Invocation: `279bde70-b3d4-45bd-8be7-1a8b9f36aa52`
- Completed 2/2 steps in approximately 133 seconds.
- Six listed files: `pk_summary.json`, `predict_admet_properties_output.txt`, `predict_admet_properties_results.json`, `qc_metrics.json`, `toxicity_report.json`, `versions.yml`.

Output contents, prediction values, compound identity preservation and QC remain unverified because the app could not deliver the files. The storage error identifies invalid signing credentials; the deployed credential source/root cause has not been established or repaired. Restore output access, then regenerate findings on this exact run and compare against actual output fields. Do not select the fixture account's newest run: it can belong to another test.

Output download uses a redirect to presigned storage. The fetch script strips authentication headers on redirect and records only sanitized error codes/messages, not signed credentials. The initial unmodified urllib attempt returned 400; the corrected redirect handling consistently returned the service's 403 InvalidAccessKeyId for all six files.

## Recommended continuation order

1. Recover the actual faculty collaboration source through this worktree/task history and produce an exact workflow-to-test mapping. Label anything still unidentified explicitly.
2. Repair deployed output signing/access and findings readiness. Verify six readable outputs, valid file content and faithful findings for the existing ADMET run before repeating compute.
3. Separate interpretation-only requests from execution routing. Reproduce DD03 and add paraphrase regressions; preserve supplied units and deterministic arithmetic.
4. Unify input readiness across chat, cards and execution. Support inline SMILES and explicit file-parameter binding without claiming missing data are configured.
5. Implement the shared evidence contract: exact result fields/units/artifact provenance; external source identifiers and supporting passages; source availability; observed/predicted/inferred distinctions; null/conflicting evidence; claim validation and persistent follow-up context.
6. Run the identified faculty workflows with suitable fixtures through input binding, computation, outputs, QC, findings and follow-up. Report coverage and blockers individually. A generated definition, catalog entry or completed compute status alone is insufficient.

Acceptance: every numeric result maps to its own source field and units; interpretive claims have relevant support or explicit uncertainty; missing evidence is not a negative biological result; failed output access cannot produce a misleading ready state. Preserve model/provider configuration and record deployed version when obtainable.

## Separate immune work — retain its boundaries

Immune research checkout: `/Users/kky/biomate-audit-fix`, branch `audit-fix-immune-llm`.

- `research/immune_llm_baseline/immune_named_inference.py`: named input adapter and export/predict CLI.
- `research/immune_llm_baseline/xverse_model.py`: study-independent biological encoding entry point.
- `research/immune_llm_baseline/test_named_pipeline_e2e.py`: eight real-file/subprocess adapter checks.
- `docs/20260911_IMMUNE_NAMED_PIPELINE_E2E.md`: complete execution report.
- `out/20260911_named_pipeline_e2e/`: bundle, full NPZ, provenance manifest and case results.

Verified: 15,000-cell raw H5AD→named preprocessing→experimental checkpoint→saved predictions; 8/8 adapter checks and 24 existing regressions passed. Temporary raw download and duplicate binaries were removed after verifying saved hashes. Use `/opt/homebrew/bin/python3` for that environment; an Anaconda interpreter failed during imports.

Limits: three-step smoke checkpoint, not held-out scientific validation; no H1–H4 or perturbation response validation; protein log-count regression is not calibrated; no connected BioMate route. Named schema enforcement protects feature identity/order and modality masks—it does not validate biological conclusions. Do not present this as a completed BioMate immune application integration or transfer experimental predictions into production findings without the typed contract and validation.

The extended immune-system plan is at `/Users/kky/biomate-immune-llm/docs/program_control/20260911_IMMUNE_SYSTEM_EXTENDED_BUILD_AND_REASONING_PLAN.md`. Continue BioMate-wide integration work in the review checkout and keep research training artifacts in the immune checkout.
