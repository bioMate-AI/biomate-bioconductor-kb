# Domain Knowledge Architecture — Verified Audit

**Date**: 2026-04-04  
**Replaces**: 20260404_DOMAIN_KNOWLEDGE_INTEGRATION_DESIGN.md (contained incorrect claims)

---

## Corrections to Previous Claims

### Claim 1: "Expert knowledge JSON files not connected to LLM" — WRONG

The JSON files ARE indexed in the DB and ARE used:
- `inject_expert_knowledge.py` loads all 7 JSON files and inserts into `tool_knowledge` table
- 151/4,117 tools (3.7%) have `_expert_guidance` injected
- 2,376/4,117 tools (57.7%) have some `recommended_parameters`
- `tool_knowledge_provider.py` queries the DB during workflow generation
- `ai_assistant.py` builds `parameter_hints` (up to 8 per workflow) and returns them in the response
- `nextflow-workflow-viewer.tsx` receives and displays these hints in the parameter panel

### Claim 2: "QC profiles never auto-selected" — WRONG

QC profiles ARE auto-selected via `infer_qc_profile()` in `qc_trace_monitor.py`:
- Called in `nextflow_executor.py` (line 2113) whenever no explicit profile is provided
- Keyword matching against the Nextflow workflow path string
- Two-layer: path keywords (e.g., `rnaseq`, `cryosparc`) → domain sub-type refinement in `ai_assistant._infer_qc_profile()`
- Covers: cryo-EM (4 sub-profiles), WGS germline/somatic, WES, RNA-seq (4 variants), scRNA-seq, proteomics, metagenomics

---

## What is Actually True

### Expert knowledge — the real gap

The expert JSON structure is:
```json
"gene_set_size_min": {
  "situations": {
    "default_recommended": { "value_or_range": "15", "when": "...", "why": "...", "source": "..." },
    "sparse_transcriptome":  { "value_or_range": "5",  "when": "scRNA-seq", ... }
  }
}
```

This context-branching "when/why/source" logic **does not survive DB injection**. The `_expert_guidance` field is empty for most tools in the DB (`SELECT json_extract(recommended_parameters, '$._expert_guidance') FROM tool_knowledge WHERE tool_name LIKE '%deseq%'` returns empty). The injection collapses the rich situations structure to flat `recommended_value + description`.

The result: `ParameterRecommendation` objects (in tool_knowledge_provider.py) have:
- `recommended_value` — a single value, not context-dependent
- `description` — a string, not branching when/why logic

Parameter hints shown in the frontend are informational ("STAR: twopassMode=Basic") but:
1. Do not branch by experimental context (sparse vs dense transcriptome)
2. Do not auto-populate parameter values (user must still fill required params)
3. Parameters for Nextflow workflows come from parsing the `.nf` file directly, not from tool_knowledge

### QC profile selection — the real gap

Auto-selection works well for named workflows where the path contains keywords (`rnaseq`, `cryosparc`, `tumor_normal`). The genuine limitation: if a user says in chat "my sample is from FFPE-preserved cardiac tissue with ribodepletion", this context does NOT influence QC profile selection — only the workflow path string is used. The `rnaseq_ffpe` and `scrna_cardiac` profiles exist but require the path to contain `ffpe` or the biology context to flow through differently.

---

## Verified Architecture Summary

```
Expert knowledge JSONs (750 KB)
  → inject_expert_knowledge.py
  → tool_knowledge DB table (151 tools with _expert_guidance, situations collapsed to flat values)
  → tool_knowledge_provider.py (reads DB, returns ParameterRecommendation)
  → ai_assistant.py _build_scientific_rationale() (builds parameter_hints, max 8)
  → API response scientific_rationale.parameter_hints
  → nextflow-workflow-viewer.tsx (displays as "TOOL: param=value" rationale text)
  ✗ NOT used to set parameter values
  ✗ Situations/context logic not preserved

QC profiles (40+)
  → nextflow_executor.py (calls infer_qc_profile on every execution)
  → qc_trace_monitor.infer_qc_profile() (keyword match on workflow path)
  → ai_assistant._infer_qc_profile() (domain sub-type refinement)
  → applied automatically, user can override
  ✗ Chat-expressed context (sample biology, tissue, preservation) not used for selection
```

---

## Genuine Remaining Gaps

### Gap 1: Situations logic not reaching the LLM

The expert JSONs contain the richest knowledge asset in BioMate — context-branching parameter guidance with literature citations per situation. This logic is lost at DB injection. It could be:
- Preserved in DB as a separate `situations` JSON column
- Queried at workflow generation time with user context as the selection key
- Used to auto-populate parameter values, not just display hints

### Gap 2: Parameter hints are display-only, not value-setting

`parameter_hints` inform but don't act. When the LLM knows `gene_set_size_min=5` for scRNA-seq, this should be reflected in the generated parameter's default value, not just shown as a sidebar hint. The Nextflow path (`_parse_nextflow_params`) reads `.nf` file defaults; expert knowledge could augment or override those defaults based on user context.

### Gap 3: QC profile selection doesn't use chat context

The profile inference uses workflow path keywords. If the user says "my data is from FFPE tissue" in the chat, the frontend's intent classifier detects RNA-seq domain but the FFPE sub-profile is not triggered. Connecting the chat-extracted sample context to profile inference would close this gap.

### Gap 4: 3.7% expert guidance coverage

151/4,117 tools have expert guidance injected. The other 96.3% rely on tool schema defaults only. This is a content gap (more tools need to be covered), not an architecture gap.
