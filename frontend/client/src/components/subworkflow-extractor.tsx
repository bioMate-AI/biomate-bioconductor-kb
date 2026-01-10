import { useState } from "react"
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogFooter } from "@/components/ui/dialog"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { Checkbox } from "@/components/ui/checkbox"
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert"
import { ScrollArea } from "@/components/ui/scroll-area"
import { Badge } from "@/components/ui/badge"
import {
  Scissors,
  Loader2,
  AlertCircle,
  Check,
  Workflow,
  Save,
  Share2
} from "lucide-react"

interface WorkflowStep {
  id: string
  name?: string
  tool_id?: string
  title?: string
}

interface SubworkflowExtractorProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  workflowId: string
  workflowName?: string
  steps: WorkflowStep[]
}

export function SubworkflowExtractor({
  open,
  onOpenChange,
  workflowId,
  workflowName = "Workflow",
  steps
}: SubworkflowExtractorProps) {
  const [selectedSteps, setSelectedSteps] = useState<Set<string>>(new Set())
  const [subworkflowName, setSubworkflowName] = useState('')
  const [description, setDescription] = useState('')
  const [saveToLibrary, setSaveToLibrary] = useState(true)
  const [shareWithTeam, setShareWithTeam] = useState(false)
  const [isExtracting, setIsExtracting] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [success, setSuccess] = useState<{
    id: string
    name: string
  } | null>(null)

  const toggleStep = (stepId: string) => {
    setSelectedSteps(prev => {
      const next = new Set(prev)
      if (next.has(stepId)) {
        next.delete(stepId)
      } else {
        next.add(stepId)
      }
      return next
    })
  }

  // Check for consecutive selection (recommended for valid subworkflows)
  const getSelectionInfo = () => {
    if (selectedSteps.size === 0) return { valid: false, message: 'Select at least one step' }

    const indices = steps
      .map((s, i) => selectedSteps.has(s.id) ? i : -1)
      .filter(i => i >= 0)
      .sort((a, b) => a - b)

    // Check if consecutive
    let isConsecutive = true
    for (let i = 1; i < indices.length; i++) {
      if (indices[i] !== indices[i - 1] + 1) {
        isConsecutive = false
        break
      }
    }

    if (!isConsecutive) {
      return {
        valid: true,
        warning: true,
        message: 'Non-consecutive steps selected. The subworkflow may have unconnected inputs.'
      }
    }

    return { valid: true, message: `${selectedSteps.size} consecutive steps selected` }
  }

  const selectionInfo = getSelectionInfo()

  // Auto-generate name suggestion based on selected tools
  const suggestName = () => {
    const selectedStepsList = steps.filter(s => selectedSteps.has(s.id))
    if (selectedStepsList.length === 0) return ''

    const toolNames = selectedStepsList
      .map(s => {
        const name = s.name || s.title || s.tool_id || 'Step'
        // Extract meaningful part (e.g., "FastQC" from "FastQC Quality Check")
        return name.split(/[\s_-]/)[0]
      })
      .filter((v, i, a) => a.indexOf(v) === i) // unique
      .slice(0, 3)

    return toolNames.join(' + ') + ' Module'
  }

  const handleExtract = async () => {
    if (!subworkflowName.trim()) {
      setError('Please provide a name for the subworkflow')
      return
    }

    if (selectedSteps.size === 0) {
      setError('Please select at least one step')
      return
    }

    setIsExtracting(true)
    setError(null)

    try {
      // Convert step IDs to step indices (Galaxy expects numeric indices)
      const stepIndices = steps
        .map((s, i) => selectedSteps.has(s.id) ? i : -1)
        .filter(i => i >= 0)

      const response = await fetch(`/api/workflows/${workflowId}/extract-subworkflow`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          step_ids: stepIndices,
          name: subworkflowName.trim(),
          description: description.trim(),
          save_to_library: saveToLibrary,
          share_with_team: shareWithTeam
        })
      })

      if (!response.ok) {
        const errorData = await response.json()
        throw new Error(errorData.message || 'Failed to extract subworkflow')
      }

      const data = await response.json()
      setSuccess({
        id: data.id,
        name: data.name
      })
    } catch (err: any) {
      setError(err.message || 'Failed to extract subworkflow')
    } finally {
      setIsExtracting(false)
    }
  }

  const handleClose = () => {
    setSelectedSteps(new Set())
    setSubworkflowName('')
    setDescription('')
    setError(null)
    setSuccess(null)
    onOpenChange(false)
  }

  return (
    <Dialog open={open} onOpenChange={handleClose}>
      <DialogContent className="max-w-2xl">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <Scissors className="h-5 w-5" />
            Extract Subworkflow
          </DialogTitle>
          <DialogDescription>
            Extract selected steps from "{workflowName}" as a reusable component
          </DialogDescription>
        </DialogHeader>

        {!success ? (
          <>
            {/* Step Selection */}
            <div className="space-y-3">
              <Label className="text-sm font-medium">Select Steps to Extract</Label>
              <ScrollArea className="h-48 border rounded-lg">
                <div className="p-2 space-y-1">
                  {steps.map((step, idx) => (
                    <div
                      key={step.id}
                      className={`flex items-center space-x-3 p-2 rounded cursor-pointer transition-colors ${
                        selectedSteps.has(step.id)
                          ? 'bg-primary/10 border border-primary/30'
                          : 'hover:bg-muted/50'
                      }`}
                      onClick={() => toggleStep(step.id)}
                    >
                      <Checkbox
                        checked={selectedSteps.has(step.id)}
                        onCheckedChange={() => toggleStep(step.id)}
                      />
                      <span className="flex items-center justify-center w-6 h-6 rounded-full bg-muted text-xs font-medium">
                        {idx + 1}
                      </span>
                      <div className="flex-1 min-w-0">
                        <p className="text-sm font-medium truncate">
                          {step.name || step.title || `Step ${idx + 1}`}
                        </p>
                        {step.tool_id && (
                          <p className="text-xs text-muted-foreground font-mono truncate">
                            {step.tool_id}
                          </p>
                        )}
                      </div>
                    </div>
                  ))}
                </div>
              </ScrollArea>

              {/* Selection info */}
              <div className="flex items-center gap-2">
                <Badge variant={selectionInfo.valid ? (selectionInfo.warning ? 'secondary' : 'default') : 'outline'}>
                  {selectedSteps.size} step{selectedSteps.size !== 1 ? 's' : ''} selected
                </Badge>
                {selectionInfo.warning && (
                  <span className="text-xs text-amber-600">{selectionInfo.message}</span>
                )}
              </div>
            </div>

            {/* Subworkflow Details */}
            <div className="space-y-4">
              <div className="space-y-2">
                <Label htmlFor="subworkflow-name" className="text-sm font-medium">
                  Subworkflow Name *
                </Label>
                <div className="flex gap-2">
                  <Input
                    id="subworkflow-name"
                    placeholder="e.g., Standard RNA-seq QC Module"
                    value={subworkflowName}
                    onChange={(e) => setSubworkflowName(e.target.value)}
                    className="flex-1"
                  />
                  {selectedSteps.size > 0 && !subworkflowName && (
                    <Button
                      variant="outline"
                      size="sm"
                      onClick={() => setSubworkflowName(suggestName())}
                    >
                      Suggest
                    </Button>
                  )}
                </div>
              </div>

              <div className="space-y-2">
                <Label htmlFor="description" className="text-sm font-medium">
                  Description
                </Label>
                <Textarea
                  id="description"
                  placeholder="Describe what this subworkflow does and when to use it..."
                  value={description}
                  onChange={(e) => setDescription(e.target.value)}
                  rows={2}
                  className="resize-none"
                />
              </div>

              {/* Options */}
              <div className="space-y-3">
                <div className="flex items-center space-x-2">
                  <Checkbox
                    id="save-library"
                    checked={saveToLibrary}
                    onCheckedChange={(checked) => setSaveToLibrary(checked as boolean)}
                  />
                  <Label htmlFor="save-library" className="text-sm cursor-pointer">
                    <Save className="h-3 w-3 inline mr-1" />
                    Save to my workflow library
                  </Label>
                </div>
                <div className="flex items-center space-x-2">
                  <Checkbox
                    id="share-team"
                    checked={shareWithTeam}
                    onCheckedChange={(checked) => setShareWithTeam(checked as boolean)}
                  />
                  <Label htmlFor="share-team" className="text-sm cursor-pointer">
                    <Share2 className="h-3 w-3 inline mr-1" />
                    Share with team
                  </Label>
                </div>
              </div>
            </div>

            {error && (
              <Alert variant="destructive">
                <AlertCircle className="h-4 w-4" />
                <AlertDescription>{error}</AlertDescription>
              </Alert>
            )}

            <DialogFooter>
              <Button variant="outline" onClick={handleClose}>
                Cancel
              </Button>
              <Button
                onClick={handleExtract}
                disabled={isExtracting || selectedSteps.size === 0 || !subworkflowName.trim()}
              >
                {isExtracting ? (
                  <>
                    <Loader2 className="h-4 w-4 mr-2 animate-spin" />
                    Extracting...
                  </>
                ) : (
                  <>
                    <Scissors className="h-4 w-4 mr-2" />
                    Extract Subworkflow
                  </>
                )}
              </Button>
            </DialogFooter>
          </>
        ) : (
          /* Success State */
          <div className="space-y-4">
            <Alert className="border-green-500/50 bg-green-50/50 dark:bg-green-950/20">
              <Check className="h-4 w-4 text-green-600" />
              <AlertTitle className="text-green-800 dark:text-green-200">
                Subworkflow Created Successfully
              </AlertTitle>
              <AlertDescription className="text-green-700 dark:text-green-300">
                <p className="text-sm">"{success.name}" has been extracted as a reusable subworkflow.</p>
                <p className="text-xs mt-1 font-mono">ID: {success.id}</p>
              </AlertDescription>
            </Alert>

            <div className="p-4 border rounded-lg bg-muted/30">
              <div className="flex items-center gap-3">
                <div className="p-2 rounded-lg bg-primary/10">
                  <Workflow className="h-6 w-6 text-primary" />
                </div>
                <div>
                  <p className="font-medium">{success.name}</p>
                  <p className="text-xs text-muted-foreground">
                    {selectedSteps.size} step{selectedSteps.size !== 1 ? 's' : ''} extracted
                  </p>
                </div>
              </div>

              {saveToLibrary && (
                <p className="text-xs text-muted-foreground mt-3">
                  <Save className="h-3 w-3 inline mr-1" />
                  Saved to your workflow library
                </p>
              )}
              {shareWithTeam && (
                <p className="text-xs text-muted-foreground mt-1">
                  <Share2 className="h-3 w-3 inline mr-1" />
                  Shared with your team
                </p>
              )}
            </div>

            <div className="text-sm text-muted-foreground">
              <p className="font-medium mb-2">What's next?</p>
              <ul className="list-disc list-inside space-y-1 text-xs">
                <li>Use this subworkflow in other pipelines as a pre-built component</li>
                <li>Find it in your workflow library when creating new workflows</li>
                <li>Updates to this subworkflow will be reflected in all workflows that use it</li>
              </ul>
            </div>

            <DialogFooter>
              <Button onClick={handleClose}>
                Done
              </Button>
            </DialogFooter>
          </div>
        )}
      </DialogContent>
    </Dialog>
  )
}
