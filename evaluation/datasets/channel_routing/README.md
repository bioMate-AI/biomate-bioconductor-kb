# channel_routing — the "which resource/channel" routing benchmark

Measures BioMate's **stage-1 routing decision**: given a user request, which *destination channel* should it
go to? This is the decision the `cross_domain_routing` benchmark does **not** test — that one assumes the
request needs a pipeline and only measures *which workflow*. Real BioMate routes among many resources first.

## Why this exists
Per project policy, a benchmark's job is to **improve BioMate's practical functions** and to **compare LLMs
(bare vs +harness)** so we can see each model's pros/cons and optimize the harness + the on-prem LLM. Channel
routing is a live BioMate capability (`frontend/server/galaxy-assistant.ts` intent classifier →
`ActionCategories`) that had no objective eval. This closes that gap.

## The 7 channels (gold labels) — 1:1 with production `ActionCategories`
| channel | production mapping | what it means |
|---|---|---|
| `workflow` | needsWorkflowGeneration | run a multi-step pipeline (ADMET, docking, RBFE, PBPK, QSAR, RNA-seq, …) |
| `tool_search` | needsToolSearch | find / recommend / compare / modify a specific tool or method |
| `database_lookup` | needsResearchAgent (DB) | live query to a structured DB (ChEMBL, DrugBank, Open Targets, PDB, UniProt, OMIM, ClinVar, FAERS) |
| `literature_research` | needsResearchAgent (literature) | synthesize published evidence (SOTA, mechanism, prior art, best practice) |
| `code_execution` | run_code / ad-hoc | short ad-hoc computation on provided/small data (similarity, stats test, format conversion, small fit) |
| `knowledge_answer` | needsLLMReasoning only | direct factual/conceptual answer from the model's own knowledge; no tool |
| `dataset_discovery` | needsDatasetAccess | find/fetch an existing dataset or accession (PDBbind, TDC, GEO/SRA/PRIDE, internal test data) |

## Composition
84 items, **12 per channel** (balanced), **64% drug-development** (ADMET/docking/PBPK/QSAR/FEP/target-ID/CRO
spanning every channel), the rest cross-domain (transcriptomics, variant, single-cell, proteomics, genomics,
clinical, metagenomics, immunology) for breadth. `acceptable_alts` credit genuinely ambiguous items (e.g. a
"modify my docking workflow" request accepts `tool_search` or `workflow`).

## Always report BOTH conditions (bare vs +harness)
`run_channel_routing.py` runs every model twice and reports both, per model:
- **BARE** — query + the 7 channel *names only* (the raw LLM's own routing judgment).
- **+HARNESS** — query + the 7 channel names *with BioMate's production definitions* (`channels.json`).

The **bare→harness dividend** shows how much BioMate's channel definitions buy for each model — the signal for
optimizing the harness and for deciding what the on-prem LLM can/can't route unaided. Empties-aware
(max_tokens budgeted past reasoning tokens, retry, low concurrency) so reasoning models don't score fake 0s.

## Run / score
```
OPENROUTER_API_KEY=... python3 run_channel_routing.py --models qwen/qwen3.5-9b,anthropic/claude-opus-5,...
python3 score.py results/<model>/channel_routing_harness.jsonl   # overall + per-channel + drug-dev subset + confusions
```

## Scoring
Exact channel match (gold or an `acceptable_alt`), reported as overall accuracy, per-channel recall, the
**drug-discovery-subset** accuracy (the product-critical slice), and a confusion summary of where mis-routes
go (e.g. database_lookup↔literature_research is the expected hard pair). Objective; no LLM judge.
