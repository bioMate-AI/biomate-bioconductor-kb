# intent_interpretation (RealBio)

Classify a BioMate user request into one **capability intent** (label-constrained). 12 labels mapped to
BioMate's tool surface: route_and_run_workflow, extract_parameters, decompose_multi_step,
fetch_public_data, resolve_accession, analyze_results, explain_error, search_literature,
get_workflow_spec, run_instrument_protocol, browse_or_preview_data, export_report.

- **Data:** `data.jsonl` — `{id, query, intent}`.
- **Predict:** `run_baseline.py intent_interpretation --model <m>` → one label per query.
- **Score:** `score.py intent_interpretation results/<m>/intent_interpretation.jsonl` → accuracy + Wilson CI.
