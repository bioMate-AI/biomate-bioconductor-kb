# 2026-11-14 08:23 — Session summary, open items, committee + Bugbot audit

Worktree: `/Users/kky/biomate-nextphase-ci-fix` · branch `sync/pr398-onto-dev`

| Field | Value |
|-------|--------|
| Live tip at audit start (`build-info.json`) | `0b63d793d78bc11a265d699468fabbd9b557d023` |
| Worktree after FF to live | `0b63d793d7` (was behind live; FF restored merge-dropped files) |
| This pass tip (post-fix commit) | `1084645a30` (fixes) + `028df9f246` (doc SHA note); branch pushed |
| Sync this pass | **BLOCKED** — `ssm.us-west-2.amazonaws.com` unreachable from Cursor env (proxy cleared). Live still `0b63d793` until operator sync. |

---

## 1. Done this arc (with SHAs)

### Example routing + dual-path
| SHA / tip | What |
|-----------|------|
| `50c18527d5` / `27ac40b9ee` | Library/molecule **dual-path**: catalog mega-chain **or** sequential step-by-step |
| `ff104f9c8a`…`73e9fd8edf` era | `input_kinds` data-shape gate, provenance self-heal, prose path leak fix (see `docs/20261113_EXAMPLE_ROUTING_FIXES_INPUT_KINDS.md`) |
| **This pass** | Harden `messageSupportsCatalogChainHint` — refuse leaked `chain_hint` on single-intent ADMET; Tier-2 uses same helper; catalog mega-chain miss → explicit clarification (no Tier-3 invent) |

### Voice UI / settings
| SHA | What |
|-----|------|
| `d72edec25f` | Slim composer; voice **off by default** |
| `d89f548c98` | Toolbar-only icons; drop ElevenLabs disclaimer copy |
| `1ecaf5c602` / `c2b02d2375` | Reachable Settings → **Voice** tab (Cursor-dense rows) |
| **This pass** | Comment fix “Settings → Chat” → “Settings → Voice”; voice-tab test asserts `updateSetting` wiring |

### Findings class — metrics-first
| SHA | What |
|-----|------|
| `a41a9a76e5` | ml_training: surface `metrics.json`, not Ludwig fluff |
| `19914c14f9` | Class-wide metrics-first gates (not only ml_training) |
| `67cb30ede2` | Docking/cryo/MultiQC + ZIP close-out |
| `c6fc7f6d89` | Genomics flat belt + `download_all` vitest `{ timeout: 45_000 }` bake-in |
| **This pass** | Stronger hollow detector for docking/Boltz empty Key Results |

### Organic user roster
| Doc / SHA | What |
|-----------|------|
| `docs/20261110_ORGANIC_USER_COMPLETE_ISSUE_COLLECTION.md` | ~47 organic / 19 friction classes (I1–I…); roster mining complete |
| Partial fixes earlier | Drive ingestion, run_code retry, clinic hard-data, etc. — see organic doc status flags |

### Sync / ancestry era (`d258bd32` → live)
| SHA | What |
|-----|------|
| `d258bd3227` | merge live `5dd9b6fb67` onto findings class line — **claimed ancestry but dropped** `deferred-materialize.ts` + BASE_URL class |
| `80e0688ce5` | merge `d258bd32` onto repro-pack line |
| `0b63d793d7` | **restore** deferred-materialize module + E2E BASE_URL class after merge drop (live tip at session start) |
| **This pass** | FF worktree to `0b63d793`; **re-wire** `ensureDeferredDatasetsMaterialized` into Confirm & Run (module was restored without call site) |

### Galaxy leverage (adjacent)
| SHA | What |
|-----|------|
| `82524c3839` | samplesheet attach, deferred URL UI, remote FTP, datatype gate |
| `94ae1391d5` | materialize deferred HDAs on Confirm & Run (history; call site restored this pass) |
| `3e8b2db292` | reproducibility pack ZIP |

---

## 2. Still open / deferred

1. **Authenticated UI autopsy** for potency Findings session still needs `drugtest@biomate.dev` (fixture 403).
2. **Chat stream prose** not rewritten retroactively — After-run Findings/report are source of truth.
3. **Voice**: TTS voice catalog / speed / mic device / submit-keywords still deferred (no fake Settings rows).
4. **Organic I1** Galaxy ECONNREFUSED on generate/run_code — intermittent; retry extension still partial.
5. **input_kinds LLM backfill** on DEV DB is optional; rule self-heal is the deploy path — see ops footgun note below.
6. **Sync from Cursor sandbox** often blocked (SSM / proxy CONNECT 403). Operator sync when lease FREE.
7. **Hell-clinic live re-run** after this pass’s assertion tighten (needs live Playwright).

---

## 3. Committee audit (5 perspectives + Bugbot)

### Verdict table

