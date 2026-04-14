# BioMate Agent Architecture — Moving Beyond Prompt Constraints

**Date**: 2026-04-04  
**Status**: Design proposal — not yet implemented  
**Context**: User identified that BioMate's current prompt constraints are preventing it from using Claude's native reasoning and coding abilities for simple tasks.

---

## The Problem

### Current system prompt constraints (galaxy-assistant.ts, lines 3036–3056)

```
- NEVER compute or calculate results yourself
- ALWAYS recommend running the appropriate BioMate tool or workflow instead
- DATA-FIRST RULE (hard prohibition — no exceptions except demo/test/mock)
- ONE-QUESTION RULE
- SECOND-TURN OVERRIDE
- TURN-2 QUALIFIER RULE
```

These rules were added for legitimate reasons:
- Prevent Claude from fabricating biological results (e.g., making up alignment statistics)
- Force reproducible, tool-backed execution
- Prevent the assistant from explaining pipeline steps instead of running them

### What they accidentally prohibit

**Example: "run the experiment using the top 10 rows of this table"**

Current BioMate behavior:
1. DATA-FIRST RULE triggers — tries to map "the experiment" to a Nextflow workflow
2. Asks the user to clarify what "experiment" means (ONE-QUESTION RULE)
3. Probably fails to find a matching workflow
4. Returns an error about needing more information
5. Never touches the table

Claude Code behavior with the same input:
1. Reads the table, takes `df.head(10)`
2. Understands "the experiment" from context (previous turns, file type, prior commands)
3. Writes the code, runs it, returns results
4. If ambiguous, makes a reasonable assumption and executes

The gap is not a capability gap — Claude can do it. It's a **constraint gap**: the prompt is explicitly prohibiting the capability.

### Why this matters at scale

Researchers have enormously varied intents:
- "Show me which samples have zero variance in this expression matrix"
- "Subset these 1000 FASTA sequences to only the mammalian ones"
- "Re-run the analysis but exclude the outlier sample"
- "What fraction of my variants are in exons?"
- "Run the top 10 rows as a pilot"

None of these map cleanly to a pre-built Nextflow workflow. All of them are trivially solvable with 5 lines of Python. The current system either fails them or forces an awkward workflow-generation path for tasks that don't need it.

---

## The Core Insight

**The "NEVER compute" rule conflates two very different things:**

1. **Fabricating biological facts** — e.g., "your BRCA1 variant is pathogenic" without running any tool. This must be prohibited.

2. **Scripting and data manipulation** — e.g., taking top 10 rows of a CSV, filtering a FASTA file, computing basic statistics on a table. This is pure computation on data the user already has. It is completely safe and should be permitted.

Claude Code is powerful because it has no rule against category 2. BioMate's rule blocks both categories indiscriminately.

---

## Proposed Architecture: Three-Tier Intent Handling

### Tier 1 — Code Agent (NEW)
**For**: Ad-hoc data manipulation, scripting, exploratory analysis, simple transformations  
**Mechanism**: Claude writes Python/R code, executes it in a sandboxed Galaxy Python tool or JupyterHub session, returns results  
**Examples**:
- "top 10 rows"
- "filter sequences by length > 1000"
- "calculate mean ± SD per group in this table"
- "reverse complement this sequence"
- "how many variants are in chromosome 17?"

### Tier 2 — Workflow Dispatch (CURRENT)
**For**: Validated, reproducible scientific pipelines with known tools  
**Mechanism**: Intent → Nextflow workflow selection → parameter filling → execution  
**Examples**:
- "run RNA-seq differential expression"
- "variant calling on these WGS samples"
- "cryo-EM single-particle analysis"

### Tier 3 — Research & Knowledge (CURRENT)
**For**: Scientific questions, literature lookup, benchmark comparisons  
**Mechanism**: Research agent, RAG, web search  
**Examples**:
- "What is the best tool for metagenomic assembly in 2024?"
- "Compare STAR vs. HISAT2 alignment accuracy"

---

## Intent Classification

Before the current `_inferDomainWithLLM()` call, add a new upstream classifier: `_classifyIntentTier()`.

```typescript
type IntentTier =
  | 'scripting'      // Tier 1: data manipulation, ad-hoc code
  | 'workflow'       // Tier 2: full pipeline dispatch
  | 'research'       // Tier 3: literature/knowledge
  | 'hybrid';        // Tier 1 preprocessing + Tier 2 pipeline

async function _classifyIntentTier(message: string): Promise<IntentTier>
```

**Scripting signals** (Tier 1):
- "top N rows", "first N entries", "subset", "filter", "exclude", "slice"
- "calculate", "count", "how many", "what fraction"
- "show me", "list", "print", "display"
- "reverse complement", "translate", "convert format"
- "rename", "sort by", "group by"
- References to uploaded file + simple operation

**Hybrid signals**:
- "run the experiment using the top 10 rows" → Tier 1 (subset) + Tier 2 (run experiment)
- "filter out low-quality samples then run RNA-seq" → Tier 1 (filter) + Tier 2 (RNA-seq)
- "pilot run with 100 reads" → Tier 1 (subset) + Tier 2 (run workflow)

---

## Code Execution Infrastructure

### What already exists

1. **Galaxy interactive tools** (`/api/interactive-tools/launch`) — launches JupyterHub / RStudio with access to Galaxy datasets
2. **Galaxy script tool** — runs arbitrary Python/R scripts via Galaxy job infrastructure
3. **Sandbox execution mode** (`mode: 'sandbox'`) — already in the run infrastructure

