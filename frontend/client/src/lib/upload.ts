/**
 * Shared client-side upload helper.
 *
 * Three real call sites need the same upload semantics — chat composer
 * attachments (chat-interface.tsx), the dataset browser (galaxy-dataset-browser.tsx),
 * and the dedicated FileUpload component (file-upload.tsx). Without this helper
 * each one was reimplementing the FormData POST, none of them branched on size,
 * and large files dead-ended at the 5 GiB hard cap.
 *
 * Path selection:
 *   - file.size <= 100 MiB → existing /api/datasets/upload (FormData → Galaxy)
 *   - file.size  > 100 MiB → /api/s3/upload/init → presigned PUT per part →
 *                            /api/s3/upload/complete → /api/datasets/register-path
 *
 * Large-file path features:
 *   - 3-way concurrent part PUTs
 *   - Per-part retry with exponential backoff (5 attempts, 0.5s base)
 *   - Abort the S3 multipart on failure so the user isn't billed for staged parts
 *   - Real progress (bytes done / total) via onProgress callback
 *   - Resumable: survives browser refresh / network interruption. State is kept in
 *     localStorage; on the next upload attempt for the same file (name + size), the
 *     already-uploaded parts are fetched from the server and skipped automatically.
 *     Stale sessions (> 20 hours) are discarded before MinIO's default 24-hour
 *     lifecycle cleanup removes the parts server-side.
 */

const SIMPLE_UPLOAD_MAX_BYTES = 100 * 1024 * 1024; // 100 MiB
const PART_CONCURRENCY = 3;
const PART_RETRY_ATTEMPTS = 5;
// Discard saved state after 20 h — MinIO's default lifecycle removes incomplete
// multipart uploads after 24 h, so anything older is unresumable server-side.
const RESUME_STATE_TTL_MS = 20 * 60 * 60 * 1000;

export interface UploadResult {
  // Galaxy dataset id when the simple path was used, OR the register-path id
  // after a multipart upload. Either way: the value to send to a workflow.
  datasetId?: string;
  // Galaxy-side dataset id (only populated by the simple/FormData path).
  galaxyDatasetId?: string;
  // S3 key written by the multipart path; undefined for the simple path.
  s3Key?: string;
  // S3 URI (s3://bucket/key) returned by the server — populated by the simple path
  // when the file was also staged to S3 for Nextflow/Batch workers.
  s3Uri?: string;
  // Which client path actually handled this upload (telemetry / tests).
  via: 'simple' | 'multipart';
}

export interface UploadOptions {
  description?: string;
  // Per-file progress in [0, 100]. Faked for the simple path (no XHR bytes),
  // real for the multipart path (sum of completed parts).
  onProgress?: (pct: number) => void;
  // Allow callers to plug their own fetch (test seams). Defaults to globalThis.fetch.
  fetchImpl?: typeof fetch;
}

// ── Resume state persisted to localStorage ────────────────────────────────────

interface ResumeState {
  uploadId: string;
  key: string;
  chunkSize: number;
  numParts: number;
  /** true when S3_ENDPOINT_URL is set (MinIO on-prem) — proxy URLs are reconstructed
   *  client-side and never expire, so no refresh-parts call is needed. */
  isOnPrem: boolean;
  /** Bucket name, used to reconstruct on-prem proxy URLs. */
  bucket?: string;
  /** Unix timestamp (ms) when the state was saved. */
  savedAt: number;
  /** Parts already confirmed by the server at the time of the last save. */
  completedParts: Array<{ PartNumber: number; ETag: string }>;
}

function resumeKey(file: File): string {
  return `bm-upload:${file.name}:${file.size}`;
}

function saveResumeState(file: File, state: ResumeState): void {
  try {
    localStorage.setItem(resumeKey(file), JSON.stringify(state));
  } catch { /* quota exceeded — ignore, resume just won't work */ }
}