| Area | Verdict | Evidence |
|------|---------|----------|
| **1. Routing/product** | **PASS after fix** | Dual-path intact (`library-triage-sequential.ts`). Bugbot High #1: leaked hint hijacked single ADMET via token `admet` — **fixed** (require slug or multi-step/library-screen phrasing). Mega-chain miss → clarification (**Medium #4 fixed**). |
| **2. Findings/report** | **PASS after fix** | Metrics-first class shipped `67cb30ede2`+; hollow + vina/boltz descriptors present. **Medium #5**: hollow now flags docking/Boltz empty Key Results without explicit “missing” admit. Download ZIP empty-fetch no longer false-success (**Medium #7**). |
| **3. Voice/UX** | **PASS** | Settings Voice tab outside `{false &&}`; composer icons gated `voiceEnabled === true`; no ElevenLabs spam (tests); default off (`user-settings.ts`). Low #8/#10 done. |
| **4. Deploy/ancestry** | **WARN → mitigated** | Live tip `0b63d793` was **ahead** of worktree `d258bd32`. Ours-merge dropped materialize + BASE_URL; live restore + this pass re-wired Confirm & Run. Branch was ahead-of-origin; do not sync a tip that is not a descendant of live without FF/merge. |
| **5. Tests/CI hygiene** | **PASS** | `download_all` suite timeout bake-in (`c6fc7f6d89`); tsc green this pass; 110 targeted vitest green. Hell-clinic false-green soft paths tightened (**Medium #6**). PIPESTATUS false-greens historically fixed in sync scripts; coldstart harness uses `PIPESTATUS[0]` correctly. |

### Bugbot table (10 findings)

| # | Sev | Finding | Status this pass |
|---|-----|---------|------------------|
| 1 | **High** | `library-triage-sequential.ts` leaked `chain_hint` hijacks single-intent ADMET | **FIXED** + test `Run ADMET on aspirin` + hint → `null` |
| 2 | **High** | Sync panel Download-all S3 client ≠ `AWS_NF_*` / runs-outputs path | **FIXED** — sync GET uses NF/MinIO client; prefers `?runId=` |
| 3 | **Medium** | Panel sync GET with invocationId only | **FIXED** — panel uses `JobButton` `download_all_zip` with `{ invocationId, runId }`; sync fallback passes `runId` |
| 4 | **Medium** | Catalog mega-chain Tier-2 miss → silent Tier-3 | **FIXED** — explicit clarification when `libraryMoleculePath === catalog_mega_chain` |
| 5 | **Medium** | Findings metrics-first incomplete for docking/Boltz hollow | **FIXED** — stronger hollow detector + unit tests |
| 6 | **Medium** | hell-clinic false-green patterns | **FIXED** — API must not be ADMET-gated; cryo API assert always runs |
| 7 | **Medium** | Partial ZIP false success (0 files after S3 skips) | **FIXED** — sync 502 `download_all_empty`; async handler throws |
| 8 | **Low** | Voice settings comment “Settings → Chat” | **FIXED** |
| 9 | **Low** | `input_kinds` destructive heal deploy footgun | **DOCUMENTED** in `docs/20261113_EXAMPLE_ROUTING_FIXES_INPUT_KINDS.md` |
| 10 | **Low** | Strengthen voice-tab test beyond static regex | **FIXED** — asserts `updateSetting` wiring |

---

## 4. Fixes applied in this pass

1. **FF** worktree `d258bd32` → live `0b63d793` (restore deferred-materialize module + BASE_URL class files).
2. **Re-wire** `ensureDeferredDatasetsMaterialized` into Nextflow Confirm & Run (`routes.ts`) — root cause of “module restored, call site still missing”.
3. **Chain-hint honesty** — `messageSupportsCatalogChainHint` + shared Tier-2 guard in `galaxy-assistant.ts`.
4. **Catalog miss disambiguation** — no silent Tier-3 placeholders for mega-chain path.
5. **Download-all S3 unify** + `runId` query + panel async JobButton + empty-ZIP hard fail.
6. **Findings hollow** docking/Boltz empty table.
7. **Hell-clinic** assertion tighten; voice comment + tab test; input_kinds ops note.

---

## 5. Test evidence

```text
cd frontend && npx tsc --noEmit -p .
# TSC_EXIT:0  (~52s)

cd frontend && npx vitest run \
  server/library-triage-sequential.test.ts \
  server/findings-quality.test.ts \
  server/ml-training-findings.test.ts \
  server/jobs/__tests__/download-all-handler.test.ts \
  server/deferred-materialize.test.ts \
  client/src/components/settings-dialog.voice-tab.test.ts \
  client/src/components/voice-controls.test.tsx \
  client/src/components/live-voice-panel.test.tsx \
  client/src/components/findings-card.test.tsx \
  shared/findings-extract.test.ts
# Test Files  10 passed (10)
# Tests       110 passed (110)
# (post-run vitest cache EPERM on results.json is sandbox noise — tests green)
```

Pre-sync checklist items covered: **tsc** + targeted vitest (findings / voice / library-triage / download-all / deferred-materialize). Full `npx vitest run` optional if time; no Python galaxy module edits this pass → step 3 N/A.

---

## 6. Sync note

Fixes **need** to be on DEV (Confirm & Run materialize wiring, download-all S3, chain_hint, panel JobButton). After commit+push:

```bash
# From a host with AWS SSM / cleared proxies:
BIOMATE_SYNC_DB=0 bash scripts/sync_to_dev.sh
# Then re-check https://dev-public.biomate.ai/build-info.json
```

Do **not** sync from a tip that is not a descendant of the current live tip without ancestry merge first.
