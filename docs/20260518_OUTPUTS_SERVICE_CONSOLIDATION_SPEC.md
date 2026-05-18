# Outputs Service Consolidation — Spec for Review

**Date:** 2026-05-18
**Author:** Opus 4.7
**Branch:** `integration/next-phase`
**Status:** Spec for approval; not yet implemented
**Why this doc exists:** the same end-user failure ("I ran a workflow, my outputs don't show") has been patched in 8+ separate places across this session and prior ones. Each fix is real but only closes one symptom because there's no canonical outputs path. This doc proposes the one-path consolidation.

---

## 1. What's broken (catalog)

Every layer that touches outputs has its own implementation. Any one broken layer produces the same user-visible symptom (empty panel) but for a different reason.

### API layer (4 endpoints, 4 separate implementations)

| Endpoint | Code path | Storage source | S3 client | Recent fix |
|---|---|---|---|---|
| `GET /api/invocations/:id/outputs` | `routes.ts:6756` | MemStorage + `addOutput` + S3 fallback | own (us-east-1, NF creds) | `f8cd7affc`, `1298a9ff5` |
| `GET /api/workflows/runs/:id/outputs` | `routes.ts:9319` | proxies to `/output_files` | n/a | `6dd35a6ac` (UI switched to this) |
| `GET /api/workflows/runs/:id/output_files` | `routes.ts:9171` | `nextflowStatus.s3_output_files` + Galaxy fallback + S3 list | own (us-east-1, NF creds, but **was** us-west-2 default) | `3765ef87c` (today) |
| `GET /api/workflows/runs/:id/step-file?path=<s3>` | `routes.ts:9332` | direct S3 GET | own | — |

### Storage layer (4 places the same data hides)

- **MemStorage** (`storage.ts:71`) — primary cache, wiped on every container restart.
- **PostgreSQL `execution_runs`** — supposed to be durable, but had 11-column schema drift that silently broke every persist (`25a00b76d`, today).
- **`nextflowStatus.s3_output_files`** — populated during a live run by Galaxy SSE; lost on restart.
- **`_findingsCache`** — in-memory only.

### ID resolution (3 IDs identify the same run)

| ID | Set by | Used by |
|---|---|---|
| `runId` (executionRunId) | frontend `randomUUID()` on create | UI test, chat hooks, useQuery |
| `galaxyInvocationId` | Galaxy `/execute` response | nextflow_executor → `s3_output_files` keying |
| `nextflowRunId` | Nextflow itself | step-file proxy path construction |

`storage.getExecutionRun` and `getExecutionRunByGalaxyId` resolve some of these inconsistently. The Galaxy invocation ID and the frontend `runId` often differ for AWS Batch runs — the React component might fetch with one while outputs were registered under the other.

### UI layer (3 components, 3 gating logics)

- `nextflow-workflow-viewer.tsx` — gates ChatOutputAttachments on `invocationId && showResults`. Fixed today to also accept `runId` (`1abc2840f`).
- `chat-message.tsx` — same component, different prop derivation, no guarantee both surfaces agree on `invocationId`.
- `chat-output-attachments.tsx` — its own useQuery with dual-fetch (`2cfa66572`), its own filter (`NF_INTERNAL_RE`, `size===0`), its own normalization.

### Format normalization (3+ output shapes in flight)

- `OutputDataset` shape (`metadata.s3Uri`, `fileType`, `isVisualizable`, `previewAvailable`) — what UI expects.
- `output_files` shape (`s3_uri`, `s3_bucket`, `s3_key`, `filename`, `extension`) — what `/output_files` endpoint returns.
- Galaxy live status `s3_output_files` shape — yet another variant.

`chat-output-attachments.tsx` does its own translation between these. The translation is brittle (today's symptom: viewer wouldn't mount because the chain dropped fields).

---

## 2. Proposed consolidation

### One service: `frontend/server/services/runs-outputs-service.ts`

