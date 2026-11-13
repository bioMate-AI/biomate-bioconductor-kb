/**
 * Models dataset picker: a project file OR a project folder (all files under it).
 */
import { folderPathsFromFiles, filesUnderFolderPrefix } from "@/lib/folder-as-input"

export type DatasetSelection =
  | { kind: "file"; fileId: string }
  | { kind: "folder"; folderPath: string }

const FILE_PREFIX = "file:"
const FOLDER_PREFIX = "folder:"

export function encodeDatasetSelection(sel: DatasetSelection | null): string {
  if (!sel) return ""
  return sel.kind === "folder" ? `${FOLDER_PREFIX}${sel.folderPath}` : `${FILE_PREFIX}${sel.fileId}`
}

export function parseDatasetSelection(value: string): DatasetSelection | null {
  if (!value) return null
  if (value.startsWith(FOLDER_PREFIX)) return { kind: "folder", folderPath: value.slice(FOLDER_PREFIX.length) }
  if (value.startsWith(FILE_PREFIX)) return { kind: "file", fileId: value.slice(FILE_PREFIX.length) }
  // Legacy bare file id (older selects / tests).
  return { kind: "file", fileId: value }
}

export function folderOptionLabel(path: string, fileCount: number): string {
  const leaf = path || "inputs"
  return `${leaf}/ (${fileCount} files)`
}

export function buildDatasetOptions<T extends { id: string; name: string; source?: string | null }>(
  files: T[],
): Array<{ value: string; label: string; kind: "file" | "folder" }> {
  const folders = folderPathsFromFiles(files)
  const folderOpts = folders.map((path) => {
    const n = filesUnderFolderPrefix(files, path).length
    return { value: encodeDatasetSelection({ kind: "folder", folderPath: path }), label: folderOptionLabel(path, n), kind: "folder" as const }
  }).filter((o) => !o.label.endsWith("(0 files)"))
  const fileOpts = files.map((f) => ({
    value: encodeDatasetSelection({ kind: "file", fileId: f.id }),
    label: f.name,
    kind: "file" as const,
  }))
  return [...folderOpts, ...fileOpts]
}

export function resolveSelectionToFileIds<T extends { id: string; name: string; source?: string | null }>(
  files: T[],
  sel: DatasetSelection | null,
): string[] {
  if (!sel) return []
  if (sel.kind === "file") return files.some((f) => f.id === sel.fileId) ? [sel.fileId] : []
  return filesUnderFolderPrefix(files, sel.folderPath).map((f) => f.id)
}

/** First delimited table in a folder (for column profiling on train). */
export function primaryTableForSelection<T extends { id: string; name: string; source?: string | null }>(
  files: T[],
  sel: DatasetSelection | null,
  isTable: (name: string) => boolean,
): T | undefined {
  if (!sel) return undefined
  if (sel.kind === "file") return files.find((f) => f.id === sel.fileId)
  const under = filesUnderFolderPrefix(files, sel.folderPath)
  return under.find((f) => isTable(f.name)) ?? under[0]
}
