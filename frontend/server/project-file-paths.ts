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

// ─── Rename / move (PATCH /api/projects/:id/files/:fileId, POST …/files/rename-folder) ───
//
// A file's `name` is its place in the project tree ("run1/fastq/S1.fastq.gz"); renaming or
// moving it only changes that name. The S3 object is NOT moved: its key is the file's storage
// identity (versions, lineage/consumer lookups and completed runs all reference the exact key).
// Because keys are derived from names, a later upload under a name a renamed file used to have
// would derive a key that is still in use — see pickFreeObjectKey, which every new object goes
// through so an upload can never overwrite bytes another file (or version) still points at.

export type NameCheck = { ok: true; name: string } | { ok: false; error: string };

/**
 * Validate a user-typed target name (may contain folders). Same segment rules as uploads
 * (projectInputPath), but anything uploads would silently drop is REFUSED here, so a rename
 * never lands somewhere the user did not type: "..", control characters, an over-long
 * segment or too many folders → error. Empty and "." segments ("a//b", "./a") are dropped.
 */
export function normalizeProjectFileName(raw: unknown): NameCheck {
  if (typeof raw !== "string") return { ok: false, error: "name must be a string" };
  // eslint-disable-next-line no-control-regex
  if (/[\u0000-\u001f\u007f]/.test(raw)) return { ok: false, error: "name contains control characters" };
  const segments = raw.replace(/\\/g, "/").split("/").map((s) => s.trim()).filter((s) => s !== "" && s !== ".");
  if (!segments.length) return { ok: false, error: "name is empty" };
  if (segments.some((s) => s === "..")) return { ok: false, error: "name may not contain '..'" };
  if (segments.some((s) => s.length > MAX_SEGMENT)) return { ok: false, error: `each folder or file name is limited to ${MAX_SEGMENT} characters` };
  if (segments.length > MAX_DEPTH) return { ok: false, error: `folders may be nested at most ${MAX_DEPTH} deep` };
  return { ok: true, name: segments.join("/") };
}

/**
 * The existing name that `target` would clash with in the tree, or null. Clashes are an
 * identical name, or a file/folder clash: target "x" while "x/…" exists (a folder), or target
 * "x/a.csv" while a FILE named "x" exists.
 */
export function findNameConflict(target: string, others: Iterable<string>): string | null {
  for (const o of others) {
    if (o === target || o.startsWith(target + "/") || target.startsWith(o + "/")) return o;
  }
  return null;
}

/** Sources whose names are not user-managed: a run output keeps the name its run gave it
 *  (run reports and lineage resolve outputs by that name). */
export const IMMUTABLE_NAME_SOURCES = new Set(["run_output"]);

export interface RenameRow { id: string; name: string; source?: string | null }
export type RenamePlan =
  | { ok: true; moves: Array<{ id: string; from: string; to: string }>; from?: string; to?: string }
  | { ok: false; status: 400 | 404 | 409; error: string; conflicts?: Array<{ name: string; existing: string }> };

/** Plan a single-file rename/move against the project's current rows (pure). */
export function planFileRename(rows: RenameRow[], fileId: string, rawName: unknown): RenamePlan {
  const file = rows.find((r) => String(r.id) === String(fileId));
  if (!file) return { ok: false, status: 404, error: "File not found" };
  if (IMMUTABLE_NAME_SOURCES.has(String(file.source ?? ""))) {
    return { ok: false, status: 400, error: "Run outputs keep the name their run gave them and cannot be renamed." };
  }
  const checked = normalizeProjectFileName(rawName);
  if (!checked.ok) return { ok: false, status: 400, error: checked.error };
  if (checked.name === file.name) return { ok: true, moves: [] };
  const clash = findNameConflict(checked.name, rows.filter((r) => r.id !== file.id).map((r) => r.name));
  if (clash !== null) {
    return { ok: false, status: 409, error: `"${checked.name}" conflicts with an existing file or folder in this project.`,
      conflicts: [{ name: checked.name, existing: clash }] };
  }
  return { ok: true, moves: [{ id: String(file.id), from: file.name, to: checked.name }] };
}

/**
 * Plan a folder rename/move: every user-managed file whose name starts with `from/` gets the
 * prefix replaced by `to/`. All-or-nothing — any clash with a file that is NOT moving refuses
 * the whole move (pure; the route applies it in one transaction).
 */
export function planFolderRename(rows: RenameRow[], rawFrom: unknown, rawTo: unknown): RenamePlan {
  const f = normalizeProjectFileName(rawFrom);
  if (!f.ok) return { ok: false, status: 400, error: `from: ${f.error}` };
  const t = normalizeProjectFileName(rawTo);
  if (!t.ok) return { ok: false, status: 400, error: `to: ${t.error}` };
  const from = f.name, to = t.name;
  if (from === to) return { ok: false, status: 400, error: "The folder already has that name." };
  if (to.startsWith(from + "/")) return { ok: false, status: 400, error: "A folder cannot be moved into itself." };
  const moving = rows.filter((r) => r.name.startsWith(from + "/") && !IMMUTABLE_NAME_SOURCES.has(String(r.source ?? "")));
  if (!moving.length) return { ok: false, status: 404, error: "Folder not found" };
  const movingIds = new Set(moving.map((r) => String(r.id)));
  const staying = rows.filter((r) => !movingIds.has(String(r.id))).map((r) => r.name);
  const moves = moving.map((r) => ({ id: String(r.id), from: r.name, to: to + r.name.slice(from.length) }));
  const conflicts: Array<{ name: string; existing: string }> = [];
  for (const m of moves) {
    if (m.to.split("/").some((s) => s.length > MAX_SEGMENT) || m.to.split("/").length > MAX_DEPTH) {
      return { ok: false, status: 400, error: `"${m.to}" would exceed the folder depth or name length limit.` };
    }
    const clash = findNameConflict(m.to, staying);
    if (clash !== null) conflicts.push({ name: m.to, existing: clash });
  }
  if (conflicts.length) {
    return { ok: false, status: 409, error: `Moving "${from}" to "${to}" would clash with ${conflicts.length} existing file(s); nothing was moved.`, conflicts };
  }
  return { ok: true, moves, from, to };
}

/** `key` with a numeric suffix before the first "." of its last segment:
 *  ("…/S1.fastq.gz", 2) → "…/S1-2.fastq.gz"; ("…/b.csv.v3", 2) → "…/b-2.csv.v3". */
export function withKeySuffix(key: string, n: number): string {
  const slash = key.lastIndexOf("/");
  const dir = key.slice(0, slash + 1), seg = key.slice(slash + 1);
  const dot = seg.indexOf(".", 1);
  return dot === -1 ? `${dir}${seg}-${n}` : `${dir}${seg.slice(0, dot)}-${n}${seg.slice(dot)}`;
}

/** Candidate keys for a new object, in preference order (the derived key first). */
export function objectKeyCandidates(desired: string, count = 20): string[] {
  const out = [desired];
  for (let n = 2; out.length < count; n++) out.push(withKeySuffix(desired, n));
  return out;
}

/** The first candidate no row references; null if all are taken (caller falls back to a random suffix). */
export function pickFreeObjectKey(candidates: string[], taken: Set<string>): string | null {
  return candidates.find((c) => !taken.has(c)) ?? null;
}
