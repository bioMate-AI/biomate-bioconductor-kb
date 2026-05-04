# Intent Classification + BOIN Benchmark: 100% (2026-05-01)

## Results
- BOIN v14: **100%** (complete 100%, incomplete 100%, neg-ctrl 100%)
- PBPK v7: 100% routing, 100% prereq, 0.90 param F1
- Previous best BOIN: 79% (v12)

## Root causes fixed
1. **Intent misclassification**: Gemini classifier lacked knowledge of drug_discovery/cryo_em/pharmacology workflows. Added full domain catalog with representative workflow names per domain.
2. **Prompt truncation**: Intent classifier prompt grew to ~9K tokens; Gemini was hitting `max_tokens=2500` and truncating JSON. Fixed by raising to `max_tokens=4096`.
3. **workflow_generation definition**: LLM didn't know BioMate has BOIN/PBPK/ADMET workflows since they don't use FASTQ files. Added explicit parameter-driven workflow examples.
4. **run_code architecture**: Direct code execution is now part of `workflow_generation` (with `needsWorkflowGeneration: false`). `isResearchIntent` now checks `!isWorkflowTurn` so code execution tasks get the compute-enabled prompt.

## Key code changes (galaxy-assistant.ts)
- Line 4651: `isWorkflowTurn` moved before `isResearchIntent` calculation
- Line 4662: `isResearchIntent` now includes `|| !isWorkflowTurn`
- Line 4703: "can compute" instruction uses `isWorkflowTurn` (not `RESEARCH_INTENT_TYPES_FOR_PROMPT`)
- Line 2924: `workflow_generation` definition covers both Nextflow and run_code paths
- Line 2964: Domain catalog replaced with representative workflow names per domain
- Line 3012+: Drug discovery section condensed but complete; cryo-EM section condensed
- Lines 3831, 3874, 4819, 4831: `max_tokens` raised 2500→4096 for intent classifier

## Architecture clarification
- `workflow_generation` + `needsWorkflowGeneration: true` → call generateWorkflow() → Nextflow panel
- `workflow_generation` + `needsWorkflowGeneration: false` → skip generateWorkflow() → LLM uses run_code
- Both are execution tasks; the distinction is BioMate's internal routing, not user intent
- Non-execution intents (experiment_design, troubleshooting, data_interpretation, etc.) preserved
