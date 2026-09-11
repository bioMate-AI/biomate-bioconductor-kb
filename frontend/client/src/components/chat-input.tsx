import { useState, useRef, useEffect, KeyboardEvent } from "react"
import { Button } from "@/components/ui/button"
import { Textarea } from "@/components/ui/textarea"
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { ScrollArea } from "@/components/ui/scroll-area"
import { Badge } from "@/components/ui/badge"
import { Send, Paperclip, X, FileText, Eye, Square, Database, FolderInput, SlidersHorizontal, ChevronDown, ChevronRight } from "lucide-react"
import { GalaxyDatasetBrowser } from "./galaxy-dataset-browser"
import { LanePreview, type LaneKind } from "./lane-preview"
import { useDebounce } from "@/hooks/useDebounce"

interface AttachedFile {
  id: string
  name: string
  size: number
  file: File
}

/**
 * A real project as returned by GET /api/projects (or projectService).
 * Only the fields the composer actually reads are typed here; the shape is
 * a subset of @shared/schema `Project`. NO synthetic/fabricated projects are
 * ever constructed — if the caller passes an empty list, the suggested-project
 * row renders nothing (honest-empty).
 */
export interface ComposerProject {
  id: string
  name: string
  category?: string
  tags?: string[]
  description?: string
  /** Standing background context for the project (schema `Project.instructions`). */
  instructions?: string
}

/**
 * Score how well a project matches the typed goal, using ONLY real project
 * fields (name / category / tags / description). Returns 0 when there is no
 * lexical overlap — the caller treats 0 as "nothing to propose" so the row
 * stays hidden (spec 06 §6.6.1: "Neither → Nothing is proposed").
 */
export function scoreProjectMatch(text: string, p: ComposerProject): number {
  const q = text.toLowerCase()
  if (!q.trim()) return 0
  // Tokenise the goal into words of length ≥ 3 (drops "the", "a", "of"…).
  const words = Array.from(new Set(q.split(/[^a-z0-9]+/i).filter((w) => w.length >= 3)))
  if (words.length === 0) return 0
  const haystacks: Array<{ text: string; weight: number }> = [
    { text: (p.name || "").toLowerCase(), weight: 3 },
    { text: (p.category || "").toLowerCase(), weight: 2 },
    { text: (p.tags || []).join(" ").toLowerCase(), weight: 2 },
    { text: (p.description || "").toLowerCase(), weight: 1 },
  ]
  let score = 0
  for (const w of words) {
    for (const h of haystacks) {
      if (h.text && h.text.includes(w)) score += h.weight
    }
  }
  return score
}

/** Pick the best-matching REAL project for a goal, or null when none clears the bar. */
export function suggestProject(
  text: string,
  projects: ComposerProject[],
  activeProjectId?: string | null,
): ComposerProject | null {
  if (!projects || projects.length === 0) return null
  let best: ComposerProject | null = null
  let bestScore = 0
  for (const p of projects) {
    // Never propose the project the chat is already filed into.
    if (activeProjectId && p.id === activeProjectId) continue
    const s = scoreProjectMatch(text, p)
    if (s > bestScore) { bestScore = s; best = p }
  }
  // A single incidental token match is noise; require a real signal.
  return bestScore >= 3 ? best : null
}

interface ChatInputProps {
  onSend: (message: string, files?: File[], contextOverride?: Record<string, unknown>) => void
  disabled?: boolean
  /** Number of messages queued behind the current AI response */
  pendingCount?: number
  placeholder?: string
  onFilesSelected?: (files: File[]) => void
  isStreaming?: boolean
  onStop?: () => void
  /** Register a setter function that can externally pre-fill the draft */
  onRegisterSetDraft?: (setter: (draft: string) => void) => void
  /** Register an adder function that can programmatically attach File objects */
  onRegisterAddFiles?: (adder: (files: File[]) => void) => void
  /**
   * Count of dataset references already attached to THIS chat session
   * (everything in chat_sessions.datasets, accumulated across all turns).
   * Surfaces the X / MAX_DATASET_REFS indicator next to the attach button
   * so users see when they're approaching the server-side cap (32; see
   * frontend/server/dataset-cap.ts).
   */
  sessionDatasetCount?: number
  /**
   * Show the advisory Instant/Cloud lane preview above the input as the
   * user types (spec 06 §6.2). Default true; set false to hide it.
   */
  showLanePreview?: boolean
  /**
   * The user's REAL projects (subset of @shared/schema `Project`), used to
   * propose a home for the current chat (spec 06 §6.6 "Project suggested").
   * The composer never invents projects — an empty/absent list means the
   * suggested-project row simply doesn't render.
   */
  projects?: ComposerProject[]
  /**
   * The project this chat is already filed into, if any (read from
   * `biomate-active-project-id`). When set, the suggested row is suppressed
   * (spec 06 §6.6.1: a chat that already has a home isn't re-proposed one).
   */
  activeProjectId?: string | null
  /**
   * File the current chat into a project (spec 06 §6.6 "File it there").
   * When absent, the suggested row still renders but "File it there" is a
   * no-op — the caller opts in to the filing action.
   */
  onFileToProject?: (projectId: string) => void
}

