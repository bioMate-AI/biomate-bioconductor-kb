# 2026-06-10 — v2 Bioconductor-handoff progress + test/integration plan

## Scope

Working from `reference/claude_design/bioconductor-handoff/HANDOFF_BIOCONDUCTOR.md`
(the engineering handoff for the three Bioconductor tutorials), this session
ported three design surfaces from the legacy prototype (`v2/Modals.tsx`
`@ts-nocheck` JSX with `window.*` globals) into strict-TS components in
`v2/`, behind RTL unit tests. None of this is merged into `integration/next-phase`
yet — per "don't touch biomate until tested" — it all lives on
**`bioc/v2-qc-audit-panel`**.

Earlier in the same session (now isolated on `billing/wallet-adapter-test`):
billing-side work — JavaBillingClient wallet/plan adapter, the envelope-check
silent-corruption fix, 2s→10s timeout for Stripe-syncing endpoints, plus
repair of 8 stale tests in `test_billing_regression.py`. Documented separately
in `docs/20260610_BILLING_TEST_AUDIT.md`.

## Branch state

```
integration/next-phase          ← untouched (no v2 / no billing fixes)
billing/wallet-adapter-test     ← billing adapter + envelope fix + timeout
bioc/v2-qc-audit-panel          ← v2 QC audit panel + Findings figures + DisambigCard
```

Both side branches are local — no remote pushes.

## Commits on `bioc/v2-qc-audit-panel`

| SHA | What | Tests |
|---|---|---|
| `8050e6c3d` | Rich `QcAuditTab` in `v2/AfterRunReport.tsx` — 4-stat header, audit log with PASS / FAIL→loop styling, chain-of-custody, hide-when-empty e-signature | 6 RTL |
| `06b7165ca` | `FindingsFigure` type + `FigBars` / `FigComposition` / `FigQc` / `FindingsFiguresPanel` data-driven figures | 4 RTL |
| `5224fcafd` | `v2/DisambigCard.tsx` strict-TS standalone (score + recommended badge + detail + countdown auto-select) | 8 RTL |

**18 RTL tests total — the first ever tests in `frontend/client/src/v2/`.**
tsc clean across the side branch. Full vitest suite stays green.

## Design fidelity matrix (handoff §3.5 + §5.1 + §5.7)

| Handoff element | Where it lives now | Production-ready? |
|---|---|---|
| 4-stat QC summary (Gates evaluated / Passed / Auto-corrected / Manual) | `v2/AfterRunReport.tsx` `QcAuditTab` | ✅ |
| QC audit log (Time/Gate/Threshold/Observed/Result/Action) | same | ✅ |
| Chain-of-custody (SHA-256 versioning copy) | same | ✅ static copy; real hash record needs backend |
| Operator e-signature (reviewer + TOTP) | same | ✅ component ready; **hidden until backend supplies record** |
| `FigBars` horizontal bars with highlight row | `v2/AfterRunReport.tsx` | ✅ |
| `FigComposition` stacked single-bar + legend | same | ✅ |
| `FigQc` conic-gradient retention ring | same | ✅ |
| "Figures from manifest, not LLM" contract note | same | ✅ |
| `DisambigCard` (score + recommended + detail + countdown auto-select) | `v2/DisambigCard.tsx` | ✅ standalone; not wired to chat yet |
| Reasoning blocks + `(why?)` anchors | only in v2/ChatStream.tsx `@ts-nocheck` demo | ❌ no strict-TS port yet |
| Section signposts (Understanding / Choosing / Running / Found) | only in legacy demo | ❌ needs backend `section` SSE events |
| Bioc tutorial demos (FF markers) | reference only | ❌ demo feature; low priority |

## Backend contracts the v2 panels rely on

