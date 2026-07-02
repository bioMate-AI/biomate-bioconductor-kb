import { useState, useRef, useEffect, KeyboardEvent } from "react"
import { Button } from "@/components/ui/button"
import { Textarea } from "@/components/ui/textarea"
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { ScrollArea } from "@/components/ui/scroll-area"
import { Badge } from "@/components/ui/badge"
import { Send, Plus, X, FileText, Eye, Clock, Square } from "lucide-react"
import { GalaxyDatasetBrowser } from "./galaxy-dataset-browser"

interface AttachedFile {
  id: string
  name: string
  size: number
  file: File
}

interface ChatInputProps {
  onSend: (message: string, files?: File[]) => void
  disabled?: boolean
  /** Number of messages queued behind the current AI response */
  pendingCount?: number
  placeholder?: string
  onFilesSelected?: (files: File[]) => void
  isStreaming?: boolean
  onStop?: () => void
  /** Register a setter function that can externally pre-fill the draft */
  onRegisterSetDraft?: (setter: (draft: string) => void) => void
  /**
   * Count of dataset references already attached to THIS chat session
   * (everything in chat_sessions.datasets, accumulated across all turns).
   * Surfaces the X / MAX_DATASET_REFS indicator next to the attach button
   * so users see when they're approaching the server-side cap (32; see
   * frontend/server/dataset-cap.ts).
   */
  sessionDatasetCount?: number
}

/** Mirrors MAX_DATASET_REFS in frontend/server/dataset-cap.ts. */
const MAX_DATASET_REFS = 32

export function ChatInput({
  onSend,
  disabled = false,
  pendingCount = 0,
  placeholder = "Ask BioMate anything — upload a paper, run a workflow, search literature, or analyze your data...",
  onFilesSelected,
  isStreaming = false,
  onStop,
  onRegisterSetDraft,
  sessionDatasetCount = 0,
}: ChatInputProps) {
  const [message, setMessage] = useState("")
  const [attachedFiles, setAttachedFiles] = useState<AttachedFile[]>([])
  const [showDatasetBrowser, setShowDatasetBrowser] = useState(false)
  const textareaRef = useRef<HTMLTextAreaElement>(null)

  // Register an external draft setter so parent can pre-fill the textarea
  useEffect(() => {
    if (onRegisterSetDraft) {
      onRegisterSetDraft((draft: string) => {
        setMessage(draft)
        // Focus the textarea so the user can see the pre-fill
        setTimeout(() => textareaRef.current?.focus(), 0)
      })
    }
  }, [onRegisterSetDraft])

  const handleSend = () => {
    if (message.trim() || attachedFiles.length > 0) {
      const files = attachedFiles.map(f => f.file)
      onSend(message.trim(), files.length > 0 ? files : undefined)
      setMessage("")
      setAttachedFiles([])
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

  return (
    <div className="border-t bg-background p-4">
      {/* Attached files chips */}
      {attachedFiles.length > 0 && (
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
                  <p className="text-sm font-medium">Binary / large file — metadata only</p>
                  <p className="text-xs text-muted-foreground">Name: {previewFile.name}</p>
                  <p className="text-xs text-muted-foreground">Size: {formatFileSize(previewFile.size)}</p>
                  <p className="text-xs text-muted-foreground">Type: {previewFile.file.type || 'application/octet-stream'}</p>
                  <p className="text-xs text-muted-foreground mt-3">
                    This file will be uploaded to Galaxy when you send your message. Preview is not available for binary formats.
                  </p>
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

      {/* Reference design: pill input with attachment + textarea + send */}
      <div className="chat-input" style={{
        border: '1px solid var(--bm-border, hsl(var(--border)))',
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
          {/* Attachment button */}
          <button
            disabled={disabled}
            title="Add data"
            onClick={() => setShowDatasetBrowser(true)}
            style={{
              width: 28, height: 28, borderRadius: 'var(--bm-r-sm, 6px)',
              border: 'none', background: 'transparent',
              color: 'var(--bm-text-dim, oklch(0.62 0.010 260))',
              cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center',
              flexShrink: 0,
            }}
          >
            <Plus className="w-4 h-4" />
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
              ? `At the ${MAX_DATASET_REFS}-attachment cap — older entries will drop when you attach another. For bulk experiments, use a Galaxy collection (1 reference for N files).`
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
              disabled={!message.trim() && attachedFiles.length === 0}
              style={{
                width: 28, height: 28, borderRadius: 'var(--bm-r-sm, 6px)',
                background: (!message.trim() && attachedFiles.length === 0)
                  ? 'var(--bm-surface-3, oklch(0.945 0.005 240))'
                  : 'var(--bm-text, oklch(0.22 0.01 260))',
                color: (!message.trim() && attachedFiles.length === 0)
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

      {/* Galaxy dataset browser dialog */}
      <GalaxyDatasetBrowser
        open={showDatasetBrowser}
        onClose={() => setShowDatasetBrowser(false)}
        onSelect={(datasetId, datasetName) => {
          // Append dataset reference to the message so the AI and workflow executor know about it
          setMessage(prev => {
            const ref = `[Galaxy dataset: ${datasetName} (id: ${datasetId})]`
            return prev ? `${prev}\n${ref}` : ref
          })
          setTimeout(() => textareaRef.current?.focus(), 0)
        }}
      />
    </div>
  )
}
