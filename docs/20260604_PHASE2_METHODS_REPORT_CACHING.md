# Phase 2 — methods-report caching via async job system (2026-06-04)

Shipped + validated end-to-end on dev. Closes the 20s sync-Claude pain in the
AfterRunReport MethodsTab.

## What changed

| Commit | What |
|---|---|
| `e6ca058fb` | `feat(jobs): Phase 2 — methods_report caching via async job system` |

Files touched:

- `frontend/server/jobs/handlers/methods-report.ts` — new handler
- `frontend/server/jobs/artifact-store.ts` — filename plumbing through .meta sidecar
- `frontend/server/jobs/executor.ts` — wire filename from handler call
- `frontend/server/jobs/router.ts` — use filename in `Content-Disposition` (sanitized)
- `frontend/server/routes.ts` — side-effect import to register handler
- `frontend/client/src/v2/AfterRunReport.tsx` — `useFetchMethods` now drives through `/api/jobs`

## Design

The legacy `GET /api/invocations/:id/methods-report` does ~600 LOC of:
parameter extraction → S3 inventory → JSON metric extraction → Claude Sonnet
prose synthesis. Cold path is 20–60s; the MethodsTab calls it on every mount.

Rather than refactor the 600 LOC (high risk, low reward for Phase 2 scope),
the handler **wraps the endpoint via loopback**:

```
useFetchMethods → POST /api/jobs (kind=methods_report)
                ↓
            executor → handler → http://127.0.0.1:3000/api/invocations/:id/methods-report
                                ↓ (same 600-LOC generator runs)
                            writes bytes verbatim into ArtifactWriteHandle
```

This guarantees byte-for-byte parity with the legacy endpoint (modulo Claude
nondeterminism). The legacy endpoint stays alive as the source of truth.

Properties this buys us (from §6 of the design doc):

- **Dedup**: simultaneous MethodsTab opens for the same invocation coalesce
  on one in-flight job — Claude is invoked once, not N times.
- **24h artifact TTL**: reopening the report within the window returns
  cached bytes in <500ms.
- **Cancellation**: the AbortController is wired through the in-flight
  fetch; if the user navigates away the executor stops the Claude call.
- **Per-user concurrency cap of 3**: a user can't queue 100 reports at once.

## Cross-cutting improvement: filename plumbing

Previously the artifact store accepted a `(jobId, contentType)` only; the
handler-supplied filename was discarded and the router defaulted
`Content-Disposition` to `filename="<row.id>"` (a UUID). Now:

- `ArtifactStore.open(jobId, contentType, filename?)` — added param
- `LocalArtifactStore` persists `filename` in the `.meta.json` sidecar
- `ArtifactReadResult.filename` populated on read
- Router sanitizes (`["\r\n]` → `_`, header-injection safe) and uses it

Result: the browser's Save-As dialog now shows the right name
(`run_report_<workflow>_<id8>.txt`) on both Phase 1 (`download_all_zip`) and
Phase 2 (`methods_report`) artifacts.

## End-to-end validation on dev

Test fixture: synthetic `execution_run` row pointing at a real cryo-EM S3
output prefix (`s3://biomate-nextflow-work/nextflow/outputs/unknown/1219b68a`)
that has 121 actual files including motion/CTF/picking/extraction/class2D/
selection/refinement/FSC reports. Cleaned up after testing.

### Latency

| Path | Time | Note |
|---|---|---|
| Legacy `GET /methods-report` (cold) | 19.6s | Claude dominates |
| Job system (cold) | 22s | +2s overhead for queue insert + loopback |
| Job system (warm — cache hit via dedup) | **435ms** | **50× speedup** |

### Content fidelity

The cold artifact produced via the job path was compared section-by-section
against the legacy artifact and against the raw S3 JSON reports. Every
number in the prose traces to a source:

| Reported value | S3 source |
|---|---|
| 20 micrographs | `motion_report_batch_0000.json:num_micrographs` |
| 27,627 blob picks | `picking_report_batch_0000.json:num_particles` |
| 150 Å diameter | `picking_report_batch_0000.json:particle_diameter_angstroms` |
| 24,880 round-1 particles | `extract_report_batch_0000.json:num_particles` |
| 34,172 round-2 particles | `extract_report.json:num_particles` |
| 192 pixel box | `extract_report_batch_0000.json:box_size_pix` |
| 1.96 Å/px | `workflow_summary.json:pixel_size_angstroms` (overrode my test-fixture param 1.06 — correct precedence) |
| 300 kV | `workflow_summary.json:voltage_kv` |
| C1 symmetry | `workflow_summary.json:symmetry` |
| 23 steps completed | `workflow_summary.json:steps_completed` |

**Zero hallucinated numbers**. The system-prompt directive
("Every number MUST come from the EXTRACTED METRICS provided — do not invent
or estimate values") held.

### Output structure

- 6/6 expected sections (`ABSTRACT`, `METHODS`, `DATA`, `OUTPUT`, `FINDINGS`,
  `SUMMARY`) present as `## H2` headings.
- Markdown DATA table with metric|value rows.
- 530 words total (within the 600-word system-prompt cap).
- Zero `MISSING` markers leaked into the final prose.
- Zero `not available` / `not captured` markers — those metric values were
  correctly filtered out of the `metricsBlock` passed to Claude.

### Cache integrity

- Warm-path artifact bytes are **byte-for-byte identical** to the cold-path
  artifact bytes from the same job — `diff -q` confirms.
- POST with the same `(kind, invocationId)` payload returns the same `jobId`
  in 435ms with `state="ready"` immediately (dedup hit).
- `expiresAt = readyAt + 24h` per the design.

### Filename

`Content-Disposition: attachment; filename="run_report_CryoSPARC_SPA_Test__test-met.txt"`
— from the upstream endpoint's disposition, parsed and rethreaded through
the artifact store, present after cache hit. (Previously was just the raw UUID.)

## What this changes for users

- **First open**: same wait as before (20s+). The progress bar in the
  MethodsTab now shows live state instead of a spinner.
- **Re-open within 24h**: report appears in <1s instead of triggering
  another 20s Claude call.
- **Multiple tabs / multiple users on same invocation**: only one Claude
  call gets made; others reuse it.
- **Filename in the download dialog**: a real name instead of a UUID.

## What's NOT cached yet (future phases)

- The legacy `GET /methods-report?format=docx` path: handler accepts
  `format='docx'` in payload but the frontend never sets it. Wiring the
  AfterRunReport's "Download DOCX" button to the job system is Phase 2.1.
- The DOCX generation itself currently happens synchronously inside the
  legacy endpoint via `pandoc`. Phase 5 (`docx_export`) reuses this pattern
  with its own kind.

## Open follow-ups

- **Phase 3** (`reproducibility_bundle`) — same shape as Phase 1, lower
  priority.
- **Phase 4** (`findings_analysis`) — replaces the FindingsCard's bespoke
  5s polling with `useJob`.
- **Branding sweep (1.6)** — server field rename + URL path rename for the
  rest of the `nextflow`-suffixed user-facing surfaces. Still awaiting
  go-ahead.
- **Gap B from 2026-06-03** — output ZIP download still broken for pipeline
  runs (both endpoints' resolveInvocation is Galaxy-only). Pre-existing.
