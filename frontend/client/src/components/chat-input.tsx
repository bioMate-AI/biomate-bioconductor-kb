import { VoiceInput } from "./voice-controls"
import { LiveVoicePanel } from "./live-voice-panel"
import { useState, useRef, useEffect, KeyboardEvent } from "react"
import { useLocation } from "wouter"
import { Button } from "@/components/ui/button"
import { Textarea } from "@/components/ui/textarea"
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { ScrollArea } from "@/components/ui/scroll-area"
import { Badge } from "@/components/ui/badge"
import { Send, Paperclip, X, FileText, Square, Database, FolderInput, SlidersHorizontal, ChevronDown, ChevronRight } from "lucide-react"
import { GalaxyDatasetBrowser } from "./galaxy-dataset-browser"
import { SkillsSelector, type SkillPack } from "./skills-selector"
import { LanePreview, type LaneKind } from "./lane-preview"
import { useDebounce } from "@/hooks/useDebounce"
import { filesFromDataTransfer } from "@/lib/folder-drop"
import { t } from "@/lib/i18n"
import { outputRequirementsToPrompt } from "@/lib/output-requirements"

interface AttachedFile {
  id: string
  name: string
  size: number
  file: File
}

export interface ComposerDatasetReference {
  id: string;
  name: string;
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
  voiceContextKey?: string;
  onSend: (message: string, files?: File[], contextOverride?: Record<string, unknown>) => void
  disabled?: boolean
  /** Number of messages queued behind the current AI response */
  pendingCount?: number
  placeholder?: string
  onFilesSelected?: (files: File[]) => void
  isStreaming?: boolean
  onStop?: () => void
  /** Latest assistant reply — used by compact live-voice read-aloud while a session is open. */
  voiceReply?: { id: string; content: string }
  /** Register a setter function that can externally pre-fill the draft */
  onRegisterSetDraft?: (setter: (draft: string) => void) => void
  /** Register an adder function that can programmatically attach File objects */
  onRegisterAddFiles?: (adder: (files: File[]) => void) => void
  /** Replace previous example inputs while preserving user-picked files. */
  onRegisterExampleFiles?: (setter: (files: File[]) => void) => void
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
  /**
   * Optional injected expert/skill packs for the composer's Experts selector
   * (spec 06 §6.5 / §0.9.2). When omitted, SkillsSelector fetches the real
   * GET /api/skills catalogue itself; injecting is for tests / a parent that
   * already holds the list. An empty array renders the honest-empty state.
   */
  skillPacks?: SkillPack[]
}

/** Mirrors MAX_DATASET_REFS in frontend/server/dataset-cap.ts. */
const MAX_DATASET_REFS = 32

