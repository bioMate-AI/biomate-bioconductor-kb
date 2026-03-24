# BioMate Project Instructions

## Development Process

**Every task follows this iterative loop — no exceptions:**

1. **Implement** — write the code change
2. **Test** — run the relevant E2E or unit test suite
3. **Record** — capture screenshots / logs / audit JSON
4. **Audit** — visually review screenshots; read logs for regressions or wrong content
5. **Fix** — patch any failures or UI issues found in the audit
6. **Repeat** — loop until all assertions pass and screenshots look correct

Do not consider a task done until the full loop completes with a green test run and a clean screenshot audit.

## Documentation Rule

**All session documents, findings, plans, and technical notes MUST go into `docs/` or a subfolder of `docs/`.**

- Use date-prefixed filenames: `docs/20260318_TOPIC_NAME.md`
- Never create `.md` files in the repo root, backend root, or frontend root
- The `docs/` directory is the single source of truth for all written technical outputs

## Testing Rules

**NEVER mock API calls in E2E tests.** All E2E tests run against the live server with real backend responses. No `page.route()` interception, no `msw`, no `nock`, no stub responses. If a test requires data that depends on backend state, set it up through the real API or real UI actions.

Unit tests may use mocks only for external third-party services (e.g. AWS, Stripe) where real calls are impractical.