function loadResumeState(file: File): ResumeState | null {
  try {
    const raw = localStorage.getItem(resumeKey(file));
    if (!raw) return null;
    const state = JSON.parse(raw) as ResumeState;
    if (Date.now() - state.savedAt > RESUME_STATE_TTL_MS) {
      localStorage.removeItem(resumeKey(file));
      return null;
    }
    return state;
  } catch {
    return null;
  }
}

function clearResumeState(file: File): void {
  try { localStorage.removeItem(resumeKey(file)); } catch { /* ignore */ }
}

// ── Part upload helpers ───────────────────────────────────────────────────────

async function putPartWithRetry(
  url: string,
  body: Blob,
  partNumber: number,
  fetchImpl: typeof fetch,
): Promise<{ PartNumber: number; ETag: string }> {
  let lastErr: unknown;
  for (let attempt = 1; attempt <= PART_RETRY_ATTEMPTS; attempt++) {
    try {
      const r = await fetchImpl(url, { method: 'PUT', body });
      if (!r.ok) throw new Error(`S3 part ${partNumber} HTTP ${r.status}`);
      const eTag = r.headers.get('ETag') ?? r.headers.get('etag');
      if (!eTag) throw new Error(`S3 part ${partNumber} returned no ETag`);
      return { PartNumber: partNumber, ETag: eTag };
    } catch (err) {
      lastErr = err;
      if (attempt < PART_RETRY_ATTEMPTS) {
        await new Promise(r => setTimeout(r, 500 * Math.pow(2, attempt - 1)));
      }
    }
  }
  throw lastErr;
}

/** Build the proxy URL for an on-prem MinIO part upload. */
function onPremPartUrl(uploadId: string, key: string, partNumber: number, bucket: string): string {
  return `/api/s3/upload/part?uploadId=${encodeURIComponent(uploadId)}&key=${encodeURIComponent(key)}&partNumber=${partNumber}&bucket=${encodeURIComponent(bucket)}`;
}

// ── Simple path (< 100 MiB) ───────────────────────────────────────────────────

async function uploadSimple(file: File, opts: UploadOptions): Promise<UploadResult> {
  const fetchImpl = opts.fetchImpl ?? fetch;
  const formData = new FormData();
  formData.append('file', file);
  formData.append('file_type', file.type || 'auto');
  if (opts.description) formData.append('description', opts.description);

  // No native byte progress without XHR; emit a steady fake counter so
  // callers can show something rather than a stuck bar.
  let fake = 0;
  const interval = opts.onProgress
    ? setInterval(() => { fake = Math.min(90, fake + 10); opts.onProgress!(fake); }, 200)
    : null;

  try {
    const r = await fetchImpl('/api/datasets/upload', {
      method: 'POST',
      body: formData,
      credentials: 'include',
    });
    if (!r.ok) throw new Error((await r.text()) || `upload failed: HTTP ${r.status}`);
    const result = await r.json();
    opts.onProgress?.(100);
    return {
      datasetId: result.dataset_id,
      galaxyDatasetId: result.galaxy_dataset_id,
      s3Uri: result.s3_uri,
      via: 'simple',
    };
  } finally {
    if (interval) clearInterval(interval);
  }
}

// ── Multipart path (≥ 100 MiB) with resume support ───────────────────────────

interface MultipartCtx {
  uploadId: string;
  key: string;
  chunkSize: number;
  numParts: number;
  partUrls: string[];
  isOnPrem: boolean;
  bucket: string | undefined;
  completedParts: Array<{ PartNumber: number; ETag: string }>;
}

