# Remove Galaxy `.ga` from Import Workflow (2026-11-15)

## Intent

BioMate personal imports execute as Nextflow (`file_content` → Batch). Offering `.ga` (Galaxy workflow JSON) on the Import Workflow path was dishonest — files could be stored in `personal_workflows` but were not runnable as Nextflow / Galaxy-engine invoke.

## Change

Fail-closed: strip `.ga` from the import surface and reject at the API.

| Layer | Change |
|-------|--------|
| Shared allowlist | `frontend/shared/personal-workflow-import.ts` — `.nf`, `.yml`, `.yaml` only |
| UI | `workflow-history-dialog.tsx` — `accept=`, labels, tip copy, client-side reject |
| i18n | en/zh `workflows_library.import_tip` + hint strings |
| API | `POST /api/workflows/upload-file` multer filter → 415 with clear `.ga` message |
| Tests | shared unit + routes wiring + dialog accept/reject; e2e `.ga` expects reject |
| Checklist | `docs/20261113_GALAXY_COVERAGE_CHECKLIST.md` Wave-7-ish row → import closed |

## Out of scope

- Full Galaxy-engine labeling everywhere (Wave 7 remainder)
- Deleting already-imported `file_type=ga` rows (legacy open path unchanged)
- Waves 5–6

## Verify

```bash
cd frontend && npx tsc --noEmit -p .
cd frontend && npx vitest run shared/personal-workflow-import.test.ts \
  server/personal-workflow-upload-types.test.ts \
  client/src/components/workflow-history-dialog.import-accept.test.tsx
```
