import { useState, useRef, KeyboardEvent } from "react"
import { Button } from "@/components/ui/button"
import { Textarea } from "@/components/ui/textarea"
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover"
import { Send, Plus, Paperclip, X, FileText, Upload } from "lucide-react"

interface AttachedFile {
  id: string
  name: string
  size: number
  file: File
}

interface ChatInputProps {
  onSend: (message: string, files?: File[]) => void
  disabled?: boolean
  placeholder?: string
  onFilesSelected?: (files: File[]) => void
}

export function ChatInput({
  onSend,
  disabled = false,
  placeholder = "Type your message here...",
  onFilesSelected
}: ChatInputProps) {
  const [message, setMessage] = useState("")
  const [attachedFiles, setAttachedFiles] = useState<AttachedFile[]>([])
  const [isPopoverOpen, setIsPopoverOpen] = useState(false)
  const textareaRef = useRef<HTMLTextAreaElement>(null)
  const fileInputRef = useRef<HTMLInputElement>(null)

  const handleSend = () => {
    if ((message.trim() || attachedFiles.length > 0) && !disabled) {
      const files = attachedFiles.map(f => f.file)
      onSend(message.trim(), files.length > 0 ? files : undefined)
      setMessage("")
      setAttachedFiles([])
      // Reset textarea height
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
                onClick={() => removeFile(file.id)}
                className="ml-1 p-0.5 rounded hover:bg-background transition-colors"
              >
                <X className="w-3 h-3 text-muted-foreground hover:text-foreground" />
              </button>
            </div>
          ))}
        </div>
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
          disabled={disabled}
          className="min-h-[44px] max-h-[200px] resize-none py-3"
          rows={1}
        />

        <Button
          data-testid="chat-send-button"
          onClick={handleSend}
          disabled={disabled || (!message.trim() && attachedFiles.length === 0)}
          size="icon"
          className="h-[44px] w-[44px] flex-shrink-0"
        >
          <Send className="w-4 h-4" />
        </Button>
      </div>
    </div>
  )
}