async function buildFreshCtx(file: File, fetchImpl: typeof fetch): Promise<MultipartCtx> {
  const initR = await fetchImpl('/api/s3/upload/init', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    credentials: 'include',
    body: JSON.stringify({
      filename: file.name,
      fileSize: file.size,
      contentType: file.type || 'application/octet-stream',
    }),
  });
  if (!initR.ok) throw new Error((await initR.text()) || 'init failed');
  const init = await initR.json() as {
    method: 'simple' | 'multipart';
    uploadId: string;
    key: string;
    partUrls?: string[];
    chunkSize?: number;
  };
  if (init.method !== 'multipart' || !init.partUrls || !init.chunkSize) {
    throw new Error('server did not return a multipart upload plan');
  }
  const isOnPrem = init.partUrls[0]?.startsWith('/api/s3/upload/part') ?? false;
  const bucket = isOnPrem
    ? new URLSearchParams(init.partUrls[0].split('?')[1] ?? '').get('bucket') ?? undefined
    : undefined;
  return {
    uploadId: init.uploadId,
    key: init.key,
    chunkSize: init.chunkSize,
    numParts: init.partUrls.length,
    partUrls: init.partUrls,
    isOnPrem,
    bucket,
    completedParts: [],
  };
}

async function tryResumeCtx(
  saved: ResumeState,
  fetchImpl: typeof fetch,
): Promise<MultipartCtx | null> {
  try {
    const lr = await fetchImpl(
      `/api/s3/upload/list-parts?uploadId=${encodeURIComponent(saved.uploadId)}&key=${encodeURIComponent(saved.key)}`,
      { credentials: 'include' },
    );
    if (!lr.ok) return null; // 404 = expired, any other error = fall through to fresh init
    const { parts } = await lr.json() as { parts: Array<{ PartNumber: number; ETag: string }> };
    const completedParts = parts.map(p => ({ PartNumber: p.PartNumber, ETag: p.ETag }));

    let partUrls: string[];
    if (saved.isOnPrem) {
      // On-prem proxy URLs are stable and never expire — reconstruct from params.
      partUrls = Array.from({ length: saved.numParts }, (_, i) =>
        onPremPartUrl(saved.uploadId, saved.key, i + 1, saved.bucket ?? 'biomate-data'),
      );
    } else {
      // AWS S3: get fresh presigned URLs for the parts we still need to upload.
      const remaining = Array.from({ length: saved.numParts }, (_, i) => i + 1)
        .filter(n => !completedParts.some(p => p.PartNumber === n));
      if (remaining.length > 0) {
        const rr = await fetchImpl('/api/s3/upload/refresh-parts', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          credentials: 'include',
          body: JSON.stringify({
            uploadId: saved.uploadId, key: saved.key,
            partNumbers: remaining, chunkSize: saved.chunkSize,
          }),
        });
        if (!rr.ok) return null;
        const { partUrls: freshUrls } = await rr.json() as { partUrls: string[] };
        const urlMap = new Map(remaining.map((n, i) => [n, freshUrls[i]]));
        partUrls = Array.from({ length: saved.numParts }, (_, i) => urlMap.get(i + 1) ?? '');
      } else {
        partUrls = Array.from({ length: saved.numParts }, () => '');
      }
    }

    return {
      uploadId: saved.uploadId,
      key: saved.key,
      chunkSize: saved.chunkSize,
      numParts: saved.numParts,
      partUrls,
      isOnPrem: saved.isOnPrem,
      bucket: saved.bucket,
      completedParts,
    };
  } catch {
    return null;
  }
}

