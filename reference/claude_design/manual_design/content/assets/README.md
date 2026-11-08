# User-manual screenshot assets

Real screenshots of the live BioMate UI (dev) referenced by the manual chapters. **Honesty rule:
screenshots are of the actual current UI — never mocked.** If a surface can't be captured yet
(e.g. needs a completed run we don't have), the chapter keeps the placeholder + `CAPTURE` spec and
the shot is filled in a later capture pass rather than faked.

## Convention (used by every chapter)

Where a visual helps, a chapter contains:

```
![<caption of what the reader sees>](../assets/<chapter>-<n>-<slug>.png)
<!-- CAPTURE route=/<path> ; state=<preconditions> ; focus=<data-testid/element> ; note=<what to show> -->
```

The `CAPTURE` comment is the **shot list**: the capture harness reads route/state/focus and produces
`<chapter>-<n>-<slug>.png` here.

## Capture harness

`frontend/e2e/manual-screenshots.spec.ts` (Playwright) logs in with the canonical fixture
(`lifeifei163361@163.com`, `x-e2e-test-token`) per `CLAUDE.md`, navigates each route, and screenshots
the focused element/full page into this directory.

- **Accessible now** (no run needed): cold start (`/` new chat), composer, `/files`, `/models`,
  `/design`, `/capabilities`, a search answer (LLM).
- **Run-dependent** (needs a completed run): the run panel, after-run report (Summary/Outputs/
  Reproducibility record), full step view. Captured from a real completed run, or deferred with the
  placeholder intact.

Run: `cd frontend && npx playwright test e2e/manual-screenshots.spec.ts` (dev target).
