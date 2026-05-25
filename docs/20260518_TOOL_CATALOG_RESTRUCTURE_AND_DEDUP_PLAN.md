# Tool Catalog Restructure: Tools vs Functions vs Wrappers

**Date:** 2026-05-18
**Status:** Plan — prototype to be built in `sandbox/retrieval_v2/` (no production touches)
**Related docs:** `20260518_RETRIEVAL_TOOLS_PRODUCTIZATION_AND_USE_CASES.md`, `20260516_AUDIT_BENCHMARK_VS_PRODUCTION_GAP.md`

## The core insight

`backend/database/galaxy_ai_tools.db` is described as "12,274 indexed tools" but the data shows otherwise:

```
SELECT COUNT(DISTINCT tool_id), COUNT(DISTINCT name), COUNT(*) FROM tools;
→ 12274 | 11442 | 12274
```

- `tool_id` is the Galaxy wrapper path including version, e.g. `toolshed.g2.bx.psu.edu/repos/iuc/deseq2/deseq2/2.11.40.8+galaxy0`.
- `name` is the wrapper's display name.
- **There is no grouping.** A search for "DESeq2" returns 5 separate rows from different wrapper authors (mvdbeek, mingchen0919, iuc) — all wrapping the same R package but appearing unrelated. A search for "star" returns `ctat_star_fusion` (RNA fusion caller), `staramr` (AMR database tool), and `aurora_star` (Aurora workflow plugin) — three different tools that share a substring.

**The DB is a flat catalog of wrappers, not a hierarchy of tools and their functions.**

This explains several persistent BioMate pain points:
- Routing benchmark plateau ~80%. The LLM has to disambiguate ~10 wrappers per substring match on every query.
- Disambiguation cards fire constantly even for unambiguous requests like "DESeq2 differential expression" — the DB has 5 candidate wrappers, the LLM legitimately can't pick.
- Auto-loop remediation suggestions like "swap STAR for HISAT2" are hard to express because "STAR" is not a row in the DB; it's the family that 10 different wrapper rows are about.
- Context cost: routing prompt has to inline candidate tool descriptions; the more candidates, the higher the token bill per turn.

## Proposed architecture: 3-level hierarchy

```
Tool Family                     ~500-1000 canonical tools
  ↓
  Function                       e.g. "differential_expression"
    ↓
    Wrapper (the 12K rows)       e.g. iuc/deseq2 v2.11.40.8+galaxy0
```

**Tool family** = the semantic identity scientists use. "DESeq2", "STAR aligner", "BWA-MEM", "GROMACS", "AlphaFold". Each has a canonical home page, citation, maintainer.

**Function** = the verb. DESeq2 has functions like `differential_expression`, `vst_normalization`, `dispersion_estimates`, each of which is a distinct LLM-callable operation.

**Wrapper** = the platform-specific deployment. The same (DESeq2, differential_expression) pair has wrappers for Galaxy (multiple author variants), nf-core/differentialabundance, plain Nextflow modules.

## LLM workflow under the new architecture

1. **Tool selection** (small space, ~500-1000 entries): "RNA-seq DE → {STAR | HISAT2 | Salmon}, {DESeq2 | edgeR | limma}." LLM picks from canonical names it already knows; fits comfortably in a single prompt.
2. **Function selection per tool**: "For DESeq2, I need `differential_expression`, not `vst` or `dispersion_estimates`."
3. **Wrapper resolution** (deterministic): map (tool_family, function, platform_preference) → specific wrapper row from the 12K. No LLM judgment needed if the mapping is curated.
4. **Param fill + chain → workflow** (as today).

Why this wins beyond just "fewer rows":
- Context budget drops 10–25× for the routing turn.
- Disambiguation becomes "did you want STAR or HISAT2?" instead of "did you want iuc/star vs aurora/star vs ctat/star_fusion vs staramr?"
- Auto-loop remediation reads naturally: "swap STAR for HISAT2" is a single tool-family edit.
- Cross-platform: nf-core, Galaxy, custom Nextflow all map to the same `(tool_family, function)` keys → user can prefer "open-source nf-core" or "Galaxy wrapper" via a single preference.

## Should we deduplicate the DB first?

**Short answer: yes, but as analysis, not as deletion.**

Pure deletion-based dedup loses information — different wrappers genuinely have different parameter UIs, version pins, container images, and may be needed by different users. We should not collapse rows.

**Better sequence:**

### Phase 0 — Dedup analysis (1 day)

Goal: quantify how much redundancy actually exists. Inputs to the canonical-tools design.

Signals to cluster on:
- `tool_id` path regex: `repos/<owner>/<package>/<tool>/<version>` — the `<tool>` segment groups wrapper-author variants of the same tool.
- `name` normalized (lowercase, strip versions).
- `edam_operations` + `edam_topics` — canonical ontology tags already in the data.
- BGE embeddings on `name + description` (already computed at `database/galaxy_ai_workflow_embeddings.npz`).

