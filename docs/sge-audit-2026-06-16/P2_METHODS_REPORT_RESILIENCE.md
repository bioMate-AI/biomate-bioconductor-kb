# P2 — Methods report resilience

**Status:** known issue; not blocking. Probable root cause identified; proposed fix below.

## Symptom

On the 2026-06-16 after-run audit, the Methods sub-tab inside `AfterRunReport` was hidden for every completed run (T02, T03, T05). The detection condition in `client/src/v2/AfterRunReport.tsx:103` reads:

```ts
if (methods.hasRealContent) t.push(["methods", "Methods"]);
```

`methods.hasRealContent` is set by the `useFetchMethods` hook (line 531+) only when the artifact body is non-empty AND not a known stub AND longer than 200 chars. If any step in the fetch chain throws, the catch on line 581 silently swallows it and `hasRealContent` stays false → tab never appears.

## Probable cause

`useFetchMethods` posts to `/api/jobs` to create a `methods_report` job, then polls `/api/jobs/<jobId>` for state. The job handler (`server/jobs/handlers/methods-report.ts`) loops back to `http://127.0.0.1:<PORT>/api/invocations/<id>/methods-report`. That endpoint:

1. Tries Galaxy proxy first
2. Falls through to local LLM-generated report via `llmGenerate` → backend Galaxy `/internal/llm/generate` → provider chain (Gemini → Claude → GPT → Qwen)

When any node in that chain is transiently unhealthy, the endpoint returns 502 with `{"error":"Methods report generation failed","details":"fetch failed"}`. The job handler throws; the hook's catch swallows it; tab stays hidden.

A direct curl on dev right after the audit confirmed 200 — so the fault is transient (Galaxy LLM proxy hiccup or temporary rate limit). The bug is **silent UX failure on transient backend errors**, not the absence of a methods report.

## Proposed fix (design, not yet coded)

`useFetchMethods` should distinguish three states:
- `hasRealContent=true` → render Methods tab with content
- `loading` → render Methods tab with skeleton + "Generating methods report…"
- `failed-retryable` → render Methods tab with error banner + Retry button

Logic:
```ts
type MethodsState = "idle" | "loading" | "ready" | "failed";
function useFetchMethods(id) {
  const [state, setState] = useState<MethodsState>("idle");
  // ... existing fetch + job loop, but expose the error
  return { text, toolVersions, hasRealContent, state, errorMessage };
}

// In AfterRunReport visibleTabs:
if (methods.hasRealContent || methods.state === "loading" || methods.state === "failed") {
  t.push(["methods", "Methods"]);
}
```

And the MethodsTab body renders accordingly. Same pattern the Outputs tab already follows (it shows the "No output files registered yet" placeholder rather than hiding the tab).

## Why not fix now

1. **Not blocking the audit's headline finding** — the Methods tab being intermittently hidden is a UX wart; the audit's value-prop (schema-grounded extraction + workflow execution) is independent.
2. **Needs a design pass** — the failure-banner copy and the Retry interaction shape need product/design alignment, especially around whether a single retry button is enough or whether we need exponential backoff.
3. **Galaxy LLM proxy stability is a separate workstream** — reducing the rate of transient failures upstream would also reduce the visible impact of this UX bug.

## Tracking

When picked up: write a vitest unit test for `useFetchMethods` that mocks a 502 response and asserts `state === "failed"` + `errorMessage` is set. Add a Playwright assertion to the after-run audit that the Methods tab is visible OR the failure state is rendered (currently it's neither).
