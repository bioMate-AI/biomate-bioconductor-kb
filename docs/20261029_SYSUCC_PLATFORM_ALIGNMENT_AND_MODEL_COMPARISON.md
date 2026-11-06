# SYSUCC: platform alignment and Claude/GPT demonstration

Date: 2026-10-29
Scope: read-only repository and catalogue review; demonstration recommendations, not a new live validation result.

Execution follow-up: [use case test results](20261029_SYSUCC_USECASE_TEST_RESULTS.md) now record real local-service checks and live dev sandbox tests. The proposed cases have not passed end-to-end acceptance; consult that result before selecting demo claims.

## Decision

Position BioMate as a scientific execution and learning workbench across drug development, not merely a target-ranking and molecule-generation interface. The hospital can contribute contextual evidence, measured experimental labels, local scientific practice and independent validation throughout this chain.

The previous hospital mapping understated existing pharmacology, experimental-learning and evidence-generation capabilities. The right preparation is to qualify selected existing paths and their connections, not propose rebuilding these domains from scratch. Conversely, source code and catalogue coverage must not be advertised as successful current end-to-end execution.

## What is already present

The local read-only catalogue contains 12,312 tool records, 4,141 tool-knowledge records, 4,223 workflow records and 69 chain records. These are content records, with aliases and overlaps: not counts of distinct installed methods or independently validated executions.

| Drug-development layer | Existing implementation evidence | Hospital contribution and demo adjustment |
| --- | --- | --- |
| Scientific method and parameter selection | `local_knowledge_query.py`, `tool_knowledge_provider.py`, workflow generation and `qc_evidence.yaml` supply typed inputs/outputs, citations, parameter guidance, limitations and QC rationale. | Add local SOPs and expert corrections. Demonstrate why a method fits the task, not simply the number of available tools. |
| Disease and target evidence | Target-ID table channels and public associations; bulk/single-cell/spatial/CRISPR workflow sources; clinical-arm immune signatures; specialized T-cell/HLA chains. | Link cohort or assay evidence to a target, preserve conflicting evidence and select the therapeutic modality. A chain definition is not composed execution proof. |
| Hit and lead evaluation | Docking/ADMET sources; HTS QC, dose-response and synergy workflows; custom Python/Docker/REST scorers. | Use real compound identities, assay endpoints and experimental controls. Evaluate appropriate candidates against the same structure/pocket and method. |
| Experimental learning | Campaign assay intake, Gaussian-process multiobjective proposals, diversity/uncertainty, refit/reproposal and CRO-order export. See `drug_discovery/api_router.py`, `bayesian_optimizer.py`, `auto_retrain.py`. | Import measured results and show what changes in the next batch. Native campaigns use SMILES; peptide research-loop integration is not automatically equivalent. |
| Translational pharmacology | PKNCA NCA, nlmixr2 population PK, exposure-response, PBPK, CYP/DDI, IVIVE, xenograft TGI, target engagement and selectivity workflow sources. | Add an exposure/response bridge to the selected candidate case. Qualify the selected method, schema and output rather than claiming this layer is absent. |
| Safety and formulation | hERG/CiPA, Ames/repeated-dose, stability, polymorph, LNP/nanoparticle and antibody PK/developability workflow sources. | Optional expansion when the hospital or a partner has relevant measured data; do not force every modality through every workflow. |
| Translational evidence and documents | Study-report ingestion, PK summary persistence, guideline retrieval, phase gating and IND-section assembly. | Produce a source-linked research package and explicit evidence gaps. Extracted fields and regulatory narratives require qualified review. |
| Institutional research assets | Project knowledge, organization rules/examples, model wrappers and research training/checkpoint paths. | Demonstrate reusable local practice and compatible model updates. Retrieval customization, predictor refitting and generator weight training are different mechanisms. |

Workflow source examples under `backend/biomni_workflows/nextflow_nfcore/subworkflows/` include `drug_discovery/nca_pknca`, `pharmacology/nlmixr2_population_pk`, `pharmacology/exposure_response_modelling`, `pharmacology/analyze_xenograft_tumor_growth_inhibition` and `biostatistics/gate3_interaction_test`.

Readiness must be recorded separately for catalogue presence, real implementation, recorded execution, and the exact current demonstration case. Historical Batch runs support particular capabilities; they do not validate every hospital dataset or composed chain. The October 14 pathology record supports a narrower real WSI/IHC capability, not an entire diagnostic pathology platform.

## Revised hospital narrative: four connected lanes

1. **Tumor evidence → target and modality.** Cohort, omics, spatial and functional evidence establish the research context. Show target rationale, uncertainty and small-molecule versus peptide suitability.
2. **Candidate → optimization decision.** Execute appropriate chemistry, docking, ADMET and selectivity evaluations with controls. Show an interpretable tradeoff, not a universal best score.
3. **Measured experiment → next design.** Import real dose-response or other compatible assay labels, update a predictor/proposal, and retain an untouched evaluation set. Show actual peptide weight adaptation separately if its artifact and controls pass rehearsal.
4. **Exposure and response → reviewed evidence.** Connect an authorized PK or xenograft dataset to an existing pharmacology workflow and a concise evidence/gap report. Use a completed authentic replay if time does not permit live execution.

For a 30-minute meeting, keep one main case and use the fourth lane as a short evidence-backed extension, not four unrelated demonstrations. The information-center audience should see data identity, permissions, institutional assets and reproducibility through all four lanes. Use existing workspace/workflow/campaign/model surfaces; a new bespoke demo interface is unnecessary.

## What to demonstrate against Claude and GPT

