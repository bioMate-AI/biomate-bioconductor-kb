# Evidence pipeline + UI refinements — session 2026-11-11

Overnight autonomous session. Everything below is committed to the shared
integration branch (`feat/skills-architecture-20261111`, the live team stack);
a standalone GitHub PR is **not cleanly producible** — the branch is 200+
commits ahead of `origin/integration/next-phase` (all unpushed team work), and a
cherry-pick of just these commits onto the pushed base conflicts on
`app-sidebar.tsx`. Per the established model, the work **rides the shared branch**
and deploys with the team's integration→dev sync.

## Commits (this session)
| SHA | What |
|---|---|
| `40fd8d02fb` | fix(ui): de-duplicate project surfaces (right sidebar hidden; top New Chat removed + 4 e2e specs; output-format examples hidden once configured) |
| `acba98ab09` | feat(research): intent-aware evidence source selection + federated fan-out + SYSUCC DB-audit doc |
| `a886beffae` | fix(research): coverage-aware confidence (kill the hardcoded 0.8 stub) |
| `880e20b450` | feat(research): route target-ranking questions to the target_id engine (`fuse_channels`), **flag-gated + inert by default** (`BIOMATE_TARGETID_IN_RESEARCH=1`) |

Verification: `tsc` clean; vitest **2834 passed / 0 failed**; `py_compile` clean on
all backend files; selector + confidence logic verified by direct execution
(pytest for the backend tests runs in CI/dev — local conda can't import
`galaxy.ai.__init__`, heavy `sentence_transformers`).

## 1. UI refinements (founder screenshots)
- **Project right sidebar** hidden outside the 项目指令 (Instructions) tab — it was
  fully redundant (standing instructions + members + details render there).
  `members-panel` kept in the DOM, so `project-detail.test.tsx` passes.
- **Top Workspace "New Chat"** removed; standalone new-chat stays on the collapsed
  icon rail (`App.tsx`). 4 sidebar e2e specs updated to assert the rail entry.
- **Output-format examples** block hidden once every example kind is already
  configured (it duplicated the list); still shown for empty/partial projects.

## 2. Evidence pipeline — the core work
**Problem (ABL1 SAR case):** a grounded chat answer defined the gene, hedged, and
truncated — and printed "reasonable confidence". Root causes, confirmed in code:
1. The research/grounded path (`research_agent._gather_evidence`) is **literature-
   only** — it never calls the 15-source `query_database` dispatcher or the
   `target_id` engine, even though **all** evidence intents route to it.
2. `federated_query` selects sources by **detected entity type**, so a target that
   reads as a "gene" never reaches ChEMBL/BindingDB/PDB/Pharos — the SAR evidence.
3. `_parse_llm_response` hardcoded `confidence: 0.8` → "reasonable" on every answer.

**Built + shipped (to the branch):**
- `evidence_source_router.select_sources()` — picks sources by **question intent**
  (facets: structure / bioactivity / target / pathway / variant / disease +
  literature), validated against the `data_sources` registry. ABL1 SAR →
  `chembl, bindingdb, pubchem, chebi, pharos, uniprot, pdb` (verified).
- `skills/evidence-source-selection.md` — the human/LLM-readable companion skill.
- Wired into `_gather_evidence`: for named targets, `federated_query(entity,
  sources=select_sources(...))` → `db_facts['federated_evidence']`, already rendered
  into the synthesis prompt. Non-fatal, Redis-cached.
- `_grounding_confidence()` replaces the 0.8 stub — from the model's
  `addresses|insufficient` verdict + grounded channels (citations + DB/federated).
  Insufficient/zero-grounding → limited; affirmed + ≥3 channels → reasonable.
- Tests: `test_evidence_source_router.py` (7), `test_research_confidence.py` (6).

## 3. What's left (the "methods" half — needs your call)
The user's point stands: evidence isn't only source selection — BioMate has
evidence-**processing** methods the pipeline should use. Analysis:
- **`target_id/arbiter.fuse_channels`** (domain-neutral z-gated channel fusion) and
  **`evidence_gate`/`rank_evidence`** — for **ranking** questions ("which
  target/gene/driver for X"). Already the engine behind `identify_targets`.
  **DONE (`880e20b450`), flag-gated:** `is_target_ranking_question()` detects
  ranking intent and `_gather_evidence` runs the `TargetIDOrchestrator`, attaching
  the ranked targets to `db_facts['target_ranking']` (rendered in the prompt).
  Inert until `BIOMATE_TARGETID_IN_RESEARCH=1` (it does live network + an LLM call).
  To finish: enable the flag on dev and validate on a "which targets for X" question.
- **`verification_layer.self_consistent` / `grounded_pick` / `consensus`** — general
  answer verification; `self_consistent` gives a **measured** confidence (sampled
  agreement) that could replace the heuristic `_grounding_confidence`. **Cost:** K
  synthesis runs per answer — a production decision to make deliberately, not
  enable silently. `_grounding_confidence` already notes this as the upgrade path.

## 4. Deploy status (needs you)
- These commits ride the integration branch → deploy with the team's normal
  integration→dev sync. I did **not** fire a full `sync_to_dev.sh` unsupervised:
  the shared worktree carries the whole team's in-flight work, so a sync from here
  would deploy far more than this session's changes.
- **Backend** changes (`research_agent.py`, `evidence_source_router.py`, the skill)
  need a **backend** sync to reach dev; after it, live-validate
  `federated_query(sources=…)` output + the `federated_evidence` rendering + latency.
- Separately pending from earlier today: the `galaxy_ai_tools.db` `real_exec_status`
  rows for SYSUCC workflows 14666/67/68 (local DB updated; deploys via
  `deploy_databases()`), and the Boltz-2 (14665) `.nf` output-collection bug
  (fold runs on GPU but 0 structures harvested — diagnosed, fix deferred as it
  needs a GPU re-run to validate).

## Next steps (recommended order)
1. Backend sync → live-validate the source fan-out on the ABL1 question.
2. Decide on `self_consistent` confidence (cost vs. calibration).
3. Route target-ranking questions to `identify_targets` (reuse `fuse_channels`).
4. Fix the Boltz `.nf` output-collection + re-run 14665.