### What needs to be added

**A lightweight inline code executor** that:
1. Accepts a Python/R/bash script
2. Runs it in a Docker container with the uploaded files mounted
3. Returns stdout, stderr, and any output files
4. Streams output back to the chat UI

This is analogous to Claude Code's `Bash` tool, but scoped to a per-session Docker container with the user's files.

**Endpoint**: `POST /api/code/run`
```json
{
  "language": "python",
  "code": "import pandas as pd\ndf = pd.read_csv('/data/input.csv')\nprint(df.head(10))",
  "input_files": ["dataset_id_123"],
  "timeout_seconds": 30
}
```

---

## Prompt Changes Required

### Remove / Relax
```diff
- NEVER compute or calculate results yourself (e.g., reverse complement, sequence alignment, etc.)
- ALWAYS recommend running the appropriate BioMate tool or workflow instead
```

### Replace With
```
COMPUTATION RULE:
- For scripting tasks (data manipulation, filtering, format conversion, basic statistics on 
  provided data): write and execute code directly. Do not route these to Nextflow workflows.
- For scientific analysis (alignment, variant calling, differential expression, structure 
  prediction): use validated BioMate tools and workflows.
- NEVER fabricate biological results (e.g., pathogenicity scores, statistical significance, 
  structural predictions) without running the appropriate tool. Computation on provided data 
  is not fabrication — it is scripting.
```

### Add
```
SCRIPTING CAPABILITY:
When the user's intent involves simple data manipulation on an uploaded file (filtering rows,
subsetting, format conversion, counting, basic statistics), respond by:
1. Writing the appropriate Python/R/bash code
2. Calling the code execution tool to run it
3. Returning the result inline in the chat
Do not ask the user to provide a Nextflow workflow for these tasks.
```

---

## The "Top 10 Rows" Example — With New Architecture

User: "Run the experiment using the top 10 rows of this table"

New BioMate flow:
1. `_classifyIntentTier()` → `'hybrid'` (scripting + workflow)
2. **Phase 1 (Tier 1)**: Generate and execute:
   ```python
   import pandas as pd
   df = pd.read_csv('/data/uploaded_table.csv')
   subset = df.head(10)
   subset.to_csv('/data/subset_10rows.csv', index=False)
   print(f"Saved {len(subset)} rows → subset_10rows.csv")
   ```
3. **Phase 2 (Tier 2)**: Route `subset_10rows.csv` to the appropriate workflow based on table content + prior context
4. Return: "I've subsetted your table to the top 10 rows and submitted them to the [experiment] workflow. You can see the results in the panel on the right."

---

## Why Claude Code Can Do This But BioMate Can't

Claude Code has:
- `Bash` tool — runs arbitrary shell commands
- `Read` tool — reads any file
- `Write` tool — writes files
- No "NEVER compute" rule
- Intent understood from context without forced question-asking

BioMate needs its own equivalent:
- `code_run` tool — executes Python/R in a sandbox
- `file_read` tool — reads uploaded Galaxy datasets
- Relaxed computation rule
- Tier-1 intent path that bypasses workflow dispatch

---

## Risks and Mitigations

| Risk | Mitigation |
|---|---|
| Claude fabricates biological results (e.g., made-up p-values) | Keep prohibition on *biological inference* without tools; allow scripting on uploaded data |
| Code execution security (arbitrary code in sandbox) | Docker container per session, no network access, read-only mounts except output dir, resource limits |
| User confused by two modes (code vs workflow) | Seamless UX — BioMate decides which mode; user sees only the result |
| Reproducibility (scripted result vs workflow) | Save generated code to session history; "Save as workflow" button |
| Long-running code (user submits expensive loop) | 30-second timeout; escalate to workflow for long tasks |

---

## Implementation Priority

**P0 — Prompt relaxation** (1 day): 
- Remove the hard "NEVER compute" prohibition
- Replace with the nuanced COMPUTATION RULE above
- No new infrastructure needed; immediately unlocks Claude's native abilities

**P1 — Inline code executor** (1 week):
- `POST /api/code/run` endpoint with Docker sandbox
- Wire into chat as a tool Claude can call
- Support Python (pandas, scipy, biopython, numpy) + bash

**P2 — Intent tier classifier** (2 days):
- `_classifyIntentTier()` using Haiku
- Hybrid flow: Tier 1 preprocessing → Tier 2 dispatch
- "Pilot run" pattern: subset data, run workflow, report if worth scaling up

**P3 — Code Canvas UI** (1 week):
- Chat message variant that shows generated code + output side by side
- "Edit & re-run" button
- "Save as step in workflow" to promote ad-hoc code into a repeatable step

---

## Related: What BioMate Already Has That Helps

1. **Galaxy Python/R script tool** — runs arbitrary scripts via Galaxy job system (slower, but exists)
2. **Interactive tools** (JupyterHub, RStudio) — full interactive environment; can be pre-loaded with user data
3. **`/api/cryo_em/context`** — example of domain knowledge being served dynamically rather than baked into prompts
4. **Research agent** — already uses Haiku for sub-tasks without constraining the main response
5. **`buildDomainSpecialistBlock()`** — already injects contextual knowledge; same pattern works for code scaffolding

The infrastructure for Tier 1 exists in fragments. The main blocker is the prompt rule and the missing `code_run` endpoint.
