/**
 * Project input file paths — the ONE place that turns an uploaded file's name (plus the
 * folder-relative path a folder upload carries) into the stored display name and the S3
 * key under `projects/<id>/inputs/`.
 *
 * - Folder structure is kept: "run1/fastq/S1_R1.fastq.gz" is stored with that name and an
 *   S3 key with the same folders, so the file tree can rebuild the folders.
 * - Every segment is sanitized: "..", ".", empty and control characters are dropped, so a
 *   crafted relativePath can never escape the project's inputs/ prefix.
 * - Key segments are ASCII-safe. When sanitizing is lossy (e.g. "样本 A.csv" → "___A.csv")
 *   an 8-hex digest of the original segment is appended, so two different names never
 *   collapse onto the same S3 object (they previously did: "数据.csv" and "样本.csv" both
 *   became "__.csv" and the second upload overwrote the first file's bytes).
 */
import path from "path";
import { createHash } from "crypto";

const MAX_DEPTH = 32;
const MAX_SEGMENT = 200;

function cleanSegments(raw: string): string[] {
  return raw
    .replace(/\\/g, "/")
    .split("/")
    // eslint-disable-next-line no-control-regex
    .map((s) => s.replace(/[\u0000-\u001f\u007f]/g, "").trim())
    .filter((s) => s !== "" && s !== "." && s !== "..")
    .map((s) => s.slice(0, MAX_SEGMENT));
}

function keySegment(seg: string): string {
  const rawExt = path.extname(seg);
  const ext = rawExt.toLowerCase().replace(/[^a-z0-9.]/g, "");
  const base = seg.slice(0, seg.length - rawExt.length);
  const safeBase = base.replace(/[^a-zA-Z0-9._-]/g, "_").slice(0, MAX_SEGMENT);
  const lossy = safeBase !== base || ext !== rawExt;
  const digest = lossy ? "-" + createHash("sha1").update(seg).digest("hex").slice(0, 8) : "";
  return `${safeBase || "file"}${digest}${ext}`;
}

export interface ProjectInputPath {
  /** Stored/display name: folder-relative path with "/" separators (original characters). */
  name: string;
  /** Path below `projects/<id>/inputs/` (sanitized, collision-safe). */
  keyPath: string;
}

/**
 * Resolve the stored name + key path for an upload. `relativePath` is the browser's
 * `webkitRelativePath` for a folder pick/drop ("" or absent for a plain file pick).
 */
export function projectInputPath(originalName: string, relativePath?: string | null): ProjectInputPath {
  const fromRel = typeof relativePath === "string" ? cleanSegments(relativePath) : [];
  // A plain file keeps only its basename (some clients send "C:\\…\\a.csv" as the filename).
  let segments = fromRel.length ? fromRel : cleanSegments(String(originalName || "")).slice(-1);
  if (!segments.length) segments = ["file"];
  if (segments.length > MAX_DEPTH) segments = [...segments.slice(0, MAX_DEPTH - 1), segments[segments.length - 1]];
  return {
    name: segments.join("/"),
    keyPath: segments.map(keySegment).join("/"),
  };
}

export function projectInputKey(projectId: string, originalName: string, relativePath?: string | null): string {
  return `projects/${projectId}/inputs/${projectInputPath(originalName, relativePath).keyPath}`;
}

/**
 * multer (busboy) decodes the multipart `filename` parameter as latin1, so a UTF-8 name like
 * "样本.csv" arrives as mojibake. Re-decode it as UTF-8 when that round-trips cleanly; a
 * string that is not a latin1 decoding (any code point > 0xFF) is returned unchanged.
 */
export function decodeMultipartFilename(name: string): string {
  // eslint-disable-next-line no-control-regex
  if (!name || /[^\u0000-ÿ]/.test(name) || !/[\u0080-ÿ]/.test(name)) return name;
  const utf8 = Buffer.from(name, "latin1").toString("utf8");
  return utf8.includes("�") ? name : utf8;
}