Output: a single CSV / JSON describing every cluster of size ≥ 2, with member tool_ids and a confidence score. This tells us:
- How many true duplicates? (estimate based on a quick grep: at least 200 "DESeq2"-named rows, hundreds of "STAR"-related rows.)
- How sharp are the boundaries? (mvdbeek's DESeq2 wrapper is the same tool as iuc's; aurora_star is NOT the same tool as ctat_star_fusion.)
- What's the size of the canonical tool space? (Probably 500-1000 — the analysis answers this concretely.)

### Phase 1 — Canonical schema (1-2 days)

Add two NEW tables alongside the existing one (no schema-breaking changes):

```sql
CREATE TABLE tool_families (
  family_id        TEXT PRIMARY KEY,           -- e.g. "deseq2", "star_aligner"
  display_name     TEXT NOT NULL,              -- "DESeq2"
  description      TEXT,                       -- canonical short description
  citation         TEXT,                       -- canonical citation
  edam_operation   TEXT,                       -- top EDAM op
  category         TEXT,                       -- "RNA", "Sequence Analysis", ...
  homepage_url     TEXT
);

CREATE TABLE tool_functions (
  function_id      TEXT,                       -- e.g. "differential_expression"
  family_id        TEXT REFERENCES tool_families(family_id),
  display_name     TEXT,                       -- "Differential expression analysis"
  description      TEXT,
  typical_inputs   TEXT,                       -- JSON
  typical_outputs  TEXT,                       -- JSON
  PRIMARY KEY (family_id, function_id)
);

CREATE TABLE tool_wrapper_mapping (
  wrapper_tool_id  TEXT PRIMARY KEY REFERENCES tools(tool_id),
  family_id        TEXT REFERENCES tool_families(family_id),
  function_id      TEXT,
  platform         TEXT,                        -- "galaxy" | "nfcore" | "biomate"
  is_primary       BOOLEAN DEFAULT 0,           -- one preferred wrapper per (family, function, platform)
  confidence       REAL                          -- clustering confidence 0-1
);
```

The 12,274 existing `tools` rows stay untouched — they get pointed at by `tool_wrapper_mapping`. Backward compatible.

### Phase 2 — Tier-0 retriever tools (2 days)

New retriever tools layered on top of canonical schema, exposed via the tool-use plan in the productization doc:

```
search_tool_families(query, category?)  → list[tool_family]
list_functions(family_id)               → list[tool_function]
resolve_wrapper(family_id, function_id, platform?) → wrapper_tool_id
```

Existing `search_workflows` (flat search) stays as fallback.

### Phase 3 — A/B routing benchmark (1 day)

Measure on existing routing benchmark (120 cases):
- Baseline: current flat search + LLM disambiguation
- Treatment: Tier-0 canonical search → Tier-1 wrapper resolution

Expected: routing accuracy 80% → 88-92%; mean candidate set per turn 10 → 3.

## Total scope: ~5 days, fully sandboxed

All Phase 0/1/2 prototyping happens in `sandbox/retrieval_v2/` (mirroring `frontend/research_agent_v2/` pattern). No production schema changes, no production code touches. New canonical DB is a separate SQLite file. The user reviews the cluster output and the routing benchmark numbers before any production integration is proposed.

## Open questions for the user

1. **Tool family granularity.** "STAR" and "STAR-Fusion" — same family or different? They share a core algorithm but have different scientific intent. Suggest: different families, with a `related_to` link in `tool_families`.
2. **Function naming.** Use EDAM operations where available (machine-readable, ontology-grounded), free-text where not?
3. **Maintenance.** As new wrappers are added (Galaxy toolshed updates, new nf-core releases), how are they assigned to families? Suggest: auto-cluster on ingest + flag low-confidence assignments for review.
4. **Galaxy vs nf-core preference.** Per-user setting? Per-task heuristic? Or always present both choices to the LLM?

## Open architectural issues flagged (not in this lane)

While auditing the codebase for this plan I noticed two production-blocking issues that belong to the LLM-fallback session, not this one. Flagging here so they don't get lost:

1. **Unresolved merge conflict in `backend/lib/galaxy/ai/llm_client.py` lines 178-261.** The file currently fails to import with a `SyntaxError` because the conflict markers (`<<<<<<< Updated upstream`, `=======`, `>>>>>>> Stashed changes`) are still in the source. This would break the entire AI assistant on this machine if anyone tried to run the backend locally.
2. **Hardcoded Mac path in `llm_client_fallback_implementation.py:58`** — `config_path: str = '/Users/kky/biomate/backend/config/llm_providers.yml'`. On Linux (dev-public EC2, this dev box, any Docker container) the YAML never loads and the system silently falls back to hardcoded defaults. The `temperature: 0` change in `llm_providers.yml` has no effect anywhere except Mac until this path is fixed.

Both should be addressed by whoever owns the fallback work.
