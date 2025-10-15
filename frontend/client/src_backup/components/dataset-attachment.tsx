import { useState } from "react"
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Textarea } from "@/components/ui/textarea"
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle, DialogTrigger } from "@/components/ui/dialog"
import { Badge } from "@/components/ui/badge"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { Trash2, Database, HardDrive, Cloud, FolderOpen, Plus } from "lucide-react"
import type { DatasetConfig } from "@shared/schema"

interface DatasetAttachmentProps {
  datasets: DatasetConfig[]
  onDatasetsChange: (datasets: DatasetConfig[]) => void
  type: "input" | "output"
}

export function DatasetAttachment({ datasets, onDatasetsChange, type }: DatasetAttachmentProps) {
  const [isDialogOpen, setIsDialogOpen] = useState(false)
  const [newDataset, setNewDataset] = useState<Partial<DatasetConfig>>({
    type,
    storageType: "local"
  })

  const handleAddDataset = () => {
    if (!newDataset.name) return

    const dataset: DatasetConfig = {
      id: `${type}_${Date.now()}`,
      name: newDataset.name,
      type,
      storageType: newDataset.storageType || "local",
      localPath: newDataset.localPath,
      s3Config: newDataset.s3Config,
      replitStoragePath: newDataset.replitStoragePath,
      description: newDataset.description,
      format: newDataset.format,
      createdAt: new Date()
    }

    onDatasetsChange([...datasets, dataset])
    setNewDataset({ type, storageType: "local" })
    setIsDialogOpen(false)
  }

  const handleRemoveDataset = (id: string) => {
    onDatasetsChange(datasets.filter(d => d.id !== id))
  }

  const getStorageIcon = (storageType: string) => {
    switch (storageType) {
      case "local": return <HardDrive className="w-4 h-4" />
      case "s3": return <Cloud className="w-4 h-4" />
      case "replit_storage": return <Database className="w-4 h-4" />
      default: return <FolderOpen className="w-4 h-4" />
    }
  }

  const getStorageLabel = (storageType: string) => {
    switch (storageType) {
      case "local": return "Local Folder"
      case "s3": return "S3 Bucket"
      case "replit_storage": return "Replit Storage"
      default: return "Unknown"
    }
  }

  return (
    <div className="space-y-3">
      <div className="flex items-center justify-between">
        <Label className="text-sm font-medium capitalize">
          {type} Datasets
        </Label>
        <Dialog open={isDialogOpen} onOpenChange={setIsDialogOpen}>
          <DialogTrigger asChild>
            <Button 
              size="sm" 
              variant="outline"
              data-testid={`button-add-${type}-dataset`}
            >
              <Plus className="w-3 h-3 mr-1" />
              Add {type}
            </Button>
          </DialogTrigger>
          <DialogContent className="max-w-2xl">
            <DialogHeader>
              <DialogTitle>Add {type} Dataset</DialogTitle>
              <DialogDescription>
                Configure a dataset {type === "input" ? "source" : "destination"} for this workflow step.
              </DialogDescription>
            </DialogHeader>

            <div className="space-y-4">
              <div className="grid grid-cols-2 gap-4">
                <div>
                  <Label htmlFor="dataset-name">Dataset Name</Label>
                  <Input
                    id="dataset-name"
                    placeholder="e.g., Raw RNA-seq reads"
                    value={newDataset.name || ""}
                    onChange={(e) => setNewDataset({ ...newDataset, name: e.target.value })}
                    data-testid="input-dataset-name"
                  />
                </div>
                <div>
                  <Label htmlFor="dataset-format">Format</Label>
                  <Input
                    id="dataset-format"
                    placeholder="e.g., FASTQ, BAM, CSV"
                    value={newDataset.format || ""}
                    onChange={(e) => setNewDataset({ ...newDataset, format: e.target.value })}
                    data-testid="input-dataset-format"
                  />
                </div>
              </div>

              <div>
                <Label htmlFor="dataset-description">Description (Optional)</Label>
                <Textarea
                  id="dataset-description"
                  placeholder="Brief description of the dataset"
                  value={newDataset.description || ""}
                  onChange={(e) => setNewDataset({ ...newDataset, description: e.target.value })}
                  className="min-h-[60px]"
                  data-testid="input-dataset-description"
                />
              </div>

              <Tabs 
                value={newDataset.storageType} 
                onValueChange={(value) => setNewDataset({ ...newDataset, storageType: value as any })}
              >
                <TabsList className="grid w-full grid-cols-3">
                  <TabsTrigger value="local">Local Folder</TabsTrigger>
                  <TabsTrigger value="replit_storage">Replit Storage</TabsTrigger>
                  <TabsTrigger value="s3">S3 Bucket</TabsTrigger>
                </TabsList>

                <TabsContent value="local" className="space-y-4">
                  <Card>
                    <CardHeader className="pb-3">
                      <CardTitle className="text-sm flex items-center gap-2">
                        <HardDrive className="w-4 h-4" />
                        Local File System
                      </CardTitle>
                    </CardHeader>
                    <CardContent>
                      <div>
                        <Label htmlFor="local-path">Folder Path</Label>
                        <Input
                          id="local-path"
                          placeholder="/path/to/data/folder"
                          value={newDataset.localPath || ""}
                          onChange={(e) => setNewDataset({ ...newDataset, localPath: e.target.value })}
                          data-testid="input-local-path"
                        />
                      </div>
                    </CardContent>
                  </Card>
                </TabsContent>

                <TabsContent value="replit_storage" className="space-y-4">
                  <Card>
                    <CardHeader className="pb-3">
                      <CardTitle className="text-sm flex items-center gap-2">
                        <Database className="w-4 h-4" />
                        Replit Storage
                      </CardTitle>
                    </CardHeader>
                    <CardContent>
                      <div>
                        <Label htmlFor="replit-path">Storage Path</Label>
                        <Input
                          id="replit-path"
                          placeholder="datasets/rna-seq"
                          value={newDataset.replitStoragePath || ""}
                          onChange={(e) => setNewDataset({ ...newDataset, replitStoragePath: e.target.value })}
                          data-testid="input-replit-path"
                        />
                      </div>
                    </CardContent>
                  </Card>
                </TabsContent>

                <TabsContent value="s3" className="space-y-4">
                  <Card>
                    <CardHeader className="pb-3">
                      <CardTitle className="text-sm flex items-center gap-2">
                        <Cloud className="w-4 h-4" />
                        Amazon S3 Bucket
                      </CardTitle>
                    </CardHeader>
                    <CardContent className="space-y-4">
                      <div className="grid grid-cols-2 gap-4">
                        <div>
                          <Label htmlFor="s3-bucket">Bucket Name</Label>
                          <Input
                            id="s3-bucket"
                            placeholder="my-biodata-bucket"
                            value={newDataset.s3Config?.bucketName || ""}
                            onChange={(e) => setNewDataset({
                              ...newDataset,
                              s3Config: { ...newDataset.s3Config, bucketName: e.target.value } as any
                            })}
                            data-testid="input-s3-bucket"
                          />
                        </div>
                        <div>
                          <Label htmlFor="s3-region">Region</Label>
                          <Select
                            value={newDataset.s3Config?.region || "us-east-1"}
                            onValueChange={(value) => setNewDataset({
                              ...newDataset,
                              s3Config: { ...newDataset.s3Config, region: value } as any
                            })}
                          >
                            <SelectTrigger id="s3-region" data-testid="select-s3-region">
                              <SelectValue />
                            </SelectTrigger>
                            <SelectContent>
                              <SelectItem value="us-east-1">US East (N. Virginia)</SelectItem>
                              <SelectItem value="us-west-2">US West (Oregon)</SelectItem>
                              <SelectItem value="eu-west-1">Europe (Ireland)</SelectItem>
                              <SelectItem value="ap-southeast-1">Asia Pacific (Singapore)</SelectItem>
                            </SelectContent>
                          </Select>
                        </div>
                      </div>
                      <div className="grid grid-cols-2 gap-4">
                        <div>
                          <Label htmlFor="s3-access-key">Access Key ID</Label>
                          <Input
                            id="s3-access-key"
                            type="password"
                            placeholder="AKIA..."
                            value={newDataset.s3Config?.accessKeyId || ""}
                            onChange={(e) => setNewDataset({
                              ...newDataset,
                              s3Config: { ...newDataset.s3Config, accessKeyId: e.target.value } as any
                            })}
                            data-testid="input-s3-access-key"
                          />
                        </div>
                        <div>
                          <Label htmlFor="s3-secret-key">Secret Access Key</Label>
                          <Input
                            id="s3-secret-key"
                            type="password"
                            placeholder="••••••••"
                            value={newDataset.s3Config?.secretAccessKey || ""}
                            onChange={(e) => setNewDataset({
                              ...newDataset,
                              s3Config: { ...newDataset.s3Config, secretAccessKey: e.target.value } as any
                            })}
                            data-testid="input-s3-secret-key"
                          />
                        </div>
                      </div>
                      <div>
                        <Label htmlFor="s3-prefix">Prefix (Optional)</Label>
                        <Input
                          id="s3-prefix"
                          placeholder="data/rna-seq/"
                          value={newDataset.s3Config?.prefix || ""}
                          onChange={(e) => setNewDataset({
                            ...newDataset,
                            s3Config: { ...newDataset.s3Config, prefix: e.target.value } as any
                          })}
                          data-testid="input-s3-prefix"
                        />
                      </div>
                    </CardContent>
                  </Card>
                </TabsContent>
              </Tabs>
            </div>

            <DialogFooter>
              <Button variant="outline" onClick={() => setIsDialogOpen(false)}>
                Cancel
              </Button>
              <Button 
                onClick={handleAddDataset}
                disabled={!newDataset.name}
                data-testid="button-save-dataset"
              >
                Add Dataset
              </Button>
            </DialogFooter>
          </DialogContent>
        </Dialog>
      </div>

      <div className="space-y-2">
        {datasets.length === 0 ? (
          <div className="text-center py-4 text-sm text-muted-foreground border border-dashed rounded-md">
            No {type} datasets configured
          </div>
        ) : (
          datasets.map((dataset) => (
            <Card key={dataset.id} className="relative" data-testid={`card-dataset-${dataset.id}`}>
              <CardContent className="p-3">
                <div className="flex items-center justify-between">
                  <div className="flex items-center gap-3">
                    {getStorageIcon(dataset.storageType)}
                    <div>
                      <div className="font-medium text-sm">{dataset.name}</div>
                      <div className="flex items-center gap-2 text-xs text-muted-foreground">
                        <span>{getStorageLabel(dataset.storageType)}</span>
                        {dataset.format && (
                          <>
                            <span>•</span>
                            <Badge variant="outline" className="text-xs h-4 px-1">
                              {dataset.format}
                            </Badge>
                          </>
                        )}
                      </div>
                      {dataset.description && (
                        <div className="text-xs text-muted-foreground mt-1 max-w-md truncate">
                          {dataset.description}
                        </div>
                      )}
                    </div>
                  </div>
                  <Button
                    variant="ghost"
                    size="sm"
                    onClick={() => handleRemoveDataset(dataset.id)}
                    data-testid={`button-remove-dataset-${dataset.id}`}
                  >
                    <Trash2 className="w-3 h-3" />
                  </Button>
                </div>
              </CardContent>
            </Card>
          ))
        )}
      </div>
    </div>
  )
}