| Endpoint | Used by | Status |
|---|---|---|
| `GET /api/workflows/runs/:id/qc-events` | `QcAuditTab` via `useFetchQcEvents` | Endpoint exists; need to verify the `{events:[…]}` shape includes the fields the rich panel reads (`ts`, `gate`, `threshold`, `measured`, `status`, `message`) and that `status` values map cleanly onto our `isPassedStatus`/`isAutoCorrectedStatus` heuristics. |
| `POST /api/jobs` (kind: `findings_analysis`) → `GET /api/jobs/:id/artifact` | `FindingsFiguresPanel` via `useFetchFindings` | Backend currently emits `{status, summary, key_results, caveats, …}`. **`figures` is a new optional field** — backend needs to populate it from the run manifest for the figures panel to ever render in prod. Tests use mocked payload. |
| `GET /api/workflows/:name/citations` | `CitationsTab` | Endpoint exists; **`workflow_chains.citations` rows for the 3 bioc chains are empty** — chains will show no citations until populated. |
| Disambiguation card | `chat-message.tsx` | Backend emits `workflow_type:'disambiguation'` already (`ai_assistant.py` ~line 2941). The v1 `WorkflowDisambiguationCard` exists but is **dead code** — never invoked. v2 `DisambigCard` ready to take its place. |

## What still needs to happen for production

### Frontend integration (small)
1. Replace `v1 WorkflowDisambiguationCard` import + render in `chat-message.tsx`
   with `v2/DisambigCard` (or just enhance v1 in place). Map backend `candidates[]`
   onto `options[]`.
2. Confirm `v2/AfterRunReport` is consumed by `nextflow-workflow-viewer.tsx`
   (already integrated in commit `924138d00a` earlier this session).

### Backend (each one independent)
1. **`workflow_chains.citations`** — populate for `bulk_rnaseq_de_analysis`,
   `methylation_450k_array_analysis`, `scrna_adt_multimodal_via_scrapper`
   (Love 2014, Zhu 2019, Aryee 2014, Phipson 2016, Amezquita 2020, Lun 2019).
2. **Findings `figures[]`** — extend the findings_analysis job to emit
   `figures: [{kind:'bars',…}, {kind:'composition',…}, {kind:'qc',…}]`
   sourced from the run manifest (not LLM).
3. **QC e-signature record** — extend `/qc-events` response or add a sibling
   `/qc-signature` endpoint that returns `{reviewer, reviewedAt, sigShort, totpVerified}`.
4. **SSE `section` events** — the chat narrative arc (Understanding / Choosing /
   Running / Found) requires backend SSE emission. Currently absent.

### Tests needed before video / demo
1. Backend contract probe on dev — see `task #44`.
2. RTL edge cases — fetch failure, empty event list, malformed JSON envelope.
3. Real E2E against dev: kick a real workflow with QC events, screenshot each
   tab, verify rich panel rendering end-to-end.

## Video prep

I cannot record video. What's needed for the user to record:

1. **Dev must have the side branch deployed** — sync `bioc/v2-qc-audit-panel`
   to dev EC2 (after user approval; same pattern as the billing branch).
2. **A real workflow run with QC events** to populate the rich audit panel.
   ADMET (small SMILES list, fast) or any nf-core run that exercises a
   gate from `qc_evidence.yaml`.
3. **Real findings figures** require backend change #2 above. Until then,
   the video only shows the figures panel hidden (which IS the
   correct hide-when-empty behavior — could be a demo point too).
4. **DisambigCard demo** requires a query that produces close KB scores.
   The bioc_kb scenario in the design uses "DESeq2 vs BP4 best-practices"
   as the canonical example.

Click path for the video:
1. Send ADMET prompt → workflow panel opens (right side).
2. Confirm & Run → phase cards step through.
3. Wait for completion → After-run section unlocks at panel bottom.
4. Click each tab: Findings, Outputs, Methods, Parameters, Software,
   Citations, QC audit. Show each rich element.
5. (If disambig wired) Send a "DESeq2 RNA-seq" query → show ranked
   candidates with score + recommended badge + countdown.

## Files changed (side branch only)

```
A  frontend/client/src/v2/AfterRunReport.test.tsx   (10 tests)
M  frontend/client/src/v2/AfterRunReport.tsx        (+QcAuditTab rich +FindingsFigure types +Fig* +FindingsFiguresPanel)
A  frontend/client/src/v2/DisambigCard.tsx
A  frontend/client/src/v2/DisambigCard.test.tsx     (8 tests)
A  docs/20260610_V2_BIOC_HANDOFF_PROGRESS.md        (this file)
A  docs/20260610_BILLING_TEST_AUDIT.md              (billing session, separate side branch)
```
