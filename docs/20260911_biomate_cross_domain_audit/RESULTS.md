# BioMate-wide reasoning and workflow audit — 2026-09-11

## Scope and conclusion

The intended reasoning interface is shared across BioMate, with immune analysis as one consumer. This audit tests the currently deployed backend, not a newly implemented shared evidence service. Actual live requests went to `https://dev-public.biomate.ai/api/chat/stream` using the repository's dedicated E2E fixture account and separate conversation sessions. Raw SSE/final payloads are saved in `raw/`; prompts and prespecified checks are in `cases.json`. No collaborator or patient data were used.

Twelve live chat cases completed: ten interpretation/retrieval cases and two workflow-generation cases. The current baseline is not ready to claim reliable end-to-end reasoning across these workflows. Several basic conclusions are appropriately restrained, but routing, evidence relevance, claim support and execution-readiness consistency need work. A successful HTTP/SSE response is not a scientific pass. These are single-request manual audits, not estimates of model accuracy or reproducibility.

## Collaboration context

The local Zhejiang People's Hospital EGFR pilot and China hospital/pharma partnership brief support testing drug screening, hospital omics and translational research. The Zhao/Zhi/Liu faculty plans found locally are UTHealth/BCM plans; this report does not identify them as China-based faculty. Exact China faculty mapping remains unconfirmed. Sources: `docs/20260403_PILOT_STUDY_PROPOSAL_DRUG_DISCOVERY.md`, `docs/20260908_CHINA_PARTNER_ORIGINAL_REQUIREMENT_EN.md`, `docs/20260908_HOSPITAL_DEPARTMENT_RESEARCH_NEEDS_VS_BIOMATE.md`, and `docs/20260701_FACULTY_SURVEY_AND_COLLABORATION_STRATEGY.md`. Historical proposal claims are not treated as current execution evidence.

## Interpretation and retrieval results

| ID | Use case | Assessment | Observed behavior |
|---|---|---|---|
| DD01 | ADMET predicted margins | Pass on prespecified checks | Correct ratios 2 and 200; explicitly avoids human safety conclusion. |
| DD02 | Docking versus measured potency | Partial | Correctly rejects measured-potency inference; adds unsupported generalizations about scoring and assays. |
| DD03 | PK/PBPK unit conversion | Fail | Requests SMILES to run PBPK instead of calculating 20 ng/mL, 0.04 µM and ratio 0.4. Prompt explicitly prohibited launching a workflow. |
| OM01 | Bulk RNA differential expression | Partial | Correctly selects only GENE_A; adds unsupported 10–20-gene enrichment heuristic and malformed Markdown table. |
| OM02 | GWAS + single-cell target interpretation | Partial | Separates association/expression from causality; adds uncited numerical fine-mapping/colocalization heuristics. |
| OM03 | Rare-disease VUS + splice outlier | Partial | Does not diagnose/reclassify; elaboration introduces unsupported rarity/segregation guidance. |
| ST01 | Cryo-EM resolution versus mechanism | Partial | Does not infer drug mechanism; final answer explicitly identifies retrieved forestry/medical sources as irrelevant. |
| CN01 | Hospital cancer biomarker / batch confounding | Partial | Correctly rejects biomarker validation from complete confounding; leaves unresolved [25]/[26] citation placeholders. |
| CN02 | Tumor peptide/HLA target | Pass on core checks | Keeps prediction, transcription, presentation, recognition and efficacy distinct; no safety/efficacy conclusion. Additional methodological prose not independently validated. |
| RG01 | Retrieve two primary methods publications | Fail, with honest abstention | Does not deliver relevant primary sources; states retrieval failed and exposes internal prompt/rule wording. |

Six of the first seven interpretation prompts reached the main conservative conclusion; that does not make their entire answers correct. Additional scientific claims were not independently validated in this platform audit. The status “partial” preserves that distinction.

BioMate already has a research/retrieval path: payloads record research-agent use and some contain citations. `datasetRAGUsed=false` does not prove literature RAG is absent. The demonstrated problem is relevant evidence reaching and supporting the final answer. RG01 narrates repeated PubMed searches, but the captured transport does not independently prove each narrated call occurred.

## Workflow generation and execution