export function ChatInput({
  voiceContextKey,
  onSend,
  disabled = false,
  pendingCount = 0,
  placeholder = t('chat.placeholder'),
  onFilesSelected,
  isStreaming = false,
  onStop,
  voiceReply,
  onRegisterSetDraft,
  onRegisterAddFiles,
  onRegisterExampleFiles,
  sessionDatasetCount = 0,
  // The pre-send lane verdict ("Answer here · with sources" / "Prepare an
  // analysis") was removed from above the composer: the routing/intent read now
  // lives only in the post-send progress stream (the scrolling status box, via
  // the 'intent' progress event's rationale). Default off; the lane override
  // simply falls back to server-decides.
  showLanePreview = false,
  projects = [],
  activeProjectId = null,
  onFileToProject,
  skillPacks,
}: ChatInputProps) {
  const [message, setMessage] = useState("")
  // Standing instructions the user adds for THIS composer/project (spec 06
  // §6.5). These are a reading lens the assistant should apply to every
  // request in this composer — they thread into the submit context so the
  // backend can honour them. Seeded from the active project's own
  // `instructions` (schema `Project.instructions`) so a filed chat inherits
  // the project's standing context. The §6.5 "experts" catalogue is now
  // surfaced alongside via <SkillsSelector>, driven by the REAL GET /api/skills
  // endpoint (frontend/server/routes.ts) — honest-empty when the catalogue is
  // unpopulated. Selected pack ids thread into the same submit context path as
  // instructions (as `skillPackIds`) so a run records which experts were on.
  const activeProject = activeProjectId
    ? projects.find((p) => p.id === activeProjectId) ?? null
    : null
  // Spec 06 §6.1 instructions chip: "A count of standing project instructions in context. Present
  // only inside a project that has them." Count the project's standing rules (one per non-empty line
  // of its instructions, matching how the Instructions page splits them) from the fresh project prop.
  const standingRuleCount = (activeProject?.instructions ?? "")
    .split("\n").map((s) => s.trim()).filter(Boolean).length
  // Mirrors MAX_COMPOSER_INSTRUCTIONS_LENGTH in server/chat-context.ts. Enforce it in the UI so a
  // long paste can't be SILENTLY truncated server-side with no signal to the user.
  const COMPOSER_INSTRUCTIONS_MAX = 24_000
  const [instructions, setInstructions] = useState<string>(activeProject?.instructions ?? "")
  const [instructionsOpen, setInstructionsOpen] = useState(false)
  // Expert/skill packs toggled on for THIS composer (spec 06 §6.5). The ids
  // thread into the submit context as `skillPackIds` so a run records which
  // experts were applied — mirrors the dataset/instruction threading below.
  const [selectedSkillIds, setSelectedSkillIds] = useState<string[]>([])
  const [projectOutputRequirements, setProjectOutputRequirements] = useState("")
  const [projectSettingsLoading, setProjectSettingsLoading] = useState(false)
  const [projectSettingsError, setProjectSettingsError] = useState("")
  useEffect(() => {
    let cancelled = false
    setSelectedSkillIds([]); setProjectOutputRequirements(""); setProjectSettingsError("")
    if (!activeProjectId) { setProjectSettingsLoading(false); return }
    setProjectSettingsLoading(true)
    fetch(`/api/projects/${activeProjectId}/instruction-settings`, { credentials: "include" })
      .then(async r => { if (!r.ok) throw new Error("Could not load project instructions. Reload before sending."); return r.json() })
      .then(data => { if (!cancelled) { setSelectedSkillIds(data.settings.skillPackIds); setProjectOutputRequirements(data.settings.outputRequirements) } })
      .catch(e => { if (!cancelled) setProjectSettingsError(e.message) })
      .finally(() => { if (!cancelled) setProjectSettingsLoading(false) })
    return () => { cancelled = true }
  }, [activeProjectId])
  // If the chat becomes filed into a project that carries standing
  // instructions and the user hasn't typed their own, adopt the project's.
  const seededProjectIdRef = useRef<string | null>(null)
  // The exact text last seeded from the project, so the send path can tell an untouched project
  // seed (which the server already injects — do NOT re-send) from chat-specific text the user typed.
  const seededInstructionsRef = useRef<string>("")
  useEffect(() => {
    const seed = activeProject?.instructions ?? ""
    if (!activeProject && seededProjectIdRef.current) { seededProjectIdRef.current = null; seededInstructionsRef.current = ""; setInstructions("") }
    if (activeProject && seededProjectIdRef.current !== activeProject.id) {
      seededProjectIdRef.current = activeProject.id
      seededInstructionsRef.current = seed
      setInstructions(seed)
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
  const [linkingDataset, setLinkingDataset] = useState(false)
  const [datasetLinkError, setDatasetLinkError] = useState("")
  useEffect(() => {
    const query = new URLSearchParams(window.location.search)
    const fileIds = [...new Set(query.getAll("attachFile"))].filter(Boolean)
    if (!fileIds.length || !activeProjectId || query.get("project") !== activeProjectId) return
    let cancelled = false
    const abort = new AbortController()
    setLinkingDataset(true)
    setDatasetLinkError("")
    Promise.all(fileIds.map(async fileId => {
      const response = await fetch(`/api/projects/${encodeURIComponent(activeProjectId)}/files/${encodeURIComponent(fileId)}/url`, {
        credentials: "include", signal: abort.signal,
      })
      if (!response.ok) throw new Error(`Cannot link this project file (${response.status}).`)
      const file = await response.json()
      if (typeof file.name !== "string") throw new Error("The project file is unavailable.")
      return { id: fileId, value: fileId, name: file.name }
    })).then(files => {
      if (cancelled) return
      setSelectedDatasets(previous => [...previous.filter(d => !fileIds.includes(d.value)), ...files])
      query.delete("attachFile")
      window.history.replaceState(null, "", `${window.location.pathname}?${query.toString()}`)
      textareaRef.current?.focus()
    }).catch(error => { if (!cancelled) setDatasetLinkError(error.message) })
      .finally(() => { if (!cancelled) setLinkingDataset(false) })
    return () => { cancelled = true; abort.abort() }
  }, [activeProjectId])
  const [showDatasetBrowser, setShowDatasetBrowser] = useState(false)
  const [, setLocation] = useLocation()
  const textareaRef = useRef<HTMLTextAreaElement>(null)
  const fileInputRef = useRef<HTMLInputElement>(null)
  const folderInputRef = useRef<HTMLInputElement>(null)

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
        setTimeout(() => {
          const textarea = textareaRef.current
          if (!textarea) return
          textarea.style.height = 'auto'
          textarea.style.height = `${Math.min(textarea.scrollHeight, 140)}px`
          textarea.focus()
          textarea.setSelectionRange(0, 0)
          textarea.scrollTop = 0
        }, 0)
      })
    }
  }, [onRegisterSetDraft])

  const demoFileIds = useRef(new Set<string>())
  useEffect(() => {
    onRegisterExampleFiles?.((files: File[]) => {
      const previousIds = demoFileIds.current
      const prefix = `demo-${Date.now()}-`
      const next = files.map((file, i) => ({ id: `${prefix}${i}`, name: file.name, size: file.size, file }))
      demoFileIds.current = new Set(next.map(f => f.id))
      setAttachedFiles(prev => [...prev.filter(f => !previousIds.has(f.id)), ...next])
    })
  }, [onRegisterExampleFiles])

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
    if (disabled || linkingDataset || projectSettingsLoading || projectSettingsError) return
    if (message.trim() || attachedFiles.length > 0) {
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
      // Composer instructions are REQUEST-scoped. In a project the standing instructions are already
      // injected server-side (routes.ts "Research goal" / "Background instructions"), so re-sending
      // the composer's seeded copy duplicated them in the prompt. Send `instructions` only when they
      // are chat-specific — i.e. the user changed them from the project seed, or there is no project.
      const isUntouchedProjectSeed = !!activeProjectId && instructions.trim() === seededInstructionsRef.current.trim()
      const chatSpecificInstructions = isUntouchedProjectSeed ? "" : instructions.trim()
      // Render output requirements through the shared helper: ONLY formats the user left switched
      // ON are sent, as prose (never the raw JSON store, which also carried the disabled ones).
      const trimmedInstructions = [chatSpecificInstructions, outputRequirementsToPrompt(projectOutputRequirements)].filter(Boolean).join("\n\n")
      const datasetReferences: ComposerDatasetReference[] = selectedDatasets.map((dataset) => ({
        id: dataset.value,
        name: dataset.name,
      }))
      // Expert/skill packs toggled on for this request (spec 06 §6.5). Ride
      // as `skillPackIds` on the SAME context path so a run records which
      // experts were applied; empty selection adds nothing (honest-empty).
      const skillPackIds = selectedSkillIds
      const contextOverride: Record<string, unknown> | undefined =
        laneOverride || trimmedInstructions || datasetReferences.length > 0 || skillPackIds.length > 0 || activeProjectId
          ? {
              ...(laneOverride
                ? { intentOverride: laneOverride === "cloud" ? "workflow_generation" : "research_question" }
                : {}),
              ...(trimmedInstructions ? { composerInstructions: trimmedInstructions } : {}),
              // Exact project objects selected for THIS operation. The server
              // filters the broader session pool to this set and reports any
              // missing reference instead of silently choosing another file.
              ...(datasetReferences.length ? { datasetReferences } : {}),
              ...((activeProjectId || skillPackIds.length) ? { skillPackIds } : {}),
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

  const handleDrop = async (e: React.DragEvent) => {
    e.preventDefault()
    setIsDraggingOver(false)
    // Expand dropped folders into their files (same handling as the upload panel).
    const dropped = await filesFromDataTransfer(e.dataTransfer)
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
      className="p-4"
      style={{ position: 'relative' }}
      onDragOver={handleDragOver}
      onDragLeave={handleDragLeave}
      onDrop={handleDrop}
    >
      {/* Hidden file/folder inputs — no visible buttons (removed 2026-10-20 per
          UI refinement: the one visible entry point is the dataset browser).
          Kept for the composer's drag-drop attach path and for programmatic /
          e2e `setInputFiles` on a hidden input. */}
      <input
        ref={fileInputRef}
        type="file"
        multiple
        style={{ display: 'none' }}
        onChange={handleLocalFilePick}
        accept="*/*"
        data-testid="chat-attach-file-input"
      />
      <input
        ref={folderInputRef}
        type="file"
        multiple
        {...({ webkitdirectory: '', directory: '', mozdirectory: '' } as Record<string, string>)}
        style={{ display: 'none' }}
        onChange={handleLocalFilePick}
        data-testid="chat-attach-folder-input"
      />
      {/* Hidden folder input — same attach path as files (matches the upload panel) */}
      <input
        ref={folderInputRef}
        type="file"
        multiple
        {...({ webkitdirectory: '', directory: '', mozdirectory: '' } as Record<string, string>)}
        style={{ display: 'none' }}
        onChange={handleLocalFilePick}
      />

      {/* Attached files + selected dataset chips */}
      {projectSettingsError && <p role="alert" className="text-xs text-destructive">{projectSettingsError}</p>}
      {linkingDataset && <p role="status" className="text-xs text-muted-foreground">Linking project file…</p>}
      {datasetLinkError && <p role="alert" className="text-xs text-destructive">{datasetLinkError} Return to Files and select an available file.</p>}
      {(attachedFiles.length > 0 || selectedDatasets.length > 0) && (
        <div className="flex flex-wrap gap-2 mb-3">
          {attachedFiles.map(file => (
            <div
              key={file.id}
              className="flex items-center gap-1.5 px-2 py-1 bg-muted rounded-md text-sm group"
              data-testid="composer-attached-file"
              data-filename={file.name}
            >
              <FileText className="w-3.5 h-3.5 text-muted-foreground" />
              <button type="button" onClick={() => openPreview(file)} title={`Preview ${file.name}`} className="max-w-[220px] truncate text-left hover:underline focus-visible:underline">{file.name}</button>
              <span className="text-xs text-muted-foreground">
                ({formatFileSize(file.size)})
              </span>
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
              {/* Live reference: the chip opens the SAME dataset object it points
                  at (data hub), so a project file referenced in chat is one
                  clickable handle, not just a name. */}
              <button
                type="button"
                onClick={() => setLocation(`/files?file=${encodeURIComponent(ds.value)}`)}
                className="max-w-[150px] truncate hover:underline text-left"
                title={`Open referenced project file · id ${ds.value}`}
                data-testid="composer-dataset-ref"
              >
                {ds.name}
              </button>
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
          <span style={{ fontSize: 'var(--fs-base)', color: 'var(--bm-primary, oklch(0.55 0.20 265))', fontWeight: 500 }}>
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
            fontSize: 'var(--fs-base)',
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
                border: "none", cursor: "pointer", fontSize: 'var(--fs-sm)', fontWeight: 600,
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
                border: "none", cursor: "pointer", fontSize: 'var(--fs-sm)',
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

      {/* Lane preview (spec 06 §6.2) — advisory Instant/Cloud verdict shown as
          the user types. Debounced so it settles rather than flickering
          mid-word. Never blocks send. Hidden while streaming or when a file/
          dataset-only message (no typed intent) is queued. */}
      {showLanePreview && !isStreaming && debouncedMessage.trim() && (
        laneOverride ? (
          <div
            data-testid="lane-preview"
            data-lane={laneOverride}
            style={{ display: "flex", alignItems: "center", gap: 8, padding: "4px 4px 8px", fontSize: 'var(--fs-sm)', flexWrap: "wrap", rowGap: 4 }}
          >
            <span style={{ display: "inline-flex", alignItems: "center", gap: 6, fontWeight: 600, color: "var(--bm-text, oklch(0.22 0.01 260))" }}>
              <span aria-hidden style={{ width: 7, height: 7, borderRadius: 999, flexShrink: 0, background: laneOverride === "cloud" ? "var(--bm-primary, oklch(0.55 0.20 265))" : "var(--bm-ok, oklch(0.62 0.14 155))" }} />
              {laneOverride === "cloud" ? "Prepare an analysis · review before starting" : "Answer here · with sources"}
            </span>
            <span style={{ color: "var(--bm-text-dim, oklch(0.62 0.010 260))" }}>· selected for this message</span>
            <button
              type="button"
              data-testid="lane-preview-clear-override"
              onClick={() => setLaneOverride(null)}
              style={{ background: "transparent", border: "none", padding: 0, cursor: "pointer", color: "var(--bm-primary, oklch(0.55 0.20 265))", fontSize: 'var(--fs-sm)', textDecoration: "underline", textUnderlineOffset: 2 }}
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
          : '1px solid var(--bm-border-strong, var(--bm-border, hsl(var(--border))))',
        borderRadius: 'var(--bm-r-lg, 12px)',
        background: 'var(--bm-bg-elev, hsl(var(--background)))',
        boxShadow: 'var(--bm-shadow-sm, 0 1px 2px rgba(15,23,42,0.04))',
        padding: '10px 12px',
        maxWidth: 660,
        margin: '0 auto',
        width: '100%',
        display: 'flex',
        flexDirection: 'column',
        gap: 9,
        transition: 'border-color .15s',
      }}>
        <div style={{ display: 'flex', alignItems: 'center', flexWrap: 'wrap', gap: 8, minWidth: 0 }}>
          {/* Add data — the single entry point. Opens the assembled dataset
              browser (upload file/folder via drop, session, project, From URL).
              The two former standalone file/folder buttons were removed: the
              browser's session box is now the one place to attach data. */}
          <button
            disabled={disabled}
            title={t('composer.browse_datasets')}
            aria-label={t('composer.browse_datasets')}
            data-testid="chat-attach-data-button"
            onClick={() => setShowDatasetBrowser(true)}
            style={{
              height: 28, padding: '0 8px', gap: 5, borderRadius: 'var(--bm-r-sm, 6px)',
              border: 'none', background: 'transparent',
              color: 'var(--bm-text-dim, oklch(0.62 0.010 260))',
              cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center',
              flexShrink: 0, fontSize: 'var(--fs-sm)',
            }}
          >
            <Paperclip className="w-4 h-4" />
            <span>{t('composer.data')}</span>
          </button>

          {/* Voice: compact toolbar icons only (Settings → Chat → Voice). No stacked panels. */}
          <VoiceInput
            key={`speak-${voiceContextKey}`}
            disabled={disabled || isStreaming}
            onTranscript={text => setMessage(previous => previous.trim() ? `${previous}\n${text}` : text)}
          />
          <LiveVoicePanel
            key={`live-${voiceContextKey}`}
            busy={!!(disabled || isStreaming)}
            reply={voiceReply}
            onSend={(text) => onSend(text)}
            onTranscript={text => setMessage(previous => previous.trim() ? `${previous}\n${text}` : text)}
          />

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
                  fontSize: 'var(--fs-xs)',
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
            disabled={disabled}
            value={message}
            onInput={handleInput}
            onKeyDown={handleKeyDown}
            placeholder={placeholder}
            className="w-full min-w-0 min-h-[44px] max-h-[140px] resize-none rounded-none border-0 border-b border-solid border-border outline-none shadow-none px-0 pt-1 pb-3 bg-transparent text-sm"
            style={{
              order: -1,
              flexBasis: '100%',
              fontFamily: 'var(--bm-font-ui)',
              fontSize: 'var(--fs-base)',
              lineHeight: 1.55,
              color: 'var(--bm-text)',
            }}
            rows={1}
          />

      {/* Instructions affordance (spec 06 §6.5). A lightweight, collapsible
          field for standing instructions the assistant applies to every
          request in this composer. Its value threads into the submit context
          as `composerInstructions`. Collapsed by default so it adds no noise;
          shows a "on" dot when instructions are present. The §6.5 "experts"
          catalogue ships alongside it — see the Experts affordance
          (SkillsSelector) below, backed by the real GET /api/skills catalogue. */}
      <div style={{ display: "flex", alignItems: "center", gap: 8, flexWrap: "wrap", minWidth: 0, flexBasis: (!activeProjectId && instructionsOpen) ? "100%" : undefined }}>
        {/* Experts affordance (spec 06 §6.5 / §0.9.2) — placed first per the
            design composer row (data → skills & experts → instructions). Backed
            by the REAL GET /api/skills catalogue; honest-empty ("No expert packs
            available yet") when unpopulated. Selection threads into the submit
            context as `skillPackIds`. */}
        <div style={{ flexShrink: 0 }}>
          <SkillsSelector
            selectedIds={selectedSkillIds}
            onChange={setSelectedSkillIds}
            packs={skillPacks}
          />
        </div>

        {/* Instructions affordance. In a project (design ChatView onOpenInstr):
            a single button that opens the project's Instructions panel directly
            — standing instructions, output requirements and experts live there
            and apply to every request. Outside a project there is no panel to
            open, so a lightweight inline field remains for projectless chats. */}
        {activeProjectId ? (
          // Design-conformant (Spec 06 §6.1 / ChatView.jsx:72): show the chip ONLY when the project
          // has standing instructions, and show their COUNT (so a user learns their run was shaped by
          // a rule they wrote weeks ago) — not an always-visible label with a dot that lit for any of
          // instructions/outputs/skills. Opening the Instructions panel is still a click away here,
          // and also from the sidebar's per-project "Instructions" link, so a 0-rule project is not
          // stranded by hiding the chip.
          standingRuleCount > 0 ? (
          <button
            type="button"
            data-testid="composer-instructions-toggle"
            onClick={() => setLocation(`/projects?project=${activeProjectId}&tab=instructions`)}
            title={`${standingRuleCount} standing instruction${standingRuleCount === 1 ? "" : "s"} from ${activeProject?.name ?? "this project"} ${standingRuleCount === 1 ? "is" : "are"} in context`}
            style={{
              display: "inline-flex", alignItems: "center", gap: 6,
              border: "none", background: "transparent", cursor: "pointer",
              fontSize: 'var(--fs-sm)', color: "var(--bm-text-dim, oklch(0.62 0.010 260))",
              padding: "2px 2px",
            }}
          >
            <SlidersHorizontal className="w-3 h-3" />
            <span>{t('composer.instructions')}</span>
            <span
              data-testid="composer-instructions-count"
              style={{
                minWidth: 16, height: 16, padding: "0 5px", borderRadius: 999,
                display: "inline-flex", alignItems: "center", justifyContent: "center",
                fontSize: 'var(--fs-xs)', fontWeight: 600, lineHeight: 1,
                background: "var(--bm-accent-soft, oklch(0.93 0.03 245))",
                color: "var(--bm-accent, oklch(0.45 0.14 245))",
              }}
            >
              {standingRuleCount}
            </span>
          </button>
          ) : null
        ) : (
          <div style={{ minWidth: 0, flex: instructionsOpen ? "1 1 100%" : undefined }}>
            <button
              type="button"
              data-testid="composer-instructions-toggle"
              onClick={() => setInstructionsOpen((o) => !o)}
              style={{
                display: "inline-flex", alignItems: "center", gap: 6,
                border: "none", background: "transparent", cursor: "pointer",
                fontSize: 'var(--fs-sm)', color: "var(--bm-text-dim, oklch(0.62 0.010 260))",
                padding: "2px 2px",
              }}
            >
              {instructionsOpen ? <ChevronDown className="w-3 h-3" /> : <ChevronRight className="w-3 h-3" />}
              <SlidersHorizontal className="w-3 h-3" />
              <span>{t('composer.instructions')}</span>
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
                placeholder={t('composer.instructions_placeholder')}
                rows={2}
                maxLength={COMPOSER_INSTRUCTIONS_MAX}
                style={{
                  width: "100%", marginTop: 6, resize: "vertical",
                  minHeight: 44, maxHeight: 160,
                  border: "1px solid var(--bm-border, oklch(0.88 0.004 240))",
                  borderRadius: "var(--bm-r-md, 8px)",
                  background: "var(--bm-bg-elev, hsl(var(--background)))",
                  padding: "6px 8px", fontSize: 'var(--fs-base)', lineHeight: 1.45,
                  fontFamily: "var(--bm-font-ui)", color: "var(--bm-text, oklch(0.22 0.01 260))",
                  outline: "none",
                }}
              />
            )}
            {instructionsOpen && instructions.length > COMPOSER_INSTRUCTIONS_MAX * 0.9 && (
              <div data-testid="composer-instructions-limit" style={{ marginTop: 2, fontSize: 'var(--fs-xs)', textAlign: "right", color: "var(--bm-text-dim, oklch(0.62 0.010 260))" }}>
                {instructions.length.toLocaleString()} / {COMPOSER_INSTRUCTIONS_MAX.toLocaleString()} — longer input is trimmed before it reaches the model
              </div>
            )}
          </div>
        )}
      </div>


          {/* Send / Stop button */}
          {isStreaming ? (
            <button
              data-testid="chat-stop-button"
              onClick={onStop}
              style={{
                marginLeft: 'auto',
                width: 28, height: 28, borderRadius: 'var(--bm-r-sm, 6px)',
                background: 'var(--bm-err, oklch(0.58 0.18 25))',
                color: 'white', border: 'none', cursor: 'pointer',
                display: 'flex', alignItems: 'center', justifyContent: 'center',
                flexShrink: 0,
              }}
              title={t('composer.stop_reply')}
            >
              <Square className="w-3.5 h-3.5 fill-current" />
            </button>
          ) : (
            <>
            {/* ⏎ hint, per spec 06 §6.1 send group ([ Enter ] [ > ]). */}
            <kbd
              aria-hidden
              style={{
                marginLeft: 'auto',
                fontSize: 'var(--fs-xs)', lineHeight: 1, color: 'var(--bm-text-dim, oklch(0.62 0.010 260))',
                border: '1px solid var(--bm-border, oklch(0.88 0.004 240))',
                borderRadius: 4, padding: '2px 5px',
                fontFamily: 'var(--bm-font-ui)', background: 'var(--bm-surface, transparent)',
              }}
            >⏎</kbd>
            <button
              data-testid="chat-send-button"
              onClick={handleSend}
              title={t('chat.send')}
              disabled={disabled || linkingDataset || projectSettingsLoading || !!projectSettingsError || (!message.trim() && attachedFiles.length === 0)}
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
            </>
          )}
        </div>
      </div>

      {/* Dataset browser dialog */}
      <GalaxyDatasetBrowser
        open={showDatasetBrowser}
        onClose={() => setShowDatasetBrowser(false)}
        projectId={activeProjectId}
        onSelect={(datasetValue, datasetName) => {
          // Add as a chip — dataset reference is appended to message text on send,
          // so the user sees a clean chip rather than raw ID text in the textarea.
          setSelectedDatasets(prev => {
            if (prev.some(d => d.value === datasetValue)) return prev
            // The stable dataset id is also the chip identity. A timestamp is
            // not unique when a comparison preselects two files in one event.
            return [...prev, { id: `ds-${datasetValue}`, name: datasetName, value: datasetValue }]
          })
          setTimeout(() => textareaRef.current?.focus(), 0)
        }}
      />
    </div>
  )
}
