# New System Functions — Plan & Status

**Date:** 2026-06-20
**Owner:** active session (Claude Opus 4.7) + handoff-ready
**Companion docs:**
- `docs/20260619_AI_GLASSES_AND_AUDIO_BIOMATE_PROTOTYPES.md` — Notes + Workbench origin discussion
- `docs/20260619_MIRA_UPGRADE_COMPARISON.md` — competitive context (Mira Wiki / Boards parity)
- `reference/claude_design/design_handoff_wiki_canvas/Wiki-Canvas-Prototype.html` — visual reference for Notes + Workbench
- `docs/20260619_THREE_FACULTIES_WORKFLOW_ROLLUP.md` + `docs/20260619_FACULTY_ZHENG_INTEGRATION.md` — Stream-B faculty integration plan

## Branch state

| Branch | Purpose | Status |
|---|---|---|
| `integration/next-phase` | Production-bound | Last commit `02074f173` (UX prune). **Do not merge to this until Stream-A features pass full validation.** |
| `qc/coverage-and-rebuilds` | Staging — all this-session work | Pushed at `f950505bb` (post-rebase, post-.db excise). User-approved for push, not for merge. |
| `tutorials-hold-for-system-update` | Quarantined tutorials enrichment | Commit `d7167827c`. Cherry-pick to staging only when system + videos ready. |

---

## Three new system functions

### 1. Notes — on-demand project synthesis

**What it is:** one click → BioMate reads every completed run + recent chat in a project and writes a structured markdown brief. Findings, recurring concepts, open questions, methods consolidation.

**Why we built it:** users have 20+ runs per project after a few weeks; no way today to ask *"what has this project learned?"*. Mira (their Wiki) shipped the same shape — we matched on a cheaper architecture (on-demand, not nightly cron).

**Status:** SHIPPED LOCALLY on `qc/coverage-and-rebuilds`, not yet promoted.

| Layer | Commit | Notes |
|---|---|---|
| Backend endpoint (`POST /api/projects/:id/notes/refresh`, `GET /api/projects/:id/notes`) | `e3955d0da` | 12 contract tests passing |
| Frontend page (`/projects/:id/notes` + Refresh button + Markdown download) | `a8b1e9856` | 4 page tests passing |
| Storage | reuses `project_knowledge` with `knowledgeType='notes_synthesis'` | No new table, no PG migration |
| LLM | gemini-3.5-flash, maxTokens=4096, ~$0.05/refresh | Cost capped |

**What's left to ship to users:**
1. Cherry-pick `e3955d0da` + `a8b1e9856` to `integration/next-phase` after staging validation
2. `scripts/sync_to_dev.sh` to push to dev EC2
3. Manual smoke test on dev: log in as fixture user, create a project, run 2 workflows, click Refresh, verify markdown lands
4. Record a tutorial video showing the flow
5. Promote the tutorials-hold-for-system-update branch to staging (Notes is mentioned in the new Key Concepts + FAQ copy)

