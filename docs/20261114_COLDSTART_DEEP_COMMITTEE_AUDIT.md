# Coldstart deep E2E — done / open + committee audit

**Timestamp:** 2026-11-14T14:07Z (doc authored ~08:10 America/Chicago)  
**Live DEV tip at audit:** `0b63d793d78b` (earlier evidence also on `d258bd3227`, `5dd9b6fb67`)  
**Runner at audit:** `run_coldstart_deep.sh` holding lock on `^design-rank-candidates-` (~3h48m elapsed, `workers=1`)

---

## 1. What was done

| Work | Status |
|------|--------|
| Deep harness: seed → clarify → Confirm&Run → terminal → After Run | Shipped (`coldstart-analysis-design-deep.e2e.ts`) |
| One-writer flocked runner (`run_coldstart_deep.sh`) | Shipped; parallel lane agents cancelled after thrash |
| Measurement audit (REINVENT vs Cryo) | `docs/20261113_HARNESS_MEASUREMENT_AUDIT_REINVENT_CRYO.md` |
| Stop force-Confirm / Confirm-anyway | Done → `BLOCKED_REQUIRED` |
| Capture `errorObserved` / fail strip | Done |
| Full matrix evidence (non-archive) | **73 graded cases** (+ older ungraded); slices through generate/fold/predict/optimise; rank in flight |
| Clarify UX fix | Code landed earlier; **sync-to-dev still pending** when lease free |

---

## 2. Still open

1. **Finish matrix** — `design-rank-candidates-*` slice still running; final rollup after DONE.
2. **Clarify sync** — not verified on tip until `sync_to_dev.sh` + retest.
3. **REINVENT4 product** — was failing with `CLI/package not found` because live ECR `:x86` ≠ repo Dockerfile (no CLI, no priors). **Code fix 2026-11-14** in `main.nf` + executor allow-list + Dockerfile Zenodo priors — see `docs/20261114_COLDSTART_FAILED_WORKFLOWS_INVENTORY.md`. Needs DEV sync + re-run to verify.
4. **Cryo** — `analysis-domain-str-0/2` correctly `BLOCKED_REQUIRED` (Movies Path / Confirm disabled); `str-1` `NO_LAUNCH` (no confirm / no workflow). Execution GPU path not claimed as pass.
5. **Disk** — ~4.8 Gi free (gate 3 Gi); still tight.
6. **FAKE_OR_SOFT_PASS / NO_LAUNCH pockets** — routing and panel gaps remain product work.

---

## 3. Committee audit (measurement + process)

### Members (roles)

| Role | Finding |
|------|---------|
| **Measurement** | Prior `DISHONEST_FAIL` rule used `diagnosisOnly` → **false**. All 30 such rows had honest `RUN FAILED` strips; Findings tab often not rendered. |
| **Product / Cryo** | User was right that Cryo is the consistent *blocked* class; harness now stops at `BLOCKED_REQUIRED` instead of manufacturing Movies Path failures. |
| **Product / REINVENT** | User belief “REINVENT fixed” **does not match** tip `0b63d793` evidence — container still exits with CLI/package missing. Earlier audit correctly refused to treat truncated `ERROR: REINV` as proven CLI miss; **current** logs now contain the full string. |
| **Ops** | Parallel agents caused EXIT 143 / lock fights; one-writer runner is mandatory. Default `BIOMATE_DEEP_WORKERS` must be **1** (was 2). |
| **QA** | Soft expects on Findings for failed runs caused Playwright ✘ even when UI was honest — assert fail-strip instead. |

### Verdict

- **Harness (pre-fix):** partially untrustworthy on fail grades (`DISHONEST` over-call).  
- **Harness (post-fix, this doc):** grades + failed-run asserts corrected; evidence JSON **regraded** offline (`gradeCommitteeRegrade=20261114`).  
- **Product:** Cryo block measurement OK; REINVENT container still broken on current tip; many honest pipeline fails remain.

### Regrade counts (root `execshots/.../coldstart-analysis-design-deep/*.json`)

| Grade | Before | After committee regrade |
|-------|--------|-------------------------|
| DISHONEST_FAIL | 30 | **0** |
| HONEST_FAIL | 7 | **37** |
| REAL_PASS | 12 | 12 |
| BLOCKED_REQUIRED | 5 | 5 |
| NO_LAUNCH | 12 | 12 |
| FAKE_OR_SOFT_PASS | 7 | 7 |

### Fixes shipped with this audit

1. `frontend/e2e/lib/coldstart-deep-grade.ts` — pure grade rules; DISHONEST only for spinner / empty dishonest fail.
2. Harness uses `gradeColdstartDeep` + `failedRunContentOk` (Findings optional on fail).
3. `run_coldstart_deep.sh` default workers **1**.
4. Vitest coverage: `e2e/lib/coldstart-deep-grade.test.ts` (vitest include updated).

### Test plan executed

| Check | Result |
|-------|--------|
| Offline regrade of evidence JSON | Done (30 `DISHONEST` → `HONEST_FAIL`) |
| `npx tsc --noEmit -p .` | **PASS** (`TSC_EXIT=0`) |
| `vitest run e2e/lib/coldstart-deep-grade.test.ts` | **PASS** 6/6 |
| `vitest run` full frontend | **FAIL unrelated:** 7 files / 12 tests failed, 374 files passed (3902 tests). Failures include pre-existing `auth-service` timeouts and `dataset-file-preview` / `markdown-report` unhandled fetch — **not** caused by coldstart grade changes. Log: `/tmp/biomate_vitest_full_20261114c.log` |
| Live DEV deep matrix | Continues under lock on `^design-rank-candidates-` — do not start a second writer |

Committee rule: do not block coldstart measurement fixes on unrelated suite flakes; track full-suite red separately.
---

## 4. Authoritative claims going forward

| Claim | Trust |
|-------|--------|
| Cryo coldstart often `BLOCKED_REQUIRED` without Movies Path | **Yes** |
| REINVENT4 generate-sm fails on tip `0b63d793` with CLI/package missing in container | **Yes** (full `errorObserved`) |
| Those REINVENT fails were “UI dishonest” | **No** — regraded to `HONEST_FAIL` |
| Full matrix complete / all REAL_PASS | **No** |
| Clarify fix live on DEV | **Unverified** until sync |