/** Mirrors MAX_DATASET_REFS in frontend/server/dataset-cap.ts. */
const MAX_DATASET_REFS = 32

export function ChatInput({
  onSend,
  disabled = false,
  pendingCount = 0,
  placeholder = "What would you like to analyze?",
  onFilesSelected,
  isStreaming = false,
  onStop,
  onRegisterSetDraft,
  onRegisterAddFiles,
  sessionDatasetCount = 0,
  showLanePreview = true,
  projects = [],
  activeProjectId = null,
  onFileToProject,
}: ChatInputProps) {
  const [message, setMessage] = useState("")
  // Standing instructions the user adds for THIS composer/project (spec 06
  // §6.5). These are a reading lens the assistant should apply to every
  // request in this composer — they thread into the submit context so the
  // backend can honour them. Seeded from the active project's own
  // `instructions` (schema `Project.instructions`) so a filed chat inherits
  // the project's standing context. NOTE (deferred): the §6.5 "experts"
  // catalogue (six owned packs picked per request) is NOT built here — there
  // is no real experts data source wired in the deployed app, so fabricating
  // a pack list would violate the honest-empty rule. Only the instructions
  // field ships; experts remain a documented follow-up.
  const activeProject = activeProjectId
    ? projects.find((p) => p.id === activeProjectId) ?? null
    : null
  const [instructions, setInstructions] = useState<string>(activeProject?.instructions ?? "")
  const [instructionsOpen, setInstructionsOpen] = useState(false)
  // If the chat becomes filed into a project that carries standing
  // instructions and the user hasn't typed their own, adopt the project's.
  const seededProjectIdRef = useRef<string | null>(null)
  useEffect(() => {
    const seed = activeProject?.instructions ?? ""
    if (activeProject && seededProjectIdRef.current !== activeProject.id) {
      seededProjectIdRef.current = activeProject.id
      setInstructions((prev) => (prev.trim() ? prev : seed))
    }
  }, [activeProject])
  // The chat has no home yet AND a real project matches the goal → propose it
  // (spec 06 §6.6). Debounced text keeps the proposal from flickering
  // mid-word. Never shown while a project is already active.
  const [suggestionDismissed, setSuggestionDismissed] = useState(false)
  // Lane override captured from the LanePreview affordance. When the user
  // clicks "run a validated pipeline instead" / "answer it instantly
  // instead", the NEXT send is forced to that lane; it resets after send.
  const [laneOverride, setLaneOverride] = useState<LaneKind | null>(null)
  const debouncedMessage = useDebounce(message, 350)
  const [attachedFiles, setAttachedFiles] = useState<AttachedFile[]>([])
  // Dataset references selected from the browser — shown as chips, injected into message on send
  const [selectedDatasets, setSelectedDatasets] = useState<Array<{ id: string; name: string; value: string }>>([])
  const [showDatasetBrowser, setShowDatasetBrowser] = useState(false)
  const textareaRef = useRef<HTMLTextAreaElement>(null)
  const fileInputRef = useRef<HTMLInputElement>(null)

  const addFiles = (files: File[]) => {
    const newAttached: AttachedFile[] = files.map(f => ({
      id: `${Date.now()}-${f.name}`,
      name: f.name,
      size: f.size,
      file: f,
    }))
    setAttachedFiles(prev => {
      const existingNames = new Set(prev.map(a => a.name))
      return [...prev, ...newAttached.filter(a => !existingNames.has(a.name))]
    })
    onFilesSelected?.(files)
  }

  // Register an external draft setter so parent can pre-fill the textarea
  useEffect(() => {
    if (onRegisterSetDraft) {
      onRegisterSetDraft((draft: string) => {
        setMessage(draft)
        setTimeout(() => textareaRef.current?.focus(), 0)
      })
    }
  }, [onRegisterSetDraft])

  // Register a file adder so parent can programmatically inject files
  useEffect(() => {
    onRegisterAddFiles?.(addFiles)
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [onRegisterAddFiles])

  const handleLocalFilePick = (e: React.ChangeEvent<HTMLInputElement>) => {
    const picked = Array.from(e.target.files ?? [])
    if (picked.length > 0) addFiles(picked)
    // Reset so the same file can be picked again
    e.target.value = ''
  }


  const handleSend = () => {
    if (message.trim() || attachedFiles.length > 0 || selectedDatasets.length > 0) {
      const files = attachedFiles.map(f => f.file)
      // Append dataset references invisibly so the AI/backend can resolve them,
      // without forcing the user to see raw IDs in the textarea.
      const datasetRefs = selectedDatasets
        .map(d => `[BioMate dataset: ${d.name} (id: ${d.value})]`)
        .join('\n')
      const fullMessage = [message.trim(), datasetRefs].filter(Boolean).join('\n')
      // Lane override -> intentOverride the backend already understands.
      // "cloud" forces workflow generation (skips ambiguity detection);
      // "instant" forces a direct research/knowledge answer. Advisory only —
      // the preview never blocks send, this just honours an explicit click.
      //
      // Standing composer instructions (spec 06 §6.5) thread into the SAME
      // context path as every other override. They ride as
      // `composerInstructions` so the backend can apply them as a reading
      // lens; empty instructions add nothing (honest-empty).
      const trimmedInstructions = instructions.trim()
      const contextOverride: Record<string, unknown> | undefined =
        laneOverride || trimmedInstructions
          ? {
              ...(laneOverride
                ? { intentOverride: laneOverride === "cloud" ? "workflow_generation" : "research_question" }
                : {}),
              ...(trimmedInstructions ? { composerInstructions: trimmedInstructions } : {}),
            }
          : undefined
      onSend(fullMessage, files.length > 0 ? files : undefined, contextOverride)
      setLaneOverride(null)
      setMessage("")
      setAttachedFiles([])
      setSelectedDatasets([])
      if (textareaRef.current) {
        textareaRef.current.style.height = "auto"
      }
    }
  }

  const handleKeyDown = (e: KeyboardEvent<HTMLTextAreaElement>) => {
    if (e.key === "Enter" && !e.shiftKey) {
      e.preventDefault()
      handleSend()
    }
  }

  const handleInput = (e: React.FormEvent<HTMLTextAreaElement>) => {
    const target = e.currentTarget
    setMessage(target.value)

    // Auto-resize textarea
    target.style.height = "auto"
    target.style.height = `${Math.min(target.scrollHeight, 200)}px`
  }

  const removeFile = (id: string) => {
    setAttachedFiles(prev => prev.filter(f => f.id !== id))
  }

  // Drag-and-drop onto the chat input
  const [isDraggingOver, setIsDraggingOver] = useState(false)

  const handleDragOver = (e: React.DragEvent) => {
    if (e.dataTransfer.types.includes('Files')) {
      e.preventDefault()
      setIsDraggingOver(true)
    }
  }

  const handleDragLeave = (e: React.DragEvent) => {
    // Only clear if leaving the container entirely
    if (!e.currentTarget.contains(e.relatedTarget as Node)) {
      setIsDraggingOver(false)
    }
  }

  const handleDrop = (e: React.DragEvent) => {
    e.preventDefault()
    setIsDraggingOver(false)
    const dropped = Array.from(e.dataTransfer.files)
    if (dropped.length > 0) addFiles(dropped)
  }

  // --- Local file preview ---
  const [previewFile, setPreviewFile] = useState<AttachedFile | null>(null)
  const [previewContent, setPreviewContent] = useState<string[]>([])
  const [previewLoading, setPreviewLoading] = useState(false)

  const openPreview = (af: AttachedFile) => {
    setPreviewFile(af)
    setPreviewContent([])
    setPreviewLoading(true)
    const ext = af.name.split('.').pop()?.toLowerCase() ?? ''
    const textExts = ['csv','tsv','txt','fasta','fa','fna','fastq','fq','vcf','bed','gff','gtf','json','xml','yaml','yml','md']
    if (!textExts.includes(ext)) {
      setPreviewLoading(false)
      setPreviewContent([]) // binary — metadata only
      return
    }
    const reader = new FileReader()
    reader.onload = (e) => {
      const text = (e.target?.result as string) || ''
      setPreviewContent(text.split('\n').slice(0, 200))
      setPreviewLoading(false)
    }
    reader.onerror = () => { setPreviewLoading(false) }
    reader.readAsText(af.file)
  }

  const getPreviewFileType = (name: string) => {
    const ext = name.split('.').pop()?.toLowerCase() ?? ''
    if (['csv','tsv','tabular'].includes(ext)) return 'table'
    if (['fasta','fa','fna','ffn','faa','fastq','fq'].includes(ext)) return 'sequence'
    if (ext === 'vcf') return 'variants'
    if (['bed','gff','gff3','gtf'].includes(ext)) return 'annotation'
    if (['h5ad','loom','bam','sam','cram','mrc','map'].includes(ext)) return 'binary'
    return 'text'
  }

  const renderPreviewTable = (lines: string[], delimiter: string) => {
    if (lines.length === 0) return null
    const header = lines[0].split(delimiter)
    const rows = lines.slice(1, 51).map(l => l.split(delimiter))
    return (
      <div className="overflow-auto">
        <table className="text-xs w-full border-collapse">
          <thead>
            <tr className="bg-muted">
              {header.map((h, i) => (
                <th key={i} className="px-2 py-1 text-left font-medium border border-border/40 whitespace-nowrap">{h}</th>
              ))}
            </tr>
          </thead>
          <tbody>
            {rows.map((row, ri) => (
              <tr key={ri} className="border-b border-border/20 hover:bg-muted/30">
                {row.map((cell, ci) => (
                  <td key={ci} className="px-2 py-1 border border-border/20 whitespace-nowrap max-w-[200px] truncate">{cell}</td>
                ))}
              </tr>
            ))}
          </tbody>
        </table>
        {lines.length > 51 && (
          <p className="text-xs text-muted-foreground mt-1 px-1">Showing 50 of {lines.length - 1} rows</p>
        )}
      </div>
    )
  }

  const formatFileSize = (bytes: number) => {
    if (bytes < 1024) return `${bytes} B`
    if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`
    return `${(bytes / (1024 * 1024)).toFixed(1)} MB`
  }

  // Real-data suggestion: only proposes an EXISTING project the goal matches
  // (spec 06 §6.6). null when there's no home to propose → row hidden.
  const suggested = (!activeProjectId && !suggestionDismissed)
    ? suggestProject(debouncedMessage, projects, activeProjectId)
    : null

  return (
    <div
      className="border-t bg-background p-4"
      style={{ position: 'relative' }}
      onDragOver={handleDragOver}
      onDragLeave={handleDragLeave}
      onDrop={handleDrop}
    >
      {/* Hidden file input for local file picking */}
      <input
        ref={fileInputRef}
        type="file"
        multiple
        style={{ display: 'none' }}
        onChange={handleLocalFilePick}
        accept="*/*"
      />

      {/* Attached files + selected dataset chips */}
      {(attachedFiles.length > 0 || selectedDatasets.length > 0) && (
        <div className="flex flex-wrap gap-2 mb-3">
          {attachedFiles.map(file => (
            <div
              key={file.id}
              className="flex items-center gap-1.5 px-2 py-1 bg-muted rounded-md text-sm group"
            >
              <FileText className="w-3.5 h-3.5 text-muted-foreground" />
              <span className="max-w-[150px] truncate">{file.name}</span>
              <span className="text-xs text-muted-foreground">
                ({formatFileSize(file.size)})
              </span>
              <button
                onClick={() => openPreview(file)}
                className="ml-0.5 p-0.5 rounded hover:bg-background transition-colors"
                title="Preview file"
              >
                <Eye className="w-3 h-3 text-muted-foreground hover:text-foreground" />
              </button>
              <button
                onClick={() => removeFile(file.id)}
                className="p-0.5 rounded hover:bg-background transition-colors"
              >
                <X className="w-3 h-3 text-muted-foreground hover:text-foreground" />
              </button>
            </div>
          ))}
          {selectedDatasets.map(ds => (
            <div
              key={ds.id}
              className="flex items-center gap-1.5 px-2 py-1 bg-blue-50 dark:bg-blue-950/40 border border-blue-200 dark:border-blue-800 rounded-md text-sm"
            >
              <Database className="w-3.5 h-3.5 text-blue-500 shrink-0" />
              <span className="max-w-[150px] truncate">{ds.name}</span>
              <button
                onClick={() => setSelectedDatasets(prev => prev.filter(d => d.id !== ds.id))}
                className="p-0.5 rounded hover:bg-background transition-colors"
              >
                <X className="w-3 h-3 text-muted-foreground hover:text-foreground" />
              </button>
            </div>
          ))}
        </div>
      )}

      {/* File Preview Dialog */}
      {previewFile && (
        <Dialog open={!!previewFile} onOpenChange={(open) => { if (!open) setPreviewFile(null) }}>
          <DialogContent className="max-w-3xl max-h-[80vh] flex flex-col">
            <DialogHeader>
              <DialogTitle className="flex items-center gap-2 text-sm">
                <FileText className="w-4 h-4" />
                {previewFile.name}
                <Badge variant="outline" className="text-xs ml-1">
                  {getPreviewFileType(previewFile.name)}
                </Badge>
                <span className="text-xs text-muted-foreground font-normal ml-auto">
                  {formatFileSize(previewFile.size)}
                </span>
              </DialogTitle>
            </DialogHeader>
            <ScrollArea className="flex-1 min-h-0 mt-2">
              {previewLoading ? (
                <p className="text-sm text-muted-foreground p-4">Loading preview…</p>
              ) : previewContent.length === 0 ? (
                <div className="p-4 space-y-2">
                  <p className="text-sm font-medium">File attached</p>
                  <p className="text-xs text-muted-foreground">Name: {previewFile.name}</p>
                  <p className="text-xs text-muted-foreground">Size: {formatFileSize(previewFile.size)}</p>
                  <p className="text-xs text-muted-foreground">Type: {previewFile.file.type || 'application/octet-stream'}</p>
                </div>
              ) : (['csv','tsv','tabular'].includes(previewFile.name.split('.').pop()?.toLowerCase() ?? '')) ? (
                <div className="p-1">
                  {renderPreviewTable(
                    previewContent,
                    previewFile.name.endsWith('.tsv') || previewContent[0]?.includes('\t') ? '\t' : ','
                  )}
                </div>
              ) : (
                <pre className="text-xs font-mono p-4 leading-relaxed whitespace-pre-wrap break-all">
                  {previewContent.join('\n')}
                  {previewContent.length >= 200 && '\n… (truncated at 200 lines)'}
                </pre>
              )}
            </ScrollArea>
          </DialogContent>
        </Dialog>
      )}

      {/* Drag-over overlay */}
      {isDraggingOver && (
        <div style={{
          position: 'absolute', inset: 0, zIndex: 10,
          background: 'rgba(99,102,241,0.06)',
          border: '2px dashed var(--bm-primary, oklch(0.55 0.20 265))',
          borderRadius: 'var(--bm-r-lg, 12px)',
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          pointerEvents: 'none',
        }}>
          <span style={{ fontSize: 13, color: 'var(--bm-primary, oklch(0.55 0.20 265))', fontWeight: 500 }}>
            Drop files to attach
          </span>
        </div>
      )}

      {/* Project suggested row (spec 06 §6.6). A quiet row proposing an
          EXISTING project as a home for this chat, driven purely by real
          project data. Honest-empty: renders nothing when the chat is already
          filed, when no project matches, or when the user has dismissed it.
          "Filing follows intent" (§6.6.1) — the chat is never gated on a
          project; this only PROPOSES one, and "Keep unfiled" is a legitimate
          resting state. */}
      {suggested && (
        <div
          data-testid="composer-project-suggested"
          data-project-id={suggested.id}
          style={{
            display: "flex", alignItems: "center", gap: 8, flexWrap: "wrap", rowGap: 6,
            padding: "8px 10px", marginBottom: 8,
            border: "1px solid var(--bm-border, oklch(0.88 0.004 240))",
            borderRadius: "var(--bm-r-md, 8px)",
            background: "var(--bm-surface, oklch(0.97 0.002 240))",
            fontSize: 12.5,
          }}
        >
          <FolderInput className="w-3.5 h-3.5 shrink-0" style={{ color: "var(--bm-text-dim, oklch(0.62 0.010 260))" }} />
          <span style={{ color: "var(--bm-text, oklch(0.22 0.01 260))" }}>
            This reads like{" "}
            <strong style={{ fontWeight: 600 }}>{suggested.name}</strong>
            {" "}· filing it there brings its files and instructions into context.{" "}
            <span style={{ color: "var(--bm-text-dim, oklch(0.62 0.010 260))" }}>Nothing runs either way.</span>
          </span>
          <span style={{ display: "inline-flex", gap: 8, marginLeft: "auto" }}>
            <button
              type="button"
              data-testid="composer-project-file-it"
              onClick={() => { onFileToProject?.(suggested.id); setSuggestionDismissed(true) }}
              style={{
                border: "none", cursor: "pointer", fontSize: 12, fontWeight: 600,
                padding: "3px 10px", borderRadius: 6, whiteSpace: "nowrap",
                background: "var(--bm-primary, oklch(0.55 0.20 265))", color: "white",
              }}
            >
              File it there
            </button>
            <button
              type="button"
              data-testid="composer-project-keep-unfiled"
              onClick={() => setSuggestionDismissed(true)}
              style={{
                border: "none", cursor: "pointer", fontSize: 12,
                padding: "3px 8px", borderRadius: 6, whiteSpace: "nowrap",
                background: "transparent", color: "var(--bm-text-dim, oklch(0.62 0.010 260))",
                textDecoration: "underline", textUnderlineOffset: 2,
              }}
            >
              Keep unfiled
            </button>
          </span>
        </div>
      )}

      {/* Instructions affordance (spec 06 §6.5). A lightweight, collapsible
          field for standing instructions the assistant applies to every
          request in this composer. Its value threads into the submit context
          as `composerInstructions`. Collapsed by default so it adds no noise;
          shows a "on" dot when instructions are present. The §6.5 "experts"
          catalogue is deliberately NOT built here — see the state comment
          above: no real experts source exists, so only the honest instructions
          field ships and experts stay a documented follow-up. */}
      <div style={{ marginBottom: 8 }}>
        <button
          type="button"
          data-testid="composer-instructions-toggle"
          onClick={() => setInstructionsOpen((o) => !o)}
          style={{
            display: "inline-flex", alignItems: "center", gap: 6,
            border: "none", background: "transparent", cursor: "pointer",
            fontSize: 12, color: "var(--bm-text-dim, oklch(0.62 0.010 260))",
            padding: "2px 2px",
          }}
        >
          {instructionsOpen ? <ChevronDown className="w-3 h-3" /> : <ChevronRight className="w-3 h-3" />}
          <SlidersHorizontal className="w-3 h-3" />
          <span>Instructions</span>
          {instructions.trim() && (
            <span
              data-testid="composer-instructions-on"
              aria-hidden
              style={{ width: 6, height: 6, borderRadius: 999, background: "var(--bm-ok, oklch(0.62 0.14 155))" }}
            />
          )}
        </button>
        {instructionsOpen && (
          <textarea
            data-testid="composer-instructions"
            value={instructions}
            onChange={(e) => setInstructions(e.target.value)}
            placeholder="Standing instructions for this composer — e.g. report FDR<0.05, use GRCh38, prefer conservative thresholds. Applied to every request here."
            rows={2}
            style={{
              width: "100%", marginTop: 6, resize: "vertical",
              minHeight: 44, maxHeight: 160,
              border: "1px solid var(--bm-border, oklch(0.88 0.004 240))",
              borderRadius: "var(--bm-r-md, 8px)",
              background: "var(--bm-bg-elev, hsl(var(--background)))",
              padding: "6px 8px", fontSize: 12.5, lineHeight: 1.45,
              fontFamily: "var(--bm-font-ui)", color: "var(--bm-text, oklch(0.22 0.01 260))",
              outline: "none",
            }}
          />
        )}
      </div>

      {/* Lane preview (spec 06 §6.2) — advisory Instant/Cloud verdict shown as
          the user types. Debounced so it settles rather than flickering
          mid-word. Never blocks send. Hidden while streaming or when a file/
          dataset-only message (no typed intent) is queued. */}
      {showLanePreview && !isStreaming && debouncedMessage.trim() && (
        laneOverride ? (
          <div
            data-testid="lane-preview"
            data-lane={laneOverride}
            style={{ display: "flex", alignItems: "center", gap: 8, padding: "4px 4px 8px", fontSize: 12, flexWrap: "wrap", rowGap: 4 }}
          >
            <span style={{ display: "inline-flex", alignItems: "center", gap: 6, fontWeight: 600, color: "var(--bm-text, oklch(0.22 0.01 260))" }}>
              <span aria-hidden style={{ width: 7, height: 7, borderRadius: 999, flexShrink: 0, background: laneOverride === "cloud" ? "var(--bm-primary, oklch(0.55 0.20 265))" : "var(--bm-ok, oklch(0.62 0.14 155))" }} />
              {laneOverride === "cloud" ? "Cloud · validated workflow" : "Instant · cited answer"}
            </span>
            <span style={{ color: "var(--bm-text-dim, oklch(0.62 0.010 260))" }}>· forced for this message</span>
            <button
              type="button"
              data-testid="lane-preview-clear-override"
              onClick={() => setLaneOverride(null)}
              style={{ background: "transparent", border: "none", padding: 0, cursor: "pointer", color: "var(--bm-primary, oklch(0.55 0.20 265))", fontSize: 12, textDecoration: "underline", textUnderlineOffset: 2 }}
            >
              let BioMate decide
            </button>
          </div>
        ) : (
          <LanePreview text={debouncedMessage} onOverride={setLaneOverride} />
        )
      )}

      {/* Reference design: pill input with attachment + textarea + send */}
      <div className="chat-input" style={{
        border: isDraggingOver
          ? '1px solid var(--bm-primary, oklch(0.55 0.20 265))'
          : '1px solid var(--bm-border, hsl(var(--border)))',
        borderRadius: 'var(--bm-r-lg, 12px)',
        background: 'var(--bm-bg-elev, hsl(var(--background)))',
        boxShadow: 'var(--bm-shadow-sm, 0 1px 2px rgba(15,23,42,0.04))',
        padding: '8px 10px',
        display: 'flex',
        flexDirection: 'column',
        gap: 4,
        transition: 'border-color .15s',
      }}>
        <div style={{ display: 'flex', alignItems: 'flex-end', gap: 6 }}>
          {/* Upload local file button */}
          <button
            disabled={disabled}
            title="Attach file"
            onClick={() => fileInputRef.current?.click()}
            style={{
              width: 28, height: 28, borderRadius: 'var(--bm-r-sm, 6px)',
              border: 'none', background: 'transparent',
              color: 'var(--bm-text-dim, oklch(0.62 0.010 260))',
              cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center',
              flexShrink: 0,
            }}
          >
            <Paperclip className="w-4 h-4" />
          </button>
          {/* Browse BioMate datasets */}
          <button
            disabled={disabled}
            title="Browse BioMate datasets"
            onClick={() => setShowDatasetBrowser(true)}
            style={{
              width: 22, height: 22, borderRadius: 'var(--bm-r-sm, 6px)',
              border: 'none', background: 'transparent',
              color: 'var(--bm-text-dim, oklch(0.62 0.010 260))',
              cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center',
              flexShrink: 0,
            }}
          >
            <Database className="w-3 h-3" />
          </button>

          {/* Attached-count indicator. Hidden at 0 (no noise pre-attach);
              muted up to 75% of the cap; amber 76–99%; red at cap with a
              tooltip pointing users at Galaxy collections for bulk files.
              Server-side cap lives in frontend/server/dataset-cap.ts. */}
          {sessionDatasetCount > 0 && (() => {
            const pct = sessionDatasetCount / MAX_DATASET_REFS
            const atCap = sessionDatasetCount >= MAX_DATASET_REFS
            const tone = atCap
              ? 'var(--bm-err, oklch(0.58 0.18 25))'
              : pct >= 0.76
                ? 'oklch(0.62 0.18 60)'
                : 'var(--bm-text-dim, oklch(0.62 0.010 260))'
            const fontWeight = atCap ? 600 : 500
            const tooltip = atCap
              ? `At the ${MAX_DATASET_REFS}-attachment cap — older entries will drop when you attach another. For bulk experiments, use an S3 folder prefix (1 reference for N files).`
              : pct >= 0.76
                ? `Approaching the ${MAX_DATASET_REFS}-attachment cap. Older entries will drop on overflow.`
                : `${sessionDatasetCount} of ${MAX_DATASET_REFS} attachment references used in this conversation.`
            return (
              <span
                data-testid="chat-input-attached-count"
                title={tooltip}
                style={{
                  fontSize: 11,
                  lineHeight: 1,
                  color: tone,
                  fontWeight,
                  padding: '4px 6px',
                  borderRadius: 4,
                  background: atCap ? 'oklch(0.95 0.04 25)' : 'transparent',
                  flexShrink: 0,
                  fontVariantNumeric: 'tabular-nums',
                  cursor: 'help',
                }}
              >
                {sessionDatasetCount} / {MAX_DATASET_REFS}
              </span>
            )
          })()}

          <Textarea
            ref={textareaRef}
            data-testid="chat-input"
            value={message}
            onInput={handleInput}
            onKeyDown={handleKeyDown}
            placeholder={placeholder}
            className="min-h-[22px] max-h-[140px] resize-none border-none outline-none shadow-none p-0 bg-transparent text-sm flex-1"
            style={{
              fontFamily: 'var(--bm-font-ui)',
              fontSize: 14,
              lineHeight: 1.5,
              color: 'var(--bm-text)',
            }}
            rows={1}
          />

          {/* Send / Stop button */}
          {isStreaming ? (
            <button
              data-testid="chat-stop-button"
              onClick={onStop}
              style={{
                width: 28, height: 28, borderRadius: 'var(--bm-r-sm, 6px)',
                background: 'var(--bm-err, oklch(0.58 0.18 25))',
                color: 'white', border: 'none', cursor: 'pointer',
                display: 'flex', alignItems: 'center', justifyContent: 'center',
                flexShrink: 0,
              }}
              title="Stop reply"
            >
              <Square className="w-3.5 h-3.5 fill-current" />
            </button>
          ) : (
            <button
              data-testid="chat-send-button"
              onClick={handleSend}
              disabled={!message.trim() && attachedFiles.length === 0 && selectedDatasets.length === 0}
              style={{
                width: 28, height: 28, borderRadius: 'var(--bm-r-sm, 6px)',
                background: (!message.trim() && attachedFiles.length === 0 && selectedDatasets.length === 0)
                  ? 'var(--bm-surface-3, oklch(0.945 0.005 240))'
                  : 'var(--bm-text, oklch(0.22 0.01 260))',
                color: (!message.trim() && attachedFiles.length === 0 && selectedDatasets.length === 0)
                  ? 'var(--bm-text-dim)' : 'white',
                border: 'none', cursor: 'pointer',
                display: 'flex', alignItems: 'center', justifyContent: 'center',
                flexShrink: 0, transition: 'background .15s',
              }}
            >
              <Send className="w-3.5 h-3.5" />
            </button>
          )}
        </div>
      </div>

      {/* Dataset browser dialog */}
      <GalaxyDatasetBrowser
        open={showDatasetBrowser}
        onClose={() => setShowDatasetBrowser(false)}
        onSelect={(datasetValue, datasetName) => {
          // Add as a chip — dataset reference is appended to message text on send,
          // so the user sees a clean chip rather than raw ID text in the textarea.
          setSelectedDatasets(prev => {
            if (prev.some(d => d.value === datasetValue)) return prev
            return [...prev, { id: `ds-${Date.now()}`, name: datasetName, value: datasetValue }]
          })
          setTimeout(() => textareaRef.current?.focus(), 0)
        }}
      />
    </div>
  )
}
