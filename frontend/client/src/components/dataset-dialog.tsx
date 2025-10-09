import { useState } from "react"
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription } from "@/components/ui/dialog"
import { Button } from "@/components/ui/button"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { Card } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Search, Upload, Database } from "lucide-react"
import type { DatasetConfig } from "@shared/schema"

interface DatasetDialogProps {
  isOpen: boolean
  onClose: () => void
  onDatasetsSelected: (inputs: DatasetConfig[], outputs: DatasetConfig[]) => void
  initialInputs?: DatasetConfig[]
  initialOutputs?: DatasetConfig[]
}

export function DatasetDialog({
  isOpen,
  onClose,
  onDatasetsSelected,
  initialInputs = [],
  initialOutputs = []
}: DatasetDialogProps) {
  const [selectedInputs, setSelectedInputs] = useState<DatasetConfig[]>(initialInputs)
  const [selectedOutputs, setSelectedOutputs] = useState<DatasetConfig[]>(initialOutputs)
  const [searchQuery, setSearchQuery] = useState("")
  const [uploadedFiles, setUploadedFiles] = useState<File[]>([])

  // Mock available datasets (replace with API call)
  const mockDatasets: DatasetConfig[] = [
    { id: "1", name: "Sample RNA-seq FASTQ", type: "fastq", size: 1024000, path: "/data/sample1.fastq" },
    { id: "2", name: "Reference Genome hg38", type: "fasta", size: 3072000, path: "/data/hg38.fasta" },
    { id: "3", name: "Gene Annotations GTF", type: "gtf", size: 512000, path: "/data/genes.gtf" },
  ]

  const filteredDatasets = mockDatasets.filter(d =>
    d.name.toLowerCase().includes(searchQuery.toLowerCase())
  )

  const handleFileUpload = (e: React.ChangeEvent<HTMLInputElement>) => {
    const files = e.target.files
    if (files) {
      setUploadedFiles(Array.from(files))
    }
  }

  const handleSave = () => {
    // Convert uploaded files to datasets
    const uploadDatasets: DatasetConfig[] = uploadedFiles.map((file, index) => ({
      id: `upload-${Date.now()}-${index}`,
      name: file.name,
      type: file.name.split('.').pop() || 'unknown',
      size: file.size,
      path: URL.createObjectURL(file), // Temporary - should upload to server
    }))

    onDatasetsSelected(
      [...selectedInputs, ...uploadDatasets],
      selectedOutputs
    )
    onClose()
  }

  const toggleInput = (dataset: DatasetConfig) => {
    setSelectedInputs(prev => {
      const exists = prev.find(d => d.id === dataset.id)
      if (exists) {
        return prev.filter(d => d.id !== dataset.id)
      }
      return [...prev, dataset]
    })
  }

  const toggleOutput = (dataset: DatasetConfig) => {
    setSelectedOutputs(prev => {
      const exists = prev.find(d => d.id === dataset.id)
      if (exists) {
        return prev.filter(d => d.id !== dataset.id)
      }
      return [...prev, dataset]
    })
  }

  return (
    <Dialog open={isOpen} onOpenChange={onClose}>
      <DialogContent className="max-w-3xl max-h-[80vh]">
        <DialogHeader>
          <DialogTitle>Select or Upload Datasets</DialogTitle>
          <DialogDescription>
            Choose existing datasets or upload new files for your workflow
          </DialogDescription>
        </DialogHeader>

        <Tabs defaultValue="upload" className="w-full">
          <TabsList className="grid w-full grid-cols-2">
            <TabsTrigger value="upload">
              <Upload className="w-4 h-4 mr-2" />
              Upload Files
            </TabsTrigger>
            <TabsTrigger value="datasets">
              <Database className="w-4 h-4 mr-2" />
              Existing Datasets
            </TabsTrigger>
          </TabsList>

          <TabsContent value="upload" className="space-y-4">
            <div className="space-y-4">
              <div className="border-2 border-dashed border-gray-300 rounded-lg p-8 text-center">
                <Upload className="w-12 h-12 mx-auto mb-4 text-gray-400" />
                <Label htmlFor="file-upload" className="cursor-pointer">
                  <span className="text-sm font-medium text-primary hover:underline">
                    Click to upload files
                  </span>
                  <span className="text-sm text-muted-foreground"> or drag and drop</span>
                </Label>
                <Input
                  id="file-upload"
                  type="file"
                  multiple
                  onChange={handleFileUpload}
                  className="hidden"
                  accept=".fastq,.fasta,.fa,.gtf,.gff,.bam,.sam,.vcf,.bed,.txt,.csv"
                />
                <p className="text-xs text-muted-foreground mt-2">
                  Supported: FASTQ, FASTA, GTF, BAM, VCF, BED, CSV
                </p>
              </div>

              {uploadedFiles.length > 0 && (
                <div className="space-y-2">
                  <h4 className="text-sm font-medium">Uploaded Files ({uploadedFiles.length})</h4>
                  {uploadedFiles.map((file, index) => (
                    <Card key={index} className="p-3 flex items-center justify-between">
                      <div>
                        <p className="text-sm font-medium">{file.name}</p>
                        <p className="text-xs text-muted-foreground">
                          {(file.size / 1024 / 1024).toFixed(2)} MB
                        </p>
                      </div>
                      <Button
                        variant="ghost"
                        size="sm"
                        onClick={() => setUploadedFiles(prev => prev.filter((_, i) => i !== index))}
                      >
                        Remove
                      </Button>
                    </Card>
                  ))}
                </div>
              )}
            </div>
          </TabsContent>

          <TabsContent value="datasets" className="space-y-4">
            <div className="relative">
              <Search className="absolute left-3 top-3 h-4 w-4 text-muted-foreground" />
              <Input
                placeholder="Search datasets..."
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                className="pl-9"
              />
            </div>

            <div className="space-y-2">
              <div className="flex items-center justify-between">
                <h4 className="text-sm font-medium">Available Datasets</h4>
                <div className="text-xs text-muted-foreground">
                  {selectedInputs.length} inputs, {selectedOutputs.length} outputs selected
                </div>
              </div>

              <div className="space-y-2 max-h-[300px] overflow-y-auto">
                {filteredDatasets.map((dataset) => {
                  const isInputSelected = selectedInputs.some(d => d.id === dataset.id)
                  const isOutputSelected = selectedOutputs.some(d => d.id === dataset.id)

                  return (
                    <Card key={dataset.id} className="p-3">
                      <div className="flex items-center justify-between">
                        <div className="flex-1">
                          <p className="text-sm font-medium">{dataset.name}</p>
                          <p className="text-xs text-muted-foreground">
                            {dataset.type.toUpperCase()} • {(dataset.size / 1024 / 1024).toFixed(2)} MB
                          </p>
                        </div>
                        <div className="flex gap-2">
                          <Button
                            variant={isInputSelected ? "default" : "outline"}
                            size="sm"
                            onClick={() => toggleInput(dataset)}
                          >
                            Input
                          </Button>
                          <Button
                            variant={isOutputSelected ? "default" : "outline"}
                            size="sm"
                            onClick={() => toggleOutput(dataset)}
                          >
                            Output
                          </Button>
                        </div>
                      </div>
                    </Card>
                  )
                })}
              </div>
            </div>
          </TabsContent>
        </Tabs>

        <div className="flex justify-end gap-2 pt-4 border-t">
          <Button variant="outline" onClick={onClose}>
            Cancel
          </Button>
          <Button onClick={handleSave}>
            Attach Datasets
          </Button>
        </div>
      </DialogContent>
    </Dialog>
  )
}
