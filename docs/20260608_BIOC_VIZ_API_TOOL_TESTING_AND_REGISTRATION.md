# Bioconductor Visualization + API/Query Tools — Testing & Tool-DB Registration (2026-06-08)

## Why this exists
Real-execution validation targets *workflows* — analysis pipelines that read a file, transform
it, and write outputs. That gate correctly skips a large set of Bioconductor packages whose
"input" is **not a file**: **visualization** tools (consume an in-memory object → emit a plot)
and **API/query** tools (consume an identifier/query → fetch from a remote database). These were
recorded as `skip_input_type` / `no_reads` and excluded from the *workflow* denominator — which
is correct for workflow accounting, **but wrong if it means they vanish from the product**. They
are real, useful capabilities the AI should know about and route to ("plot a heatmap of my SCE",
"map these gene symbols to Entrez IDs"). This document defines how to **test** them in the right
mode and **register/enrich** them in the AI tool DB, aligned with how Galaxy describes tools.

## Current state (DB audit, 2026-06-08)
- The AI tool DB `tools` table holds **2,273 Bioconductor tools** (`tool_id = bioconductor/<pkg>`),
  each with BiocViews `category`, `requirements`, `edam_operations`, and `scientific_context_v2`.
- **All 2,273 are uncharacterized**: `inputs`, `outputs`, `parameters`, `galaxy_inputs` are
  `None` — unlike Galaxy ToolShed tools, which carry structured `parameters` (name/label/type/help),
  `inputs`/`outputs` (typed formats), and `requirements`.
- By BiocViews: **129 Visualization** tools (`Visualization`/`GraphAndNetwork`) and **271 API/query**
  tools (`ThirdPartyClient`/`DataImport`). Lists: `backend/scripts/bioc_viz_tools.txt`,
  `backend/scripts/bioc_api_tools.txt`.

## How Galaxy describes a tool (the target schema)
A Galaxy tool wrapper (`<tool>` XML) and its mirror in the `tools` table specify:
- `requirements` — conda/container deps (e.g. `bioconductor-complexheatmap`).
- `command` — the invocation.
- `inputs` — typed parameters, each `<param type="data" format="...">` (the data inputs) or
  primitive params (text/select/integer).
- `outputs` — typed `<data format="...">` results.
- placement in `integrated_tool_panel.xml` under a `<section>` (Genomics, Database, …).

The Bioconductor viz/API tools must be characterized in this **same structure** so they are
first-class alongside the ToolShed/nf-core tools (uniform `inputs`/`outputs`/`parameters`), and
placed in the right tool-panel section (Visualization, Database).

## Testing methodology — two modes (do NOT reuse the file-input workflow harness as-is)

### Mode V — Visualization tools (129) — offline-testable
A viz tool's contract is **object → figure**. Test:
1. Construct a **synthetic S4 object** of the documented input class — reuse the fixture builder's
   S4 constructors (`SingleCellExperiment`, `SummarizedExperiment`, `flowSet`, `GRanges`,
   `ExpressionSet`, matrix). The object, not a file, is the input; serialize to `.rds` for the run.
2. Call the package's **primary plotting function** (from `scientific_context_v2.key_functions` /
   the vignette) on the object, writing to a device (`png()`/`pdf()`/`ggsave()`).
3. **Assert a non-empty figure file** (PNG/PDF > a few KB) is produced. That is the pass signal —
   analogous to "declared non-trivial outputs produced" for workflows.
- Runs offline in the domain container (no network). This is the high-value, achievable lane.
- Record `tool_test_status = figure_ok | exec_error | construct_failed` and the figure produced.

### Mode A — API/Query tools (271) — network-bound, honest constraint
An API tool's contract is **identifier/query → remote fetch**. Test:
1. Call the documented query function with a **canonical identifier** (e.g. `mygene::queryMany("CDK2")`,
   `rWikiPathways::getPathwayIdsByGene("TP53")`, `biomaRt::getBM(...)`).