**Follow-ups (not blocking ship):**
- Sidebar link (current `app-sidebar.tsx` has no per-project slot; URL-only access for v1)
- Nightly auto-refresh option (currently on-demand only)
- "Refresh diff" UI — show what changed since the last synthesis
- Cross-link citations into actual run pages (currently the markdown mentions runs by name, doesn't deep-link)

---

### 2. Workbench — multi-file side-by-side canvas

**What it is:** pin any output file (CSV, plot, PDB structure, paper, methods doc) from any run to a project's Workbench, then open multiple pinned files as tabs with optional 2-pane split.

**Why we built it:** actual scientific work is comparative — RNA-seq DE table beside volcano plot beside GSEA dotplot. Today `step-output-preview` opens one file at a time in a modal. Mira's Boards is the same idea (they support MD trajectories too — see "Phase 2" below).

**Status:** SHIPPED LOCALLY on `qc/coverage-and-rebuilds`, not yet promoted.

| Layer | Commit | Notes |
|---|---|---|
| Backend endpoints (GET pins, POST pin, DELETE pin) + repo `deleteProjectKnowledgeRow` | `0ba50ee96` | 12 contract tests passing |
| Frontend `WorkbenchPanel` (tabs + 2-pane split) + `project-workbench` page + Pin button on `step-output-preview` | `abcaed7ec` | 6 component tests passing |
| Storage | `project_knowledge` with `knowledgeType='workbench_pin'` | Same pattern as Notes |
| Pin scope | project-scoped delete (cross-project deletes impossible even with guessed id) | Locked in by contract test (f) |

**What's left to ship to users:**
1. Cherry-pick `0ba50ee96` + `abcaed7ec` to `integration/next-phase`
2. Sync to dev
3. Manual smoke test: pin 3 different file types (CSV, image, structure), open as tabs, split-view
4. Record a tutorial video
5. Promote tutorials-hold-for-system-update

**Phase 2 (next quarter):**
- **MD trajectory preview** (.xtc / .dcd / .trr / .nc) — Mira's Boards differentiator. Needs NGL.js integration (~1 week)
- Drag-and-drop reorder of pins (HTML5 drag API, no library)
- Free-layout grid (replace tabs with positional placement) — only if user pull demands it
- Y.js collaborative state (skip for v1 — single-user works fine)

---

### 3. Evidence Search — cross-cutting grounded retrieval

**What it is:** `POST /api/evidence/search` takes any claim, parses entities (gene / pathway / compound / trait), queries PubMed + OpenTargets + STRING in parallel, LLM-reranks, returns evidence with citations. Trigger: any findings card, a chat `/evidence` command, or auto-fire when a strong claim is generated.

**Why we built it:** user request — "if Dr. Zhi wants to find data to support their output or hypothesis, auto search from web or direct datasets could be carried out to find strong evidence with sources." Grounded retrieval over our 137-dataset catalog (with the new evidence-only datasets — PubMed E-utilities, OpenTargets v24, STRING v12 — registered in commit `b4f537ca5`).

**Status:** BACKEND ONLY, on `qc/coverage-and-rebuilds`. No UI yet.

| Layer | Commit | Notes |
|---|---|---|
| Backend endpoints (`POST /search`, `GET /sources`) | `21ad13f39` | 20 contract tests passing |
| Adapters | PubMed E-utils + OpenTargets GraphQL + STRING (all live) | ClinVar / GTEx / Reactome / KEGG / MSigDB stubbed as TODO(v2) |
| Caching | In-process Map, 1h TTL on `(claim, context)` hash | Resets on process restart — v2 should persist |
| Cost cap | maxTokens=2048, PubMed≤10 / OpenTargets≤5 / STRING≤5 | Configurable constants |
| Failure containment | `Promise.allSettled` — one source failing doesn't break the whole search | Locked in by tests |

**What's left to ship to users:**
1. **Frontend trigger surfaces** — at minimum:
   - "Find supporting evidence" button on each findings card
   - `/evidence <claim>` chat command
   - Optional: auto-fire when an after-run report claims something (e.g. "BMT-44 is a cardiac risk") — toggle in settings
2. Cherry-pick `21ad13f39` to `integration/next-phase`
3. Sync to dev
4. Test against real PubMed quota — confirm we don't get rate-limited
5. Add `NCBI_API_KEY` env var on dev for higher PubMed rate-limit
6. Promote tutorials-hold-for-system-update

**Phase 2:**
- Wire ClinVar / GTEx / Reactome / KEGG / MSigDB adapters (5 TODO sources from v1)
- Replace in-process Map with persistent Redis cache (1-day TTL)
- API-key vault for OMIM, OpenTargets paid tier, etc.
- "Evidence trail" persisted to project_knowledge so users can revisit prior searches

---

## Tutorials enrichment — HELD until system + videos updated

**What it is:** `/tutorials` page gains a **Key Concepts** section (8 surface descriptions: Run Manager, Workflow Panel, QC Gates + Self-correct, Notes, Workbench, Evidence Search, Outputs, Project Library) and a **FAQ** section (12 collapsible Q/As covering real user questions).

**Why we paused:** user explicitly directed *"you should not push the webpage updates until the system is updated and video updated too."* The copy mentions Notes / Workbench / Evidence Search — publishing it before those features are live on prod, or before the videos match, would break user expectations.

**Status:** commit `d7167827c` preserved on local branch `tutorials-hold-for-system-update`. **Not in `qc/coverage-and-rebuilds`. Not in `integration/next-phase`. Not pushed.**

**Release gate (all 3 must be met):**
1. Notes + Workbench + Evidence Search merged into `integration/next-phase` and synced to prod
2. New tutorial videos recorded showing each of the 3 features end-to-end
3. Tutorials page videos array updated with new video IDs (`bpG0IWrwN5g`, `C4gQD-xbHnQ`, `F2DgmBa5gq8`, `IDcICWmB0Oo` are the current 4 — add 3 new ones, or replace if outdated)

**To release:**
```
git cherry-pick d7167827c
# review for any stale references vs current feature shape
git push origin integration/next-phase
bash scripts/sync_to_dev.sh
```

---

## Cross-cutting Stream-B work (faculty wraps, same session)

Shipped on `qc/coverage-and-rebuilds`:
- **MAGMA** `abd21c5ec` (Zhi + Zhao cross-faculty unblock)
- **LDSC** `d994869273` (Zhi heritability)
- **METAL** `bdd46c23f5` (Zhi meta-analysis)
- **GCTA** `04b602ec1` (Zhi primary engine — landed during DL discussion)
- **AI-MARRVEL** `7e3470fb1` (Liu L01-v2)
- **14 reference datasets** registered (`b4f537ca5`) — 1000G, HPO, OMIM, ClinVar, GTEx, gnomAD, Reactome, KEGG, MSigDB, VEP, UCSC + PubMed/OpenTargets/STRING APIs
- **Liu L01 yaml backfill** `efbeb5785` (qc_evidence + rationale for chain id 1)

In flight from the same batch:
- **FUMA** wrap (combined agent with GCTA — completion notification pending)

Not yet started (queued):
- **ASpdb wrap** for Zheng Phase 1 (task #74 — held until other batch lands, plus the `biodataai.uth.edu/aspdb` URL returned 404 in probe; need real URL from Zheng bibliography HTML)
- **PRS-CS, RaPID, turep, ImmuneApp standalone, PolyAMiner-Bulk** wraps
- **scGWAS ECR push** (needs AWS write creds approval)
- **Z01 5-step chain extension** (TorchGWAS → GCTA → MAGMA → METAL → LDSC → FUMA) — unlocked now that MAGMA/LDSC/METAL/GCTA shipped; needs FUMA to complete
- **Per-step `qc_steps` DB backfill** for chain id 1 (sarek/VEP/rnaseq/drop/fraser) — SQL-write script, deferred from yaml-only Liu task
- **Python `_GATE_REGISTRY` entries for rare_disease** (5 phase callables) — wires Liu yaml citations into runtime QC evaluation

---

## Deep Learning module — proposed, not started

**Rationale:** all 4 faculty (Zhi, Zhao, Liu, Zheng) ship DL tools. If we don't surface DL as first-class workflow type, every faculty integration becomes a custom Python-script wrap. With first-class DL support, they bring a HuggingFace model name or a Lightning script and we orchestrate.

**Phase 1 (~2 weeks, 1 engineer):**
1. New workflow domain `deep_learning` with 4 phase templates: `data_prep → train → eval → infer`
2. **HuggingFace** integration — register HF model by name, infer + fine-tune templates
3. **PyTorch Lightning** train template — "drop in a LightningModule, we run it on the GPU queue"
4. **Model registry** — extend `project_knowledge` with `knowledgeType='trained_model'`. Checkpoint to S3, metrics in row payload. No new table.

**Phase 2 (~2 weeks):**
5. **MLflow** integration as the registry backend (replaces the project_knowledge stub)
6. **Eval after-run tab** — loss curves, AUC, confusion matrix using existing chart renderers
7. **scvi-tools** template for single-cell DL users (Zhao)
8. **ONNX Runtime** inference endpoints — deploy registered model as callable URL

**Phase 3 (deferred until pull):**
9. Hyperparameter sweeps as auto-loop variant (Optuna)
10. Distributed training (FSDP / DeepSpeed)
11. Multi-run comparison view (likely reuses Workbench tabs)

**Open-source projects integrated directly (no reinvention):**
- PyTorch Lightning (training loop standard)
- HuggingFace Transformers + Hub (foundation models)
- scvi-tools (single-cell DL)
- deepchem (drug-discovery DL)
- MLflow (model registry + experiment tracking, self-hostable)
- ONNX Runtime (inference serving)
- Optuna (hyperparameter optimization)

**Identity guardrail:** position as *"run your model inside your bio project"* — not *"BioMate is now a model-training platform"*. Don't drift into rebuilding MLflow.

---

## Quality gates for promotion to `integration/next-phase`

Before any cherry-pick from `qc/coverage-and-rebuilds` → `integration/next-phase`:

1. Full local sweep green:
   - `cd frontend && npx tsc --noEmit -p .` clean
   - `cd frontend && npx vitest run` — currently 923 passed / 4 skipped / 0 failed
   - `cd backend && PYTHONPATH=lib python3 -m pytest tests/test_qc_gate_reader.py -q` — currently 70/70
2. Per-feature manual smoke on dev (Notes / Workbench / Evidence Search each require their own smoke run with the e2e fixture user)
3. No `backend/database/galaxy_ai_tools.db` binary in any commit (it's .gitignored — agents have repeatedly auto-staged it; check `git diff --stat HEAD~N..HEAD -- backend/database/` before any push)
4. Cost burn during smoke ≤ $5 (Lago dashboard check)

After all 4 conditions: `git cherry-pick <sha>...<sha>` onto `integration/next-phase`, `git push origin integration/next-phase`, `bash scripts/sync_to_dev.sh`.

---

## Recommended next session shape

| Priority | Item | Effort | Why |
|---|---|---|---|
| P0 | Manual smoke on dev for Notes + Workbench + Evidence Search | half day | Required before promoting to next-phase |
| P0 | Record 3 new tutorial videos (one per system function) | 2-3 hours | Unblocks tutorials-hold release |
| P1 | Wire ClinVar / GTEx / Reactome / KEGG / MSigDB adapters into Evidence Search (Phase 2) | 2 days | Closes the v1 TODO; broader evidence coverage |
| P1 | FUMA wrap completion + Z01 5-step chain extension | 1 day | Closes Zhi flagship paper-faithful demo |
| P1 | Per-step `qc_steps` DB backfill (chain id 1) + `rare_disease` `_GATE_REGISTRY` callables | 1 day | Wires Liu yaml citations into runtime QC |
| P2 | DL module Phase 1 (HF + Lightning + model registry) | 2 weeks | All 4 faculty use DL; unblocks faster integration |
| P2 | Real Docker builds + ECR push for MAGMA / LDSC / METAL / GCTA / AI-MARRVEL containers | 1 day | All wraps Phase-A stub-tested only; B-D need real containers |
| P3 | ASpdb wrap for Zheng pilot Phase 1 | 1 day | Lowest priority of the four faculties (Zheng has no GitHub org; wrap is thin client of unverified endpoint) |

---

## Out-of-scope reminders

- Scupa (Zhao ZZ01 step 2) — license blocker, dropped
- 13 Tier-B Zhi repos — license blockers, dropped
- SEAGAL (Liu) — repo URL not findable, dropped
- UK Biobank brain MRI (Zhi UDIP) — needs credential sponsorship, dropped
- Mira's Expert Team feature — not in their own docs, PilotExperimentPanel covers our use case
- Telegram + Discord messaging integrations — wrong audience (we have Slack + Email + Webhook)
- Image generation as quota'd service — wrong vertical (Mira is materials; we're bio)
- New separate help-site — replaced by tutorials enrichment (held)
