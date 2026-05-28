# ANDV Campaign — Milestone Checklist

**Branch:** `integration/next-phase`  
**Last updated:** 2026-05-28 (GROMACS retry `20260528T033751Z`; commit `6358231b4`)  
**Tracks:** (A) Platform / E2E reliability · (B) Inhibitor pipeline · (C) Plan A epitope · (D) Plan B codon · (E) Science / manuscripts

---

## Glossary (read once)

### “Wrong DB” — `/tmp/biomate_connection_formal.sqlite`

| Database | Path | Used for |
|----------|------|----------|
| **Formal / connection test DB** | `/tmp/biomate_connection_formal.sqlite` | Default in `backend/start_backend.sh` — lightweight Galaxy DB for billing/connection experiments. **Does not** hold the full workflow registry used by ANDV E2E. |
| **Universe DB (correct for ANDV)** | `backend/database/universe.sqlite` | Set in `backend/config/galaxy.yml` — workflows **10813** (codon), **12700** (epitope), **12824** (Vina), AI tool index. **Use this for all ANDV UI + API work.** |

**Symptom when wrong DB is active:** Chat returns *“I processed your request using the available tools”* with **no workflow card**, `generate_workflow` errors, or `OutdatedDatabaseError`.

**Fix:** Start Galaxy with `GALAXY_CONFIG_FILE=config/galaxy.yml` and **do not** override `database_connection` to `/tmp/...`.

```bash
cd /home/yzhang/biomate/backend
set -a && source .env && set +a
export GALAXY_CONFIG_FILE=config/galaxy.yml
export GALAXY_CONFIG_ENABLE_AI_ASSISTANT=true
unset GALAXY_CONFIG_DATABASE_CONNECTION GALAXY_CONFIG_INSTALL_DATABASE_CONNECTION
.venv/bin/gunicorn "galaxy.webapps.galaxy.fast_factory:factory()" \
  --timeout 300 --pythonpath lib -k uvicorn.workers.UvicornWorker \
  -b 127.0.0.1:8081 --workers 2
```

### “Fast path” — workflow generation shortcut

When the user (or E2E prompt) **names a registry workflow explicitly** (e.g. `registry id 10813`, `AutoDock Vina`, `pdb_input = 1IEP`), the backend can:

1. **`get_workflow(id)`** — direct SQLite lookup (~seconds)
2. **Skip BGE embedding search** — avoids loading `bge-small-en-v1.5` on cold start (often **2–5+ min**, worker timeout)
3. **Skip param LLM** when query already has `target_sequence`, `outdir`, `pdb_input`, etc.

Implemented in `ai_assistant.py`: `_try_fast_path_explicit_codon_workflow` (10813), `_try_fast_path_explicit_docking_workflow` (12824).  
Frontend: `galaxy-assistant.ts` collapses multi-intent to a **single workflow card** when the user says “Show … workflow card”.

---

## Week 0 — Infrastructure gate (blocking)

| ID | Milestone | Owner | Status | Evidence |
|----|-----------|-------|--------|----------|
| I0.1 | Galaxy on `universe.sqlite` (verify with `lsof` on gunicorn PID) | Eng | 🔄 | gunicorn restarted 2026-05-28 (`/tmp/galaxy_andv.pid`, HTTP 200 on :8081) |
| I0.2 | Frontend `:5000` → proxy to `:8081` | Eng | ⬜ | `curl localhost:5000` + one chat turn |
| I0.3 | Document canonical start command in this file | Eng | ✅ | See above |
| I0.4 | E2E runs **serial** (max 1–2 Playwright jobs) | Eng | ⬜ | Logs under `frontend/e2e/logs/` |

---

## Week 1 — Platform / E2E (promising demo)

