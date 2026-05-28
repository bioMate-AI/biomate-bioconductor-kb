# After-Run Panel Audit — Findings (#27)

**Date:** 2026-05-28
**Scope:** 41 representative workflows × 7 candidate tabs (Findings · Outputs · Methods · Parameters · Software · Citations · QC audit)

## Backend reality check

| Tab | Source | Coverage signal |
|---|---|---|
| **Findings** | `/api/workflows/runs/:id/findings` (`routes.ts:10370`) | No workflow emits a real `findings_report.md` / `findings_data.json` sidecar today. Every workflow falls back to Claude Sonnet inline analysis off the S3 file listing. → **AI-fallback only**, no "real" data path exists |
| **Methods** | `/api/invocations/:id/methods-report` (`nextflow_executor.py:4570`) | Galaxy proxy returns 404 for Nextflow-native runs. Local fallback writes 5 lines + QC `methods_text`. `methods_text` + `tool_versions` populated **only when `monitor.qc_handler` exists** (auto-loop families: ADMET / CYP-DDI / Docking / NCA-PK / PBPK / Structure-prediction / Cryo-EM). All other workflows get a stub |
| **Parameters** | viewer echo of submitted params | yes for every workflow (already wired) |
| **Software** | not surfaced | `*/versions.yml` is emitted by **2,129 of 2,178** module main.nf files (~98%). Backend only collects them in the reproducibility-bundle endpoint (`nextflow_executor.py:6594`); nothing reads `versions.yml` at run end and exposes via UI route. `tool_versions` dict in `methods-report` is sparsely populated by QC handler events (auto-loop only) |
| **Citations** | cryo-EM RAG + `qc_evidence.yaml` `paper_doi` fields | Cryo-EM: 11 publication-grounded topics. `qc_evidence.yaml` carries `paper_doi` for every gate across 21 domain sections. All other domains (rnaseq / sarek / chipseq / atacseq / proteomics / methylseq / raredisease / scrnaseq / wgs / etc.) have **no citations anywhere** |
| **QC audit** | `qc_trace_monitor` SSE history + `qc_overrides_audit.jsonl` | Real per-event audit only for the 21 domains in `qc_evidence.yaml`. nf-core genomics / transcriptomics / proteomics have no QC gate definitions → audit tab would be empty |

## Per-tab coverage summary (41 sampled workflows)

| Tab | Real data | Partial / fallback | None |
|---|---|---|---|
| Findings | 0% | 100% (AI-fallback) | 0% |
| Methods | 0% (Galaxy proxy never works for Nextflow-native) | 56% have QC `methods_text` paragraph; 44% get the 5-line stub | 0% |
| Parameters | 100% | — | — |
| Software | 0% surfaced today (98% of modules emit `versions.yml` — extractable) | 56% have sparse `tool_versions` via QC handler events | 44% |
| Citations | 12% (cryo-EM 5 workflows with 11-topic RAG) | 56% have per-gate DOIs in `qc_evidence.yaml` | 44% (all genomics/transcriptomics/proteomics) |
| QC audit | 56% (auto-loop + qc_evidence domains) | — | 44% (genomics, transcriptomics, proteomics, survival, etc.) |

## v0 ship recommendation — 7-tab spec

**Must-ship (universal coverage):**
1. **Outputs** — already wired everywhere (per A2 audit, when complete)
2. **Parameters** — already wired everywhere
3. **Findings** — AI-fallback good enough for v0; every workflow returns something useful

**Ship for ~half the catalog (gracefully hide for the rest):**
4. **QC audit** — show tab only when `qc_evidence.yaml` has a section matching the workflow's domain. Hide tab entirely otherwise (do NOT show empty placeholder)
5. **Methods** — same conditional: when `tool_versions`/`methods_text` is non-empty, render. Otherwise hide. Don't ship the 5-line "Methods: No QC events recorded" stub; it looks broken
6. **Citations** — render when (a) cryo-EM RAG returns topics, OR (b) `qc_evidence.yaml` gate DOIs exist for the domain. Hide otherwise

