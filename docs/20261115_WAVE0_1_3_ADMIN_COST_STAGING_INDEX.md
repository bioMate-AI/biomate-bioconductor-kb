# Wave 0 + Wave 1 (admin cost) + Wave 3 (staging indexes) — 2026-11-15

**Branch:** `devline/ds-audit-20261112`  
**Scope:** Open-leverage roadmap Waves 0, 1 (into existing admin), 3. Waves 4–7 not started. IGV (Wave 2) left untouched except if a regression is introduced.

## Admin surface found (Wave 1)

- **Existing:** `/admin` → `SystemDashboardPage` (`frontend/client/src/pages/admin/system-dashboard.tsx`)
  - Already hosts Health / Run stats / LLM probe / LLM config behind `subscriptionTier === 'admin'`.
  - APIs already gated with `authenticateToken` + `requireAdmin` in `routes.ts`.
- **Not created:** parallel `/admin/cost` page (user correction).
- **How cost landed:** new **CostPanel** card on the same `/admin` dashboard + routes:
  - `GET|POST /api/admin/cost/estimate`
  - `GET /api/admin/cost/runs/:runId`
  - `GET /api/admin/cost/compare`
- Honesty: `confidence: historical | prior | unavailable` + vCPU-hrs; public `/api/workflows/estimate_cost` no longer invents `$0.50–$5` on 503.
- User panel: `CostEstimateBadge` stays commented; `wiring-contracts` §5 still asserts absent. `OPEN_IN` untouched.
- Optional: `execution.costEstimateSnapshot` written at launch for admin compare.

## Wave 0

1. FTP / remote fetch keys: `users/{userId}/remote/{projectId|inbox}/{uuid}-{filename}` (Galaxy `fetch_public_data` + Node proxy passes `user_id`/`project_id`; Data Hub picker sends `project_id`; fetch timeout 120s).
2. Datatype gate: bare param `input` is samplesheet-gated **only** when schema hints samplesheet/csv/tsv; FASTA on generic `input` no longer hard-blocks. Unit tests added.
3. Live smoke: `frontend/e2e/wave0-deferred-ftp-smoke.e2e.ts` (fixture account, `_e2e-base-url` precedence, password from env/file never printed).

## Wave 3

- `frontend/server/staging-index.ts`: fail-closed `samtools index` / `tabix -p vcf` before Batch staging.
- Execute path: 409 `staging_index_failed` if tool missing or index fails.
- `stageLocalFilesForBatch` also uploads sibling `.bai` / `.tbi` next to staged objects.

## Checklist

See `docs/20261113_GALAXY_COVERAGE_CHECKLIST.md` updates for FTP uniqueness, admin cost, converters/indexes Partial→Have for staging path.