| ID | Milestone | Status | Evidence path |
|----|-----------|--------|----------------|
| E1 | **PA-4** execute → Batch completed | ⬜ | `plan-a-suite-audit.json` |
| E2 | **PA-5** completion UX | ⬜ | `PA-5_completed.png` |
| E3 | **PB-1** codon routing / card | ⬜ | `plan-b-suite-audit.json` |
| E4 | **PB-4–PB-5** codon panel + terminal status | ⬜ | `plan-b-codon/` screenshots |
| E5 | **INH-C1–C4** chained manifest (all steps completed or failed, not skipped) | ⬜ | `inhibitor-chained-manifest.json` |
| E6 | Push audit JSON + screenshots | ⬜ | Git on `integration/next-phase` |

**Pass criteria for E5:** `docking_vina` has `runId` and `status` ∈ {`completed`, `failed`} — not `skipped`.

---

## Week 1–2 — Inhibitor track (execution)

| ID | Milestone | Status | Notes |
|----|-----------|--------|-------|
| B1 | Pocket + druggability run completes on Batch | ⬜ | User: pocket **fixed** — re-verify |
| B2 | Pharmacophore completes (known good) | ⬜ | Prior runId `d15a4dbe-…` |
| B3 | ADMET completes on Batch | ⬜ | User: ADMET **fixed** — re-verify |
| B4 | Vina docking card + execute | ⬜ | Fast path 12824 + UI collapse |
| B5 | Update `pipeline_manifest.json` / `AUDIT.md` from UI or CLI | ⬜ | `research/anti-virus/runs/` |

---

## Week 2–3 — Plan B (fastest positive science narrative)

| ID | Milestone | Status |
|----|-----------|--------|
| D1 | UI codon workflow green (PB-1–PB-5) | ⬜ |
| D2 | CLI/UI parity: optimized sequence + outdir on S3 | ⬜ |
| D3 | Manuscript Plan B section: real numbers (not placeholder) | ✅ `MANUSCRIPT_PLAN_B_CODON_v1_0.md` (codon 25/57, 43.86%) |

---

## Week 3–4 — Plan A (epitope)

| ID | Milestone | Status |
|----|-----------|--------|
| A1 | UI epitope workflow green (PA-1–PA-5) | ⬜ |
| A2 | MHCnuggets run reproduces or improves vs 810-negative baseline | ⬜ |
| A3 | Manuscript: honest baseline + optional tool comparison | ⬜ |

---

## Week 4–6 — Science sprint (positive publication) **PRIORITY**

Orchestrator: `research/anti-virus/science_sprint/run_sprint_parallel.sh`  
Docs: `research/anti-virus/science_sprint/README.md`

| ID | Milestone | Script | Status |
|----|-----------|--------|--------|
| S1a | GROMACS MD on full 9P3I tetramer | `track_inh_md.py` | 🔄 retry `20260528T033751Z` — run `9bf5f9a2-…`, S3 `94e4fe18`; SYSTEM_SETUP on Batch ~12h+ (48h limit; prior fail at 2h) |
| S1b | Ensemble Vina (6 conformers vs rigid baseline) | `track_inh_ensemble_docking.py` | ✅ `20260527T195530Z` — 6/6 conformers; 3/3 improved vs baseline |
| S2a | Epitope: MHCnuggets + NetMHCpan | `track_plan_a_multitool.py` | ⚠️ MHCnuggets ✅ (~506s); NetMHCpan blocked — upload DTU `netMHCpan-4.1b.Linux.tar.gz` to S3 (script fix committed `6358231b4`) |
| S2b | Structural epitope patches (9P3I) | `track_plan_a_structural_epitopes.py` | ✅ `20260527T180210Z` — 4 patches, 92 exposed Cα |
| S2c | Cross-species ANDV/SNV/PUUV conservation | `track_plan_a_cross_species.py` | ✅ `20260527T180210Z` — 405 peptides, 3 triple-conserved |
| S3 | Manuscript: replace `[planned expansion]` with sprint outputs | manual | ✅ `MANUSCRIPT_PLAN_A_VACCINE_v1_0.md`, `MANUSCRIPT_ANDV_INHIBITOR_v1_0.md` |
| S4 | bioRxiv-ready package | `docs/biorxiv_package_v1/INDEX.md` | 🔄 draft index + figure paths; pending GROMACS + NetMHCpan |

