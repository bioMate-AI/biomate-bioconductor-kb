BioMate + Nextflow Integration Progress
Timestamp: 2026-02-08 23:57

Scope
- Worktree: /home/yzhang/biomate_worktrees/connection_formal
- Goal: Nextflow is default execution engine; Galaxy workflows only when explicitly reused.

Changes Completed
1) Default Nextflow execution (transparent to user)
   - Engine selection now defaults to Nextflow unless workflow is explicitly marked as Galaxy reuse.
   - Galaxy reuse detection uses workflow metadata/tags/source flags.
   - Nextflow workflows are tagged with "nextflow".

2) Execution run tracking
   - Persisted execution engine in run records (storage + schema).
   - Execution status response now includes Nextflow status when applicable.

3) Output retrieval improvements
   - Fetch-outputs resolves run IDs to invocation IDs when needed.
   - Nextflow-specific fallback: if time-filtered outputs are empty, use all OK datasets from history.

4) Nextflow status integration
   - Added Galaxy API proxy method to read Nextflow status.
   - Run status endpoint returns `nextflowStatus`.

Files Updated
- frontend/server/routes.ts
- frontend/server/storage.ts
- frontend/server/galaxy-api-proxy.ts
- frontend/shared/schema.ts

Open Items (next steps)
- Add AutoFix 3.0 proxy endpoints on the frontend server.
- Wire AutoFix status/run into run details UI.
- Consider standardizing workflow "reuse source" markers for Galaxy workflows.
- Run E2E checks on Nextflow execution flow.

