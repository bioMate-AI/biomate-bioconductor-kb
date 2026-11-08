# Legacy run alias access repair — 2026-11-07

A live read-only probe found that the legacy reproducibility endpoint returned an existing owned fixture's export without authentication, while the canonical reproducibility endpoint required login. No private export contents are recorded here.

The repair applies authenticated registered-run resolution before legacy handlers can proxy or mutate. Read access uses the same owner/project-member policy as canonical run outputs. Mutations require the run owner. Frontend, Galaxy invocation and Nextflow aliases normalize to a registered execution record; an unknown raw backend ID is never treated as authorization.

Additional boundaries: both compared runs must be readable; iteration children are filtered individually; output saving requires write access to the destination project. PATCH accepts only validated parameter/data-scope changes and rejects forged ownership, execution/output bindings and trusted launch snapshots. Shared membership callbacks now use the real project repository instead of an absent storage method.

## Post-deployment verification

Using only a dedicated synthetic QA run or an existing owned test fixture, check these GET aliases without cookies, bearer token or API key. Each must return **401**, without export/log/run/output content:

- `/api/workflows/runs/<run-or-invocation-id>`
- `/api/workflows/runs/<run-or-invocation-id>/status`
- `/api/workflows/runs/<run-or-invocation-id>/download_commands`
- `/api/workflows/runs/<run-or-invocation-id>/iterations`
- `/api/workflows/runs/<run-or-invocation-id>/reproducibility`
- `/api/workflows/runs/<run-or-invocation-id>/compare?with=<other-owned-test-run>`
- `/api/workflows/runs/<run-or-invocation-id>/logs`

Then authenticate as the owner: legacy reproducibility and status must still resolve the existing record, including the invocation alias. Unknown aliases must return 404. A different non-member must receive 403; a project member retains read access but cannot mutate another owner's run.

Do not execute pause, resume, rerun, cancellation, promotion, deletion or AI actions merely to check the deployed boundary. Their authentication/owner guards are exercised locally with mocked handlers. Optional anonymous method probes must be stopped by authentication before any side effect.

Local validation: the real legacy middleware is exercised with anonymous, stranger, owner, member, unknown-ID and lookup-failure requests; route wiring checks cover each alias. A separate strict-update test ensures parameter overrides remain valid while protected fields cannot be forged. Deployment verification remains pending until the repaired build is live.
