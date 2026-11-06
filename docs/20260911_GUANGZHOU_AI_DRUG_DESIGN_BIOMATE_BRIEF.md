# BioMate Brief and Discovery Questions — Guangzhou AI Drug Discovery Project

**Working status:** Draft for today's project discussion; do not send externally without commercial and scientific review.

## Recommended BioMate positioning

BioMate is a governed research-analysis and workflow-execution platform for life-science R&D. For this project, it can provide the decision-support and evidence layer around molecular design: capture the project objective and constraints, run configured computational workflows, prevent invalid launches before compute is spent, compare candidate compounds against explicit criteria, and preserve inputs, parameters, outputs, QC outcomes, and decision context.

For the requested molecular-generation and optimization capability, BioMate should be proposed as a **jointly scoped and validated workstream**, not as an already validated autonomous “drug-from-a-button” system. The pilot should combine selected, verified capabilities—structure/property assessment, docking or target-interaction analysis where an appropriate target structure is available, selected ADMET/safety triage, ranking, and evidence-pack generation—with an agreed molecular-generation/optimization model and prospective assay validation.

### Why this is differentiated

- **From design objective to reproducible run:** scientists can express the target product profile and constraints in ordinary language, then review explicit parameters rather than hidden assumptions.
- **Multi-objective governance:** potency/affinity, developability, synthesis feasibility, and safety can be reported as separate, inspectable criteria; no single opaque score should decide a compound.
- **Execution safety and provenance:** BioMate blocks runs with missing required parameters or unsupported data bindings, and records what was run and why.
- **Human-in-the-loop decision support:** medicinal chemists and biologists retain approval authority for generated or ranked candidates.
- **Pilot-ready extensibility:** the team can integrate the partner's assay data, preferred scoring models, chemistry constraints, and existing computational pipelines behind a versioned workflow contract.

## Claims to avoid

- Do not say BioMate can independently discover an efficacious drug, nominate a clinical candidate, or validate efficacy.
- Do not promise that generated molecules are synthesizable, active, safe, novel, or patentable without prospective experimental evidence.
- Do not call computational ADMET or docking results regulatory-grade, clinical-grade, or a substitute for experimental assays.
- Do not imply that a generic model will work on the partner's target without target-specific data, evaluation criteria, and retrospective/prospective validation.

## First-meeting discovery questions

The canonical Chinese questionnaire asks 20 platform-scoping questions across modality and target scope, company data and systems, configurable multi-objective optimisation, wet-lab DMTA feedback, delivery, deployment, and acceptance. The questions below are a concise meeting version; see [20260911_GUANGZHOU_CLIENT_QUESTIONNAIRE_EN.md](20260911_GUANGZHOU_CLIENT_QUESTIONNAIRE_EN.md) for the faithful English reference.

### Scientific objective and data

1. What is the first decision the project must improve: hit expansion, lead optimization, scaffold hopping, candidate ranking, or another decision?
2. What target, target class, therapeutic area, and molecular modality are in scope? Is a target structure, binding site, or validated assay available?
3. What historical data can be used: structures, activity endpoints, assay protocols, selectivity panels, ADMET results, synthesis routes, and failed-series data? What are the data rights and quality constraints?
4. Which endpoints are decision-critical, and how are they measured (for example IC50, Ki, EC50, cellular potency, permeability, microsomal stability, hERG, DILI)?

### Design contract

5. What are the non-negotiable constraints: scaffold/warhead exclusions, physicochemical ranges, selectivity, CNS exposure, oral route, patent-space constraints, or known toxicophores?
6. How should synthetic accessibility be defined for this team: a heuristic score, purchasable building blocks, route length, chemistry availability, cost, or medicinal-chemist review?
7. How should conflicting objectives be handled? Which criteria are hard exclusions, which are ranking factors, and who can override them?
8. What baseline—current medicinal-chemistry process, existing vendor tool, or historical series—will BioMate be compared against?

### Validation and delivery

9. What retrospective benchmark can be used before prospective work: time-split assay data, known active/inactive compounds, or prior lead-optimization campaigns?
10. What prospective validation is possible during the pilot: number of compounds synthesized, assays, turnaround time, budget, and success threshold?
11. What evidence would make the pilot successful: enrichment of actives, improved multi-parameter profile, novelty/diversity, fewer synthesis cycles, faster decision time, or reproducibility/auditability?
12. What deliverable format is required: ranked compound set, design rationale, synthesis-aware handoff, methods/QC report, API integration, or an internal deployment?

### Operating model

13. Who are the named scientific decision-makers—medicinal chemistry, computational chemistry, biology, DMPK, toxicology, and IP—and how will review decisions be recorded?
14. What model, compute, deployment, IP, confidentiality, and data-residency constraints apply? May any model be trained or fine-tuned on the partner's data?
15. What pilot scope, acceptance milestones, ownership of foreground work, and expansion decision are expected within the available budget and timeline?

## Proposed pilot shape

1. **Discovery and data audit:** agree the target product profile, data dictionary, scoring contract, baseline, and validation protocol.
2. **Retrospective evaluation:** test candidate-generation/ranking approaches on held-out historical data; report coverage, calibration, enrichment, failure modes, and uncertainty.
3. **Human-reviewed design cycle:** generate or retrieve a diverse candidate set; apply explicit chemistry, affinity/activity, developability, and safety gates; document why candidates were retained or removed.
4. **Prospective assay loop:** synthesize/test an agreed small set; compare predicted and observed outcomes; refine only under versioned data/model governance.
5. **Decision package:** deliver ranked candidates with evidence, limitations, parameter/model versions, and a recommendation on whether to expand.
