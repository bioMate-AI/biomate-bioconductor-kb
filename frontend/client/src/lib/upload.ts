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
 * Large-file path features (mirror s3-client.multipart.test.ts contract):
 *   - 3-way concurrent part PUTs
 *   - Per-part retry with exponential backoff (5 attempts, 0.5s base)
 *   - Abort the S3 multipart on failure so the user isn't billed for staged parts
 *   - Real progress (bytes done / total) via onProgress callback
 */

const SIMPLE_UPLOAD_MAX_BYTES = 100 * 1024 * 1024; // 100 MiB
const PART_CONCURRENCY = 3;
const PART_RETRY_ATTEMPTS = 5;

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

async function uploadMultipart(file: File, opts: UploadOptions): Promise<UploadResult> {
  const fetchImpl = opts.fetchImpl ?? fetch;

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
    numParts?: number;
  };
  if (init.method !== 'multipart' || !init.partUrls || !init.chunkSize) {
    throw new Error('server did not return a multipart upload plan');
  }
  const { uploadId, key, partUrls, chunkSize } = init;
  const numParts = partUrls.length;

  const completedParts: Array<{ PartNumber: number; ETag: string }> = [];
  let bytesDone = 0;

  try {
    for (let i = 0; i < numParts; i += PART_CONCURRENCY) {
      const batch: Array<Promise<{ PartNumber: number; ETag: string }>> = [];
      for (let j = i; j < Math.min(i + PART_CONCURRENCY, numParts); j++) {
        const start = j * chunkSize;
        const end = Math.min(start + chunkSize, file.size);
        const blob = file.slice(start, end);
        batch.push(
          putPartWithRetry(partUrls[j], blob, j + 1, fetchImpl).then(res => {
            bytesDone += (end - start);
            opts.onProgress?.(Math.floor((bytesDone / file.size) * 100));
            return res;
          }),
        );
      }
      completedParts.push(...await Promise.all(batch));
    }
  } catch (err) {
    // Best-effort cleanup: tell S3 to stop billing the staged parts.
    try {
      await fetchImpl('/api/s3/upload/abort', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        credentials: 'include',
        body: JSON.stringify({ key, uploadId }),
      });
    } catch { /* ignore */ }
    throw err;
  }

  const completeR = await fetchImpl('/api/s3/upload/complete', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    credentials: 'include',
    body: JSON.stringify({ key, uploadId, parts: completedParts }),
  });
  if (!completeR.ok) throw new Error((await completeR.text()) || 'complete failed');

  // Register the resulting S3 key as a Galaxy dataset reference so workflows
  // can use it. Use s3:// URL form — register-path accepts it explicitly.
  const regR = await fetchImpl('/api/datasets/register-path', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    credentials: 'include',
    body: JSON.stringify({ path: `s3://${key}`, name: file.name }),
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