WF01 generated an ADMET Nextflow definition with all three supplied SMILES. However, chat prerequisite validation said `fulfilled=false`, reported no missing inputs/parameters, and asked for a dataset. The execution API accepted the same definition without an override. This is contradictory readiness signaling. Generated prose also described output files and model details that must be checked against actual artifacts, not assumed true.

Own execution identifiers (never selected from the fixture account's newest run):

- BioMate run: `47381c6c-7a32-4d7c-b8a6-59f10a12912a`
- Nextflow run: `a1422bd1-d864-45d3-9584-db1697f6acbe`
- Final compute status: completed, 2/2 steps, approximately 133 seconds. Six output files were listed.
- **End-to-end result: FAIL at output delivery/findings.** All six download endpoints redirected to storage returning HTTP 403 `InvalidAccessKeyId`. Sanitized error codes are in `raw/WF01_output_access_checks.json`; presigned credentials are not retained.
- Findings returned `status=ready` with an unreadable-output message and empty `key_results`. This is not a successful findings result.
- Output contents, numeric prediction values, compound identity preservation and QC could not be verified through the application. Compute completion is therefore reported separately from scientific correctness.
- Request, response, latest status, output-file inventory and findings are stored as `raw/WF01_execution_*.json` and `raw/WF01_run_*.json`.

WF02 correctly selected bulk `nf-core/differentialabundance` with DESeq2, but did not bind the supplied inline matrix or sample sheet. Required matrix data appeared as an optional parameter with no value. It is not an executed DESeq2 test; prose about expected outputs is not an output artifact. A deliberate upload/parameter-binding continuation is still required.

These tests exercise backend APIs, not browser UI rendering. No completed drug-development chain, faculty cohort replication, clinical validation, or production readiness follows from them.

## Remediation plan and acceptance gates

0. **Repair output signing/access and readiness status.** Restore the deployed output-signing credential/provider configuration; verify all six files can be read through the app. Findings must remain unavailable/failed, not ready, while outputs cannot be read. Reprocess this exact run and compare result rows to findings before rerunning compute.
1. **Separate interpretation from execution intent.** A PK question with supplied numbers and explicit “do not launch” must return checked arithmetic; only an execution request should enter PBPK prerequisites. Add paraphrase and mixed-intent regressions around the routing decision in `frontend/server/galaxy-assistant.ts`.
2. **Use one deterministic readiness contract.** Chat, workflow card and execute endpoint must agree on required files and inline parameters. Accept valid SMILES lists without requiring a file; bind matrix/sample metadata explicitly. Verify exact input values in run provenance.
3. **Implement the shared evidence interface.** Carry input result records, units, computation lineage, retrieved source identifiers and supporting passages to findings/chat. Rank source relevance and reject unrelated sources before synthesis. Reuse existing retrieval/tool connectors; this is not a separate reasoning-model training project.
4. **Validate claims and preserve abstention.** Numeric claims must match the specific source field and units; measured, predicted, association and causal claims need distinct evidence requirements. Do not accept an answer merely because one number occurs somewhere in the inputs. Remove unsupported heuristics and internal prompt text from user-visible answers.
5. **Complete representative workflows after resolving each gate.** Drug: SMILES→ADMET→outputs→findings→follow-up; hospital omics: count matrix + sample sheet→DE→QC→faithful interpretation; translational: GWAS/single-cell or tumor antigen evidence→ranked hypotheses with explicit missing evidence. Track exact run IDs and compare findings with output rows. Include failed/missing/stale inputs and source-unavailable cases.
6. **Confirm partner-specific fixtures.** Map the exact China faculty workflows when identified. Use approved/public or synthetic fixtures first; define success criteria with each collaborator rather than claim that generic tests validate their study.

## Separate immune result

The named immune adapter completed a 15,000-cell raw-file-to-saved-output run, eight adapter E2E checks and 24 regressions. This is a three-step experimental checkpoint, not a scientifically validated predictor, and has no connected BioMate backend route. See `/Users/kky/biomate-audit-fix/docs/20260911_IMMUNE_NAMED_PIPELINE_E2E.md`. The adapter checks feature names/order, counts and missing-modality masks; it cannot establish the biological validity of the model.