async function uploadMultipart(file: File, opts: UploadOptions): Promise<UploadResult> {
  const fetchImpl = opts.fetchImpl ?? fetch;

  // ── Step 1: attempt resume; fall back to fresh init ───────────────────────
  const saved = loadResumeState(file);
  let ctx: MultipartCtx;
  if (saved) {
    const resumed = await tryResumeCtx(saved, fetchImpl);
    if (resumed) {
      ctx = resumed;
      // Credit already-uploaded bytes toward progress.
      const bytesDoneAlready = ctx.completedParts.reduce((acc, p) => {
        const start = (p.PartNumber - 1) * ctx.chunkSize;
        return acc + Math.min(ctx.chunkSize, file.size - start);
      }, 0);
      opts.onProgress?.(Math.floor((bytesDoneAlready / file.size) * 100));
    } else {
      clearResumeState(file);
      ctx = await buildFreshCtx(file, fetchImpl);
    }
  } else {
    ctx = await buildFreshCtx(file, fetchImpl);
  }

  // Persist initial state so a crash immediately after init is recoverable.
  saveResumeState(file, {
    uploadId: ctx.uploadId, key: ctx.key, chunkSize: ctx.chunkSize,
    numParts: ctx.numParts, isOnPrem: ctx.isOnPrem, bucket: ctx.bucket,
    savedAt: Date.now(), completedParts: ctx.completedParts,
  });

  // ── Step 2: upload remaining parts ────────────────────────────────────────
  const { uploadId, key, chunkSize, numParts, partUrls, isOnPrem, bucket } = ctx;
  const completedParts = [...ctx.completedParts];
  const doneSet = new Set(completedParts.map(p => p.PartNumber));
  let bytesDone = completedParts.reduce((acc, p) => {
    const start = (p.PartNumber - 1) * chunkSize;
    return acc + Math.min(chunkSize, file.size - start);
  }, 0);

  try {
    for (let i = 0; i < numParts; i += PART_CONCURRENCY) {
      const batch: Array<Promise<{ PartNumber: number; ETag: string }>> = [];
      for (let j = i; j < Math.min(i + PART_CONCURRENCY, numParts); j++) {
        const partNumber = j + 1;
        if (doneSet.has(partNumber)) continue; // already done in a previous session

        const start = j * chunkSize;
        const end = Math.min(start + chunkSize, file.size);
        const url = isOnPrem
          ? onPremPartUrl(uploadId, key, partNumber, bucket ?? 'biomate-data')
          : partUrls[j];
        const blob = file.slice(start, end);
        batch.push(
          putPartWithRetry(url, blob, partNumber, fetchImpl).then(res => {
            bytesDone += (end - start);
            opts.onProgress?.(Math.floor((bytesDone / file.size) * 100));
            return res;
          }),
        );
      }

      if (batch.length > 0) {
        const newParts = await Promise.all(batch);
        completedParts.push(...newParts);
        // Persist after each successful batch so an interruption mid-upload
        // only loses at most PART_CONCURRENCY parts worth of work.
        saveResumeState(file, {
          uploadId, key, chunkSize, numParts, isOnPrem, bucket,
          savedAt: Date.now(), completedParts,
        });
      }
    }
  } catch (err) {
    // Best-effort abort. We do NOT clear localStorage so the user can retry
    // and resume from the last successful batch.
    try {
      await fetchImpl('/api/s3/upload/abort', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        credentials: 'include',
        body: JSON.stringify({ key, uploadId }),
      });
      clearResumeState(file); // abort succeeded → session is dead
    } catch { /* ignore */ }
    throw err;
  }

  // ── Step 3: complete ──────────────────────────────────────────────────────
  const completeR = await fetchImpl('/api/s3/upload/complete', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    credentials: 'include',
    body: JSON.stringify({ key, uploadId, parts: completedParts }),
  });
  if (!completeR.ok) throw new Error((await completeR.text()) || 'complete failed');
  const completeData = await completeR.json().catch(() => ({} as Record<string, string>));
  const s3Bucket = completeData.bucket as string | undefined;
  const s3FullUri = s3Bucket ? `s3://${s3Bucket}/${key}` : `s3://${key}`;

  clearResumeState(file); // fully assembled — safe to drop resume state

  const regR = await fetchImpl('/api/datasets/register-path', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    credentials: 'include',
    body: JSON.stringify({ path: s3FullUri, name: file.name }),
  });
  if (!regR.ok) throw new Error((await regR.text()) || 'register-path failed');
  const reg = await regR.json();
  return { datasetId: reg.dataset_id, s3Key: key, via: 'multipart' };
}

/** Upload a single file, branching on size. */
export async function uploadFile(file: File, opts: UploadOptions = {}): Promise<UploadResult> {
  if (file.size <= SIMPLE_UPLOAD_MAX_BYTES) return uploadSimple(file, opts);
  return uploadMultipart(file, opts);
}

/** Exposed for tests / fine-grained UIs that want to skip the size branch. */
export const _internals = { uploadSimple, uploadMultipart, SIMPLE_UPLOAD_MAX_BYTES };
