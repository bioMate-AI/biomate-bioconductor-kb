# SFT Data-Sourcing Plan — real resources first, build our own only where needed (2026-09-26)

**Policy (per task, in priority order):** (a) adopt existing **gold-labeled public datasets**; (b) mine our
**own real artifacts** (Claude Code logs, run/CI logs, workflow DAGs, KG); (c) **targeted synthetic** only
where no source exists (N1–N4). **Retire teacher-distilled doc-summaries** for the QA tasks — the committee
showed they're low-value and hallucination-prone (e.g. the `rtracklayer→marraylm` fabrication).

## Per-task sourcing map

| Task | Public gold datasets to adopt | Our own real artifacts | Synthetic |
|---|---|---|---|
| knowledge_recall / scientific_qa | **PubMedQA, BioASQ, MedMCQA, MedQA, SciQ, MMLU(bio/med)** | PubMed corpus + **PrimeKG-grounded QA** (built) | — |
| task_decomposition | ToolBench / TaskBench / AgentInstruct (structure) | **Claude Code logs (8,428 mined)** + workflow DAGs (bio gold) | — |
| workflow_routing / tool_recommendation | Gorilla, ToolLLM/ToolBench (tool-select format) | workflow DB + accept-sets (gold) | — |
| parameter_extraction | Schema-Guided Dialogue (SGD), MultiWOZ (slot-fill) | workflow param schemas (gold) | — |
| clarification_request | ClariQ, abg-CoQA | under-specified request logs | small |
| log_diagnosis / autofix_repair | SWE-bench-style (structure) | **real run/CI logs** (not the leaked CI-metadata) | small |
| findings_interpretation | (limited public for omics) | real run outputs + reports | small |
| N1 out_of_catalog_composition | (none) | WKG + composition | yes, w/ graph-valid + abstention checks |
| N2 lane_arbitration / N3 design_constraint / N4 model_selection | (none) | BioMate config/design | yes, structured w/ programmatic checks |

## Findings this session

- **Claude Code logs — USABLE, mined.** 5,467 transcripts / 2.6 GB. **No TodoWrite/ExitPlanMode exist**
  (0 across all files) — plans aren't stored explicitly. The usable signal is **(user narrative → the
  assistant's opening interpretation/plan text)**; `mine_claude_logs.py` extracts it → **8,428 examples
  (5,356 unique)**, in the user's own assignment style. Caveats: **coding/BioMate-dev domain** (teaches
  decomposition *structure*, not bio content) and natural planning prose (some conversational preamble) —
  best used for structure + paired with **workflow-DAG decompositions** (bio gold) and public planning sets.
- **KG→SFT reasoning (built, smoke-verified):** PrimeKG facts → grounded scientific_qa + multi-hop
  kg_reasoning, **hallucination-free** (facts are ground truth). Fixes the committee's weak-reasoning +
  teacher-hallucination findings.

## Build order (highest leverage first)

1. ✅ Claude Code decomposition miner (8,428 examples) — done, local; push to S3.
2. **Adopt biomedical QA gold** (PubMedQA/BioASQ/MedMCQA/MedQA/MMLU-bio) → convert to SFT `scientific_qa`/
   `knowledge_recall`; **replace** the teacher-distilled doc-summary slice. [next]
3. KG→SFT reasoning generation (`kg_sft_gen.py`, ready) — grounded scientific_qa + kg_reasoning.
4. Workflow-DAG → `task_decomposition` (goal→ordered steps, bio gold) from the workflow DB.
5. Tool-use / slot-fill / clarification public sets for routing/param/clarification *format*.
6. Real run/CI logs → log_diagnosis/autofix (replacing the CI-metadata-leaked rows).

## Honesty / caveats
- Public-dataset licenses to confirm at productization (research use is fine now).
- Claude-logs are coding-domain; weight accordingly, don't over-rely for bio decomposition.
- All adopted datasets get the same family-disjoint split discipline + gold (not teacher-fidelity) scoring.
