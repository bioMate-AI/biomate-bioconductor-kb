# Temporarily disable Galaxy `.ga` Import Workflow (2026-11-15)

## Intent

BioMate personal imports execute as Nextflow (`file_content` → Batch). Offering `.ga` on Import was dishonest until Galaxy-engine invoke (or conversion) exists. **Not a permanent hard delete** — gated / commented so it can be re-enabled after testing.

## Change

Temporary fail-closed behind one flip:

```ts
// frontend/shared/personal-workflow-import.ts
export const GA_IMPORT_ENABLED = false; // TODO: re-enable when .ga execution is supported
```

| Layer | Change |
|-------|--------|
| Shared | `GA_IMPORT_ENABLED` drives allowlist; `.ga` commented with TODO |
| UI | `accept=` / labels omit `.ga`; client reject stays fail-closed |
| i18n | tip/hints say “temporarily disabled” |
| API | multer uses shared allowlist → 415 while gated off |
| Tests | assert `GA_IMPORT_ENABLED === false` + reject `.ga` |
| Checklist | import closed for now; re-open via flag |

## Re-enable

1. Set `GA_IMPORT_ENABLED = true`
2. Update tip copy if needed
3. Flip e2e/unit expectations that assert the gate is off

## Pre-sync prediction

With `GA_IMPORT_ENABLED=false`: Import file picker `accept` is `.nf,.yml,.yaml`; selecting `.ga` shows unsupported message and submit stays disabled; `POST /api/workflows/upload-file` with `.ga` returns **415**. Smoke should not claim `.ga` import success.

## Verify

```bash
cd frontend && npx tsc --noEmit -p .
cd frontend && npx vitest run shared/personal-workflow-import.test.ts \
  server/personal-workflow-upload-types.test.ts \
  client/src/components/workflow-history-dialog.import-accept.test.tsx
```
