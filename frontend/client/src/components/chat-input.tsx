import { useState, useRef, useEffect, KeyboardEvent } from "react"
import { Button } from "@/components/ui/button"
import { Textarea } from "@/components/ui/textarea"
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover"
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { ScrollArea } from "@/components/ui/scroll-area"
import { Badge } from "@/components/ui/badge"
import { Send, Plus, X, FileText, Upload, Eye, Clock, Square, Database, Loader2, HelpCircle } from "lucide-react"
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from "@/components/ui/tooltip"

// Accession ID patterns — conservative to avoid false positives
const ACCESSION_RE = /\b((?:SRR|ERR|DRR|SRP|ERP|DRP)\d{6,9}|EMDB-?\d+|EMD-\d+|GSE?\d+)\b|\bPDB[:\s]([A-Z0-9]{4})\b/gi

interface AccessionHint {
  raw: string        // matched text
  resolved?: any     // API result
  loading: boolean
  error?: boolean
}

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
  /** Pre-fill the input with this text (e.g. from "Adjust via chat" buttons) */
  externalDraft?: string
}

export function ChatInput({
  onSend,
  disabled = false,
  pendingCount = 0,
  placeholder = "Type your message here...",
  onFilesSelected,
  isStreaming = false,
  onStop,
  externalDraft,
}: ChatInputProps) {
  const [message, setMessage] = useState("")
  const [attachedFiles, setAttachedFiles] = useState<AttachedFile[]>([])
  const [isPopoverOpen, setIsPopoverOpen] = useState(false)
  const [accessionHints, setAccessionHints] = useState<AccessionHint[]>([])
  const textareaRef = useRef<HTMLTextAreaElement>(null)
  const fileInputRef = useRef<HTMLInputElement>(null)
  const accessionTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null)

  // Pre-fill from external source (e.g. "Adjust via chat" button in workflow viewer)
  useEffect(() => {
    if (externalDraft) {
      setMessage(externalDraft)
      textareaRef.current?.focus()
    }
  }, [externalDraft])

  // Accession ID detection — debounced, resolves SRR/PDB/EMDB/GEO IDs
  useEffect(() => {
    if (accessionTimerRef.current) clearTimeout(accessionTimerRef.current)
    accessionTimerRef.current = setTimeout(() => {
      ACCESSION_RE.lastIndex = 0
      const matches: string[] = []
      let m: RegExpExecArray | null
      while ((m = ACCESSION_RE.exec(message)) !== null) {
        const id = (m[1] || m[2]).trim()
        if (!matches.includes(id)) matches.push(id)
      }
      if (matches.length === 0) { setAccessionHints([]); return }

      // Keep existing resolved data, mark new ones as loading
      setAccessionHints(prev => {
        const existing = new Map(prev.map(h => [h.raw, h]))
        return matches.map(id => existing.get(id) ?? { raw: id, loading: true })
      })

      // Resolve ones that aren't already resolved
      matches.forEach(id => {
        setAccessionHints(prev => {
          const existing = prev.find(h => h.raw === id)
          if (existing?.resolved || (existing && !existing.loading)) return prev
          return prev
        })
        fetch('/api/accession/resolve', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ accession: id }),
          credentials: 'include',
        })
          .then(r => r.ok ? r.json() : Promise.reject())
          .then(data => setAccessionHints(prev => prev.map(h => h.raw === id ? { ...h, resolved: data, loading: false } : h)))
          .catch(() => setAccessionHints(prev => prev.map(h => h.raw === id ? { ...h, loading: false, error: true } : h)))
      })
    }, 600)
  }, [message])

  const handleSend = () => {
    if (message.trim() || attachedFiles.length > 0) {
      const files = attachedFiles.map(f => f.file)
      // Append resolved accession context so the AI gets the actual URLs
      let finalMessage = message.trim()
      const resolved = accessionHints.filter(h => h.resolved)
      if (resolved.length > 0) {
        const accCtx = resolved.map(h =>
          `${h.raw}: ${h.resolved.description} — ${h.resolved.download_url || h.resolved.ftp_url || h.resolved.url}`
        ).join('; ')
        finalMessage += `\n\n[Resolved accessions: ${accCtx}]`
      }
      onSend(finalMessage, files.length > 0 ? files : undefined)
      setMessage("")
      setAttachedFiles([])
      setAccessionHints([])
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

  const handleFileSelect = (e: React.ChangeEvent<HTMLInputElement>) => {
    const files = e.target.files
    if (files && files.length > 0) {
      const newFiles: AttachedFile[] = Array.from(files).map(file => ({
        id: `${file.name}-${Date.now()}-${Math.random()}`,
        name: file.name,
        size: file.size,
        file
      }))
      setAttachedFiles(prev => [...prev, ...newFiles])

      // Notify parent if callback provided
      if (onFilesSelected) {
        onFilesSelected(Array.from(files))
      }

      setIsPopoverOpen(false)
    }
    // Reset input so same file can be selected again
    if (fileInputRef.current) {
      fileInputRef.current.value = ""
    }
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

  const acceptedTypes = ".fastq,.fastq.gz,.fq,.fq.gz,.bam,.sam,.mzML,.mzXML,.csv,.tsv,.txt,.fasta,.fa,.vcf,.bed,.gff,.gtf,.h5ad"

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

      {/* Accession ID chips */}
      {accessionHints.length > 0 && (
        <div className="flex flex-wrap gap-2 mb-3">
          {accessionHints.map(hint => (
            <div
              key={hint.raw}
              className={`flex items-center gap-1.5 px-2 py-1 rounded-md text-xs border ${
                hint.error ? 'bg-amber-50 border-amber-200 text-amber-800 dark:bg-amber-900/20 dark:text-amber-300' :
                hint.resolved ? 'bg-blue-50 border-blue-200 text-blue-800 dark:bg-blue-900/20 dark:text-blue-300' :
                'bg-muted border-muted-foreground/20 text-muted-foreground'
              }`}
              title={hint.resolved
                ? `${hint.resolved.description} — ${hint.resolved.download_url || hint.resolved.ftp_url || hint.resolved.url}`
                : hint.error
                ? 'Not recognised. Supported: SRR/ERR/DRR, GSE/GSM, PDB:XXXX, EMD-XXXX'
                : 'Resolving…'}
            >
              {hint.loading ? <Loader2 className="w-3 h-3 animate-spin" /> : <Database className="w-3 h-3" />}
              <span className="font-mono">{hint.raw}</span>
              {hint.resolved && <span className="text-[10px] opacity-70">{hint.resolved.type}</span>}
              {hint.error && (
                <TooltipProvider>
                  <Tooltip>
                    <TooltipTrigger asChild>
                      <span className="text-[10px] underline decoration-dotted cursor-help">not recognised</span>
                    </TooltipTrigger>
                    <TooltipContent className="max-w-[220px] text-xs">
                      Supported databases: SRA (SRR/ERR/DRR), GEO (GSE/GSM), Protein Data Bank (PDB:XXXX), EMDB (EMD-XXXX). Check the accession format or paste the direct download URL instead.
                    </TooltipContent>
                  </Tooltip>
                </TooltipProvider>
              )}
              <button onClick={() => setAccessionHints(prev => prev.filter(h => h.raw !== hint.raw))}>
                <X className="w-3 h-3 opacity-50 hover:opacity-100" />
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

      <div className="flex gap-2 items-end">
        {/* Attachment button with popover */}
        <Popover open={isPopoverOpen} onOpenChange={setIsPopoverOpen}>
          <PopoverTrigger asChild>
            <Button
              variant="outline"
              size="icon"
              className="h-[44px] w-[44px] flex-shrink-0"
              disabled={disabled}
            >
              <Plus className="w-5 h-5" />
            </Button>
          </PopoverTrigger>
          <PopoverContent
            className="w-64 p-3"
            side="top"
            align="start"
            sideOffset={8}
          >
            <div className="space-y-3">
              <p className="text-sm font-medium">Attach files</p>
              <p className="text-xs text-muted-foreground">
                Supported: FASTQ, BAM, SAM, mzML, CSV, TSV, FASTA, VCF, BED, h5ad
              </p>

              <input
                ref={fileInputRef}
                type="file"
                accept={acceptedTypes}
                multiple
                onChange={handleFileSelect}
                className="hidden"
                id="chat-file-input"
              />

              <Button
                variant="outline"
                className="w-full justify-start gap-2"
                onClick={() => fileInputRef.current?.click()}
              >
                <Upload className="w-4 h-4" />
                Choose files
              </Button>

              <p className="text-xs text-muted-foreground">
                Max 500MB per file. Files are uploaded to Galaxy for analysis.
              </p>
              <p className="text-xs text-muted-foreground mt-2 border-t pt-2">
                <strong>No file to upload?</strong> Type a public accession ID directly in the message instead. BioMate will look up the download URL automatically. Supported: <span className="font-mono">SRR/ERR/DRR</span> (SRA runs), <span className="font-mono">GSE/GSM</span> (GEO), <span className="font-mono">PDB:XXXX</span> (protein structures), <span className="font-mono">EMD-XXXX</span> (cryo-EM maps). For other databases, paste the direct download URL.
              </p>
            </div>
          </PopoverContent>
        </Popover>

        <Textarea
          ref={textareaRef}
          data-testid="chat-input"
          value={message}
          onInput={handleInput}
          onKeyDown={handleKeyDown}
          placeholder={placeholder}
          className="min-h-[44px] max-h-[200px] resize-none py-3"
          rows={1}
        />

        {isStreaming ? (
          <Button
            data-testid="chat-stop-button"
            onClick={onStop}
            size="icon"
            variant="destructive"
            className="h-[44px] w-[44px] flex-shrink-0 relative"
            title="Stop reply"
          >
            {pendingCount > 0 && (
              <span className="absolute -top-1.5 -right-1.5 flex h-4 w-4 items-center justify-center rounded-full bg-amber-500 text-[10px] font-bold text-white">
                {pendingCount}
              </span>
            )}
            <Square className="w-4 h-4 fill-current" />
          </Button>
        ) : (
          <Button
            data-testid="chat-send-button"
            onClick={handleSend}
            disabled={!message.trim() && attachedFiles.length === 0}
            size="icon"
            className="h-[44px] w-[44px] flex-shrink-0 relative"
            title={pendingCount > 0 ? `${pendingCount} message${pendingCount > 1 ? 's' : ''} queued` : undefined}
          >
            {pendingCount > 0 ? (
              <>
                <Clock className="w-4 h-4" />
                <span className="absolute -top-1.5 -right-1.5 flex h-4 w-4 items-center justify-center rounded-full bg-amber-500 text-[10px] font-bold text-white">
                  {pendingCount}
                </span>
              </>
            ) : (
              <Send className="w-4 h-4" />
            )}
          </Button>
        )}
      </div>
      {/* Persistent discovery hint */}
      <TooltipProvider>
        <Tooltip>
          <TooltipTrigger asChild>
            <p className="mt-1.5 text-[11px] text-muted-foreground/60 flex items-center gap-1 cursor-default w-fit">
              <HelpCircle className="w-3 h-3 flex-shrink-0" />
              Include a public database ID and BioMate will look up its download URL for you:&nbsp;
              <span className="font-mono">SRR123456</span>&nbsp;·&nbsp;
              <span className="font-mono">PDB:1ABC</span>&nbsp;·&nbsp;
              <span className="font-mono">EMD-1234</span>&nbsp;·&nbsp;
              <span className="font-mono">GSE12345</span>
            </p>
          </TooltipTrigger>
          <TooltipContent className="max-w-[300px] text-xs space-y-1">
            <p className="font-medium">Supported public databases</p>
            <p><span className="font-mono">SRR/ERR/DRR</span> — NCBI SRA sequencing runs</p>
            <p><span className="font-mono">SRP/ERP/DRP</span> — SRA studies</p>
            <p><span className="font-mono">GSE/GSM</span> — NCBI GEO expression datasets</p>
            <p><span className="font-mono">PDB:XXXX</span> — Protein Data Bank structures</p>
            <p><span className="font-mono">EMD-XXXX</span> — EMDB cryo-EM density maps</p>
            <p className="text-muted-foreground/80 pt-1 border-t">BioMate resolves the ID to a download URL and passes it to the AI. The workflow executor fetches the data at run time. For databases not listed here, paste the direct download URL in your message instead.</p>
          </TooltipContent>
        </Tooltip>
      </TooltipProvider>
    </div>
  )
}