2. Assert a non-empty, well-typed result (data.frame / annotation object).
- **These require network access** to the upstream service (NCBI, WikiPathways, Ensembl,
  AnnotationHub). The offline validation fleet **cannot** test them directly — this is a genuine
  constraint, not a bug. Options, in order of preference:
  - **(a) Network test lane**: a separate, network-enabled runner that hits the live services with
    rate-limiting; record `tool_test_status = query_ok | service_unreachable`.
  - **(b) Recorded fixtures (VCR-style)**: cache one real response per tool, replay offline.
  - **(c) Signature-only registration**: when neither is feasible, characterize the query
    signature (input = identifier type, output = result type) from the docs **without** asserting a
    live call, and mark `availability_status = requires_network, tool_test_status = not_executed`.
- Do **not** report a network-bound tool as "validated" on the strength of an offline parse.

## Tool-DB registration / enrichment (what to write back to `tools`)
For each viz/API tool, populate the currently-`None` fields so they match Galaxy tools:
| Field | Viz tool | API tool |
|---|---|---|
| `inputs` | object class, e.g. `["rds (SingleCellExperiment)"]` | identifier type, e.g. `["gene symbol", "Entrez ID"]` |
| `outputs` | `["png","pdf"]` | result type, e.g. `["data.frame (annotation)"]` |
| `parameters` | the plot function's documented args (name/label/type/help) | query args (id type, attributes, filters) |
| `galaxy_inputs`/`galaxy_outputs` | Galaxy `<param>`/`<data>` mirror | same |
| `tool_test_status` *(new)* | `figure_ok` / … | `query_ok` / `requires_network` |
| `availability_status` | `installable` | `requires_network` where applicable |
- Add `tool_test_status` (+ `tool_test_at`, `tool_test_evidence`) columns to `tools`, mirroring the
  `real_exec_status` family on `workflows`, so the tool list records what was actually exercised.
- Place tested viz tools under a **Visualization** section and API tools under **Database** /
  **Data Import** in `integrated_tool_panel.xml`.

## Product impact
Once characterized + tested, BioMate can:
- **Route** object-level requests to viz tools ("heatmap of my DESeq2 results" → `ComplexHeatmap`/
  `EnhancedVolcano`) and identifier requests to API tools ("convert these symbols" → `mygene`).
- Show the AI the tool's real `inputs`/`outputs`/`parameters` instead of `None`, improving
  workflow-generation grounding (the Paper-2 thesis) for the object/query layer too.

## Phased plan
| Phase | Work | Status |
|---|---|---|
| P1 | Classify viz (129) + API (271) by BiocViews; persist lists | ✅ done (`bioc_viz_tools.txt`, `bioc_api_tools.txt`) |
| P2 | Mode-V viz test harness (synthetic object → plot → assert figure); run on fleet; record `tool_test_status` | ▶ next (reuses fixture S4 constructors) |
| P3 | Mode-A API: network test lane OR recorded fixtures; honest `requires_network` for the rest | pending |
| P4 | Enrich `tools` rows (inputs/outputs/parameters/galaxy_*/tool_test_status); add panel sections | pending |
| P5 | Route + surface viz/API tools in BioMate; feed characterized fields to the generator | pending |

## Honesty notes
- The 271 API tools are **genuinely network-dependent**; a meaningful fraction cannot be
  offline-validated and will carry `requires_network` rather than a green status. Reported as a
  constraint, not hidden.
- "Visualization" by BiocViews is a superset — a few entries are object-construction utilities
  that draw nothing; Mode-V's "non-empty figure produced" gate filters those honestly (they get
  `exec_error`/`no_figure`, not a pass).

## Key files
- `backend/scripts/bioc_viz_tools.txt` (129) · `backend/scripts/bioc_api_tools.txt` (271)
- `backend/scripts/build_bioc_fixtures_structured.py` — S4 constructors to reuse for Mode-V objects
- `backend/database/galaxy_ai_tools.db` — `tools` table (2,273 bioconductor rows to enrich)
- `backend/config/integrated_tool_panel.xml` — tool-panel sections for placement
