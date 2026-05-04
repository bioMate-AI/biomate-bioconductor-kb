# Routing + SSE Fix — 14/14 Routing Test Pass (2026-05-01)

## Routing test results
All 14 cases passing across 3 categories:
- run_code (5/5): gc_content, rev_comp, pk_halflife, boin_boundary, pk_fit — all direct computations via run_code tool
- workflow (5/5): RNA-seq/SRR, ADMET, BOIN Phase I, PBPK caffeine, CryoSPARC SPA — all generate Nextflow workflow panels
- research (4/4): BOIN concept, hERG mechanism, RNA-seq troubleshoot, experiment planning — substantive text responses

## Root causes fixed

### 1. SSE streaming broken (routes.ts)
`req.on('close', ...)` was firing immediately after body-parser consumed the POST body (IncomingMessage stream auto-destroys after body is read). This triggered `abortController.abort()`, blocking all SSE events after `event: ready`.

**Fix**: Changed to `req.socket?.on('close', ...)` — listens to TCP socket close (actual client disconnect) instead of IncomingMessage stream close (body consumed).

### 2. needsWorkflowGeneration: false over-generalized (galaxy-assistant.ts)
Single few-shot example showed reverse-complement → `needsWorkflowGeneration: false`. Gemini generalized this to ALL workflow_generation queries including RNA-seq/SRR accessions.

**Fix**: Added a second example showing RNA-seq on SRR accession → `needsWorkflowGeneration: true`, with a clear note: "needsWorkflowGeneration: true when data is accession/file path; false when user pastes inline data."

### 3. PBPK SMILES detection missed caffeine (galaxy-assistant.ts)
Caffeine SMILES `Cn1cnc2c1c(=O)n(c(=O)n2C)C` was not detected because:
- `\b(c1|...)` requires word boundary before `c1`, but in "c2c1c" the preceding `2` is alphanumeric (no word boundary)
- `_smilesAfterFor` captured "caffeine" (compound name) not the SMILES

**Fix**: Added `\(=O\)` (carbonyl, unique to SMILES), `\[n[Hh]\]` (aromatic NH), and `[A-Za-z0-9]\([A-Za-z=]` + `[a-z]\d` patterns. Also fixed `_smilesAfterFor` to capture the second token after "for" (skipping the compound name).

## Architecture summary
- `workflow_generation` intent covers ALL execution tasks
- `needsWorkflowGeneration: true` → generateWorkflow() → Nextflow panel
- `needsWorkflowGeneration: false` → LLM uses run_code directly
- `isResearchIntent = !isWorkflowTurn || intent_in_set` so both code-execution and research cases get the compute-enabled prompt
