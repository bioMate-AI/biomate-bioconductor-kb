# Wave 4 — BioMate-native pre-filled run landings (2026-11-15)

## Goal

Shareable pre-filled **run** links (CRO handoff / “run this exact card”), without Galaxy `workflow_landings` or re-enabling Open-in / Interactive Tools.

## Design choices

| Choice | Rationale |
|--------|-----------|
| New Postgres `run_landings` (not Galaxy table) | BioMate auth/history/project model; Node owns claim UX |
| Token URL `/run/:token` | Distinct from owner-scoped `/workflow/:id` drafts (`workflow_drafts`) |
| Create requires auth; preview public (name only); claim requires auth | Matches project join-link pattern; params never in public preview |
| Unknown token → 404; expired → 410 | Same existence policy as drafts / project ownership (404 not 403) |
| Reusable until expiry (claim_count audit) | CRO handoff: multiple recipients can open the same recipe |
| Payload: workflow id/path/name + `params` + optional `dataset_refs` / `workflow` object / `projectId` | Enough to open panel Confirm & Run ready; dataset refs stored for later binding |
| Panel open via synthetic chat session (`metadata.type === 'workflow'`, `source: 'run_landing'`) | Reuses existing ChatWithArtifacts auto-open (same as WorkflowDeepLink) |
| No Galaxy `workflow_landings` proxy; `OPEN_IN_AVAILABLE` stays false | Plan constraint |

## API

| Method | Path | Auth | Role |
|--------|------|------|------|
| `POST` | `/api/workflows/landings` | yes | Create → `{ id, token, url, claim_path, expires_at }` |
| `GET` | `/api/workflows/landings/:token` | no | Preview name/domain/expiry |
| `POST` | `/api/workflows/landings/:token/claim` | yes | Full payload for panel |
| `DELETE` | `/api/workflows/landings/:token` | yes | Creator revoke (foreign → 404) |

Claim URL: `{APP_URL}/run/{token}`.

## Files

- `frontend/migrations/0024_run_landings.sql`
- `frontend/server/run-landings.ts` + `run-landings.test.ts`
- `frontend/client/src/pages/RunLanding.tsx`
- Wiring: `routes.ts` (`registerRunLandingRoutes`), `App.tsx` (`/run/:token`)
- Checklist: `docs/20261113_GALAXY_COVERAGE_CHECKLIST.md` landings row → **Have**

## Out of scope (Waves 5–7)

S3 purge UX, in-app notification feed, `.ga` engine labeling.

## Tests

- `frontend/server/run-landings.test.ts` — route contracts, validation, panel merge, OPEN_IN stays false
- PRE_SYNC: `npx tsc --noEmit -p .` + `npx vitest run` (touched area + suite)
