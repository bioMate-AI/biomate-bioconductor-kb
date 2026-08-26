# Supplementary — Overlap & Difference vs Biomni and ToolUniverse

A structural comparison of BioMate against the two nearest open tool-ecosystem agents, **Biomni** (Stanford; `snap-stanford/biomni`) and **ToolUniverse/TxAgent** (Harvard; `mims-harvard/ToolUniverse`). Counts are from primary sources / the live repos (fetched 2026-08-25). We compare on **unit, count, how the space is carved, shared substrate, and execution/governance** — and are explicit about what is *not* directly comparable.

## O1. The three systems carve the space differently — so raw counts are not like-for-like

| | BioMate | Biomni | ToolUniverse / TxAgent |
|---|---|---|---|
| **Unit of coverage** | validated multi-step **workflow** (containerised pipeline) | **Python/R function** the LLM composes into code | **API/tool** the agent calls |
| **Count** | **4,057 workflows** · 12,301 indexed tools | **150+ tools · 100+ software · 59 databases** across ~23 modules | **211 tools** (TxAgent paper 2025) → **≈640 tool-source files in the live repo** (grown since) |
| **Organising axis** | **analysis modality** (transcriptomics, variant-calling, single-cell, epigenomics, …; 39 domains) | **biological subfield** (biochemistry, cancer_biology, immunology, pharmacology, …; 23 modules) | **data source / API** (AlphaFold, BindingDB, BioGRID, arXiv, Bioconductor, …) |
| **Execution** | executes the pipeline on **AWS Batch** (containerised, governed) | LLM **generates and runs code** over the functions | **calls the tool/API**; reasoning agent (TxAgent) chains calls |
| **Governance** | evidence-graded QC gates + 21 CFR Part 11-aligned audit trail | not documented | not documented |

Because the units differ (a BioMate *workflow* bundles many steps and tools; a Biomni *function* or a ToolUniverse *API-tool* is a single call), **a raw count comparison — "4,057 vs 211" — is not meaningful and we make no such claim.** The comparable axes are how the space is carved (above), the shared substrate (O2), and execution/governance (O1 last two rows, the real difference).

## O2. Overlap — the shared substrate is the *databases*, not the tools

The clearest overlap is not at the tool level (different units/naming) but at the **underlying biomedical databases** all three wrap:

- **Both BioMate and ToolUniverse wrap Bioconductor** (ToolUniverse `bioconductor_tools.json`; BioMate holds 3,315 Bioconductor workflows) — a direct, verified overlap.
- **All three front the same core databases** — UniProt, PDB, AlphaFold, ChEMBL/PubChem, BindingDB, BioGRID, Ensembl, GEO — BioMate's "60+ databases," Biomni's **59 curated databases**, and ToolUniverse's data-source tools (AlphaFold/BindingDB/BioGRID/… JSONs) draw on the same public resources.
- **Domain overlap (name-mapped, approximate):** BioMate ∩ Biomni on genomics, systems-biology, imaging↔bioimaging, and drug-discovery↔pharmacology; the axes only partially align because BioMate indexes by *analysis modality* and Biomni by *biological subfield*, so a precise domain-Venn understates the true conceptual overlap in both directions.

*Why we do not report a precise tool-name overlap %:* the three inventories use different units and naming conventions (a workflow's `tools_used` entry, a Biomni `def query_uniprot`, a ToolUniverse `UniProt_get_entry`), so any exact-string intersection would be an artefact of naming, not capability. The honest overlap statement is the shared-database substrate above.

## O3. Difference — what each uniquely provides

- **BioMate uniquely:** validated, containerised **executable pipelines** (not tools to compose) run under **evidence-graded QC governance + audit trail**; the widest *analysis-modality* scope (39 domains incl. clinical pharmacology, cryo-EM, imaging); a domain-aware phase/step semantic layer.
- **Biomni uniquely:** the broadest **LLM-code-generation** action space over a curated function+software+database environment across 23 biological subfields; the most-adopted co-scientist (10,000+ labs); a published Science 2025 architecture.
- **ToolUniverse/TxAgent uniquely:** a large, unified **API-tool calling** layer (≈640 sources in the live repo) purpose-built for **therapeutic-reasoning** agents; strongest on real-time database/API breadth.

**Net:** the three are complementary rather than substitutable — BioMate *executes governed pipelines*, Biomni *writes and runs code over functions*, ToolUniverse *calls a broad API layer for reasoning*. They overlap on the public-database substrate they all sit on, and on Bioconductor specifically (BioMate + ToolUniverse); they differ on the unit of coverage and on whether execution is a governed validated pipeline.

## O4. Method / reproducibility

Biomni inventory fetched from `snap-stanford/biomni/biomni/tool/*.py` (23 domain modules; per-module `def` functions); ToolUniverse from `mims-harvard/ToolUniverse/src/tooluniverse/data/*_tools.json` (≈640 tool-source files). BioMate counts from `galaxy_ai_tools.db` (2026-08-17). Primary-source counts: Biomni 150+ tools / 59 DB / 100+ software (Science 2025; HAI Stanford); ToolUniverse 211 tools (arXiv 2503.10970) with the live repo now larger. Exhaustive per-tool-name intersection was **not** computed by design (unit/naming mismatch, O2); the fetch script and inventories are released with the supplement.
