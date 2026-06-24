import { useState, useRef, useCallback } from "react"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Progress } from "@/components/ui/progress"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { RadioGroup, RadioGroupItem } from "@/components/ui/radio-group"
import { Upload, File, X, Check, AlertCircle, Loader2, Link2, Server, Info, HardDrive, Clock, Zap, FolderArchive, Lightbulb } from "lucide-react"
import { analytics } from "@/lib/analytics"

// Maximum file size: 5GB for local uploads
// AWS workflows require file upload first, so we constrain to reduce latency
const MAX_LOCAL_FILE_SIZE_GB = 5
const MAX_LOCAL_FILE_SIZE_BYTES = MAX_LOCAL_FILE_SIZE_GB * 1024 * 1024 * 1024

interface UploadedFile {
  id: string
  name: string
  size: number
  type: string
  status: 'uploading' | 'completed' | 'error' | 'queued'
  progress: number
  datasetId?: string
  error?: string
  description?: string
  source?: 'local' | 'url' | 'ftp' // Track upload source
}

interface FileUploadProps {
  accept?: string
  multiple?: boolean
  maxSize?: number // in MB (for backward compatibility, capped at 5GB)
  onUploadComplete?: (files: UploadedFile[]) => void
  // Resource constraint info
  availableStorageGB?: number
  totalUploadedGB?: number
}

