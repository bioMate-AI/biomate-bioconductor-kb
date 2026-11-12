/** A download's file name: the last path segment of a project file's display name
 *  ("run1/fastq/S1.fastq.gz" → "S1.fastq.gz"), never the S3 key (keys carry ".vN" version and
 *  "-2" collision suffixes the user never typed). */
export function downloadName(name: string): string {
  return String(name ?? "").split("/").pop() || "download";
}

/** RFC 5987 ext-value: encodeURIComponent leaves ' ( ) * unescaped, but they are not attr-chars,
 *  so "o'brien (1).csv" would end the parameter early in a strict parser. */
function rfc5987(value: string): string {
  return encodeURIComponent(value).replace(/['()*]/g, (c) => "%" + c.charCodeAt(0).toString(16).toUpperCase());
}

/** RFC 6266 attachment header: ASCII fallback + UTF-8 filename* (Chinese and other names survive). */
export function attachmentDisposition(name: string): string {
  // eslint-disable-next-line no-control-regex
  const base = downloadName(name).replace(/[\u0000-\u001f\u007f]/g, "_");
  // quoted-string fallback: ASCII only, no quote or backslash (they would need escaping).
  const ascii = base.replace(/["\\]/g, "_").replace(/[^\x20-\x7e]/g, "_");
  return `attachment; filename="${ascii}"; filename*=UTF-8''${rfc5987(base)}`;
}
