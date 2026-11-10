# BioMate research and publication skill compatibility audit

Date: 2026-10-29

BioMate already has parallel literature retrieval, grounded paper synthesis, expert skills, analysis execution and report export. The next step is to connect these capabilities into reliable research and publication workflows, not introduce a second competing workbench. New open-source components should improve a measured weakness: evidence extraction, review screening, hypothesis evaluation, editable presentation design or reproducible publication figures.

Current compatibility is **partial**. Developers can integrate prompt skills and executable tools, and users can select existing skill packs. The custom upload handler is not yet a safe, portable installer for complete third-party skill packages. Source presence below means implemented code, not a fresh successful live test of every feature.

## Existing capabilities and their boundaries

| Area | Current implementation | Boundary relevant to this request |
| --- | --- | --- |
| Multi-channel search | `backend/lib/galaxy/ai/federated_query.py`: parallel entity-aware fan-out, Redis caching, per-source status. Literature sources include corpus_fs, PubMed, Europe PMC, Semantic Scholar, OpenAlex and Crossref. | Multiple channels are already present. Assess latency, coverage, relevance and source failure reporting rather than add another generic search layer. |
| Research retrieval | `agents/literature_clients.py:search_bioinformatics`: iterative federated search, relevance ordering and identifier enrichment; PubMed/arXiv/Semantic Scholar clients also exist. | Identifier validity alone does not establish that a paper supports a specific claim. Abstract-only evidence must remain distinguishable from full text. |
| Paper synthesis | `webapps/galaxy/api/ai_assistant.py:paperqa_synthesize`, `frontend/server/orchestrator.ts:synthesize_papers`; `paper-qa` is already in backend requirements. | This is an existing integration, not a new candidate. Runtime installation, embeddings/model configuration, file authorization and successful live synthesis still require feature-specific checks. |
| Local corpus | `ai/corpus_fs/`, including FTS5 index, section paths and grounded extracts. | `corpus_fs/map.py` leaves synthesis as an injection point; the module describes itself as inert. Do not equate this with a fully connected private-corpus research agent. The October 8 document saying the entire substrate is missing is now stale in that respect. |
| Research skill guidance | `agents/skill_loader.py` loads SKILL.md and optional Markdown references for research intents and domains. | Separate loader and catalogue from expert packs; no script or asset installation. Default path is a hard-coded Linux directory, absent on this local machine. Dev availability was not inferred from that local absence. |
| Expert and package skills | `ai/skill_manager.py`, `/api/skills`, `/detect`, `/block`; composer selection reaches `galaxy-assistant.ts:processMessage` and prompt construction. Nine expert Markdown files are present, plus the Bioconductor manifest loader. | This is real instruction injection, not automatic capability installation. The two loader formats and discovery paths are not unified. |
| User custom skills | Backend `/api/skills/upload` accepts Markdown and reloads the manager. | The handler writes a global directory, uses the supplied name as a filename and can overwrite a matching pack. No owner/project namespace or approval/version lifecycle is expressed in the handler. A user-context dependency is present; anonymous access has not been established. No matching frontend upload proxy/UI was found in the inspected routes/components. |
| Manuscript support | Domain-specific grounded manuscript-section prompts in `frontend/server/routes.ts`, Methods export and a run-linked append-only report-version model. | Useful foundations, not evidence of a complete journal-aware manuscript workspace with claim-by-claim source support, coauthor review and final rendered submission checks. |
| Slides | Authenticated `/api/reports/convert` uses Pandoc to generate PPTX, with an optional branded reference deck. | Export is not equivalent to designed scientific slides. Template availability, visual rendering, editable figures, overflow, reading order and Chinese font coverage need explicit checks. |
| Figures | `frontend/server/findings-figures.ts` projects real result metrics into QC/composition/bar figures; workflow outputs and code execution supply other plots. | Existing result visualization should be preserved. It does not establish a general multipanel publication-figure workflow with figure specifications, editable source and journal-specific preflight. |
| Executable extensions | Existing MCP/connectors and `frontend/server/code-runner.ts` sandbox; the code sandbox disables networking. | Reuse these execution boundaries. Skills needing internet, credentials, Node, TeX or newer Python do not become executable merely by loading their Markdown. |

