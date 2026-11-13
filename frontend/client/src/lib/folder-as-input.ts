/**
 * Folder → all files as the analysis / models input set.
 *
 * Project folders are virtual path prefixes on project_files. Selecting a folder
 * means every input file under that prefix (recursive), not a samplesheet-only
 * stand-in and not a single fake file id.
 */

export interface FolderFileRef {
  id: string
  name: string
}

/** Chat deep-link: expand `attachFolder` in the composer to every file under the path. */
export function analyzeFolderChatUrl(projectId: string | null | undefined, folderPath: string): string {
  const q = new URLSearchParams()
  if (projectId) q.set("project", projectId)
  q.set("attachFolder", folderPath)
  return `/?${q.toString()}`
}

/** Client-side filter mirroring server `filesUnderFolder` (inputs only when source is known). */
export function filesUnderFolderPrefix<T extends { name: string; source?: string | null }>(
  rows: T[],
  folder: string,
): T[] {
  const prefix = folder ? `${folder}/` : ""
  return rows.filter((r) => {
    if (r.source === "run_output" || r.source === "run_code") return false
    return typeof r.name === "string" && r.name.startsWith(prefix)
  })
}

/** Unique folder paths implied by file names ("" = inputs root). */
export function folderPathsFromFiles(files: Array<{ name: string; source?: string | null }>): string[] {
  const out = new Set<string>()
  for (const f of files) {
    if (f.source === "run_output" || f.source === "run_code") continue
    const name = f.name
    if (typeof name !== "string" || !name.includes("/")) continue
    const parts = name.split("/")
    for (let i = 1; i < parts.length; i++) out.add(parts.slice(0, i).join("/"))
  }
  return [...out].sort()
}

export function folderFilesUrl(projectId: string, path: string): string {
  const q = new URLSearchParams({ path })
  return `/api/projects/${encodeURIComponent(projectId)}/folders/files?${q.toString()}`
}

/** Load every input file id under a project folder (recursive prefix). */
export async function loadFolderFileRefs(
  projectId: string,
  folderPath: string,
  init?: RequestInit,
): Promise<FolderFileRef[]> {
  const res = await fetch(folderFilesUrl(projectId, folderPath), {
    credentials: "include",
    ...init,
  })
  if (!res.ok) {
    const body = await res.json().catch(() => ({})) as { error?: string }
    throw new Error(typeof body.error === "string" ? body.error : `Cannot list folder files (${res.status})`)
  }
  const body = await res.json() as { files?: FolderFileRef[] }
  const files = Array.isArray(body.files) ? body.files : []
  return files.filter((f) => f && typeof f.id === "string" && f.id && typeof f.name === "string")
}
