# SYSUCC work handoff

Date: 2026-10-30
Repository: `/Users/kky/biomate-review` (git top-level). The nested `/Users/kky/biomate-review/biomate/` folder is a separate, older clone; it was not used.
Branch: `cursor/tutorial-live-recording-and-report-editing-4ea7`. The branch is ahead of `origin` and has not been pushed.

## 1. What this work is for

BioMate is preparing a **first meeting** with the Director of the Information Center at Sun Yat-sen University Cancer Center (SYSUCC, 中山大学肿瘤防治中心), Guangzhou. The meeting is arranged through our Chinese agency.

- **Goal:** briefly introduce BioMate and learn what the hospital expects. **No demo is planned.**
- **BD document:** BD receives only the **Chinese** document.
- **After the meeting:** BD fills in the feedback table (section 11.4 of the BD document). Which areas we develop next depends on that feedback.
- **Deployment assumption:** on-premises. The hospital's compliance and network rules are things we ask about in the meeting, not things we promise.
- **IND module:** commented out in the product. **Do not work on IND** (including species handling in IND assembly) unless asked.

## 2. Deliverables and where they are

### For BD (final)

| File | Notes |
| --- | --- |
| `docs/20261030_SYSUCC_BD_CAPABILITY_AND_USE_CASES_ZH.docx` | **The document BD gets.** Self-contained, with no references to other documents. Generated from the `.md` next to it. |
| `docs/20261030_SYSUCC_BD_CAPABILITY_AND_USE_CASES_ZH.md` | Source of the Chinese document. |
| `docs/20261030_SYSUCC_BD_CAPABILITY_AND_USE_CASES_EN.md` / `.docx` | Internal English mirror, kept in sync. It contains links to the research files; do not give it to BD. |

Regenerate the Word files after any edit:

```sh
cd docs
pandoc 20261030_SYSUCC_BD_CAPABILITY_AND_USE_CASES_ZH.md -f gfm -t docx --toc --toc-depth=2 -M toc-title="目录" -o 20261030_SYSUCC_BD_CAPABILITY_AND_USE_CASES_ZH.docx
pandoc 20261030_SYSUCC_BD_CAPABILITY_AND_USE_CASES_EN.md -f gfm -t docx --toc --toc-depth=2 -o 20261030_SYSUCC_BD_CAPABILITY_AND_USE_CASES_EN.docx
```

Rule for the Chinese document: keep it self-contained. Before regenerating, run `grep -c '\.md' …ZH.md`; it must print 0.