## Reproduced compatibility failures

The public [Agent Skills specification](https://agentskills.io/specification) describes a directory containing SKILL.md, with optional scripts, references and assets. Required metadata includes name and description; BioMate-specific triggers are not required by that standard.

Read-only local checks against the actual `skill_manager._parse_frontmatter` reproduced:

1. A standard minimal skill with `name` and `description` fails the upload handler's `name` plus `triggers` requirement.
2. A folded YAML description is parsed as the literal `>` rather than its text.
3. A YAML block list under `triggers` is parsed as an empty string, so upload rejects it.

These are parser/contract findings, not a live upload test. No skill was installed or overwritten. The other research loader uses `yaml.safe_load`; the inconsistency is between two existing systems, not an absence of skill support altogether.

Additional integration gaps:

- Expert packs scan flat `*.md` files; external packages commonly use nested `skill-name/SKILL.md` directories.
- Research skill lookup uses fixed category paths, while the current upstream scientific-skill repository exposes a different package layout. An upgrade needs an explicit path migration and resolution test.
- Research references are limited to immediate Markdown files, loaded into memory; scripts, templates and recursive references are not managed as a package.
- `buildSkillBlock` silently returns an empty block on upstream errors. Explicit selection needs a visible unavailable state instead of appearing successfully active.
- There is no demonstrated shared lockfile for source commit, content digest, dependencies, declared permissions and approved execution image.
- The upload reload is process-local; multi-worker cache invalidation and persistence across container replacement need verification.

## Open-source candidates

These are adoption candidates, not approved installations. Verify an exact release/commit, dependencies, transitive licenses and model/data terms before packaging. An open code license does not grant rights to every paper, template, image or model used by it.

| Component | Fit for BioMate | Integration decision and constraints |
| --- | --- | --- |
| [K-Dense scientific agent skills](https://github.com/K-Dense-AI/scientific-agent-skills), MIT | Scientific writing, slides, visualization and review guidance; the repository previously named claude-scientific-skills is already part of BioMate's design. | Refresh selected packages rather than import the entire collection indiscriminately. The current slides package declares scripts, references, assets and substantial runtime dependencies. Adapt tool names and execution contracts; retain attribution and review external-service instructions. |
| [GROBID](https://github.com/grobidOrg/grobid), Apache-2.0 code | Structured scholarly PDF extraction, including bibliographic structure, for document-linked evidence. | High-value parsing pilot behind the existing corpus ingestion interface. Preserve page/section coordinates and compare against existing extraction on real biomedical PDFs, including tables and multicolumn layouts. A parser is not a fact checker or universal OCR solution. |
| [MarkItDown](https://github.com/microsoft/markitdown), MIT | Office and mixed-document intake for manuscripts, lab material and prior slides. | Complement GROBID, not a duplicate scholarly parser. Keep original documents and locations; Markdown conversion alone loses layout fidelity needed for final presentation review. |
| [ASReview](https://github.com/asreview/asreview), Apache-2.0 | Active-learning prioritization of records for systematic review with human screening decisions. | Strong optional review-screening adapter. Feed BioMate retrieval results into a versioned screening task; keep criteria, labels, exclusions and search history. Prioritization does not prove complete recall or make an automatic systematic review. |
| [STORM](https://github.com/stanford-oval/storm), MIT | Multi-perspective question asking and outline development for broad surveys. | Evaluate its planning pattern or a bounded adapter against existing research decomposition. Do not replace BioMate's evidence records, routing or workbench UI with another report application. |
| [OpenScholar](https://github.com/AkariAsai/OpenScholar), Apache-2.0 code | Retrieval-grounded synthesis, retrieval/reranking methods and ScholarQABench evaluation. | Use first as a benchmark and optional specialist backend. Model weights, source corpora, retrieval serving resources and their separate terms require assessment; code availability is not a free hosted corpus. |
| [PptxGenJS](https://github.com/gitbrent/PptxGenJS), MIT | Editable slide objects, charts, shapes and branded slide masters in the existing TypeScript stack. | Preferred slide-generation pilot alongside current Pandoc export. Generate from an approved content/figure manifest, render in an isolated worker and inspect every slide before offering the final deck. |
| [Manubot](https://github.com/manubot/manubot), BSD-2-Clause Plus Patent | Identifier-based bibliography metadata and manuscript preparation for Pandoc. | Reuse the citation/build utilities within BioMate's existing versioned artifact flow. Do not require users to publish a GitHub repository or send confidential drafts to a public CI workflow. |
| [Quarto manuscripts](https://quarto.org/docs/manuscripts/), primarily MIT code under its [copyright notice](https://github.com/quarto-dev/quarto-cli/blob/main/COPYRIGHT) | Journal-oriented manuscript outputs connected to computational notebooks, figures and cross-references. | Evaluate as an optional publishing worker when notebook-linked articles are needed. Compare with the existing Pandoc path before adding another renderer; do not require a public manuscript website. Bundled components and templates need their own license review. |
| [SciencePlots](https://github.com/garrettj403/SciencePlots), MIT | Consistent Matplotlib styles for scientific figures. | Low-complexity plotting improvement, not a full figure generator. Pair with existing plotting tools, explicit panel specifications and typography/layout checks. Account for TeX and CJK font requirements. |
| [PaperVizAgent](https://github.com/google-research/papervizagent), Apache-2.0, and the [PaperBanana continuation](https://github.com/dwzhu-pku/PaperBanana) | Reference-guided diagram planning, styling and iterative visual critique. | Promising experimental schematic adapter, not the default statistical-plot engine. The upstream quick start uses Python 3.12 and model services, so isolate it from Galaxy's Python 3.9 environment. Treat rendered diagrams as drafts, review all biological relationships and do not promise editable vectors from an image-generation pipeline. |

PaperQA2 should be upgraded or benchmarked through its existing adapter, not listed as a new import. Existing Paperclip research also distinguishes the open client from a hosted corpus service; do not advertise its client repository as a self-hosted literature corpus.

For autonomous hypothesis systems, [AI-Scientist](https://github.com/SakanaAI/AI-Scientist) and [AI-Researcher](https://github.com/HKUDS/AI-Researcher) are useful architectural comparisons, not first-priority drop-ins. BioMate already owns execution and orchestration. AI-Scientist has a custom responsible-use license and disclosure obligations; AI-Researcher's commercial reuse license was not established in this inspection. Neither is evidence that a proposed biomedical hypothesis is novel, safe or experimentally validated.

## A coherent integration contract

Use one package identity across instruction selection, connector tools and reproducible jobs. Keep existing expert and Bioconductor IDs as aliases rather than break saved projects.

1. **Discover:** read standard metadata; list capability, publisher, version, required runtime and permissions before activation. Distinguish an instruction-only skill from a tool or executable workflow.
2. **Resolve:** pin repository commit and package digest. Resolve relative references/assets within the approved package root. Reject traversal, archive bombs, symlink escapes and unsafe file types.
3. **Authorize:** record user/project/workspace scope and who approved the package. A user import must not replace a globally installed skill. Team publishing requires a separate action.
4. **Execute:** instructions use BioMate's existing tool registry; scripts run in approved isolated images. Dependencies are installed during reviewed image builds, not arbitrary package installation in the live application. MCP tools retain connector-scoped credentials and consent. Prompt-declared allowed-tools cannot grant permissions.
5. **Register:** every output belongs to the project and records input file IDs/hashes, run IDs, source passages, skill/tool versions, generating code and output hashes. Reuse current report versioning where appropriate; extend it for decks, figure bundles and manuscripts.
6. **Review:** show the rendered artifact in the existing workspace and accept revisions as versions. A failed render, absent dependency or unresolved reference is a failed/incomplete artifact, not successful prose.

For a user, the intended flow is: import a package or select an approved pack, inspect its requirements, attach project files, ask for an output, review the preview and revise it. A lab should be able to contribute its journal template, figure style or protocol-review instructions without writing a backend adapter. New privileged tools and execution images remain an administrator/developer integration.

This adds no mandatory multi-pane choreography or new dashboard. A compact import/detail view and the existing skill selector, files and preview surfaces can expose the lifecycle.

## Research and publication acceptance tests

Search speed must be measured independently from answer quality. Two static findings deserve regression tests before more channels are added: the federated cache key omits the selected sources and result cap, and the ThreadPoolExecutor context waits for running tasks on exit even after an `as_completed` timeout. Consequently, the advertised aggregate deadline is not necessarily a hard return deadline. Test these with controlled local fixtures and then real provider outages; they were identified by code inspection, not a production latency measurement.

Research tests should cover:

- Recall of expert-selected primary papers; relevance, duplicate resolution and source diversity; explicit abstract/full-text distinction; p50/p95 first-evidence and final-answer latency; cold/warm caches and partial outages.
- Query expansion and citation chasing without laundering a review's claim into independent experimental support. Surface contradictory and negative evidence.
- Protocol extraction with source/version, organism, sample type, units, timing, controls, missing steps and hazards. An inferred condition must not be presented as a cited experimental method.
- Hypothesis outputs with supporting and conflicting passages, novelty-search scope/date, proposed mechanism, falsifiable prediction, controls and feasibility. “No match found” must not mean proven novelty. Expert judgment and experimental validation remain separate outcomes.

Publication tests should cover:

- A slide deck from an actual completed run: exact numeric fidelity, editable text/charts, working citations, original plots retained, no overflow, Chinese/English fonts and successful rendering.
- A manuscript from two cited result files and literature: all reported values match inputs, methods link to run provenance, unsupported claims are flagged, references resolve, and revisions preserve the immutable original.
- A multipanel figure: units, transformations, sample counts, statistical tests and uncertainty are explicit; no fabricated points or image manipulation. Deliver source data, code/specification, editable vector output when supported, and the requested raster format/resolution.
- A schematic: distinguish established from proposed interactions, check direction/labels/compartments and obtain scientific review. Generative images must not replace measured microscopy, gels or quantitative plots. Check the destination journal's image policy before submission.
- Cross-project denial, malicious skill instructions, secret exfiltration attempts, invalid package paths, conflicting versions, missing dependencies, offline mode, rollback and worker restart.

## Recommended implementation phases

**Phase 1 — Portable and scoped skills.** Replace the minimal expert parser with validated YAML, accept standard name/description metadata, retain optional triggers, unify catalogue adapters, configure research skill paths and implement package identity/scope/version rules. Add a real frontend import path only after the backend ownership and overwrite boundaries are enforced. Exit gate: portable package fixtures, cross-project isolation, no silent activation failures, restart persistence and provider-route tests.

**Phase 2 — Publication artifacts.** Deliver three reviewed packages: scientific manuscript drafting, editable scientific slides and reproducible multipanel figures. Reuse grounded research, run-linked reports and existing plotting/execution. Pilot PptxGenJS, citation/build utilities and figure styles with local rendering. Exit gate: one realistic end-to-end project per package, artifact fidelity and visual/scientific review, including failure cases.

**Phase 3 — Research depth and speed.** Correct and benchmark search contracts; evaluate structured PDF intake and ASReview; compare STORM/OpenScholar patterns against the current baseline. Add only components with measurable benefit. Keep a fast bounded search mode and a separately scoped deeper research task rather than making every question expensive. Exit gate: biomedical retrieval/claim-support benchmarks and outage tests, followed by expert-reviewed protocol and hypothesis cases.

**Phase 4 — Optional advanced diagram and discovery agents.** Evaluate PaperVizAgent and selected hypothesis-planning patterns in isolated workers with explicit external-service policy and bounded execution. Promote packages only after domain-specific evaluation; do not turn exploratory model output into a claim of scientific discovery.

Each phase requires implementation, tests and audit before the next. These priorities do not remove later capabilities from scope. No third-party code, package or service was installed or enabled during this audit.
