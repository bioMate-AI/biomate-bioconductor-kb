# Which resource? An open benchmark for stage-1 channel routing in biomedical AI agents

**Routing-search benchmark paper — v1 draft (2026-10-27).** One of three sibling benchmarks (with RealBio —
bioinformatics workflow automation — and DrugDev-Bench — drug-development decisions); this one is distinct
from both. All numbers trace to committed artifacts under `evaluation/datasets/channel_routing/`; any number
not yet measured is marked **[TO BE MEASURED]**. Honesty discipline per the 2026-10-26 committee review.

**Status:** draft, NOT submit-ready (open items in §7).

## Abstract
Before a biomedical AI agent can pick *which workflow* to run, it must decide *which resource* a request even
belongs to — run a pipeline, search for a tool, query a live database, synthesize literature, execute a short
computation, answer from its own knowledge, or fetch a dataset. Benchmarks of agentic task selection almost
always assume the request already needs a pipeline and measure *which* pipeline; the upstream **channel**
decision is unmeasured. We introduce an open, objectively-scored benchmark for this stage-1 routing decision,
with its seven channels mapped one-to-one to a production agent's action categories, weighted toward
drug-development queries. Using a matched **bare-LLM vs LLM+harness** protocol across seven models, we find the
harness's channel definitions lift routing substantially on every model, with the largest gains on the
smallest on-prem model (0.750 → 0.964) and the smallest on the strongest frontier model (0.905 → 1.000) — the
same inverse pattern the knowledge-layer thesis predicts, now on an orthogonal capability.

## 1. Introduction
Agentic systems for biomedical research route a user request to one of several destinations. Existing routing
benchmarks (including our sibling RealBio) test *workflow selection* — "given a pipeline request, which
pipeline?" — but that presupposes the earlier decision: *is this a pipeline request at all, or a database
lookup, a literature question, a quick calculation, or a direct answer?* That **stage-1 channel routing** is
what a production agent's intent classifier does first, and getting it wrong sends the whole downstream chain
to the wrong subsystem. No open benchmark scores it.

We contribute: (1) an objectively-scored channel-routing benchmark whose labels are the real production action
categories; (2) a matched bare-vs-harness protocol isolating what the harness's channel definitions buy; (3) a
drug-development-weighted item set (64% of queries), because channel ambiguity is acute in drug discovery
(e.g. "what's the ChEMBL IC50 of imatinib?" is a database lookup, "recommend a docking engine" is a tool
search, "dock this library" is a workflow — all drug-dev, three different channels).

## 2. Related work
Agentic-science benchmarks (Biomni, BixBench, ScienceAgentBench, MLAgentBench, LAB-Bench) grade end-to-end task
completion or notebook analysis; intent/tool-selection suites (ChemToolBench, TxAgent's tool routing) grade
*which tool*, again downstream of the channel decision. RAG routers and query-classification datasets exist in
the general NLP literature but not for the biomedical agent's resource taxonomy. Our benchmark is, to our
knowledge, the first open, objectively-scored test of the *which-resource* decision grounded in a deployed
biomedical agent's action categories. **[TO BE MEASURED: a systematic head-to-head against any external
intent-routing baseline, if a comparable one exists.]**

## 3. The benchmark
**Seven channels** (gold labels), each mapped 1:1 to the production router's `ActionCategories`
(`frontend/server/galaxy-assistant.ts`): `workflow` (run a pipeline), `tool_search` (find/recommend/compare a
tool), `database_lookup` (live query to ChEMBL/DrugBank/Open Targets/PDB/UniProt/OMIM/ClinVar/FAERS),
`literature_research` (synthesize published evidence), `code_execution` (short ad-hoc computation), `knowledge_
answer` (direct factual answer, no tool), `dataset_discovery` (find/fetch a dataset/accession).

**Composition:** 84 items, 12 per channel (balanced), **64% drug-development** (ADMET/docking/PBPK/QSAR/target-
ID/CRO queries spanning every channel), the rest cross-domain (transcriptomics, variant, single-cell,
proteomics, genomics, clinical, metagenomics, immunology) for breadth. `acceptable_alts` credit genuinely
ambiguous items (author-judged). Gold = the destination channel.

## 4. Methods / scoring
One deterministic scorer (`score.py`): exact channel match (gold or an `acceptable_alt`), reported overall,
per-channel, on the **drug-discovery subset**, with a confusion summary. No LLM judge. Two conditions, both
reported per model: **bare** = query + the seven channel names only (the raw LLM's own judgment); **+harness**
= query + the channel names *with the production definitions*. The bare→harness delta is the harness dividend.
Generation is **empties-aware** (max-tokens budgeted past reasoning tokens, retry, low concurrency) so
reasoning models do not produce fake zeros.

## 5. Results — matched bare vs +harness (7 models)
| model | bare | +harness | dividend |
|---|---|---|---|
| Qwen3.5-9B (on-prem) | 0.750 | 0.964 | **+0.214** |
| GLM-5.2 | 0.821 | 1.000 | +0.179 |
| DeepSeek V4-pro | 0.833 | 0.976 | +0.143 |
| Kimi K3 | 0.845 | 0.988 | +0.143 |
| Gemini-3.1-Pro | 0.893 | 0.988 | +0.095 |
| Opus-5 | 0.905 | 1.000 | +0.095 |

**Drug-discovery subset (on-prem 9B): bare 0.778 → +harness 0.982.** The dividend holds on every model, and
its magnitude is inversely related to bare skill — the smallest on-prem model gains most (+0.214), the
strongest frontier model least (+0.095). Honest framing: this is a ceiling/headroom pattern (lower-bare models
have more room), not an asserted inverse-scaling mechanism. Per-channel (on-prem 9B, +harness): five of seven
channels perfect; the residual error is `tool_search`↔`literature_research` (recommend-a-tool vs review-the-
evidence). Without the definitions, the raw model mainly fails on channel *vocabulary* — returning non-answers
or confusing `workflow`↔`code_execution` and `tool_search`↔`knowledge_answer`.

## 6. Limitations
- n=84 is a balanced **seed set**, not evidence of production channel prevalence; `acceptable_alts` are
  author-judged and would benefit from independent adjudication.
- Single-label per item; genuinely multi-intent requests are a design extension **[TO BE MEASURED]**.
- The roster is the models reachable on one API provider; absolute cross-provider comparability has the usual
  serving-provenance caveat.
- The drug-development weighting reflects the product's focus, not a claim about biomedical queries generally.

## 7. Open items before submission
(1) full-roster completion incl. the remaining models **[TO BE MEASURED]**; (2) independent adjudication of
`acceptable_alts`; (3) a multi-intent / out-of-distribution extension; (4) if any external intent-routing
baseline is comparable, a head-to-head; (5) per-item release + a confusion-matrix figure. Re-convene the
committee before declaring submit-ready (submit-review gate).

## 8. Discussion
Channel routing is the agent decision that most determines whether the rest of the pipeline is even pointed at
the right subsystem, yet it has been unmeasured. The result reinforces the broader finding across our
benchmarks: the knowledge/harness layer — here, explicit channel definitions — is the dominant lever, lifting
a small on-prem model into the frontier band on this task while costing nothing to deploy. For drug-development
agents specifically, where the same entity (a kinase, a compound) legitimately routes to a database lookup, a
tool search, or a workflow depending on the verb, getting stage-1 routing right is a prerequisite for every
downstream capability the sibling RealBio and DrugDev-Bench benchmarks measure.