**Coming-soon (do NOT ship in v0):**
7. **Software** — data is physically present (`versions.yml` in every work dir on AWS Batch + local /tmp) but nothing aggregates it. Ship as "Coming soon" until backend wires `/api/invocations/:id/software` that walks the run dir's `**/versions.yml` and merges into a flat dict

## Backend changes required

**Frontend-only work** (ship the tab without backend changes):
- Outputs, Parameters, Findings (wire to existing endpoints)
- Methods, QC audit, Citations — render-with-graceful-hide pattern (just check response shape and hide the tab if empty)

**Backend changes required:**
1. **Software tab (new endpoint)** — `GET /api/invocations/:id/software` walks the run work dir for `**/versions.yml`, parses YAML, returns `{tool_name: version}` flat dict. ~30 LOC in `nextflow_executor.py`. Could reuse the glob logic at line 6594
2. **Methods tab upgrade** — current `methods-report` is plain text. Need structured `GET /api/invocations/:id/methods-structured` returning `{methods_text, tool_versions, citations[], parameters_summary}`. ~50 LOC
3. **Citations tab (cross-domain)** — `GET /api/workflows/:name/citations` that:
   - For cryo-EM domain: queries `cryo_em_knowledge.retriever` for topics keyed by workflow
   - For any domain in `qc_evidence.yaml`: returns the `paper_doi` list from gates in that section
   - Otherwise: returns `[]` (frontend hides tab)
4. **Findings sidecar emission** — Optional but high-value: have Nextflow workflows write a `findings_data.json` sidecar so the AI-fallback path isn't always invoked. Per-workflow effort, not central. v0 can skip

## Software tab callout

`versions.yml` files DO exist in 98% of module work dirs:
- AWS Batch runs: in S3 work bucket under `{work_dir}/**/versions.yml`
- Local runs: in `/tmp/nextflow_runs/{run_id}/**/versions.yml`

Nextflow's nf-core convention also emits a consolidated `pipeline_info/software_versions.yml` for the 17 nf-core workflows. That single file is the cleanest source for genomics / transcriptomics / proteomics workflows.

**Recommendation**: ship Software tab in v1 (not v0) with a 2-tier reader: prefer `pipeline_info/software_versions.yml` if present (nf-core), else glob `**/versions.yml` and merge. ~30-LOC backend route, 98% coverage.

## Citations callout

44% of the catalog has zero citations infrastructure. Options:

- **Option A (recommended for v0)**: Hide the Citations tab entirely for these workflows. Do not show a placeholder — placeholders read as "this product is unfinished"
- **Option B (v1)**: Ship a generic "References" tab populated from the workflow's nf-core `meta.yml` (every nf-core module has a `tools.<name>.doi` field). Uniform citations across all 17 nf-core pipelines, ~1 day backend work
- **Option C (deferred)**: build a non-cryo `knowledge_base` patterned on `cryo_em_knowledge/`. Multi-week. Park

## Key files referenced

- `backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py` (methods-report @ 4570; versions.yml glob @ 6594; QC handler integration @ 1657, 3322)
- `frontend/server/routes.ts` (findings @ 10370; methods-report proxy @ 4227)
- `backend/config/qc_evidence.yaml` (21 domain sections with `paper_doi` per gate)
- `backend/lib/galaxy/ai/cryo_em_knowledge/populate.py` (11 publication topics)
- `backend/lib/galaxy/ai/retrievers/qc_gate_reader.py` (loads qc_evidence for runtime citation lookup)
- `backend/experiments/{admet,cyp_ddi,docking,nca_pk,pbpk,structure_prediction,cryo_em_autoloop_ux}_autoloop/knowledge_base.py` (per-domain auto-loop knowledge — currently used for remediation rules, not surfaced to citations tab)
