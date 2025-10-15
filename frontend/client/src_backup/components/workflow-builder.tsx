import { useState } from "react"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { ScrollArea } from "@/components/ui/scroll-area"
import { WorkflowStep, type WorkflowStep as WorkflowStepType } from "./workflow-step"
import { Plus, Play, Save, Download, MessageCircle, Zap } from "lucide-react"

//todo: remove mock functionality
const mockWorkflowSteps: WorkflowStepType[] = [
  {
    id: "step1",
    title: "Quality Control",
    description: "Assess the quality of raw sequencing reads and generate quality reports using FastQC",
    status: "completed",
    tool: "FastQC",
    parameters: {
      "Input format": "FASTQ",
      "Quality threshold": 20,
      "Adapter trimming": "Auto-detect"
    },
    complexity: "simple",
    estimatedTime: "3 min"
  },
  {
    id: "step2", 
    title: "Read Alignment",
    description: "Align quality-controlled reads to the reference genome using HISAT2",
    status: "running",
    tool: "HISAT2",
    parameters: {
      "Reference genome": "hg38",
      "Splice-aware": true,
      "Max intron length": 500000
    },
    complexity: "intermediate",
    estimatedTime: "15 min"
  },
  {
    id: "step3",
    title: "Gene Expression Quantification", 
    description: "Count reads mapping to genes and calculate expression levels using featureCounts",
    status: "pending",
    tool: "featureCounts",
    parameters: {
      "Annotation": "GENCODE v40",
      "Feature type": "exon",
      "Strand specificity": "unstranded"
    },
    complexity: "complex",
    estimatedTime: "8 min"
  },
  {
    id: "step4",
    title: "Differential Expression Analysis",
    description: "Identify genes with significant expression changes between conditions",
    status: "pending", 
    tool: "DESeq2",
    parameters: {
      "Contrast": "treatment vs control",
      "P-value threshold": 0.05,
      "Log2 fold change": 1.5
    },
    complexity: "complex",
    estimatedTime: "12 min"
  }
]

interface WorkflowBuilderProps {
  workflowSteps?: WorkflowStepType[]
  onRunWorkflow?: () => void
  onSaveWorkflow?: () => void
  onExportWorkflow?: () => void
  onGetHelp?: () => void
  workflowName?: string
}

export function WorkflowBuilder({
  workflowSteps = mockWorkflowSteps, //todo: remove mock functionality
  onRunWorkflow = () => console.log('Run workflow triggered'),
  onSaveWorkflow = () => console.log('Save workflow triggered'),
  onExportWorkflow = () => console.log('Export workflow triggered'),
  onGetHelp = () => console.log('Get help triggered'),
  workflowName = "RNA-seq Analysis Pipeline" //todo: remove mock functionality
}: WorkflowBuilderProps) {
  const [steps, setSteps] = useState(workflowSteps)

  const totalSteps = steps.length
  const completedSteps = steps.filter(s => s.status === "completed").length

  const handleAddStep = () => {
    console.log('Add step triggered')
  }

  const handleStepEdit = (step: WorkflowStepType) => {
    console.log('Edit step:', step.title)
  }

  const handleStepRun = (step: WorkflowStepType) => {
    setSteps(prev => prev.map(s => 
      s.id === step.id ? { ...s, status: "running" as const } : s
    ))
    
    // Simulate step completion
    setTimeout(() => {
      setSteps(prev => prev.map(s => 
        s.id === step.id ? { ...s, status: "completed" as const } : s
      ))
    }, 2000)
  }

  const handleStepRemove = (step: WorkflowStepType) => {
    setSteps(prev => prev.filter(s => s.id !== step.id))
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <Card>
        <CardHeader>
          <div className="flex items-start justify-between">
            <div className="space-y-2">
              <CardTitle className="text-2xl">{workflowName}</CardTitle>
              <CardDescription>
                Build and customize your bioinformatics analysis pipeline
              </CardDescription>
              <div className="flex items-center gap-4">
                <div className="flex items-center gap-2">
                  <span className="text-sm text-muted-foreground">Progress:</span>
                  <Badge variant="outline">
                    {completedSteps} / {totalSteps} steps
                  </Badge>
                </div>
              </div>
            </div>
            <Button
              variant="outline"
              onClick={onGetHelp}
              data-testid="button-get-workflow-help"
            >
              <MessageCircle className="w-4 h-4 mr-2" />
              Get Help
            </Button>
          </div>
        </CardHeader>
      </Card>

      {/* Workflow Steps */}
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <div className="lg:col-span-2 space-y-4">
          <div className="flex items-center justify-between">
            <h3 className="text-lg font-semibold">Workflow Steps</h3>
            <Button
              variant="outline"
              onClick={handleAddStep}
              data-testid="button-add-step"
            >
              <Plus className="w-4 h-4 mr-2" />
              Add Step
            </Button>
          </div>
          
          <ScrollArea className="h-[500px]">
            <div className="space-y-4 pr-4">
              {steps.map((step, index) => (
                <WorkflowStep
                  key={step.id}
                  step={step}
                  index={index}
                  onEdit={handleStepEdit}
                  onRun={handleStepRun}
                  onRemove={handleStepRemove}
                />
              ))}
            </div>
          </ScrollArea>
        </div>

        {/* Actions Panel */}
        <div className="space-y-4">
          <Card>
            <CardHeader>
              <CardTitle className="text-lg">Workflow Actions</CardTitle>
            </CardHeader>
            <CardContent className="space-y-3">
              <Button 
                className="w-full"
                onClick={onRunWorkflow}
                data-testid="button-run-workflow"
              >
                <Play className="w-4 h-4 mr-2" />
                Run Workflow
              </Button>
              <Button 
                variant="outline" 
                className="w-full"
                onClick={onSaveWorkflow}
                data-testid="button-save-workflow"
              >
                <Save className="w-4 h-4 mr-2" />
                Save Workflow
              </Button>
              <Button 
                variant="outline" 
                className="w-full"
                onClick={onExportWorkflow}
                data-testid="button-export-workflow"
              >
                <Download className="w-4 h-4 mr-2" />
                Export Workflow
              </Button>
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle className="text-lg flex items-center">
                <Zap className="w-5 h-5 mr-2" />
                Simplification Tips
              </CardTitle>
            </CardHeader>
            <CardContent className="space-y-3 text-sm">
              <div className="p-3 bg-blue-50 dark:bg-blue-950 rounded-lg">
                <p className="font-medium text-blue-900 dark:text-blue-100">
                  Combine Similar Steps
                </p>
                <p className="text-blue-700 dark:text-blue-300 mt-1">
                  Steps 2 and 3 could be combined into a single alignment + quantification step.
                </p>
              </div>
              <div className="p-3 bg-green-50 dark:bg-green-950 rounded-lg">
                <p className="font-medium text-green-900 dark:text-green-100">
                  Parallel Processing
                </p>
                <p className="text-green-700 dark:text-green-300 mt-1">
                  Quality control can run in parallel with reference genome preparation.
                </p>
              </div>
              <div className="p-3 bg-yellow-50 dark:bg-yellow-950 rounded-lg">
                <p className="font-medium text-yellow-900 dark:text-yellow-100">
                  Parameter Optimization
                </p>
                <p className="text-yellow-700 dark:text-yellow-300 mt-1">
                  Some parameters can be auto-tuned based on your data characteristics.
                </p>
              </div>
            </CardContent>
          </Card>
        </div>
      </div>
    </div>
  )
}