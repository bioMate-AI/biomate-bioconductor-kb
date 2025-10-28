import { useState, useRef } from "react"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Progress } from "@/components/ui/progress"
import { Upload, File, X, Check, AlertCircle, Loader2 } from "lucide-react"

interface UploadedFile {
  id: string
  name: string
  size: number
  type: string
  status: 'uploading' | 'completed' | 'error'
  progress: number
  datasetId?: string
  error?: string
  description?: string
}

interface FileUploadProps {
  accept?: string
  multiple?: boolean
  maxSize?: number // in MB
  onUploadComplete?: (files: UploadedFile[]) => void
}

export function FileUpload({
  accept = ".fastq,.fastq.gz,.bam,.sam,.mzML,.mzXML,.csv,.tsv,.txt",
  multiple = true,
  maxSize = 500, // 500MB default
  onUploadComplete
}: FileUploadProps) {
  const [files, setFiles] = useState<UploadedFile[]>([])
  const [isDragging, setIsDragging] = useState(false)
  const fileInputRef = useRef<HTMLInputElement>(null)

  const formatFileSize = (bytes: number): string => {
    if (bytes === 0) return '0 Bytes'
    const k = 1024
    const sizes = ['Bytes', 'KB', 'MB', 'GB']
    const i = Math.floor(Math.log(bytes) / Math.log(k))
    return Math.round(bytes / Math.pow(k, i) * 100) / 100 + ' ' + sizes[i]
  }

  const handleFileSelect = async (selectedFiles: FileList | null) => {
    if (!selectedFiles) return

    const newFiles: UploadedFile[] = Array.from(selectedFiles).map(file => ({
      id: `${Date.now()}-${file.name}`,
      name: file.name,
      size: file.size,
      type: file.type || 'application/octet-stream',
      status: 'uploading' as const,
      progress: 0,
    }))

    // Check file sizes
    const oversizedFiles = newFiles.filter(f => f.size > maxSize * 1024 * 1024)
    if (oversizedFiles.length > 0) {
      alert(`The following files exceed the ${maxSize}MB limit:\n${oversizedFiles.map(f => f.name).join('\n')}`)
      return
    }

    setFiles(prev => [...prev, ...newFiles])

    // Upload each file
    for (let i = 0; i < selectedFiles.length; i++) {
      const file = selectedFiles[i]
      const uploadedFile = newFiles[i]
      await uploadFile(file, uploadedFile)
    }

    // Notify parent component
    if (onUploadComplete) {
      const completedFiles = files.filter(f => f.status === 'completed')
      onUploadComplete(completedFiles)
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
          {files.length > 0 && (
            <div className="flex items-center gap-2">
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
            </div>
          )}
        </div>
      </CardHeader>
      <CardContent className="space-y-4">
        {/* Drop zone */}
        <div
          className={`border-2 border-dashed rounded-lg p-8 text-center transition-colors cursor-pointer ${
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
          <Upload className="w-12 h-12 mx-auto mb-4 text-muted-foreground" />
          <p className="text-lg font-medium mb-2">
            {isDragging ? 'Drop files here' : 'Click to upload or drag and drop'}
          </p>
          <p className="text-sm text-muted-foreground mb-4">
            Supported formats: FASTQ, BAM, SAM, mzML, mzXML, CSV, TSV
          </p>
          <p className="text-xs text-muted-foreground">
            Maximum file size: {maxSize}MB {multiple && '• Multiple files allowed'}
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
