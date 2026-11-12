/**
 * The open object follows the project's file list (data hub). It is identified by file id: a
 * rename / move changes only the row's name (the storage key stays), a new version changes the key,
 * a delete removes the row. Without this the open object kept a stale snapshot of the row.
 */
import type { ProjectFile } from "@/components/project-file-tree"

export type FollowResult =
  | { kind: "same" }
  | { kind: "updated"; file: ProjectFile }
  | { kind: "deleted"; name: string }

/** What became of the open file in the current list. */
export function followFileList(open: ProjectFile, files: ProjectFile[]): FollowResult {
  const row = files.find((f) => f.id === open.id)
  if (!row) return { kind: "deleted", name: open.name }
  const changed = (Object.keys(row) as (keyof ProjectFile)[]).some((k) => row[k] !== open[k])
  return changed ? { kind: "updated", file: { ...open, ...row } } : { kind: "same" }
}

/** An open folder path after the folder `from` moved to `to` (the folder itself, or one inside). */
export function followFolderRename(path: string, from: string, to: string): string {
  if (path === from) return to
  if (from !== "" && path.startsWith(`${from}/`)) return `${to}${path.slice(from.length)}`
  return path
}