**Structure of the BD document:**
1. Background for non-specialists.
2. The hospital: profile, drug-development role, its own origination (EBV, cell therapy), strategy, the Director (Li Chaofeng), existing IT/AI (Yidu Tech's AI middle platform with DeepSeek-R1), and a maturity/gap map of their platforms and providers.
3. BioMate in brief.
4. Core abilities.
5. The four function modules from the home page.
6. Research support across instruments.
7. Drug-development support.
8. How hospital data fit in.
9. A 10-minute introduction, with no demo.
10. Why BioMate rather than DeepSeek or GPT alone.
11. Conversation guide: questions, including network and database access; Q&A; next steps; the feedback table.
12. Wording guide.
13. Cheat sheet.

### Background research (internal, English, with sources and dates)

- `docs/research/20261030_SYSUCC_DRUG_DEVELOPMENT_COLLABORATIONS_AND_AMBITIONS.md`: China's leading oncology trial site. First-in-class is an ambition but early (EBV, TCR-T). Strategy: "IIT-IND dual track".
- `docs/research/20261030_SYSUCC_IT_AI_PLATFORM_AND_VENDORS_RESEARCH.md`:
  - the Director's profile;
  - Yidu Tech runs the clinical AI stack;
  - a hardware-only bioinformatics HPC was awarded in September 2026, with no workflow layer.
- `docs/research/20261030_SYSUCC_CORE_FACILITIES_RESEARCH.md`: maturity by instrument area. The main gap is analysis capacity; groups still outsource "sequencing + analysis".
- `docs/research/20261030_SYSUCC_DRUG_RESEARCH_ECOSYSTEM_RESEARCH.md`: no AI drug-design, computational chemistry or ADMET capability or partner found.

**Positioning conclusion:**
- **Don't compete** with the clinical AI or data platforms, pathology AI, imaging, or sequencing itself.
- **Lead with:**
  - analysis and workflows on their new research compute;
  - IIT statistics and biomarker analysis;
  - organoid and drug-response analysis;
  - drug-design and ADMET support for a small set of groups.

### Earlier planning documents (2026-10-29, internal)

- `docs/20261029_SYSUCC_DRUG_DEVELOPMENT_DEMO_PLAN.md`: a 30-minute demo plan. Superseded for the first meeting (no demo); still useful for a later faculty session.
- `docs/20261029_SYSUCC_DATA_TO_DRUG_DEVELOPMENT_SHOWCASES.md`: 36 showcase ideas by stage.
- `docs/20261029_SYSUCC_PLATFORM_ALIGNMENT_AND_MODEL_COMPARISON.md`: platform alignment and the Claude/GPT comparison protocol.
- `docs/20261029_SYSUCC_USECASE_TEST_RESULTS.md`: the original test round (19 passed, 13 failed), which drove the fixes below.

## 3. Code fixes: committed and deployed to dev

Commit `400aeffb7`, deployed to https://dev-public.biomate.ai on 2026-10-30. The dev frontend reports build `400aeffb7`. Details: `docs/20261030_SYSUCC_FIXES_SESSION.md`.

- **Sandbox output files** (`frontend/server/code-runner.ts`): only the per-run `output/` directory is handed to the non-root sandbox user. User code still never runs as root, and symlinks are not followed.
- **Assay data fidelity** (`drug_discovery/assay_schema.py`, `assay_ingestion.py`):
  - physical-range rules per endpoint (a negative IC50 is rejected);
  - canonical-structure identity conflicts are detected;
  - coverage-aware ranking: incomplete compounds are flagged and ranked last.
- **Report ingestion** (`evidence_provenance.py` new, `wetlab_report_ingester.py`, `study_report_ingester.py`):
  - species and GLP status are unknown unless the source states them;
  - predictions go to `predicted_values`, never to measured fields;
  - Cmax and AUC are extracted;
  - numeric-regex fix.
- **Learning loop** (`auto_retrain.py`, `bayesian_optimizer.py`, `ml_training/*`):
  - a shared `combined_score` contract;
  - incomplete compounds are excluded from training labels;
  - round numbers increase monotonically;
  - quality gates fail closed on missing or non-finite metrics;
  - a real Bemis–Murcko scaffold split (`ml_training/splits.py`);
  - stub trainers now fail explicitly.
- **Model versioning** (`custom_model_registry.py` rewritten, `api_router.py`, `models_inference.py`):
  - immutable versions with artifact and data hashes;
  - promotion requires a passed gate and a named reviewer;
  - rollback;
  - reload after restart with a hash check;
  - holdout comparison;
  - fixed the registry being created per request and the broken register route.

  Endpoints: `/api/drug-discovery/{campaign_id}/models/{name}/versions|promote|reject|rollback|compare`.

Tests: new suites under `drug_discovery/tests/` and `ml_training/tests/`. The local use-case runner passes 29 of 29. Full frontend `tsc` and `vitest` were clean.

**Live check on dev after the sync:** `scripts/test_sysucc_usecases.py --live` gives **31 passed, 1 failed**, up from 19 passed and 13 failed. Artifact saving now works. The remaining failure is expected: PKNCA is not installed in the generic R code-runner; the indexed PKNCA workflow runs in its own container.

Later commits are documentation and analysis only:
- `38dd6f468`: dev verification note; Chinese document made self-contained.
- `6146c12a6`: open-LLM comparison harness and results.
- `03f45f659` and `b100e38db`: BD research sections.
- `71df3bb43`: this handoff.
- `d73489b58` and `5c895a82c`: Benchling integration assessment, including the MCP path.

## 4. Open-LLM comparison (internal only; not for the hospital)

- Results: `docs/20261030_SYSUCC_OPEN_LLM_COMPARISON.md`; raw data: `docs/qa/20261030-open-llm-comparison.json`.
- Harness: `scripts/compare_open_llm_sysucc.py`. `--rescore` re-scores saved responses with no model calls; `--resume` re-issues only failed calls. The run cost about $3.39 on OpenRouter.
- Models: DeepSeek V4-pro, Qwen3.8-Max, GLM-5.2 and Kimi K3, without tools.
- **Results:** ties on candidate selection, report extraction and labelling predicted values. BioMate wins on planted data errors. PK/NCA was not measured for BioMate.
- **Key observation:** DeepSeek with reasoning off gave three different wrong half-lives at temperature 0.
- **Caveat:** the tasks are tiny, so this is illustrative, not a benchmark.

## 5. Open items, in priority order

1. **Authenticated dev verification.** Blocked: `E2E_FIXTURE_PASSWORD` is unset (fixture account `lifeifei163361@163.com`). With it:
   1. Run the model-versioning journey on dev: train v1 and v2 → restart the Galaxy container → confirm the exact active artifact reloads with a hash check → compare, promote, roll back.
   2. Run campaign retraining through the public API.
   3. Run the indexed **PKNCA** workflow against the comparison's NCA references, then rescore T2 in the comparison. This is the strongest unmeasured case.
2. **Identical predicted scores** in campaign proposals: both candidates get the same score (0.636, then 0.353). Diagnosis was started, but the task was stopped before any code change.
   - **Hypotheses to test:**
     - GP length-scale collapsing to the lower bound: the runner shows sklearn's `ConvergenceWarning ... length_scale close to the lower bound 1e-05`;
     - a featurization mismatch between fit and predict;
     - too few training points;
     - near-duplicate candidates.
   - `test_bo.py` fits on 256-dim random features but proposes on 2048-bit fingerprints; fix that too.
   - Partial diagnostics: `/tmp/bo_diag/` (temporary).
   - **Expected outcome:** either discriminating scores (e.g. a Tanimoto kernel, consistent features) or an explicit "cannot discriminate" flag with uncertainty. Never fake differences.
3. **Assay data contract gaps.** No code change yet; design notes from the stopped task:
   - **Benchling:** see `docs/20261030_BENCHLING_INTEGRATION_ASSESSMENT.md` for the connection options and a full defect list. In short, the polling connector uses the wrong auth scheme and API host, lacks the required `schemaId`, and treats compound links as SMILES. Also, `benchling_connector.py` emits `assay_name/assay_value/created_at`, but the validator expects `assay_type/value/assay_date`.
     - Plan: split the validator into row-level `validate_rows`, and give `AssayIngestionService` a shared `ingest_rows` used by both CSV and LIMS.
     - Map at the connector boundary. Benchling entity-link fields reference registry IDs, not SMILES, so the mapping must be configurable.
     - Make any missing-API-key mock fallback explicit.
   - **Censored values** (`<`, `>`): the operator is stored, but values are treated as exact. Expose `censored`, rank conservatively, and exclude censored values from regression labels in `auto_retrain.build_training_rows` (report the reason as `censored_value`).
   - **Salt forms:** a salt and its free base are treated as different compounds.
     - Use RDKit `rdMolStandardize` or SaltRemover parent normalization for identity checks, storing both the submitted structure and the parent.
     - Note: RDKit's salt list takes priority over fragment size. For example, the oxalate in ethylamine oxalate is stripped even though it is larger. Test co-drug and mixture cases.
4. **No UI for model versions:** promote, rollback and compare exist only as API endpoints. Any UI work must follow the UX standards in `CLAUDE.md`.
5. **Workflow readiness for likely SYSUCC needs:** verify by real execution before any later demo:
   - organoid dose–response, `hts_plate_qc_hit_calling`, `synergyfinder`;
   - the tumor-reactive T-cell chain;
   - `screpertoire`;
   - BOIN/PK.

   `powertcr` and `midashla` show `exec_error` in the catalogue.
6. **Better comparison tasks:** realistic, larger, multi-file inputs and real omics analysis, where a bare model cannot compute the answer.
7. **Other gaps** (see the session doc):
   - the Ludwig scaffold split is untested against real Ludwig;
   - the ADMET follow-up after a retrain is not automated;
   - `GET /retrain` still triggers a retrain (kept for backward compatibility).

## 5b. Benchling integration (added late on 2026-10-30)

Full write-up: `docs/20261030_BENCHLING_INTEGRATION_ASSESSMENT.md`. Benchling does not apply to SYSUCC: it is hosted in the US/EU, with no documented China region, and needs a public endpoint. It matters for US/EU biotech and CRO customers.

**Fastest path: MCP AI Connector, with no new code.**
- Benchling AI (Chat and Deep Research) accepts external MCP servers as "AI Connectors". The admin path is Tenant Admin Console → Settings → AI Connectors → Add AI Connector:
  - Server: `https://<biomate-host>/mcp`;
  - Type: HTTP;
  - OAuth: dynamic discovery / dynamic client registration.
- Each user then connects under AI → Settings → AI Connectors and signs in to BioMate.
- BioMate's existing remote MCP server (repo `/Users/kky/biomate-connector`, `remote_mcp/`, deployed behind `https://dev-public.biomate.ai/mcp`) already provides:
  - a Streamable HTTP endpoint;
  - a 401 response with an RFC 9728 `resource_metadata` challenge;
  - RFC 8414 authorization-server metadata;
  - dynamic client registration at `/oauth/register`;
  - PKCE S256 and refresh tokens;
  - 24 tools.

  The metadata endpoints were verified live on dev on 2026-10-30.
- **Not yet tested; needs a Benchling tenant:**
  - **Client authentication:** our metadata advertises `token_endpoint_auth_methods_supported: ["none"]`. If Benchling registers as a confidential client (`client_secret_basic` or `client_secret_post`), add support for that.
  - **Callback:** confirm the redirect URI `https://<tenant>.benchling.com/1/api/llm/mcp/oauth/callback` is accepted.
  - **Resource parameter:** confirm we handle RFC 8707 `resource`.
  - **Default tool set:** decide which tools are on by default; keep `run_instrument_protocol` off.
  - **Data processing:** the customer's prompts and tool inputs reach BioMate's cloud, so a data-processing agreement is needed.
- **Benchling MCP Directory listing** (one-click install for all customers): through Benchling partnerships, integrations@benchling.com or https://www.benchling.com/partnerships. A draft outreach email is in the appendix of the Benchling assessment.

**Reverse direction:** Benchling's own MCP server, `https://<tenant>.mcp.benchling.com/mcp`.
- OAuth 2.1 delegated auth with dynamic client registration; no API keys.
- The tenant needs Benchling Chat, Benchling MCP and V3 APIs enabled.
- Good for conversational access. It does **not** replace a structured REST or warehouse sync for training labels.

**Structured sync (REST): the existing connector is broken.** `backend/lib/galaxy/ai/drug_discovery/benchling_connector.py`:
- sends API keys as Bearer, but Benchling needs Basic, or OAuth for an app;
- uses the wrong host `api.benchling.com`; it must be the tenant URL;
- treats `schemaId` as optional, but it is required;
- reads `molecule_link` IDs as SMILES;
- takes the "first numeric field" as the assay value;
- outputs keys that don't match the validator;
- falls back to mock mode silently;
- accepts the API key in a query string;
- ignores review and archive status.

`backend/lib/integrations/benchling_connector.py` uses Basic auth correctly and is the better base. A 9-step rebuild plan is in the assessment, section 4. Do this only when a Benchling customer is in the pipeline, and test against a real tenant.

## 6. Working-tree cautions

- **Uncommitted work from other sessions, not part of this handoff and never deployed.** This is a private-skills access-control change:
  - frontend: `frontend/server/{routes,auth-middleware,galaxy-assistant,scientific-chat-tools}.ts`, `scientific-chat-tools.test.ts`, `skill-access*.ts`, `optional-auth-mfa-boundary.test.ts`;
  - backend: `backend/lib/galaxy/ai/{skill_manager.py,agents/skill_loader.py}`, `backend/lib/galaxy/webapps/galaxy/api/ai_assistant.py`;
  - plus three untracked `backend/lib/galaxy/ai/target_id/bench_targetid_llm*.py` scripts.

  A backup copy is in `~/sysucc_sync_aside/`. The working-tree copies are restored and identical to it. About 580 other uncommitted paths also exist in the tree. **Do not commit them blindly.**
- **How `scripts/sync_to_dev.sh` picks up code:**
  - The **frontend archive comes from the working tree**, so uncommitted frontend edits would be deployed.
  - The backend uses `git show HEAD:` plus **untracked** `.py` files.
  - The script refuses to run if backend source files are uncommitted.

  To deploy only committed fixes, the 2026-10-30 sync temporarily set aside the unrelated files and restored them after the frontend archive was built. Repeat that procedure, or resolve the other session's changes first.
- **Python:** use `/opt/homebrew/bin/python3` (3.14, with RDKit and sklearn) for tests. Anaconda `python3.9` has a broken scipy, so package imports fail there. Check Python 3.9 compatibility with an AST scan of changed files (no PEP 604 `X | None` runtime annotations without `from __future__ import annotations`, no `match` statements). FastAPI tests used a throwaway venv in `/tmp/biomate_api_venv`.
- **Disk:** the Mac disk was nearly full earlier (about 200 MB at one point; 6.3 GB free at handoff). Low space caused failed writes.
- **Pre-sync checklist** (`docs/PRE_SYNC_CHECKLIST.md`): `cd frontend && npx tsc --noEmit -p . && npx vitest run`, Python import or AST checks, then `scripts/test_sysucc_usecases.py`. After a sync, run `scripts/test_sysucc_usecases.py --live --output /tmp/...`. Don't overwrite the tracked `docs/qa/20261029-*.json`.

## 7. Key commands

```sh
# Local use-case contract tests (expect all pass)
/opt/homebrew/bin/python3 scripts/test_sysucc_usecases.py --output /tmp/sysucc_local.json
# Live dev checks (code-runner); expect 31 pass / 1 known PKNCA failure
/opt/homebrew/bin/python3 scripts/test_sysucc_usecases.py --live --output /tmp/sysucc_live.json
# New backend suites
cd backend/lib/galaxy/ai && /opt/homebrew/bin/python3 -m pytest drug_discovery/tests/test_assay_report_fidelity.py drug_discovery/tests/test_campaign_learning_loop.py drug_discovery/tests/test_model_versioning.py ml_training/tests/test_gate_and_split_contracts.py -q
# Re-score the open-LLM comparison without model calls
/opt/homebrew/bin/python3 scripts/compare_open_llm_sysucc.py --rescore
```
