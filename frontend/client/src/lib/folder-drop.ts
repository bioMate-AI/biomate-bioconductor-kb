/**
 * Expand a drop's DataTransfer into a flat File[] — including every file inside
 * dropped folders (via the webkitGetAsEntry directory API). Falls back to
 * dataTransfer.files when the browser doesn't expose entries.
 *
 * Shared by the upload panel (file-upload.tsx) and the chat composer
 * (chat-input.tsx) so a dropped folder behaves identically in both — the
 * "same constraint as the panel" requirement.
 *
 * IMPORTANT: the entry objects must be pulled off the DataTransferItemList
 * synchronously, before any await — the list is only valid during event
 * dispatch. The entry-collection loop below therefore runs before the first
 * await; the FileSystemEntry objects it captures stay valid afterwards.
 */
export async function filesFromDataTransfer(dt: DataTransfer): Promise<File[]> {
  const items = dt.items
  const canWalk =
    !!items &&
    items.length > 0 &&
    typeof (items[0] as unknown as { webkitGetAsEntry?: unknown }).webkitGetAsEntry === 'function'
  if (!canWalk) return Array.from(dt.files)

  // Collect entries synchronously (before any await).
  const entries: FileSystemEntry[] = []
  for (let i = 0; i < items.length; i++) {
    const it = items[i]
    if (it.kind !== 'file') continue
    const entry = (it as unknown as { webkitGetAsEntry?: () => FileSystemEntry | null }).webkitGetAsEntry?.()
    if (entry) entries.push(entry)
  }
  if (entries.length === 0) return Array.from(dt.files)

  const out: File[] = []

  function readFile(entry: FileSystemEntry, prefix: string): Promise<void> {
    return new Promise((resolve) => {
      ;(entry as FileSystemFileEntry).file(
        (file: File) => {
          const rel = prefix + file.name
          if (rel !== file.name) {
            try {
              Object.defineProperty(file, 'webkitRelativePath', { value: rel, configurable: true })
            } catch {
              /* read-only in some engines; the flat name still uploads */
            }
          }
          out.push(file)
          resolve()
        },
        () => resolve(),
      )
    })
  }

  function readDir(entry: FileSystemEntry, prefix: string): Promise<void> {
    return new Promise((resolve) => {
      const reader = (entry as FileSystemDirectoryEntry).createReader()
      // readEntries yields in chunks; keep calling until it returns empty.
      const pump = () =>
        reader.readEntries(
          async (batch: FileSystemEntry[]) => {
            if (!batch || batch.length === 0) {
              resolve()
              return
            }
            await Promise.all(batch.map((e) => walk(e, prefix + entry.name + '/')))
            pump()
          },
          () => resolve(),
        )
      pump()
    })
  }

  function walk(entry: FileSystemEntry, prefix: string): Promise<void> {
    if (entry.isFile) return readFile(entry, prefix)
    if (entry.isDirectory) return readDir(entry, prefix)
    return Promise.resolve()
  }

  await Promise.all(entries.map((e) => walk(e, '')))
  return out.length ? out : Array.from(dt.files)
}
