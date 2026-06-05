# Bug — legacy findings endpoint never parses Claude's JSON output (2026-06-04)

Surfaced during Phase 4 validation. **Pre-existing — not introduced by
Phase 4**.

## Symptom

`GET /api/workflows/runs/:id/findings` returns:
```json
{
  "summary": "{\n  \"summary\": \"The CryoSPARC SPA test workflow successfully processed 20 movies...\",\n  \"key_results\": [...]\n}",
  "key_results": [],
  "caveats": [],
  "next_steps": []
}
```

The entire JSON response from Claude — including the structured
`key_results`, `caveats`, `next_steps` it produced — is dumped verbatim
into the `summary` field as a string. The dedicated structured fields
are always empty.

## Impact

FindingsCard reads `key_results` directly to render its bulleted panel.
For every AWS Batch run that doesn't have a pre-existing
`findings_data.json` sidecar on S3 (i.e. nearly all of them today), the
panel is silently empty. The user sees only the `summary` field, which
itself is a barely-readable JSON blob with escaped quotes.

## Where to fix

`frontend/server/routes.ts` around line 10739 (`const runAsync`). After
Claude returns its response, the code stuffs the raw string into
`_findingsCache.set(runId, ...)` without parsing it as JSON and splitting
into the four structured fields.

The Phase 4 wrapper faithfully mirrors this buggy shape — that's by
design (the wrapper's job is parity). Fixing it in legacy will also fix
the Phase 4 cached artifacts produced after the fix.

## How to fix

```ts
// After Claude returns its synthesis (currently writes raw text to cache):
let parsed: Record<string, any> = {};
try {
  parsed = JSON.parse(synthesisText);
} catch {
  // Fall back to raw text in summary if Claude didn't return JSON
  parsed = { summary: synthesisText };
}
_findingsCache.set(runId, {
  summary: parsed.summary ?? '',
  key_results: parsed.key_results ?? [],
  caveats: parsed.caveats ?? [],
  next_steps: parsed.next_steps ?? [],
});
```

## Severity

P1 user-visible. The findings tab is a primary value-prop of the
AfterRunReport and it's currently degraded for the dominant run type.
