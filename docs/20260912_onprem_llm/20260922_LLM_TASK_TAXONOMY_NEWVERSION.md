# BioMate LLM task taxonomy — re-examined for the current/new version (2026-09-22)

Re-derived from **live call-sites** (frontend `galaxy-assistant.ts` = live production chat; backend
`ai_assistant.py` = parallel/older), the **new-version design** (`reference/claude_design/
data_centroid_design_v2/spec/00–13`), the **v3 composition plan**, and the **live model map**.

## Headline
- **T01–T28 is still ~90% accurate as a task INVENTORY** — every catalog task still has live or secondary
  code. The data-centric / de-Galaxy move **reorganizes the surface** (4 user modules + a 2-lane
  Instant/Cloud model), it does **not delete** the underlying LLM tasks.
- **The new tracks — Models/Train, Design & Generate, pre-trained inference — are EXECUTION BACKENDS,
  not new LLM tasks.** They're reached by the *existing* intent→routing LLM, then run deterministic
  compute: `bionemo_client.py` (NIMs), `drug_discovery/generators.py` (REINVENT), `data_perception.py`
  ("NO LLM", l.20), `federated_query.py`, `chain_planner.py` (BFS), `org_rule_compiler.py` (edit mining).
- **Live model routing:** intent=gemini-3.5-flash, tool-ranking=claude-haiku-4-5, response=gemini-3.5-flash;
  backend fallback gemini-3.1-pro→gemini-3.5-flash→claude-sonnet-4-5→gpt-4o→**qwen3:32b**.

## Genuinely NEW LLM tasks (N1–N8) — the real re-targeting
| ID | task | status | note |
|---|---|---|---|
| **N1** | **Compositional out-of-catalog generation** (phases→steps→blocks from WKG, abstention) | **NEW P0, flagship** | = the removal-eval task we've been on; eval harness + measured gap exist; not yet a live chat route |
| **N2** | **Lane arbitration verdict** (Instant-cited / Instant-compute / Cloud-workflow / Cloud-design / Cloud-models + why) | **NEW P0 (design)** | implicit in T01 today; design promotes to explicit user-facing verdict |
| **N3** | **Design-intent / generate-request interpretation** (goal → stage + constraints: target/scaffold/property-envelope/count) | **NEW P0 (design)** | routes via reinvent4 today; dedicated constraint extractor is new |
| **N4** | **Pre-trained model / NIM selection + applicability/confidence** | **NEW secondary** | inference is non-LLM; the *selection + trust narration* is the new surface |
| N5 | ML-training intent→config (Train track) | **gated OFF** | `ML_TRAINING_ROUTING` off; `llm_fill` not wired — deprioritize |
| N6 | Multi-omics integration routing | **gated OFF** | `MULTIOMICS_ROUTING` off — deprioritize |
| N7 | Learned-rule adaptation (Adapt) | **shipped** | deterministic extractor + **T22 per-org LoRA** consumer (the real fine-tuning-on-user-edits path) |
| N8 | Cryo-EM knowledge RAG | mostly non-LLM | Anthropic-embed = NotImplementedError → TF-IDF fallback |

(Full reconciliation T01–T28→code with file:line: agent transcript / this session.)

## Decision for training-data targeting
1. **Keep the core T-tasks** — our corpus (routing T05, param T06, decompose T01/T09, autofix T19,
   wfgen T08, clarification T03, diagnosis T18, knowledge T12/T14, chaining T09, dataset-compat T07) is
   aimed at REAL, live tasks. Valid.
2. **ADD the new high-value LLM tasks: N1–N4.** N1 (out-of-catalog composition) is the flagship and we
   already have its eval + composition_sft; N2 (lane arbitration) and N3 (design-constraint extraction)
   are partly live inside T01/T02 and worth explicit training targets; N4 (model-selection narration) secondary.
3. **Do NOT allocate training volume to compute backends** — NIMs, REINVENT generators, data_perception,
   ml_training executors are non-LLM; they're *routed to*, not *performed by*, the model.
4. **Deprioritize N5/N6** (flag-gated OFF, rules-only at call-site — no live LLM traffic).
5. **T22 per-org LoRA is the live "Adapt" track** — the one place fine-tuning on user edits already ships.
6. **Target the LIVE path** (frontend `galaxy-assistant.ts` prompts + the gemini/haiku model roles),
   not the older backend orchestrator, when matching production prompt format.
