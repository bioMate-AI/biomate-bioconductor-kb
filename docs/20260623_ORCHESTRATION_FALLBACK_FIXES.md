# 20260623 — Orchestration Fallback Fixes

## Problem

BioMate was less capable than a generic LLM for a broad class of requests because the orchestration layer silenced the model instead of augmenting it. Three compounding failures:

1. **Intent misclassification** — "generate the workflow from this paper" was routed to `workflow_generation` but then gated by the DATA-FIRST rule which rejected the paper as non-data. "Extract the study protocol" was routed to `workflow_generation` (file present → highest-priority rule fired) instead of `protocol_guidance`.

2. **Hardcoded fallback format** — The `**Missing: [what is needed]**` response was a prompt instruction enforced across ALL turns regardless of intent type. Any request that didn't produce a workflow fell into this template, even `general_question` and `protocol_guidance` intents. `Do NOT deviate from these three formats` locked the LLM out of answering freely.

3. **Paper content never reached the LLM** — When a user provided a URL, DOI, arXiv ID, or uploaded PDF, the content was never fetched. The LLM received only the filename or URL string, then was constrained into asking for FASTQ/S3 because no bioinformatics data was detected.

## Changes (`frontend/server/galaxy-assistant.ts`)

### 1. Intent classifier — paper-to-workflow rule

Added explicit bullet to the HIGHEST PRIORITY RULE (before other routing logic):

> **Paper-to-workflow (CRITICAL):** If the user provides a research paper (URL, DOI, arXiv ID, PMID, uploaded PDF) AND uses any execution verb (run, reproduce, implement, build, execute, replicate) → `workflow_generation`. The paper is the workflow specification.

Complementary rule for non-execution intent:

> **Document reading without execution intent:** paper/URL + read/summarize/extract/explain (no execution verb) → `protocol_guidance` or `research_question`.

### 2. DATA-FIRST rule — paper-as-specification exception

Added exception to the `DATA-FIRST RULE`:

> When the user provides a research paper AND asks to reproduce/run/implement the workflow from it, the rule does NOT apply. The paper is the workflow specification. Generate the workflow first; ask for sample input data after presenting it, not before.

### 3. Response format — non-workflow turns freed from "Missing:" template

The three rigid response formats (`Workflow generated` / `Missing:` / `Could not generate workflow`) previously applied to all turns. Fixed so they apply **only when `isWorkflowTurn` is true**.

Non-workflow turns now get:
- `FORMAT: Research / document answer` — when research agent returned results
- `FORMAT: Direct answer` — for general/conceptual/protocol turns

This allows the LLM to answer document extraction, general questions, protocol guidance, etc. without being forced into asking for FASTQ/S3.

### 4. Parallel paper content fetch — `_fetchPaperContentFromMessage`

New function that detects paper references in the user message and fetches content **in parallel** with tool/dataset search (no added latency on the critical path).

Supported input types:

| Input | Resolution |
|---|---|
| `arxiv.org/abs/XXXX.XXXXX` or `arxiv:XXXX.XXXXX` | arXiv Atom API → abstract + rough PDF text extraction |
| `10.XXXX/...` (DOI) | Crossref API → title + abstract |
| `PMID:XXXXXXXX` or pubmed URL | NCBI E-fetch → abstract text |
| Any `https://` URL | HTTP fetch → HTML stripped to text, or PDF bytes rough-extracted |

Content capped at 8000 chars. Injected into message as `[Paper content: <ref>]\n<text>` before `generateWorkflow` and `generateResponse` run, so both the workflow generator and the research agent see the actual paper text.

PDF text extraction is best-effort (latin1 decode + ASCII filter) — sufficient for methods sections, which are typically ASCII. No native PDF library required.

## Known Open Issues (next session)

### Paper-aware workflow generation gap

The backend `nextflow_composer.py` receives the paper content as part of the intent text, but has no paper-specific logic. The current flow:

1. `generate_workflow_unified()` extracts intent keywords from the full message text
2. Searches 12,274-tool catalog against those keywords
3. Generates Nextflow DSL2 from matched tools

This misses:
- **Methods extraction** — paper content needs to be parsed for the methods section specifically, not treated as generic intent text
- **Tool identification** — paper names specific tools/versions ("STAR v2.7.9a", "featureCounts v2.0.1") that need to be mapped to catalog entries by name, not by keyword similarity
- **Gap analysis** — tools described in paper but absent from BioMate's catalog need explicit handling: install from Bioconductor/conda/GitHub, or generate process block from paper description
- **Parameter pre-fill** — numeric parameters stated in paper ("FDR < 0.05", "minimum 10 reads") should pre-fill workflow params, not be re-asked

**Required engineering (not yet implemented):**
1. Methods section extractor — identify and isolate the methods/protocol section from paper text
2. Tool name normalizer — map paper tool names to catalog entries (fuzzy match + version awareness)
3. Gap classifier — for each identified tool: catalog match / installable / paper-described-custom / opaque
4. Process block generator for paper-described custom tools — uses paper's method description as spec
5. Param extractor — pull numeric thresholds and settings from methods text as pre-satisfied parameters

The `[Paper content: ...]` block is injected and visible to the LLM, which provides a baseline — the LLM can read the methods and attempt to map tools — but deterministic gap analysis and structured param extraction require the above engineering work.

### GPT-4o missing from main chat backbone

`llm_providers.yml` defines the full fallback chain (Gemini Pro → Gemini Flash → Claude → GPT-4o → Ollama) and it is used by `/internal/llm/generate`. However, the main chat response path in `galaxy-assistant.ts` uses its own hardcoded backbone check (`isGeminiBackbone` / `isOllamaBackbone` / else-Claude) and does not go through the YAML chain. GPT-4o is absent from the main path.

### Multimodal file content (not yet implemented)

All LLM backends currently receive plain text only. Gemini, Claude, and vision-capable Ollama models all support native multimodal input (PDF document blocks, image data), but the message-building layer strips non-text content before any backend call. This is a separate workstream from the paper content fetch above (which handles text-extractable sources).
