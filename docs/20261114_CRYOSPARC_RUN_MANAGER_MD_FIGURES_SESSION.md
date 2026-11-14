# 2026-11-14 — CryoSPARC license + Run Manager + MD figures wrap-up

**Branch (start):** `fix/skills-restore-on-live` @ `3747c3aa6f`  
**Live dig tip at audit open:** `0b63d793d78bc11a265d699468fabbd9b557d023` (`build-info.json`)  
**Fixture:** `lifeifei163361@163.com` via `~/.config/biomate/e2e_fixture_password` (not committed)

---

## What was done

### Product

| Fix | Commit | Behavior |
|-----|--------|----------|
| Run Manager → owning chat | `a14514c997` | `runManagerSwitchHref` → `/?session=&focusRun=`; left chat remounts with the run’s conversation, not empty New Chat |
| CryoSPARC license hard-block | `a14514c997` | UI fail-closed; Node + Galaxy refuse silent `CRYOSPARC_LICENSE` env inject unless `BIOMATE_ALLOW_SHARED_CRYOSPARC_LICENSE=true`; execute **402** `cryosparc_license_required` |
| `data-blocked` clears after user key | `1001dec42f` | LicenseGate `isBlocked` matches `onBlockedChange` (was `hardPath \|\| …`) |
| MD sibling figures | `babd11c1b8` | Always fetch project files; `resolveSiblingImage` leaf/basename fallbacks; reference-style images render |
| **License before dedupe** (this wrap-up) | *(pending commit)* | Idempotent execute dedupe must not return HTTP 200 for CryoSPARC when the caller has no user license — return **402** instead |

### E2E

- Harness: `frontend/e2e/run-manager-chat-and-cryosparc-license.e2e.ts` (Flow A license → Confirm & Run + cancel; Flow B Run Manager)
- Companion: `frontend/e2e/chat-files-and-reports.e2e.ts` (MD figures beside chat)
- Hardening (local line after dig tip): race HTTP vs panel badge/bar, pre-cancel + `e2e_nonce` against dedupe, ENOSPC-tolerant screenshots
- **This wrap-up:** remove page-wide `\bRunning\b` false-green; hard-assert `data-blocked=false` after save; wait briefly after cancel before A6 shot

### Dig sync tips (verified ancestry)

| SHA | Role |
|-----|------|
| `429c3dbc` / `ecf9fedc4d` | Earlier live tips that carried Run Manager + MD figure landings |
| `1001dec42f` | Confirm & Run / `data-blocked` product fix (`.last_dev_sync_commit` still pointed here) |
| `d258bd3227` | Merge-base of local CryoSPARC E2E line and live |
| `0b63d793` | **Live tip at wrap-up open** — restores deferred-materialize + BASE_URL class; **contains** `a14514c997`, `1001dec42f`, `babd11c1b8` |
| Local-only (not on dig until sync): `9d531bc9b5`…`558ddc77af`, `3747c3aa6f` | E2E race / docs merges |

---

## Evidence (do not invent greens)

### Commits (product + prior live E2E)

```
a14514c997 fix(ux): Run Manager opens owning chat; CryoSPARC license hard-blocks
babd11c1b8 fix(data): resolve MD report figures when paths or image syntax disagree
1001dec42f fix(ux): clear CryoSPARC license gate after user key; E2E Confirm & Run
ba62dd95bb docs: record live dig E2E pass for Run Manager + CryoSPARC license
7bf46f5058 docs: record dig Confirm&Run past license gate (A+B green)
```

### Dig build-info

- Fetched 2026-11-14 via WebFetch: `{"commit":"0b63d793d78bc11a265d699468fabbd9b557d023"}`
- Ancestry check (local git):
  - `a14514c997` ∈ live — **YES**
  - `1001dec42f` ∈ live — **YES**
  - `babd11c1b8` ∈ live — **YES**
  - `558ddc77af` (E2E race) ∈ live — **NO** (harness-only until sync)
- Cursor sandbox curl often fails (proxy CONNECT 403 / DNS when proxies cleared); WebFetch + EC2 sync path remain the reliable readers.

### Prior E2E claims (from dated docs + screenshots — not re-proven until retest section)

| Source | Claim |
|--------|--------|
| `docs/20261113_RUN_MANAGER_CHAT_AND_CRYOSPARC_LICENSE.md` | A+B green on tip `1001dec42f` / race `558ddc77af` (~2.4m / ~1.9m); cancel, no full GPU SPA |
| `docs/20261113_MD_FIGURE_RESOLVE_AND_E2E_RETEST.md` | chat-files + A + B green on tip `ecf9fedc4d` |
| Shots present on disk | `frontend/e2e/execshots/run-manager-cryosparc-license/` A3–A6, B0–B1 (mtime 2026-11-13 19:04) |
| Shots present on disk | `frontend/e2e/screenshots/chat-files-and-reports/` 1–5 |
| `frontend/e2e/reports/results.json` (stale) | Flow A **failed** with `ENOSPC` on A4 screenshot — predates try/catch in `shot()`; **not** a product fail. `.last-run.json` later shows `passed` |

### Post-sync log

