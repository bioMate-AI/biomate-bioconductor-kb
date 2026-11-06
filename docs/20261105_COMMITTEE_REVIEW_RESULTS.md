# Multi-model committee review — results + disposition (2026-11-05)

Four reviewers on different models audited this session's work against
`docs/20261105_WORK_AND_TEST_MANUAL.md`. Per the "experts may be right or wrong" rule, EVERY finding
was re-verified against the code before acting; verdicts below are mine after that check.

## Members
- **Haiku** — mechanical cross-cutting sanity.
- **Sonnet** — chat/UI + billing + run-record + test legitimacy.
- **Opus** — findings-pipeline correctness + regressions.
- **Fable** — the review-patch DIAGNOSES (`.nf`/backend docs).

## What the committee VALIDATED (independently corroborated across members)
- Core #5a (A sidecar-shape, B 90s bound, D response-contract, E Anthropic-key), the shadow's
  side-effect-freeness, S3#2 DESeq2 autodelim, S3#4 MODIFIER exact-match, #8 finalization, #9, and
  the reconcile-test legitimacy — all judged correct. tsc clean; suites green.

## Confirmed real → FIXED in frontend (commit 157af08b1; tsc + vitest 2183/0)
| Member | Issue | Fix |
|---|---|---|
| Sonnet-1 | empty-schema param guard dropped ALL inline params incl. user-supplied SMILES/dataset refs (a regression I introduced) | drop only when a schema is present to validate against; test reverted |
| Opus-2 | `reconcileFindingsDocument` early-return trusted a document false-positive over a CLEAN deterministic flat | `flatIsDeterministic` flag; deterministic call passes true; +2 tests |
| Opus-1 | rare-disease parser reported a truncated ~8KB PREVIEW count as "Variants analyzed" + whitelisted it to the LLM | relabel as preview; de-whitelist the total |
| Opus-3 | DESeq2 col-0 gene fallback mislabeled with numbers when col 0 is numeric or == LFC/padj | fall back to col 0 only in the true empty-header row-name case |
| Sonnet-3 | billing storage "$0.15/GB" over a PUT count; GPU row duplicated the single total_seconds as hours | blanked both unreconcilable cells |

## Confirmed real → FIXED in the review-patch DOCS (these would have broken workflows if applied)
| Member | Doc | Correction |
|---|---|---|
| Fable-1 | GEO patch | R block WON'T COMPILE (verified via `nextflow run`): escape every R `$`→`\$`, `\d`→`\\\\d`/`[0-9]`, avoid `$|`; `^source_name` exclusion risky. ⚠️ section added. |
| Fable-2 | phase2_dose (NF §2) | `primary_dose=None` → TypeErrors; `unknown=NOT-safe` over-corrects (default mtd_auc null → never recommends). Revise: keep unknown as a 3rd "provisional" state; explicit status not None. |
| Fable-3 | NF §5 ADMET per-compound DILI | MISLOCATED — the `.nf` already writes per-compound from the compound's own value; the overstated value (if real) is in a CONSUMER. Re-scope / drop. |
| Fable-6 | DILI patch "same bug" | `ADMET_pred` overrides DILI from a **ClinTox** prob (no DILI model) — identical fix does NOT transfer; would set `dili := clintox`. Corrected. |
| Fable-4 | B4 (GOLD on zero gates) | real but NOT live-reachable where claimed; latent hygiene, downgraded. |
| Fable-5 | B6 (`inf` quota) | mechanism is an HTTP **500** (allow_nan=False → ValueError), not an `Infinity` token the browser rejects; verify a 500. |
| Fable-3b | docking (NF §3) | correct, but `params.smoke_test` must be exported via `script:` or it's an unused param. |

## Rejected-with-reason (verified NOT a regression/bug)
- **Sonnet-2 "reconcile re-creates the contradiction"** — my S3#1 fix made the DOCUMENT self-consistent
  (its target); the flat-vs-document issue it raised is the pre-existing, already-shadow-gated
  simplification. Opus-2's precise version (clean-deterministic case) WAS a real hole and is now fixed.
- **Opus-4 / Sonnet-4 `stepKeyFromUri`/SSE collision on a shared trailing token** — niche (duplicate-token
  processes), no worse than pre-fix; documented, no code change.

## Net
The committee validated the big-ticket fixes and caught a cluster of my own over-corrections (Sonnet-1,
Opus-1/2/3, Sonnet-3) + two review patches that would have broken workflows (GEO, phase2_dose) + several
diagnosis inaccuracies. All frontend items fixed + shipped; all doc items corrected with ⚠️ sections so a
human applier sees them first. "No one does it perfect once" — borne out, and fixed together.