The strongest claim to test is: **BioMate turns general-model reasoning into a connected, inspectable drug-research process with less manual scientific plumbing.** It is not that general assistants cannot analyze files, code or conduct research. OpenAI explicitly documents [sandboxed code execution and file processing](https://developers.openai.com/api/docs/guides/tools-code-interpreter) and [deep research with connected sources](https://developers.openai.com/api/docs/guides/deep-research). Declare the actual Claude and GPT configurations and enabled tools on the test date.

| Case | Identical task and inputs | Evidence to score |
| --- | --- | --- |
| 1. Method selection and numerical fidelity | A concentration-time/dose file and an SOP: choose an appropriate PK analysis, identify schema problems, compute the requested endpoints and explain assumptions. | Correct method, units, numerical agreement with independently checked reference calculations, appropriate limitations and saved artifacts. Standalone assistants may succeed; measure it. |
| 2. Two-file research operation | A target-evidence table plus candidate result files: compare candidates under explicit criteria and identify the next experiment. | Correct file/compound/target identity, faithful numerical extraction, missing-result handling, citations and executable next steps. No invented evaluated candidates. |
| 3. Scientific failure and recovery | Supply a wrong concentration unit, missing receptor or contradictory assay metadata; then supply the correction. | Detect the scientific issue, explain its consequence, request the right correction and resume the correct step. Never loosen a biological threshold just to produce a pass. |
| 4. Experimental learning | Baseline assay batch, a genuinely new measured batch and a fixed holdout: refit, compare and propose the next candidates. | A real changed artifact/proposal, no holdout leakage, correct evaluation, uncertainty and justified acceptance or rejection. Improvement is not guaranteed. |
| 5. Translational evidence package | PK/toxicity outputs and a study report: summarize measured findings, uncertainties and next evidence needs. | Exact values/units/species, source traceability, consistency across calculations and text, and clear distinction between measured and predicted results. |
| 6. Resume and hand off | Return to the same research project and ask a second authorized reviewer to inspect/reproduce a selected result. | Recover exact inputs, parameters, model/run outputs and reviewer context; quantify manual reconstruction. Test actual persistence/access controls before showing this case. |

For the hospital, prioritize cases 2, 4 and 5, with a short deliberate error from case 3. These show useful research work rather than a writing contest. Use cases 1 and 6 as technical supporting evidence.

### Two comparisons, two different interpretations

**Product comparison:** BioMate versus standalone Claude and ChatGPT, each with the normal declared tools enabled. Same task, files and agreed resource budget. This measures the researcher's experience of each product, including the scientific stack available in BioMate. It does not isolate model intelligence.

**Platform ablation:** the same supported foundation model and settings with generic tools versus BioMate's scientific knowledge/workflow layer. This more directly estimates the contribution of BioMate's grounding and execution. Verify provider tool support before choosing a model: the plain OpenRouter chat route must not be assumed equivalent to the tool-enabled provider routes.

If a general agent receives BioMate's scientific APIs/MCP tools, report that as a third configuration. Success in that configuration demonstrates the usefulness of BioMate's infrastructure through another interface; it is not evidence that the infrastructure has no value.

### Fair evaluation and allowed claims

- Freeze prompts, file hashes, reference answers, endpoint definitions, model versions/settings, tools and budgets before running. Keep preparation time and manual intervention visible.
- Use independent scientific review and programmatic checks of actual artifacts. A polished answer, tool-call success or structurally valid JSON alone is not completion.
- Score scientific correctness, task completion, numerical/data-identity fidelity, unsupported claims, reproducibility, manual interventions and observed duration/cost. Do not collapse correctness and speed into an opaque overall score.
- Include held-out cases and repeated trials; publish denominators, failures and ties. A small live demonstration is illustrative, not a statistically established benchmark.
- Keep public-assistant baselines on authorized nonconfidential data. Do not send hospital files to additional providers without explicit permission.
- Existing microtask benchmarks and promotional aggregate numbers are not proof of superiority on these hospital workflows. See `20261024_DRUGDEV_LEADERBOARD_HONEST_SCOPE.md`.

No paid model comparisons, new compute jobs, hospital-data uploads or deployments were performed for this review. The comparison cases are a proposed protocol, not measured wins.

## Focused preparation findings

These are integration/qualification tasks, not evidence that BioMate lacks the entire capability:

- Normalize tool-knowledge parameter shapes: some rows use `parameter`, `scientific_meaning` and `typical_values` while consumers expect `name`; verify that scientific guidance reaches the generated task intact.
- Reject placeholder receptor paths and missing required outputs before execution. Show the actual structure identity and chemistry representation.
- Extend or explicitly constrain assay intake: concentration-unit support does not cover every endpoint, replicate, batch, donor, censoring or experimental condition needed for hospital assays.
- Disable or clearly isolate synthetic connector fallbacks in a claimed live experiment. Benchling's missing-key mock fallback is not a real laboratory connection.
- Qualify Chinese SOP/correction retrieval; the English-only organization-example tokenizer needs attention before claiming equivalent Chinese adaptation.
- Verify durable model identity, fixed holdouts, missing-metric rejection and promotion/rollback for the selected training path. Generic skeleton/simulated training routes are not substitutes for real research checkpoints.
- Keep workflow purpose accurate: `survival_analysis_km` simulates survival from parameters, not patient-level survival analysis. The specific patient-enrichment entry is a stub, but real Gate3 biomarker–treatment interaction code exists. Review its confidence-level handling before use.
- Rehearse the final visible scientific answer, not just successful backend calls: the current target-ID answer discrepancy remains a release gate.

## Next acceptance gate

Select one authorized or public proxy dataset for each shown lane; map each visible claim to source, run and output; then rehearse the exact build twice. Record current execution evidence separately from the inventory. Do not expand the demo merely to showcase catalogue breadth. The desired outcome is a bounded hospital pilot with a scientific owner, data owner, explicit evaluation criteria and an institutional learning asset.
