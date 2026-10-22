# Agent-flexibility refactor — test-first implementation plan

Date: 2026-10-21
Companion to `docs/20261021_BIOMATE_AGENT_FLEXIBILITY_AUDIT_AND_DESIGN.md` (the what/why). This is the HOW:
a strictly test-first, flag-gated, reversible plan so the live chat is never changed on faith. User
directive: "I am worried about it, it should be tested fully." Order of operations: **build the test net
first, prove it catches regressions, then change code behind flags, A/B against the net, gate every sync.**

## Non-negotiable principles
- **Net before change.** Phase 0 (characterization oracle) ships and is validated BEFORE any product-code edit.
- **Flag-gated, default = today.** Every behavior change is behind an env flag defaulting to current behavior;
  prod is byte-identical until a flag flips. Instant revert.
- **Equivalence protects accumulated knowledge.** A predefined routing (any of the ~15 regexes, any curated
  workflow mapping) is migrated ONLY where the agent + `search_workflow` is proven to return the IDENTICAL
  workflow. Proven case-by-case, never assumed. Nothing in the 4,210-workflow catalog or the domain KB is deleted.
- **Fabrication is a tested failure, not a judgment call.** An assertion forbids rendering `<run_code>` as
  "executed" unless it actually ran.
- **E2E is real-backend, no mocks, fixture account** (`lifeifei163361@163.com`, `BIOMATE_URL=dev-public`),
  per the repo testing rules. Consolidated flows (`scripts/e2e_use_cases.sh`), not per-case logins.

## Phases (each gated; do not advance until the prior is green)

### Phase 0 — Characterization baseline (NO product-code change)
Build a regression oracle capturing TODAY's behavior over a golden message set:
- the requests the 15 regexes handle (clusterProfiler, ADMET, AutoDock, codon, epitope, pocket, GWAS→eQTL,
  multi-omics, ml_training, pathway-enrichment, trial-feasibility, HPO+ENSG, target-evidence, …),
- genuine pipeline requests (RNA-seq, WGS/sarek, CryoEM, ADMET screen),
- explicit direct-compute asks ("use run_code to …"),
- novel analytical needs (the ICB-evidence type) that match no card.
For each, record the DETERMINISTIC routing outcome: which `_isX` detector fires; `inferActionsFromType(type)`
flags; the gate result `toolsEnabledThisTurn` under each (hasRunnableWorkflow, useThinking) combination; and
the fabrication-risk condition. Deliverable: a vitest suite `galaxy-assistant.characterization.test.ts` that
snapshots these. **Validation that the net works:** introduce a deliberate break locally and confirm the
suite fails (then revert the break). This proves the oracle detects regressions.
Gate to advance: suite green on current code + demonstrated to catch an injected regression.

### Phase 1 — Kill fabrication (smallest, additive-ish; flag `BIOMATE_AGENT_TOOLS_WITH_CARD`)
- Remove the `!hasRunnableWorkflow` term from the tool gate (`galaxy-assistant.ts:8760`/`:9156`) so a turn
  showing a workflow card keeps its tools — behind the flag (off → current behavior).
- Add an authoritative integrity guard: an un-executed tool block can never render as "executed" (make the
  guard at `:8823` enforce, not advise).
Tests: unit asserts (gate truth table under flag on/off; guard blocks fabricated "executed" text). Oracle
must still pass with flag OFF (equivalence).
Gate: unit + oracle green; pre-sync checklist (tsc + vitest).

### Phase 2 — Evidence/exec tools in the loop (flag `BIOMATE_AGENT_EVIDENCE_TOOLS`)
Register `query_database`, `identify_targets`, `fetch_public_data`, `search_workflow`, `run_workflow` into
`BIOMATE_TOOLS` with real dispatch (proxy to the existing MCP/REST handlers, mirroring `userMcpTools`).
Tests: each tool's dispatch has an integration test (real handler, no mock of the handler). A novel-need E2E
(ICB-evidence) shows a real composed answer (OpenTargets + run_code + provenance), not a card/fabrication.
Gate: integration + e2e_use_cases green; flag OFF path unchanged (oracle green).

### Phase 3 — Reference-recipe library live + workflows-as-tool (flag `BIOMATE_CHAIN_REFERENCE_LIVE`)
Wire the dormant `chain_composer`/`WorkflowChain` reference library into the live path (currently shadow-only)
and generalize a chain step to allow TOOL calls (OpenTargets/run_code/DB), not only workflows. Migrate the
known compositions (incl. the 15 regexes' intent) into curated chains (DATA, with `example_queries`/provenance).
Demote `analyzeIntent`/`inferActionsFromType` + the `:4096-4400` override block to a HINT; the agent chooses
`search_workflow`/`run_workflow` as a tool. **A regex is deleted only when the equivalence test proves the
agent+reference returns its exact workflow; otherwise it stays.** Biggest regression surface → flag off by
default, A/B the full golden set + e2e_use_cases, deep per-use-case screenshot audit.
Gate: equivalence proven per migrated route; full E2E + workflow-panel state suite green.

### Phase 4 — Staged rollout
Flag ON on dev only → run the 6 use-case scenarios (ADMET/RNA-seq/WGS/CryoEM/CRO/drug-discovery) + the
workflow-panel states on dev → monitor → default-on only after all green. Any regression → flag off (revert).

## What is NOT touched
The 4,210-workflow catalog, `query_domain_knowledge` KB, `nextflow_composer`, the evidence sources, and the
dormant agent machinery are all KEPT. Phase 3 ELEVATES the curated routing from regex to a searchable recipe
library; it does not delete knowledge. See the audit/design doc for the code anchors.
