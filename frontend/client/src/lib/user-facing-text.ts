/** User-facing text sanitizers for workflow-panel labels and parameter values.
 *  Storage locations, upload UUIDs and infrastructure words never reach the user
 *  (founder rules 2026-11-10/11; same policy as the server's redactStoragePaths). */

/** Raw dataset/dataset-ref UUIDs the user never needs to read (founder 2026-11-11:
 *  "unnecessary id"). Strip "(id: <uuid>)" / "id=<uuid>" / a bare 32-hex or dashed
 *  UUID from a displayed parameter value — keep the human part (e.g. the filename). */
export function cleanParamValueForDisplay(v: unknown): string {
  let s = v == null ? '' : String(v);
  // Demo fixture tokens (e.g. fixture:empiar-10028-movies) → friendly label, never
  // the underlying storage URI (resolved only at execute time).
  {
    const fix = /^fixture:([A-Za-z0-9_-]+)$/i.exec(s.trim());
    if (fix) {
      const labels: Record<string, string> = {
        'empiar-10028-movies': 'EMPIAR-10028 movies',
        'mg-demo-samplesheet': 'MG demo samplesheet',
        'mg-demo-matrix': 'MG demo count matrix',
        'mg-demo-contrasts': 'MG demo contrasts',
        'mg-demo-gene-list': 'MG demo DE gene list',
      };
      return labels[fix[1].toLowerCase()] || fix[1];
    }
  }
  // A storage location is shown as the file it names, never as a path: s3://, gs://,
  // file://, http(s):// or an absolute/relative path whose last segment is a file.
  // Same policy as the server's redactStoragePaths (no storage paths in user text).
  s = s.replace(/(?:(?:s3|gs|file|https?):\/\/|\/)?[^\s,;'"()]*\/([^\s,;'"()/]+\.[A-Za-z0-9]{1,8}(?:\.gz)?)/g, '$1');
  s = s.replace(/(?:s3|gs):\/\/[^\s,;'"()]+\/?/gi, '');
  s = s.replace(/\s*[\(（]\s*id[:=]\s*[0-9a-f]{8}-[0-9a-f-]{8,}\s*[\)）]/gi, '');
  s = s.replace(/\s*\bid[:=]\s*[0-9a-f]{8}-[0-9a-f-]{8,}\b/gi, '');
  s = s.replace(/\s*\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b/gi, '');
  return s.replace(/\s{2,}/g, ' ').replace(/\s*·\s*·/g, ' ·').trim();
}

/** A backend step label names the work, not the infrastructure: drop "from S3",
 *  "on AWS Batch", "to the bucket" (no storage/infra words in user-facing text). */
export function userFacingStepName(name: unknown): string {
  return String(name ?? '')
    .replace(/\s+(?:from|to|on|in|via|into)\s+(?:the\s+)?(?:AWS\s+)?(?:S3|Batch|bucket)(?:\s+bucket)?\b/gi, '')
    .replace(/\s*\((?:S3|AWS(?:\s+Batch)?)\)/gi, '')
    .trim();
}

export { userFacingErrorText } from '@shared/user-facing-error';