---

## Parallel work queue (active)

| Stream | Action | Log / artifact |
|--------|--------|----------------|
| **Infra** | BASH_FUNC env sanitization in `nextflow_executor.py` + gunicorn reload | Batch jobs no longer instant-fail |
| **Science** | Sprint run `20260527T191853Z` — MD, multitool, ensemble | `science_sprint/logs/20260527T191853Z_*.log` |

---

## Full parallel TODO queue (2026-05-27)

| Priority | ID | Task | Owner | Status | Blocker |
|----------|-----|------|-------|--------|---------|
| P0 | S1a | GROMACS MD full 9P3I — poll → manuscript | Science | 🔄 SYSTEM_SETUP on Batch | Tetramer tleap runtime |
| P0 | S2a-fix | NetMHCpan: add `netmhcpan_path`, rerun | Eng + Science | 🔄 code fixed | Upload `netMHCpan-4.1b.Linux.tar.gz` to S3 |
| P0 | infra-poll | False-success detection in `nextflow_executor.py` | Eng | ✅ committed + gunicorn live | — |
| P1 | S4 | bioRxiv package (`docs/biorxiv_package_v1/`) | Science | 🔄 INDEX draft | GROMACS + NetMHCpan |
| P1 | infra-commit | Commit executor + Vina + sprint script fixes | Eng | ✅ `6358231b4` | Push to origin |
| P2 | E5 | E2E inhibitor chained manifest (universe DB) | Eng | ⬜ | Serial E2E; Batch stable |
| P2 | E1–E4 | E2E Plan A + Plan B UI suites | Eng | ⬜ | I0.1 universe DB verified |
| P2 | B1–B5 | Re-verify inhibitor UI steps on Batch | Eng | ⬜ | Pocket/ADMET fixes |
| P3 | D3 | Plan B manuscript real numbers | Science | ⬜ | Codon run green |
| P3 | I0.1–I0.4 | Infra gate (universe DB, frontend proxy, serial E2E) | Eng | ⬜ | — |

---

## Quick status dashboard

Update after each run:

```
Galaxy DB:     [ ] verify universe.sqlite  [ ] /tmp/biomate_connection_formal.sqlite
Batch fix:     [x] BASH_FUNC stripped in nextflow_executor
False-success: [x] committed + 5 tests pass (`test_nextflow_false_success.py`)
Science S1a:   [ ] completed  [x] running  [ ] failed  (9bf5f9a2; SYSTEM_SETUP ~12h+ on full 9P3I)
Science S1b:   [x] completed  [ ] running  [ ] failed  (20260527T195530Z, 3/3 improved)
Science S2a:   [x] mhcnuggets  [ ] netmhcpan  (blocked: DTU tarball → S3)
Science S2b/c: [x] structural + cross-species (20260527T180210Z)
Manuscripts:   [x] Plan A + Inhibitor + Plan B sprint prose
S4 bioRxiv:    [ ] submit-ready  [x] INDEX draft
PA-4/5:        [ ] pass
PB-1/4/5:      [ ] pass
INH-C1–C4:     [ ] E2E pass on universe DB
```

---

## References

- CLI evidence: `research/anti-virus/runs/andv_nf_pipeline_20260512T181054Z/AUDIT.md`
- Strategic plan: `research/anti-virus/feedback_review/TEAM_ACTION_PLAN_EXECUTIVE_SUMMARY.md`
- E2E specs: `frontend/e2e/plan-a-epitope-stepwise.e2e.ts`, `plan-b-codon-stepwise.e2e.ts`, `andv-inhibitor-chained-manifest.e2e.ts`
