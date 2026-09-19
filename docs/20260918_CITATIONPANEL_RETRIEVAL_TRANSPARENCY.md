# CitationPanel retrieval transparency + source conflicts in the live chat answer

Date: 2026-09-18
Branch: `citationpanel-retrieval`

## What changed

The live chat research answer now renders the rich `CitationPanel` (instead of the
lean References list), and surfaces two honest-empty affordances driven by REAL
backend state:

1. **"How this was searched"** — per-source `found`/`kept` retrieval transparency.
2. **"Sources disagree"** — source conflicts, only when the synthesis step
   genuinely reported disagreeing sources.

Both render ONLY when the backend supplies real data; otherwise the panel degrades
to a plain source list. Nothing is fabricated or inferred from the citation list.

## Real signals used (honesty statement)

### `retrieval` (found / kept) — REAL, computed from source-tagged pool
- Every retrieved paper is a `LiteratureCitation` carrying a real `.source`
  (`pubmed`, `europepmc`, `semantic_scholar`, `openalex`, …) set by the federated
  query fan-out (`federated_query._merge_results` → `_federated_item_to_citation`).
- In `_synthesize_response` we now compute, per source:
  - `found` = count of that source's papers in the merged/deduped candidate pool
    that was actually injected into the synthesis prompt (`evidence['citations']`).
  - `kept`  = how many of those the answer actually cites (the grounded pool from
    `_ground_citations`, matched by object identity — not by re-deriving from the
    final citation list).
- Papers with no `.source` tag are skipped (never given an invented label). If the
  pool has no source tags at all, `retrieval` is `[]` (honest-empty).

### `conflicts` — REAL when present, deliberately empty otherwise
There was no pre-existing conflict signal in the agent. Rather than invent one, I
extended the **synthesis prompt** (`_CONFLICT_INSTRUCTION`, appended to both the
normal and evidence-review instruction blocks) to ask the model to emit, ONLY when
two or more of the numbered Retrieved Literature sources materially disagree on the
same point, a machine-parseable block:

```
<<<CONFLICTS_JSON>>> [{"topic": "...", "positions": [{"claim":"...","source":"..."}, ...]}]
```

`_parse_conflicts_block` extracts and strips that block from the displayed answer,
validates it (each conflict needs ≥2 positions each with a non-empty claim), and
returns `[]` when the model emitted no marker / an empty block / malformed JSON.
The model is explicitly told: silence = no conflict; never manufacture one. So
`conflicts` is genuinely empty unless the synthesis step reported a real
disagreement — no client-side or heuristic fabrication.

## Files changed

Backend:
- `backend/lib/galaxy/ai/agents/research_agent.py`
  - `_CONFLICT_MARKER` / `_CONFLICT_INSTRUCTION` module constants (after `log`).
  - `ResearchResponse`: added `retrieval` + `conflicts` fields.
  - `_source_display_name`, `_compute_retrieval_stats`, `_parse_conflicts_block`.
  - `_synthesize_response`: parse conflicts before grounding; compute retrieval
    stats from pool + grounded pool; attach both to the response.
  - `_build_synthesis_prompt`: append `_CONFLICT_INSTRUCTION` to both instruction
    modes.
- `backend/lib/galaxy/webapps/galaxy/api/ai_assistant.py`
  - `research_query` endpoint: emit `retrieval` / `conflicts` only when non-empty.

Frontend (pass-through requires NO Node.js changes — `queryResearch` returns the
full research_query JSON verbatim as `researchResponse`, which the client sets as
`metadata.research_response`):
- `frontend/client/src/components/benchmark-evidence.tsx`
  - `ResearchResponseData`: optional `retrieval` + `conflicts` typed fields.
  - `toEvidenceCitations()` maps `ResearchCitation` → `EvidenceCitation`
    (tool_name := title, tool_id := doi>pmid>index; formatted_* left empty).
  - `ResearchResponseDisplay`: rich `CitationPanel` replaces the lean References
    card, fed citations + retrieval + conflicts + answerText. Boundary and
    Save/Check-against-data exits kept intact.
- `frontend/client/src/components/citation-panel.tsx`
  - Top-level "Export BibTeX" button now hidden unless a workflow is present or a
    citation carries `formatted_bibtex` — literature answers have neither, so no
    dead button that would emit an empty file. (Per-item BibTeX button was already
    disabled without `formatted_bibtex`.)

## Tests

- `frontend/client/src/components/chat-message.research-citation-panel.test.tsx` (new)
  - renders retrieval transparency ("2 of 28 kept") + a conflict row when the
    response supplies them;
  - renders neither (no crash), source list + boundary intact, when absent;
  - empty `retrieval: []` / `conflicts: []` → no section (no fabrication).

## Verification

- `python3.9 -m py_compile` on both changed backend files: OK.
- `npx tsc --noEmit -p .` (cwd=frontend): clean.
- `npx vitest run`: 128 files / 1580 tests pass, 2 files / 7 tests skipped.

## Notes / known gaps

- Conflict detection relies on the synthesis LLM honestly reporting disagreements.
  When the model reports none, the section is genuinely empty by design.
- Full backend module import fails locally (missing `beaker` dep — env gap);
  py_compile is the syntax gate used here.
