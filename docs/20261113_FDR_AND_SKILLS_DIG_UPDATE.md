# 2026-11-13 — FDR project-rule fills + dig skills catalog

## FDR / instruction obedience (closed)

**Symptom:** Project instructions carried Ref-Tag + genome + FDR in replies, but DE card sometimes showed `differential_max_qval=0.05` / `differential_min_fold_change=1`.

**Root causes:**
1. Galaxy already applied rule fills (`e62927c`); a bad probe used literal `$PID` in a quoted heredoc → no project rules → schema default 0.05.
2. Real class bug: with `SCHEMA_GROUNDED_EXTRACTION=1`, `groundInlineParameters` could overwrite rule-backed fills. Fixed by `mergeInlineParamsPreferringRuleFills` (`e5aabdb`).

**Proof on dig:** `instructions-obedience.e2e.ts` green (retries=0, twice): Ref-Tag `KX-7741`, `genome=GRCh38`, `differential_max_qval=0.01`, `differential_min_fold_change=2`. Tip at close of FDR work: `c119d8b3` / later ancestry tip `23036f10`.

## Skills & experts list on dig (in progress)

**Symptom:** Platform / Generator Adaptation showed long wall-of-text descriptions; list lacked UI groups / Evidence-Based Writer.

**Cause:** Short-description + foldable/line-clamp UI lived only on `feat/skills-architecture-20261111` (`fe957c7`, `ba377712`, `0edacff`) — not on F9 deploy tip. Dig `/api/skills` still served generator-adaptation description ~745 chars.

**Fix (this session):** Cherry-picked onto `fix/f9-turn-busy-and-cards-20261112`:
- `ba377712` — foldable groups + locked BioMate default + 2-line clamp
- `fe957c7` — short generator-adaptation frontmatter (~146 chars)
- `0edacff` — Evidence-Based Writer skill markdown

Pre-sync: `tsc` clean; `skills-selector.test.tsx` 18/18 pass.

**Synced:** Sync OK at `7e75daed` (frontend+backend), then **clobbered** by ds-audit tip `f41f884` (long generator desc + flat pre-groups UI). Screenshot 2026-11-13 confirmed.

**Restore:** ancestry-merge `f41f884` `-s ours` → `776d8da8`; force frontend+backend sync in flight. Expect again: generator desc ~146, Default locked group, 2-line clamp (`WebkitLineClamp: 2`).

## Open

- Confirm restore Sync OK + live `/api/skills` + UI groups.
- Re-run `chat-files-and-reports.e2e.ts` on dig; audit.
