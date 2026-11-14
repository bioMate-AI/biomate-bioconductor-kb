# Harness measurement audit — REINVENT4 vs Cryo (2026-11-13)

User challenge: only consistent product error seen is **Cryo**; REINVENT4 was already fixed; are harness grades trustworthy?

## Verdict

**No — prior harness grades over-claimed REINVENT4 root cause and under-measured Cryo.** Soft After Run “oks” were also inflated. Treat `_pre_20261113_mixed` REINVENT rows as **stale / incompletely instrumented**, not as current product truth on tip `5dd9b6fb`.

## What the logs actually contain

### `design-generate-sm-0` (REINVENT4)

| Field | Logged value |
|--------|----------------|
| tip | `1001dec42` (ancestor of live `5dd9b6fb`, not tip) |
| `launch` | `confirm` (real click — not force) |
| `runId` | `f7aef7d2-86b7-4758-ba81-fc9d231c602a` |
| `terminal.status` | `failed` |
| `terminal.error` | **empty string** |
| After Run strip | `Process GENERATE_REINVENT4 (reinvent4_sampling) failed: Essential container in task exited — ERROR: REINV` (**truncated**) |
| Findings / Parameters tabs | `visible: false` — never opened |
| `outputsOk` / `findingsOk` / `paramsOk` | all `true` from the **same diagnosis banner** |

The audit doc line “`REINVENT4 CLI/package not found in container`” was **inferred from `main.nf`**, not captured verbatim from the run API or a full container log. That inference is unverified against live tip `5dd9b6fb`.

### Cryo

Coldstart deep mixed evidence folder has **no cryo case JSON**. Clinic hell covers Cryo **pre-run** (Movies Path required, Confirm blocked) and intentionally skips GPU when a license exists. Constant Cryo execution errors the user sees (Movies Path / license / panel) were **not** what the coldstart deep matrix graded as HONEST_FAIL for REINVENT.

### Harness bugs that polluted measurement

1. **Force / Confirm-anyway on disabled Confirm** — would launch Cryo without Movies Path and reproduce the same execution error every time. **Removed** (`confirm_blocked_required` → grade `BLOCKED_REQUIRED`).
2. **Empty `terminal.error`** — API field unused; UI fail strip not promoted into the JSON.
3. **Tab audit false positives** — diagnosis banner counted as Outputs + Findings + Parameters content without clicking Findings/Parameters.
4. **Root-cause upgrade** — truncated `ERROR: REINV` written up as full CLI/package message in docs.

## Harness fixes (this session)

- No force-click / Confirm-anyway for blocked required params.
- Grade `BLOCKED_REQUIRED` when Confirm stays disabled.
- Capture `failSnippet` / `errorObserved` from After Run text.
- Require real tab click; diagnosis-only banner ≠ `outputsOk`.
- Do not invent full error strings beyond what UI/API returns.

## What is still valid vs not

| Claim | Status |
|--------|--------|
| REINVENT4 routed correctly for generate-sm-0 | Valid (workflow name in JSON) |
| That run reached `failed` on tip `1001dec42` | Valid |
| Exact cause = CLI/package missing | **Not proven** from harness logs |
| REINVENT still broken on tip `5dd9b6fb` | **Unknown — needs re-measure** |
| Cryo consistent Movies Path / license class | Consistent with clinic + product; not covered by reinvent HONEST_FAIL rows |
| Soft after-run “pass” plumbing | Invalid for those REINVENT rows |

## Next measure (when flock free)

Re-run only `design-generate-sm-*` on live tip; store full `errorObserved`. Cryo coldstart cases must stop at `BLOCKED_REQUIRED` unless Movies Path + license are intentionally provisioned — never force Confirm.

## Superseded by 2026-11-14 committee

See `docs/20261114_COLDSTART_DEEP_COMMITTEE_AUDIT.md`. On tip `0b63d793`, generate-sm now has **full** `errorObserved` (`REINVENT4 CLI/package not found in container`) graded **HONEST_FAIL**; Cryo str-0/2 are **BLOCKED_REQUIRED**. Prior `DISHONEST_FAIL` over-call from `diagnosisOnly` was fixed and evidence regraded.
