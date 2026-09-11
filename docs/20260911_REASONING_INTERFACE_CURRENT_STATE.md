# BioMate reasoning interface: source audit and next design

Date: 2026-09-11. Inspected checkout: integration/dev-test, HEAD 0c6aa7ce3. This is a source-code audit, not verification of deployed behavior or live source availability.

## Finding

BioMate already implements scientific retrieval. The opportunity is to share and strengthen evidence handling across chat and findings, rather than introduce a separately trained reasoning LLM.

## Current paths

- `frontend/server/galaxy-assistant.ts:3924`: intent-gated tool and dataset searches; referenced-paper content is fetched and injected. Dataset discovery is not equivalent to claim-supporting scientific retrieval. The response path also injects domain-specific cryo-EM retrieval context around line 8147.
- `backend/lib/galaxy/ai/agents/research_agent.py:1560`: literature retrieval uses decomposed queries, merges/deduplicates candidates, and attempts full-text retrieval. Retrieved literature and full-text excerpts enter synthesis around lines 2437–2471. These are implemented capabilities, not measured guarantees of retrieval or citation accuracy.
- `frontend/server/routes.ts:13441`: findings first tries existing reports/sidecars, then generates a fallback. Its fallback samples up to six readable output files, truncates content to 8,000 bytes/characters per file depending on the read path, and uses deterministic preprocessing where available. Around line 13703 it asks an existing LLM to interpret those outputs, explicitly forbids literature citations, and later removes any citations returned. No scientific evidence retrieval is present in this inspected fallback.
- `backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py:9882` and `backend/lib/galaxy/ai/finding_reporter.py:68`: a separate backend report path searches PubMed using analysis-derived queries. The reporter appends citations to an already-created analysis; its citation record stores title, year, PMID and an abstract prefix as relevance. This is weaker than evidence-conditioned interpretation with claim-to-passage support.

## Concrete gaps

1. Different entry points provide different evidence support. Reuse one backend evidence service across chat, report generation and findings fallback.
2. Output excerpts are useful previews but cannot establish complete dataset statistics. Prefer typed result parsers and computed summaries with row/column or artifact references.
3. In the frontend findings fallback, the numeric filter accepts a result when any number in its value appears anywhere in the sampled outputs. It does not verify every number, its metric, unit, or source. Invalid source filenames are removed rather than making the claim fail validation.
4. Citation existence and relevant paper retrieval do not establish claim support. Preserve the supporting passage or structured record for each interpretive claim.
5. Retrieval is conditional and may fail. Persist whether a source was searched, succeeded, returned no evidence, or was unavailable; distinguish these states in answers.

## Proposed next implementation

Keep existing LLM providers. Build a shared evidence contract and service on top of existing retrieval clients:

1. Extract observed results deterministically, with exact provenance and completeness indicators.
2. Retrieve scientific context from literature, structured source APIs and KG queries as needed for the question. Retain source release, identifiers, tissue/disease context and overlapping-study information.
3. Synthesize separate observed findings, literature-supported interpretation, and hypotheses or predicted results.
4. Validate numeric claims against their actual fields and scientific claims against evidence records. Report unresolved support and source failures explicitly.
5. Save the evidence packet with the response so follow-up chat can reuse and inspect it.

Start with one representative findings workflow and its follow-up chat questions. Compare current behavior against the shared evidence path on fixed artifacts and evidence snapshots. Measure numerical correctness, claim support, retrieval coverage, uncertainty handling, latency and cost. Do not claim improvement before this comparison. Fine-tuning remains optional only after measured failures persist.

No application behavior was changed by this audit.

## Tracked implementation task — integration/dev-test

Task ID: BIOMATE-REASONING-INTERFACE. Status: TODO (documented; implementation not started). Target branch: `integration/dev-test`. Scope: shared backend system reasoning using existing LLM providers; no separate reasoning LLM.

- [ ] Define a versioned evidence packet with artifact/record/passage provenance, source status, context, uncertainty and observed/predicted/inferred labels.
- [ ] Reuse research retrieval clients through one backend evidence service for chat and findings.
- [ ] Add typed result extraction and metric/unit/source-specific numerical validation; avoid interpreting truncated previews as complete dataset summaries.
- [ ] Retrieve scientific context before findings interpretation; preserve direct versus adjacent evidence and conflicting/null results.
- [ ] Validate claim support and persist evidence alongside findings for follow-up chat.
- [ ] Pilot one representative workflow and follow-up questions against the current path with frozen fixtures and evidence snapshots.
- [ ] Record correctness, claim support, coverage, abstention, latency and cost; document deployment readiness separately from source implementation.

Acceptance: observed findings trace to exact result fields; external claims trace to supporting records/passages; retrieval failures are not biological negatives; unsupported numerical/interpretive claims are rejected or explicitly qualified; follow-up chat reuses the same evidence packet. Include missing-output, source-failure, conflicting-evidence and multiple-number regression cases. Demonstrate the comparison before claiming improvement.

Out of scope: custom reasoning-model training, a new asthma study, changes to the Mohan pilot, or launching immune-model training. Future validated immune-model predictions enter as structured tools with uncertainty and applicability limits.

Related immune-system plan: `/Users/kky/biomate-immune-llm/docs/program_control/20260911_IMMUNE_SYSTEM_EXTENDED_BUILD_AND_REASONING_PLAN.md` (revised to system reasoning).