- `docs/postsync_test_results/20261113_180631_1001dec42f6b7fd0efff0ad1cf6a1834f47332a7.log` — smoke-auth after `1001dec42f` sync (not the full A+B Playwright transcript).

---

## What’s still open

| Item | Status |
|------|--------|
| GPU warm-up / `cryosparc_execution_failed` HTTP 500 while license already cleared | **Open** — orthogonal to license gate; panel may stay `idle` when execute 500s without `runId` UX |
| License check before execute dedupe | **Fixed this wrap-up** in `routes.ts` (was open) |
| A6 shot lag (cancel 200 before panel leaves Running) | **Mitigated** — short waitForFunction before A6 shot; still best-effort |
| Local HEAD ↔ live tip divergence | Live `0b63d793` not ancestor of local `3747c3aa6f` and vice versa (diverged after `d258bd32`). Sync requires merge of live tip first |
| Shared-env license flag on dig | Must remain **off** in prod/dev; only `BIOMATE_ALLOW_SHARED_CRYOSPARC_LICENSE=true` re-enables env fallback |
| Disk pressure on agent host | ~3.8 Gi free at wrap-up; ENOSPC previously failed A mid-run |

---

## Audit (committee: product / E2E honesty / deploy hygiene)

### 1. Product correctness

| Finding | Severity | Risk |
|---------|----------|------|
| License hard-block + no silent env license: present in Node (`routes.ts`) and Galaxy (`nextflow_executor.py`); gated by explicit shared-env flag | — | Low residual if flag left on by mistake |
| `data-blocked` after save: fixed in `1001dec42f`; **on dig** | — | Was critical UI/E2E lie; closed |
| Run Manager owning chat: `focusRun` + session nav; unit tests in `run-manager-utils.test.ts` | — | Closed for the screenshot bug |
| MD sibling figures: general `MarkdownReport` path, not ADMET-only | — | Closed for founder class |
| **Dedupe before license:** no-license caller could inherit in-flight twin (HTTP 200 / `deduplicated`) and skip 402 | **High** (false acceptance) | Root cause of A2 flakes; **fixed this wrap-up** before re-sync |

### 2. E2E honesty

| Finding | Severity | False-confidence |
|---------|----------|------------------|
| Soft `data-blocked` warn-only after save | Medium | Could green while dig lacked `1001dec42f`. Dig now has the fix → **hardened to hard expect `false`** |
| A5 matched `/\bRunning\b/` on **full page text** | **High** | Unrelated Run Manager / sidebar “Running” could pass Confirm & Run without this workflow leaving idle → **removed**; badge/bar only |
| A5 accepts panel non-idle **or** infra 500 / runId | Medium (intentional) | Proves license gate, not GPU SPA success — documented; cancel in `finally` |
| A2 retries on dedupe + unique `e2e_nonce` | Low | Honest isolation; product fix makes retry less necessary |
| Stale `results.json` ENOSPC fail vs docs “green” | Medium (docs hygiene) | Disk-full ≠ product; shots + `.last-run.json` + dated docs are stronger. Do not cite that JSON as a product regression |
| chat-files asserts `markdown-figure` visible | — | Honest for sibling figures |

### 3. Deploy / sync hygiene

| Finding | Severity | Risk |
|---------|----------|------|
| Dig tip `0b63d793` **contains** product fixes for this slice | — | Product already live |
| Local E2E hardening + license-before-dedupe **not** on dig until sync | Medium | Harness/product drift |
| `.last_dev_sync_commit` = `1001dec42f` while live moved to `0b63d793` via other lines | Medium | Marker lag; next sync must merge live tip first |
| Uncommitted at audit open | Low | Only e2e report/playwright noise + probe file — **no uncommitted product** until this wrap-up’s edits |
| SSM/proxy from Cursor | Known | Sync needs proxies unset + `all` perms + takeover reason |

**Audit verdict:** Product core (license / Run Manager / MD figures) is on dig and previously proven. Highest false-confidence holes were **dedupe-before-license** and **page-wide Running match**. Those are fixed in this wrap-up; retest on dig required before calling the slice closed.

---

## Audit → fix → retest (fill after sync)

### Fixes shipped this wrap-up

1. `frontend/server/routes.ts` — CryoSPARC license gate **before** idempotent dedupe return (402 if no user key).
2. `frontend/e2e/run-manager-chat-and-cryosparc-license.e2e.ts` — hard `data-blocked=false`; panel badge/bar only for A5; A6 cancel settle wait.

### Pre-sync

- *(pending)* `npx tsc --noEmit -p .`
- *(pending)* vitest: `license-gate`, `run-manager-utils`, `markdown-report`

### Sync

- *(pending)* merge live `0b63d793` → sync with `BIOMATE_DEPLOY_TAKEOVER_REASON`, proxies unset

### Live dig E2E retest

| Suite | Result | Notes |
|-------|--------|-------|
| `run-manager-chat-and-cryosparc-license.e2e.ts` A | *pending* | Cancel CryoSPARC; no full GPU SPA |
| Flow B | *pending* | |
| `chat-files-and-reports.e2e.ts` | *pending* | |

### Dig tip after sync

- *(pending)*