export function FileUpload({
  accept = ".fastq,.fastq.gz,.bam,.sam,.mzML,.mzXML,.csv,.tsv,.txt",
  multiple = true,
  maxSize = 5000, // 5GB default (capped by MAX_LOCAL_FILE_SIZE_GB)
  onUploadComplete,
  availableStorageGB = 50, // Default available storage
  totalUploadedGB = 0
}: FileUploadProps) {
  // Ensure maxSize doesn't exceed 5GB limit
  const effectiveMaxSize = Math.min(maxSize, MAX_LOCAL_FILE_SIZE_GB * 1024)
  const [files, setFiles] = useState<UploadedFile[]>([])
  const [isDragging, setIsDragging] = useState(false)
  const [urlInput, setUrlInput] = useState('')
  const [isUrlLoading, setIsUrlLoading] = useState(false)
  const [uploadTab, setUploadTab] = useState<'local' | 'url'>('local')
  const [urlImportMode, setUrlImportMode] = useState<'immediate' | 'deferred'>('deferred')
  const fileInputRef = useRef<HTMLInputElement>(null)

  const formatFileSize = (bytes: number): string => {
    if (bytes === 0) return '0 Bytes'
    const k = 1024
    const sizes = ['Bytes', 'KB', 'MB', 'GB']
    const i = Math.floor(Math.log(bytes) / Math.log(k))
    return Math.round(bytes / Math.pow(k, i) * 100) / 100 + ' ' + sizes[i]
  }

  // Calculate total upload size
  const currentUploadSizeBytes = files.reduce((sum, f) => sum + f.size, 0)
  const currentUploadSizeGB = currentUploadSizeBytes / (1024 * 1024 * 1024)
  const remainingStorageGB = availableStorageGB - totalUploadedGB - currentUploadSizeGB

  const handleFileSelect = async (selectedFiles: FileList | null) => {
    if (!selectedFiles) return

    const newFiles: UploadedFile[] = Array.from(selectedFiles).map(file => ({
      id: `${Date.now()}-${file.name}`,
      name: file.name,
      size: file.size,
      type: file.type || 'application/octet-stream',
      status: 'queued' as const,
      progress: 0,
      source: 'local' as const,
    }))

    // Check individual file sizes (5GB limit)
    const oversizedFiles = newFiles.filter(f => f.size > MAX_LOCAL_FILE_SIZE_BYTES)
    if (oversizedFiles.length > 0) {
      // Show helpful error instead of browser alert
      setFiles(prev => [...prev, ...oversizedFiles.map(f => ({
        ...f,
        status: 'error' as const,
        error: `File exceeds ${MAX_LOCAL_FILE_SIZE_GB}GB limit. Use URL import for large files, or compress/split the file.`
      }))])

      // Filter out oversized files and continue with valid ones
      const validFiles = newFiles.filter(f => f.size <= MAX_LOCAL_FILE_SIZE_BYTES)
      if (validFiles.length === 0) return
    }

    // Check total storage constraint
    const validFiles = newFiles.filter(f => f.size <= MAX_LOCAL_FILE_SIZE_BYTES)
    const totalNewSize = validFiles.reduce((sum, f) => sum + f.size, 0) / (1024 * 1024 * 1024)
    if (totalNewSize > remainingStorageGB) {
      setFiles(prev => [...prev, ...validFiles.map(f => ({
        ...f,
        status: 'error' as const,
        error: `Insufficient storage. Available: ${remainingStorageGB.toFixed(2)}GB, Required: ${totalNewSize.toFixed(2)}GB`
      }))])
      return
    }

    setFiles(prev => [...prev, ...validFiles])

    // PARALLEL UPLOADS - Upload all files concurrently (with limit of 3)
    const filesToUpload = Array.from(selectedFiles).filter(
      (_, i) => validFiles.some(vf => vf.id === newFiles[i].id)
    )

    // Parallel upload with concurrency limit
    const CONCURRENT_UPLOADS = 3
    const uploadQueue = filesToUpload.map((file, i) => ({
      file,
      uploadedFile: validFiles.find(vf => vf.name === file.name)!
    }))

    // Process in batches
    for (let i = 0; i < uploadQueue.length; i += CONCURRENT_UPLOADS) {
      const batch = uploadQueue.slice(i, i + CONCURRENT_UPLOADS)
      await Promise.all(batch.map(({ file, uploadedFile }) => uploadFile(file, uploadedFile)))
    }

    // Notify parent component with ALL completed files
    if (onUploadComplete) {
      // Use setTimeout to ensure state is updated
      setTimeout(() => {
        setFiles(currentFiles => {
          const completedFiles = currentFiles.filter(f => f.status === 'completed')
          if (completedFiles.length > 0) {
            try { analytics.track('dataset_uploaded', { total_samples: completedFiles.length }); } catch {}
          }
          onUploadComplete(completedFiles)
          return currentFiles
        })
      }, 100)
    }
  }

  // URL Import - reference remote files without uploading (Galaxy will fetch)
  // Supports two modes:
  // - immediate: Galaxy fetches the file now
  // - deferred: Galaxy creates a reference, fetches when workflow needs it
  const handleUrlImport = async () => {
    if (!urlInput.trim()) return

    const url = urlInput.trim()
    // Validate URL format
    try {
      const parsedUrl = new URL(url)
      if (!['http:', 'https:', 'ftp:', 's3:'].includes(parsedUrl.protocol)) {
        throw new Error('Unsupported protocol')
      }
    } catch {
      setFiles(prev => [...prev, {
        id: `url-${Date.now()}`,
        name: url,
        size: 0,
        type: 'url',
        status: 'error',
        progress: 0,
        source: 'url',
        error: 'Invalid URL format. Supported: HTTP, HTTPS, FTP, S3 URLs.'
      }])
      return
    }

    setIsUrlLoading(true)
    const fileName = url.split('/').pop() || 'remote-file'

    const urlFile: UploadedFile = {
      id: `url-${Date.now()}`,
      name: fileName,
      size: 0, // Unknown for URL imports
      type: 'url',
      status: 'uploading',
      progress: 0,
      source: 'url',
      description: urlImportMode === 'deferred' ? 'Deferred - will fetch when workflow runs' : undefined,
    }

    setFiles(prev => [...prev, urlFile])

    try {
      // Choose endpoint based on import mode
      const endpoint = urlImportMode === 'deferred'
        ? '/api/datasets/deferred'
        : '/api/datasets/import-url'

      const response = await fetch(endpoint, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ url, filename: fileName, name: fileName }),
      })

      if (!response.ok) {
        const errorData = await response.json().catch(() => ({}))
        throw new Error(errorData.message || errorData.error || 'URL import failed')
      }

      const result = await response.json()

      setFiles(prev => prev.map(f =>
        f.id === urlFile.id
          ? {
              ...f,
              status: 'completed',
              progress: 100,
              datasetId: result.dataset_id || result.id,
              size: result.size || 0,
              description: urlImportMode === 'deferred'
                ? 'Deferred - data will be fetched when workflow executes'
                : undefined
            }
          : f
      ))

      setUrlInput('')
    } catch (error: any) {
      setFiles(prev => prev.map(f =>
        f.id === urlFile.id
          ? { ...f, status: 'error', error: error.message }
          : f
      ))
    } finally {
      setIsUrlLoading(false)
    }
  }

  const uploadFile = async (file: File, uploadedFile: UploadedFile) => {
    try {
      const formData = new FormData()
      formData.append('file', file)
      formData.append('file_type', file.type || 'auto')

      // Add description if available
      if (uploadedFile.description) {
        formData.append('description', uploadedFile.description)
      }

      // Simulate progress updates
      const progressInterval = setInterval(() => {
        setFiles(prev => prev.map(f =>
          f.id === uploadedFile.id && f.progress < 90
            ? { ...f, progress: f.progress + 10 }
            : f
        ))
      }, 200)

      const response = await fetch('/api/datasets/upload', {
        method: 'POST',
        body: formData,
      })

      clearInterval(progressInterval)

      if (!response.ok) {
        const error = await response.text()
        throw new Error(error || 'Upload failed')
      }

      const result = await response.json()

      setFiles(prev => prev.map(f =>
        f.id === uploadedFile.id
          ? { ...f, status: 'completed', progress: 100, datasetId: result.dataset_id }
          : f
      ))

      console.log(`[FileUpload] File uploaded successfully: ${file.name} -> ${result.dataset_id}`)
    } catch (error: any) {
      console.error(`[FileUpload] Failed to upload ${file.name}:`, error)
      setFiles(prev => prev.map(f =>
        f.id === uploadedFile.id
          ? { ...f, status: 'error', progress: 0, error: error.message }
          : f
      ))
    }
  }

  const updateFileDescription = (fileId: string, description: string) => {
    setFiles(prev => prev.map(f =>
      f.id === fileId ? { ...f, description } : f
    ))
  }

  const removeFile = (fileId: string) => {
    setFiles(prev => prev.filter(f => f.id !== fileId))
  }

  const handleDragOver = (e: React.DragEvent) => {
    e.preventDefault()
    setIsDragging(true)
  }

  const handleDragLeave = (e: React.DragEvent) => {
    e.preventDefault()
    setIsDragging(false)
  }

  const handleDrop = (e: React.DragEvent) => {
    e.preventDefault()
    setIsDragging(false)
    handleFileSelect(e.dataTransfer.files)
  }

  const handleClick = () => {
    fileInputRef.current?.click()
  }

  const completedCount = files.filter(f => f.status === 'completed').length
  const uploadingCount = files.filter(f => f.status === 'uploading').length
  const errorCount = files.filter(f => f.status === 'error').length

  return (
    <Card>
      <CardHeader>
        <div className="flex items-center justify-between">
          <div>
            <CardTitle>Upload Files</CardTitle>
            <CardDescription>
              Upload your data files for workflow execution
            </CardDescription>
          </div>
          <div className="flex items-center gap-2">
            {/* Storage indicator */}
            <Badge variant="outline" className="text-xs">
              <HardDrive className="w-3 h-3 mr-1" />
              {remainingStorageGB.toFixed(1)}GB available
            </Badge>
            {files.length > 0 && (
              <>
                {completedCount > 0 && (
                  <Badge variant="outline" className="bg-green-50 text-green-700 border-green-200">
                    <Check className="w-3 h-3 mr-1" />
                    {completedCount} completed
                  </Badge>
                )}
                {uploadingCount > 0 && (
                  <Badge variant="outline" className="bg-blue-50 text-blue-700 border-blue-200">
                    <Loader2 className="w-3 h-3 mr-1 animate-spin" />
                    {uploadingCount} uploading
                  </Badge>
                )}
                {errorCount > 0 && (
                  <Badge variant="outline" className="bg-red-50 text-red-700 border-red-200">
                    <AlertCircle className="w-3 h-3 mr-1" />
                    {errorCount} failed
                  </Badge>
                )}
              </>
            )}
          </div>
        </div>
      </CardHeader>
      <CardContent className="space-y-4">
        {/* Tips panel */}
        <div className="rounded-lg border border-muted bg-muted/30 divide-y divide-muted text-xs">
          {/* Size limits */}
          <div className="flex gap-2 px-3 py-2.5">
            <Info className="h-3.5 w-3.5 text-blue-500 mt-0.5 shrink-0" />
            <div className="space-y-0.5 text-muted-foreground">
              <span className="font-medium text-foreground">Size limits: </span>
              Local upload <strong>{MAX_LOCAL_FILE_SIZE_GB} GB</strong> per file · URL/S3 import <strong>no limit</strong> (Galaxy downloads server-side)
            </div>
          </div>

          {/* Accepted formats */}
          <div className="flex gap-2 px-3 py-2.5">
            <File className="h-3.5 w-3.5 text-violet-500 mt-0.5 shrink-0" />
            <div className="space-y-0.5 text-muted-foreground">
              <span className="font-medium text-foreground">Accepted formats: </span>
              FASTQ, BAM, SAM, CRAM, FASTA, VCF, BED, GFF, GTF, CSV, TSV, H5AD, LOOM, MRC, TIFF, mzML, mzXML, IPYNB, RDS, ZIP, TAR.GZ,&nbsp;
              <span className="text-muted-foreground/70">and 30+ more</span>
            </div>
          </div>

          {/* Folder tip */}
          <div className="flex gap-2 px-3 py-2.5">
            <FolderArchive className="h-3.5 w-3.5 text-amber-500 mt-0.5 shrink-0" />
            <div className="space-y-0.5 text-muted-foreground">
              <span className="font-medium text-foreground">Folders: </span>
              No folder picker — zip your folder first (<code className="font-mono bg-background/60 px-1 rounded">zip -r data.zip folder/</code>), then upload the <code className="font-mono bg-background/60 px-1 rounded">.zip</code>.
              For S3 folders, use URL Import with your bucket prefix instead.
            </div>
          </div>

          {/* Many files tip */}
          <div className="flex gap-2 px-3 py-2.5">
            <Lightbulb className="h-3.5 w-3.5 text-green-500 mt-0.5 shrink-0" />
            <div className="space-y-0.5 text-muted-foreground">
              <span className="font-medium text-foreground">Many files: </span>
              Up to <strong>32</strong> individual file references are kept per conversation (oldest drop on overflow).
              For 100+ samples, zip them into one archive or use an S3 prefix URL.
            </div>
          </div>
        </div>

        {/* Upload method tabs */}
        <Tabs value={uploadTab} onValueChange={(v) => setUploadTab(v as 'local' | 'url')}>
          <TabsList className="grid w-full grid-cols-2">
            <TabsTrigger value="local" className="text-xs">
              <Upload className="w-3 h-3 mr-1" />
              Local Upload
            </TabsTrigger>
            <TabsTrigger value="url" className="text-xs">
              <Link2 className="w-3 h-3 mr-1" />
              URL Import
            </TabsTrigger>
          </TabsList>

          {/* Local file upload */}
          <TabsContent value="local" className="mt-4">
            <div
              className={`border-2 border-dashed rounded-lg p-6 text-center transition-colors cursor-pointer ${
                isDragging
                  ? 'border-primary bg-primary/5'
                  : 'border-muted-foreground/25 hover:border-primary/50 hover:bg-muted/50'
              }`}
              onDragOver={handleDragOver}
              onDragLeave={handleDragLeave}
              onDrop={handleDrop}
              onClick={handleClick}
              data-testid="file-upload-drop-zone"
            >
              <Upload className="w-10 h-10 mx-auto mb-3 text-muted-foreground" />
              <p className="text-sm font-medium mb-1">
                {isDragging ? 'Drop files here' : 'Click to upload or drag and drop'}
              </p>
              <p className="text-xs text-muted-foreground mb-2">
                FASTQ · BAM · VCF · FASTA · CSV · H5AD · MRC · ZIP · and 40+ more
              </p>
              <p className="text-xs text-muted-foreground">
                Max {MAX_LOCAL_FILE_SIZE_GB} GB per file{multiple && ' · multiple files upload in parallel'}
              </p>
              <p className="text-xs text-muted-foreground/60 mt-1">
                Folders: zip first · Files &gt;5 GB: use URL Import tab
              </p>
              <input
                ref={fileInputRef}
                type="file"
                accept={accept}
                multiple={multiple}
                onChange={(e) => handleFileSelect(e.target.files)}
                className="hidden"
                data-testid="file-upload-input"
              />
            </div>
          </TabsContent>

          {/* URL Import */}
          <TabsContent value="url" className="mt-4 space-y-4">
            <div className="space-y-2">
              <Label htmlFor="url-input" className="text-xs font-medium">
                Enter file URL (HTTP, HTTPS, FTP, or S3)
              </Label>
              <div className="flex gap-2">
                <Input
                  id="url-input"
                  placeholder="https://example.com/data.fastq.gz or ftp://..."
                  value={urlInput}
                  onChange={(e) => setUrlInput(e.target.value)}
                  onKeyDown={(e) => e.key === 'Enter' && handleUrlImport()}
                  className="text-sm"
                />
                <Button
                  onClick={handleUrlImport}
                  disabled={!urlInput.trim() || isUrlLoading}
                  size="sm"
                >
                  {isUrlLoading ? (
                    <Loader2 className="w-4 h-4 animate-spin" />
                  ) : (
                    <>
                      <Link2 className="w-4 h-4 mr-1" />
                      Import
                    </>
                  )}
                </Button>
              </div>
            </div>

            {/* Import Mode Selection */}
            <div className="space-y-3">
              <Label className="text-xs font-medium">Import Mode</Label>
              <RadioGroup
                value={urlImportMode}
                onValueChange={(v) => setUrlImportMode(v as 'immediate' | 'deferred')}
                className="space-y-2"
              >
                <div
                  className={`flex items-start space-x-3 p-3 rounded-lg border cursor-pointer transition-colors ${
                    urlImportMode === 'deferred' ? 'border-primary bg-primary/5' : 'hover:bg-muted/50'
                  }`}
                  onClick={() => setUrlImportMode('deferred')}
                >
                  <RadioGroupItem value="deferred" id="deferred" className="mt-0.5" />
                  <div className="flex-1">
                    <Label htmlFor="deferred" className="text-sm font-medium cursor-pointer flex items-center gap-2">
                      <Clock className="h-4 w-4 text-blue-500" />
                      Deferred (Recommended for large files)
                    </Label>
                    <p className="text-xs text-muted-foreground mt-1">
                      Galaxy downloads only when workflow needs the data. Start designing immediately, no waiting.
                    </p>
                    <div className="flex flex-wrap gap-1 mt-2">
                      <Badge variant="secondary" className="text-xs">No upfront wait</Badge>
                      <Badge variant="secondary" className="text-xs">No storage until needed</Badge>
                      <Badge variant="secondary" className="text-xs">Best for large files</Badge>
                    </div>
                  </div>
                </div>

                <div
                  className={`flex items-start space-x-3 p-3 rounded-lg border cursor-pointer transition-colors ${
                    urlImportMode === 'immediate' ? 'border-primary bg-primary/5' : 'hover:bg-muted/50'
                  }`}
                  onClick={() => setUrlImportMode('immediate')}
                >
                  <RadioGroupItem value="immediate" id="immediate" className="mt-0.5" />
                  <div className="flex-1">
                    <Label htmlFor="immediate" className="text-sm font-medium cursor-pointer flex items-center gap-2">
                      <Zap className="h-4 w-4 text-amber-500" />
                      Immediate Download
                    </Label>
                    <p className="text-xs text-muted-foreground mt-1">
                      Galaxy fetches the file now. Data available for preview before workflow runs.
                    </p>
                    <div className="flex flex-wrap gap-1 mt-2">
                      <Badge variant="outline" className="text-xs">Preview before run</Badge>
                      <Badge variant="outline" className="text-xs">Better for small files</Badge>
                    </div>
                  </div>
                </div>
              </RadioGroup>
            </div>

            <div className="rounded-md border border-muted bg-muted/30 text-xs text-muted-foreground px-3 py-2.5 space-y-1">
              <div className="flex gap-1.5 items-start">
                <Lightbulb className="h-3.5 w-3.5 text-green-500 mt-0.5 shrink-0" />
                <div>
                  <span className="font-medium text-foreground">No size limit</span> — Galaxy fetches the file server-side; the 5 GB cap does not apply.
                </div>
              </div>
              <div className="flex gap-1.5 items-start">
                <FolderArchive className="h-3.5 w-3.5 text-amber-500 mt-0.5 shrink-0" />
                <div>
                  <span className="font-medium text-foreground">S3 folder:</span> paste a bucket prefix (<code className="font-mono bg-background/60 px-1 rounded">s3://bucket/samples/</code>) to reference all files under it at once.
                </div>
              </div>
              <div className="flex gap-1.5 items-start">
                <Info className="h-3.5 w-3.5 text-blue-500 mt-0.5 shrink-0" />
                <div>
                  <span className="font-medium text-foreground">Public datasets:</span> NCBI SRA, EBI ENA, EMPIAR, and any public HTTPS/FTP URL work without credentials.
                </div>
              </div>
            </div>
          </TabsContent>
        </Tabs>

        {/* File list */}
        {files.length > 0 && (
          <div className="space-y-3">
            <h4 className="text-sm font-semibold">Uploaded Files</h4>
            {files.map((file) => (
              <div
                key={file.id}
                className="flex items-center gap-3 p-3 border rounded-lg hover:bg-muted/50 transition-colors"
              >
                <div className="flex-shrink-0">
                  {file.status === 'uploading' && (
                    <Loader2 className="w-5 h-5 animate-spin text-blue-500" />
                  )}
                  {file.status === 'completed' && (
                    <div className="w-5 h-5 rounded-full bg-green-500 flex items-center justify-center">
                      <Check className="w-3 h-3 text-white" />
                    </div>
                  )}
                  {file.status === 'error' && (
                    <div className="w-5 h-5 rounded-full bg-red-500 flex items-center justify-center">
                      <AlertCircle className="w-3 h-3 text-white" />
                    </div>
                  )}
                </div>

                <div className="flex-1 min-w-0">
                  <div className="flex items-center justify-between mb-1">
                    <p className="text-sm font-medium truncate">{file.name}</p>
                    <span className="text-xs text-muted-foreground ml-2 flex-shrink-0">
                      {formatFileSize(file.size)}
                    </span>
                  </div>

                  {file.status === 'uploading' && (
                    <Progress value={file.progress} className="h-1.5" />
                  )}

                  {file.status === 'completed' && file.datasetId && (
                    <p className="text-xs text-muted-foreground">
                      Dataset ID: {file.datasetId}
                    </p>
                  )}

                  {file.status === 'error' && (
                    <p className="text-xs text-red-600">{file.error || 'Upload failed'}</p>
                  )}

                  {file.status === 'completed' && (
                    <input
                      type="text"
                      placeholder="Optional: Describe this dataset (e.g., 'RNA-seq from liver tissue')"
                      value={file.description || ''}
                      onChange={(e) => updateFileDescription(file.id, e.target.value)}
                      className="mt-2 text-xs border rounded px-2 py-1 w-full"
                      onClick={(e) => e.stopPropagation()}
                    />
                  )}
                </div>

                <Button
                  variant="ghost"
                  size="sm"
                  onClick={(e) => {
                    e.stopPropagation()
                    removeFile(file.id)
                  }}
                  className="flex-shrink-0"
                >
                  <X className="w-4 h-4" />
                </Button>
              </div>
            ))}
          </div>
        )}
      </CardContent>
    </Card>
  )
}
