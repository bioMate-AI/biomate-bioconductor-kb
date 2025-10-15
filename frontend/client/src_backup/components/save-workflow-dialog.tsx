import { useState } from "react"
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter, DialogDescription } from "@/components/ui/dialog"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Badge } from "@/components/ui/badge"
import { Loader2, Save, X } from "lucide-react"
import type { WorkflowStep } from "./workflow-step"

interface SaveWorkflowDialogProps {
  isOpen: boolean
  onClose: () => void
  workflowName: string
  workflowSteps: WorkflowStep[]
  onSave: (template: any) => Promise<void>
}

export function SaveWorkflowDialog({
  isOpen,
  onClose,
  workflowName,
  workflowSteps,
  onSave
}: SaveWorkflowDialogProps) {
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  // Form state
  const [name, setName] = useState(workflowName || "")
  const [description, setDescription] = useState("")
  const [useCaseName, setUseCaseName] = useState("")
  const [useCaseDescription, setUseCaseDescription] = useState("")
  const [category, setCategory] = useState<string>("genomics")
  const [analysisType, setAnalysisType] = useState("")
  const [difficulty, setDifficulty] = useState<string>("intermediate")
  const [estimatedTime, setEstimatedTime] = useState("")
  const [sampleTypes, setSampleTypes] = useState<string[]>([])
  const [inputTypes, setInputTypes] = useState<string[]>([])
  const [expectedOutputs, setExpectedOutputs] = useState<string[]>([])
  const [tags, setTags] = useState<string[]>([])
  const [newTag, setNewTag] = useState("")
  const [newSampleType, setNewSampleType] = useState("")
  const [newInputType, setNewInputType] = useState("")
  const [newOutput, setNewOutput] = useState("")

  const handleSave = async () => {
    // Validate required fields
    if (!name.trim()) {
      setError("Workflow name is required")
      return
    }
    if (!useCaseName.trim()) {
      setError("Use case name is required")
      return
    }
    if (!analysisType.trim()) {
      setError("Analysis type is required")
      return
    }

    setLoading(true)
    setError(null)

    try {
      // Convert workflow steps to Galaxy .ga format
      const workflowGa = {
        a_galaxy_workflow: "true",
        format_version: "0.1",
        name: name,
        annotation: description,
        tags: tags,
        steps: workflowSteps.reduce((acc, step, index) => {
          acc[index] = {
            id: index,
            tool_id: step.tool,
            tool_version: "latest",
            label: step.title,
            annotation: step.description,
            tool_state: step.parameters || {},
          }
          return acc
        }, {} as Record<number, any>)
      }

      const template = {
        name,
        description,
        use_case_name: useCaseName,
        use_case_description: useCaseDescription,
        category,
        analysis_type: analysisType,
        sample_types: sampleTypes,
        input_types: inputTypes,
        expected_outputs: expectedOutputs,
        difficulty,
        estimated_time: estimatedTime,
        tags,
        workflow_ga: workflowGa,
      }

      await onSave(template)
      onClose()
    } catch (err: any) {
      console.error('[SaveWorkflowDialog] Failed to save workflow:', err)
      setError(err.message || 'Failed to save workflow template')
    } finally {
      setLoading(false)
    }
  }

  const addTag = () => {
    if (newTag.trim() && !tags.includes(newTag.trim())) {
      setTags([...tags, newTag.trim()])
      setNewTag("")
    }
  }

  const removeTag = (tag: string) => {
    setTags(tags.filter(t => t !== tag))
  }

  const addSampleType = () => {
    if (newSampleType.trim() && !sampleTypes.includes(newSampleType.trim())) {
      setSampleTypes([...sampleTypes, newSampleType.trim()])
      setNewSampleType("")
    }
  }

  const removeSampleType = (type: string) => {
    setSampleTypes(sampleTypes.filter(t => t !== type))
  }

  const addInputType = () => {
    if (newInputType.trim() && !inputTypes.includes(newInputType.trim())) {
      setInputTypes([...inputTypes, newInputType.trim()])
      setNewInputType("")
    }
  }

  const removeInputType = (type: string) => {
    setInputTypes(inputTypes.filter(t => t !== type))
  }

  const addOutput = () => {
    if (newOutput.trim() && !expectedOutputs.includes(newOutput.trim())) {
      setExpectedOutputs([...expectedOutputs, newOutput.trim()])
      setNewOutput("")
    }
  }

  const removeOutput = (output: string) => {
    setExpectedOutputs(expectedOutputs.filter(o => o !== output))
  }

  return (
    <Dialog open={isOpen} onOpenChange={onClose}>
      <DialogContent className="max-w-3xl max-h-[90vh] overflow-hidden flex flex-col">
        <DialogHeader>
          <div className="flex items-center gap-2">
            <Save className="w-5 h-5" />
            <DialogTitle>Save Workflow Template</DialogTitle>
          </div>
          <DialogDescription>
            Save this workflow as a reusable template with use case metadata
          </DialogDescription>
        </DialogHeader>

        <div className="flex-1 overflow-y-auto pr-2 space-y-6">
          {/* Basic Information */}
          <div className="space-y-4">
            <h3 className="text-sm font-semibold">Basic Information</h3>

            <div className="space-y-2">
              <Label htmlFor="name">
                Workflow Name <span className="text-destructive">*</span>
              </Label>
              <Input
                id="name"
                value={name}
                onChange={(e) => setName(e.target.value)}
                placeholder="e.g., RNA-seq Differential Expression"
              />
            </div>

            <div className="space-y-2">
              <Label htmlFor="description">Description</Label>
              <Textarea
                id="description"
                value={description}
                onChange={(e) => setDescription(e.target.value)}
                placeholder="Brief description of this workflow..."
                className="min-h-[60px]"
              />
            </div>
          </div>

          {/* Use Case Metadata */}
          <div className="space-y-4 border-t pt-4">
            <h3 className="text-sm font-semibold">Use Case Details</h3>

            <div className="space-y-2">
              <Label htmlFor="useCaseName">
                Use Case Name <span className="text-destructive">*</span>
              </Label>
              <Input
                id="useCaseName"
                value={useCaseName}
                onChange={(e) => setUseCaseName(e.target.value)}
                placeholder="e.g., Human RNA-seq QC and Differential Expression"
              />
            </div>

            <div className="space-y-2">
              <Label htmlFor="useCaseDescription">Use Case Description</Label>
              <Textarea
                id="useCaseDescription"
                value={useCaseDescription}
                onChange={(e) => setUseCaseDescription(e.target.value)}
                placeholder="When to use this workflow..."
                className="min-h-[60px]"
              />
            </div>

            <div className="grid grid-cols-2 gap-4">
              <div className="space-y-2">
                <Label htmlFor="category">Category</Label>
                <Select value={category} onValueChange={setCategory}>
                  <SelectTrigger id="category">
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="genomics">Genomics</SelectItem>
                    <SelectItem value="proteomics">Proteomics</SelectItem>
                    <SelectItem value="metabolomics">Metabolomics</SelectItem>
                    <SelectItem value="clinical">Clinical</SelectItem>
                    <SelectItem value="quality_control">Quality Control</SelectItem>
                    <SelectItem value="preprocessing">Preprocessing</SelectItem>
                    <SelectItem value="analysis">Analysis</SelectItem>
                    <SelectItem value="other">Other</SelectItem>
                  </SelectContent>
                </Select>
              </div>

              <div className="space-y-2">
                <Label htmlFor="analysisType">
                  Analysis Type <span className="text-destructive">*</span>
                </Label>
                <Input
                  id="analysisType"
                  value={analysisType}
                  onChange={(e) => setAnalysisType(e.target.value)}
                  placeholder="e.g., Differential Expression"
                />
              </div>

              <div className="space-y-2">
                <Label htmlFor="difficulty">Difficulty</Label>
                <Select value={difficulty} onValueChange={setDifficulty}>
                  <SelectTrigger id="difficulty">
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="beginner">Beginner</SelectItem>
                    <SelectItem value="intermediate">Intermediate</SelectItem>
                    <SelectItem value="advanced">Advanced</SelectItem>
                  </SelectContent>
                </Select>
              </div>

              <div className="space-y-2">
                <Label htmlFor="estimatedTime">Estimated Time</Label>
                <Input
                  id="estimatedTime"
                  value={estimatedTime}
                  onChange={(e) => setEstimatedTime(e.target.value)}
                  placeholder="e.g., 30-45 minutes"
                />
              </div>
            </div>
          </div>

          {/* Sample Types */}
          <div className="space-y-4 border-t pt-4">
            <h3 className="text-sm font-semibold">Sample Types</h3>
            <div className="space-y-2">
              <div className="flex gap-2">
                <Input
                  value={newSampleType}
                  onChange={(e) => setNewSampleType(e.target.value)}
                  onKeyDown={(e) => e.key === 'Enter' && (e.preventDefault(), addSampleType())}
                  placeholder="e.g., Human RNA-seq, Mouse ChIP-seq"
                />
                <Button type="button" onClick={addSampleType} size="sm">
                  Add
                </Button>
              </div>
              {sampleTypes.length > 0 && (
                <div className="flex flex-wrap gap-2">
                  {sampleTypes.map((type) => (
                    <Badge key={type} variant="secondary">
                      {type}
                      <X
                        className="w-3 h-3 ml-1 cursor-pointer"
                        onClick={() => removeSampleType(type)}
                      />
                    </Badge>
                  ))}
                </div>
              )}
            </div>
          </div>

          {/* Input Types */}
          <div className="space-y-4 border-t pt-4">
            <h3 className="text-sm font-semibold">Input Types</h3>
            <div className="space-y-2">
              <div className="flex gap-2">
                <Input
                  value={newInputType}
                  onChange={(e) => setNewInputType(e.target.value)}
                  onKeyDown={(e) => e.key === 'Enter' && (e.preventDefault(), addInputType())}
                  placeholder="e.g., FASTQ, BAM, mzML"
                />
                <Button type="button" onClick={addInputType} size="sm">
                  Add
                </Button>
              </div>
              {inputTypes.length > 0 && (
                <div className="flex flex-wrap gap-2">
                  {inputTypes.map((type) => (
                    <Badge key={type} variant="secondary">
                      {type}
                      <X
                        className="w-3 h-3 ml-1 cursor-pointer"
                        onClick={() => removeInputType(type)}
                      />
                    </Badge>
                  ))}
                </div>
              )}
            </div>
          </div>

          {/* Expected Outputs */}
          <div className="space-y-4 border-t pt-4">
            <h3 className="text-sm font-semibold">Expected Outputs</h3>
            <div className="space-y-2">
              <div className="flex gap-2">
                <Input
                  value={newOutput}
                  onChange={(e) => setNewOutput(e.target.value)}
                  onKeyDown={(e) => e.key === 'Enter' && (e.preventDefault(), addOutput())}
                  placeholder="e.g., DEG list, QC report, BAM files"
                />
                <Button type="button" onClick={addOutput} size="sm">
                  Add
                </Button>
              </div>
              {expectedOutputs.length > 0 && (
                <div className="flex flex-wrap gap-2">
                  {expectedOutputs.map((output) => (
                    <Badge key={output} variant="secondary">
                      {output}
                      <X
                        className="w-3 h-3 ml-1 cursor-pointer"
                        onClick={() => removeOutput(output)}
                      />
                    </Badge>
                  ))}
                </div>
              )}
            </div>
          </div>

          {/* Tags */}
          <div className="space-y-4 border-t pt-4">
            <h3 className="text-sm font-semibold">Tags</h3>
            <div className="space-y-2">
              <div className="flex gap-2">
                <Input
                  value={newTag}
                  onChange={(e) => setNewTag(e.target.value)}
                  onKeyDown={(e) => e.key === 'Enter' && (e.preventDefault(), addTag())}
                  placeholder="e.g., rna-seq, differential-expression"
                />
                <Button type="button" onClick={addTag} size="sm">
                  Add
                </Button>
              </div>
              {tags.length > 0 && (
                <div className="flex flex-wrap gap-2">
                  {tags.map((tag) => (
                    <Badge key={tag} variant="outline">
                      {tag}
                      <X
                        className="w-3 h-3 ml-1 cursor-pointer"
                        onClick={() => removeTag(tag)}
                      />
                    </Badge>
                  ))}
                </div>
              )}
            </div>
          </div>

          {error && (
            <div className="bg-destructive/10 text-destructive px-4 py-3 rounded-md">
              <p className="text-sm">{error}</p>
            </div>
          )}
        </div>

        <DialogFooter className="border-t pt-4">
          <Button variant="outline" onClick={onClose} disabled={loading}>
            Cancel
          </Button>
          <Button onClick={handleSave} disabled={loading}>
            {loading && <Loader2 className="w-4 h-4 mr-2 animate-spin" />}
            Save Template
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
