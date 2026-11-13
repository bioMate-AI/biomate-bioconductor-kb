/**
 * Project folders — the ONE place that turns project_files rows into folder facts for the
 * folder profile and for the per-file profiler's folder context.
 *
 * A folder exists only through its files' names ("pairs/S1_R1.fastq.gz" ⇒ folder "pairs",
 * see project-file-paths.ts); input files are every file that is not a run output or a
 * chat-generated result (same split as the file tree's buildTree). Folder paths in the API are
 * relative to the project's inputs ("" = the inputs root, "pairs", "run1/fastq").
 *
 * Why the folder logic is split this way: Node owns the project's file list and its
 * authorization (Postgres project_files + owner/member checks), the Python backend owns the
 * profilers and Galaxy's pairing code (galaxy.model.dataset_collections.auto_pairing). So Node
 * selects the folder's files and the Python folder_profile decides what they are; for one
 * file's profile Node attaches the names of its folder siblings (`folderContext`) and the
 * profiler applies the same pairing — one pairing implementation, never a second one here.
 */

const MAX_DEPTH = 32;

export interface FolderFileRow {
  id?: string;
  name: string;
  s3_key?: string | null;
  source?: string | null;
}

/** Files that live in the inputs tree (not run outputs / chat-generated results). */
export function isInputFile(row: FolderFileRow): boolean {
  return row.source !== "run_output" && row.source !== "run_code";
}

/**
 * Normalize a folder path from a query string: "/" separators, no empty / "." / ".." segments,
 * a leading "inputs/" (the tree's own prefix) accepted. Returns null for an invalid path.
 */
export function normalizeFolderPath(raw: unknown): string | null {
  if (raw == null) return "";
  if (typeof raw !== "string") return null;
  // eslint-disable-next-line no-control-regex
  if (/[\u0000-\u001f\u007f]/.test(raw)) return null;
  const segs = raw.replace(/\\/g, "/").split("/").map((s) => s.trim()).filter((s) => s !== "" && s !== ".");
  if (segs.includes("..") || segs.length > MAX_DEPTH) return null;
  if (segs[0] === "inputs") segs.shift();
  return segs.join("/");
}

/** Directory part of a stored name ("" for a file at the inputs root). */
export function dirOf(name: string): string {
  const i = name.lastIndexOf("/");
  return i < 0 ? "" : name.slice(0, i);
}

/** Every input file below `folder` (any depth); all inputs for the root. */
export function filesUnderFolder<T extends FolderFileRow>(rows: T[], folder: string): T[] {
  const prefix = folder ? `${folder}/` : "";
  return rows.filter((r) => isInputFile(r) && typeof r.name === "string" && r.name.startsWith(prefix));
}

/** The other input files of `name`'s own directory (direct children only). */
export function folderSiblings(rows: FolderFileRow[], name: string): string[] {
  const d = dirOf(name);
  const out: string[] = [];
  for (const r of rows) {
    if (!isInputFile(r) || r.name === name || dirOf(r.name) !== d) continue;
    if (!out.includes(r.name)) out.push(r.name);
  }
  return out;
}

/** Escape a string for a SQL LIKE pattern (with ESCAPE '\'). */
export function likePrefix(s: string): string {
  return s.replace(/[\\%_]/g, (c) => `\\${c}`);
}

export type QueryFn = (sql: string, params: unknown[]) => Promise<{ rows: any[] }>;

/** Rows of every file below `folder` in `projectId` (inputs only), ids + names + keys. */
export async function loadFolderFiles(query: QueryFn, projectId: string, folder: string): Promise<FolderFileRow[]> {
  const params: unknown[] = [projectId];
  let where = "";
  if (folder) {
    params.push(`${likePrefix(folder)}/%`);
    where = ` AND name LIKE $2 ESCAPE '\\'`;
  }
  const r = await query(
    `SELECT id::text AS id, name, s3_key, source FROM project_files WHERE project_id::text = $1${where} ORDER BY name`,
    params,
  );
  return filesUnderFolder(r.rows as FolderFileRow[], folder);
}

/**
 * `folderContext` for one project file: its stored name + the names of its directory's other
 * input files. Null when the file is not an input (run outputs have no user folder).
 */
export async function loadFolderContext(
  query: QueryFn, projectId: string, row: FolderFileRow,
): Promise<{ name: string; siblings: string[] } | null> {
  if (!row?.name || !isInputFile(row)) return null;
  const d = dirOf(row.name);
  const params: unknown[] = [projectId];
  let where = ` AND position('/' in name) = 0`;
  if (d) {
    params.push(`${likePrefix(d)}/%`);
    where = ` AND name LIKE $2 ESCAPE '\\'`;
  }
  const r = await query(
    `SELECT name, source FROM project_files WHERE project_id::text = $1${where}`,
    params,
  );
  return { name: row.name, siblings: folderSiblings(r.rows as FolderFileRow[], row.name) };
}

/** Download file name for a folder's samplesheet ("pairs" → "pairs_samplesheet.csv"). */
export function samplesheetFilename(folder: string): string {
  const leaf = folder.split("/").filter(Boolean).pop() || "inputs";
  return `${leaf.replace(/[^A-Za-z0-9._-]/g, "_")}_samplesheet.csv`;
}

/** Project-files stored name for a persisted samplesheet (under the folder prefix). */
export function samplesheetStoredName(folder: string, filename?: string | null): string {
  const raw = (filename && String(filename).trim()) || samplesheetFilename(folder);
  const leaf = raw.replace(/\\/g, "/").split("/").filter(Boolean).pop() || samplesheetFilename(folder);
  const safe = leaf.replace(/[^A-Za-z0-9._-]/g, "_") || "samplesheet.csv";
  return folder ? `${folder}/${safe}` : safe;
}

type SamplesheetLike = {
  csv?: unknown;
  filename?: unknown;
  single?: { csv?: unknown; filename?: unknown } | null;
} | null | undefined;

/** Pick the CSV body (+ leaf filename) from a folder profile samplesheet block. */
export function pickFolderSamplesheetCsv(
  samplesheet: SamplesheetLike,
  layout?: "paired" | "single_end" | string | null,
): { csv: string; filename: string } | null {
  if (!samplesheet || typeof samplesheet !== "object") return null;
  if (layout === "single_end") {
    const csv = samplesheet.single?.csv;
    if (typeof csv !== "string" || !csv) return null;
    const filename =
      typeof samplesheet.single?.filename === "string" && samplesheet.single.filename
        ? samplesheet.single.filename
        : "samplesheet_single_end.csv";
    return { csv, filename };
  }
  if (typeof samplesheet.csv !== "string" || !samplesheet.csv) return null;
  const filename =
    typeof samplesheet.filename === "string" && samplesheet.filename
      ? samplesheet.filename
      : "samplesheet.csv";
  return { csv: samplesheet.csv, filename };
}