```ts
// Single source of truth. Every endpoint, every UI consumer goes through this.

export interface CanonicalOutput {
  id: string;                  // stable: `${runId}:${s3Key}` (idempotent)
  name: string;                // filename only
  extension: string;           // lowercased, no dot
  size: number;                // bytes (0 if unknown but always set)
  fileType: FileType;          // density_map | structure | image | table | sequence | binary | …
  downloadUrl: string;         // presigned S3 URL, 1hr TTL — always set
  s3Uri: string;               // canonical s3://bucket/key
  step?: string;               // step name if derivable (CryoSPARC dir, NF process)
  previewable: boolean;        // true if browser-renderable
}

export interface CanonicalRunMeta {
  runId: string;
  galaxyInvocationId: string | null;
  nextflowRunId: string | null;
  s3Outdir: string | null;     // canonical s3://bucket/prefix/
  status: ExecutionStatus;
  workflowName: string;
}

export class RunsOutputsService {
  // ONE id resolver. Accepts any flavor; returns canonical meta or null.
  async resolve(anyId: string): Promise<CanonicalRunMeta | null>;

  // ONE listing path. Tries (in order): MemStorage cached files → PG cached files
  // → S3 list. Result is normalized and presigned.
  async list(anyId: string): Promise<CanonicalOutput[]>;

  // ONE step-file proxy that knows how to map any output ID back to S3 bytes.
  async fetchBytes(anyId: string, outputId: string): Promise<NodeJS.ReadableStream>;
}
```

S3 client is a singleton inside the service: `us-east-1`, `followRegionRedirects: true`, NF creds when available, falls back to default chain. No more drift.

### One endpoint (with backward-compat aliases)

```
GET /api/runs/:anyId/outputs           → canonical
GET /api/invocations/:id/outputs       → 301 → /api/runs/:id/outputs
GET /api/workflows/runs/:id/outputs    → 301 → /api/runs/:id/outputs
GET /api/workflows/runs/:id/output_files → 301 → /api/runs/:id/outputs

GET /api/runs/:anyId/files/:outputId   → fetch bytes (replaces step-file)
GET /api/workflows/runs/:id/step-file  → 301 → above
```

### One UI consumer: `<OutputsPanel runId={runId} />`

```tsx
// Replaces ChatOutputAttachments. Renders WHENEVER runId is set —
// no `&& invocationId && showResults` gymnastics. Inside:
//   - useQuery(['outputs', runId]) → service
//   - Switch on fileType → DensityMapViewer, StructureViewer, …
//   - One filter list, declared once
```

Old `ChatOutputAttachments` becomes a thin re-export so callers don't break during migration.

### Storage truth source

Single write path: when a run is registered, `RunsOutputsService.registerRun()` writes the canonical meta to PostgreSQL. MemStorage becomes a 60-second cache only. Lookups always hit PG (fast), wrapped by MemStorage for hot data.

---

## 3. Migration plan (3 PRs, each independently shippable)

### PR 1: Service + canonical endpoint (no UI changes)

- Add `runs-outputs-service.ts` with `resolve()` + `list()` (`fetchBytes` deferred).
- Add `GET /api/runs/:anyId/outputs` returning canonical shape.
- Existing 4 endpoints unchanged.
- Service has unit tests for each ID resolution path + each listing fallback.

Shipping bar: `curl /api/runs/<v14_runId>/outputs` returns 258 normalized items with `downloadUrl` present.

### PR 2: UI migration

- Add `<OutputsPanel>` component using the new endpoint.
- Replace both `<ChatOutputAttachments>` call sites in `nextflow-workflow-viewer.tsx` and `chat-message.tsx`.
- Delete the dual-fetch + normalization in `chat-output-attachments.tsx`.
- Existing test selectors (`data-testid="density-map-viewer"`, `phase-card-preview-btn-*`, etc.) preserved.

Shipping bar: v15-equivalent super-test passes (or fails on a single line that points at the service, not the UI).

### PR 3: Legacy endpoint removal

- 301 the 4 old endpoints to canonical.
- Delete the old listing + normalization code.
- Delete unused storage paths.

Shipping bar: no production code outside `runs-outputs-service.ts` constructs an `S3Client` for output listing.

---

## 4. Out of scope (deliberately)

- Galaxy backend `nextflow_executor.py` task_files emission — stays as-is. The service consumes whatever Galaxy provides; if Galaxy's payload changes, only the service's parser changes.
- Auth/quota — the service inherits whatever middleware is on the endpoint.
- Sidecar `run_code` (separate track, `5b9e70164`).
- CI/CD migration (parallel agent).

---

## 5. Cost estimate

- PR 1: ~1 day (service + tests + canonical endpoint).
- PR 2: ~½ day (UI migration; mostly delete code).
- PR 3: ~½ day (301s, delete old paths, manual smoke).
- Total: ~2 days of focused work, but the trailing benefit is that a future "outputs don't show" bug is now a 1-file investigation instead of a 4-endpoint hunt.

---

## 6. Decision needed from reviewer

- [ ] Approve the consolidation plan as drafted.
- [ ] Modify and approve (call out which sections to change).
- [ ] Reject — keep patching individual surfaces.

Once approved I'll start PR 1 immediately.
