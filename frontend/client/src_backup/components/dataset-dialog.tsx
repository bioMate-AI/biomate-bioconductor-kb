import { useState, useEffect } from "react"
import { Button } from "@/components/ui/button"
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { DatasetAttachment } from "./dataset-attachment"
import { Database } from "lucide-react"
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
  const [inputDatasets, setInputDatasets] = useState<DatasetConfig[]>(initialInputs)
  const [outputDatasets, setOutputDatasets] = useState<DatasetConfig[]>(initialOutputs)

  // Sync internal state with props when they change (e.g., after message send clears datasets)
  useEffect(() => {
    setInputDatasets(initialInputs)
    setOutputDatasets(initialOutputs)
  }, [initialInputs, initialOutputs])

  const handleSave = () => {
    onDatasetsSelected(inputDatasets, outputDatasets)
    onClose()
  }

  const handleCancel = () => {
    // Reset to initial values
    setInputDatasets(initialInputs)
    setOutputDatasets(initialOutputs)
    onClose()
  }

  return (
    <Dialog open={isOpen} onOpenChange={onClose}>
      <DialogContent className="max-w-4xl max-h-[80vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <Database className="w-5 h-5" />
            Configure Datasets
          </DialogTitle>
          <DialogDescription>
            Set up input and output datasets for this workflow step. Configure local folders, 
            S3 buckets, or Replit storage locations.
          </DialogDescription>
        </DialogHeader>

        <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
          <div>
            <DatasetAttachment
              datasets={inputDatasets}
              onDatasetsChange={setInputDatasets}
              type="input"
            />
          </div>
          
          <div>
            <DatasetAttachment
              datasets={outputDatasets}
              onDatasetsChange={setOutputDatasets}
              type="output"
            />
          </div>
        </div>

        <DialogFooter>
          <Button variant="outline" onClick={handleCancel}>
            Cancel
          </Button>
          <Button onClick={handleSave} data-testid="button-save-datasets">
            Save Datasets
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}