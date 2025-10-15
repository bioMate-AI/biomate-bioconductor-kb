import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { CheckCircle, Circle, Clock, AlertCircle, ChevronDown, ChevronRight, Database, HardDrive, Cloud } from "lucide-react"
import { cn } from "@/lib/utils"
import { useState } from "react"
import type { DatasetConfig } from "@shared/schema"

export interface WorkflowStep {
  id: string
  title: string
  description: string
  status: "pending" | "running" | "completed" | "error"
  tool: string
  parameters?: Record<string, any>
  complexity: "simple" | "intermediate" | "complex"
  estimatedTime?: string
  inputs?: DatasetConfig[]
  outputs?: DatasetConfig[]
}

interface WorkflowStepProps {
  step: WorkflowStep
  index: number
  onEdit?: (step: WorkflowStep) => void
  onRun?: (step: WorkflowStep) => void
  onRemove?: (step: WorkflowStep) => void
}

export function WorkflowStep({ 
  step, 
  index,
  onEdit = (step) => console.log('Edit step:', step.title),
  onRun = (step) => console.log('Run step:', step.title),
  onRemove = (step) => console.log('Remove step:', step.title)
}: WorkflowStepProps) {
  const [isExpanded, setIsExpanded] = useState(false)

  const statusIcons = {
    pending: Circle,
    running: Clock,
    completed: CheckCircle,
    error: AlertCircle
  }

  const statusColors = {
    pending: "text-muted-foreground",
    running: "text-blue-500",
    completed: "text-green-500", 
    error: "text-red-500"
  }

  const complexityColors = {
    simple: "bg-green-500",
    intermediate: "bg-yellow-500",
    complex: "bg-red-500"
  }

  const StatusIcon = statusIcons[step.status]

  const getStorageIcon = (storageType: string) => {
    switch (storageType) {
      case "local": return <HardDrive className="w-3 h-3" />
      case "s3": return <Cloud className="w-3 h-3" />
      case "replit_storage": return <Database className="w-3 h-3" />
      default: return <Database className="w-3 h-3" />
    }
  }

  const getStorageLabel = (storageType: string) => {
    switch (storageType) {
      case "local": return "Local"
      case "s3": return "S3"
      case "replit_storage": return "Replit Storage"
      default: return "Unknown"
    }
  }

  return (
    <Card className="w-full" data-testid={`card-workflow-step-${step.id}`}>
      <CardHeader className="pb-3">
        <div className="flex items-center gap-3">
          <div className="flex items-center justify-center w-8 h-8 rounded-full bg-muted text-muted-foreground text-sm font-medium">
            {index + 1}
          </div>
          <StatusIcon className={cn("h-5 w-5", statusColors[step.status])} />
          <div className="flex-1">
            <CardTitle className="text-base">{step.title}</CardTitle>
            <CardDescription className="text-sm">
              {step.tool} • {step.estimatedTime || "~5 min"}
            </CardDescription>
          </div>
          <div className="flex items-center gap-2">
            <Button
              variant="ghost"
              size="sm"
              onClick={() => setIsExpanded(!isExpanded)}
              data-testid={`button-expand-step-${step.id}`}
            >
              {isExpanded ? <ChevronDown className="h-4 w-4" /> : <ChevronRight className="h-4 w-4" />}
            </Button>
          </div>
        </div>
      </CardHeader>
      
      {isExpanded && (
        <CardContent className="pt-0">
          <p className="text-sm text-muted-foreground mb-4">
            {step.description}
          </p>
          
          {step.parameters && Object.keys(step.parameters).length > 0 && (
            <div className="mb-4">
              <h4 className="text-sm font-medium mb-2">Parameters</h4>
              <div className="space-y-1">
                {Object.entries(step.parameters).map(([key, value]) => (
                  <div key={key} className="flex justify-between text-xs">
                    <span className="text-muted-foreground">{key}:</span>
                    <span className="font-mono">{String(value)}</span>
                  </div>
                ))}
              </div>
            </div>
          )}

          {/* Dataset Inputs */}
          {step.inputs && step.inputs.length > 0 && (
            <div className="mb-4">
              <h4 className="text-sm font-medium mb-2 flex items-center gap-2">
                <Database className="w-3 h-3" />
                Input Datasets
              </h4>
              <div className="space-y-2">
                {step.inputs.map((dataset) => (
                  <div key={dataset.id} className="flex items-center gap-2 p-2 rounded-md bg-muted/50">
                    {getStorageIcon(dataset.storageType)}
                    <div className="flex-1 min-w-0">
                      <div className="text-xs font-medium truncate">{dataset.name}</div>
                      <div className="text-xs text-muted-foreground">
                        {getStorageLabel(dataset.storageType)}
                        {dataset.format && ` • ${dataset.format}`}
                      </div>
                    </div>
                  </div>
                ))}
              </div>
            </div>
          )}

          {/* Dataset Outputs */}
          {step.outputs && step.outputs.length > 0 && (
            <div className="mb-4">
              <h4 className="text-sm font-medium mb-2 flex items-center gap-2">
                <Database className="w-3 h-3" />
                Output Datasets
              </h4>
              <div className="space-y-2">
                {step.outputs.map((dataset) => (
                  <div key={dataset.id} className="flex items-center gap-2 p-2 rounded-md bg-muted/50">
                    {getStorageIcon(dataset.storageType)}
                    <div className="flex-1 min-w-0">
                      <div className="text-xs font-medium truncate">{dataset.name}</div>
                      <div className="text-xs text-muted-foreground">
                        {getStorageLabel(dataset.storageType)}
                        {dataset.format && ` • ${dataset.format}`}
                      </div>
                    </div>
                  </div>
                ))}
              </div>
            </div>
          )}
          
          <div className="flex gap-2">
            <Button
              variant="outline"
              size="sm"
              onClick={() => onEdit(step)}
              data-testid={`button-edit-step-${step.id}`}
            >
              Edit
            </Button>
            <Button
              variant="outline"
              size="sm"
              onClick={() => onRun(step)}
              disabled={step.status === "running"}
              data-testid={`button-run-step-${step.id}`}
            >
              {step.status === "running" ? "Running..." : "Run"}
            </Button>
            <Button
              variant="ghost"
              size="sm"
              onClick={() => onRemove(step)}
              data-testid={`button-remove-step-${step.id}`}
            >
              Remove
            </Button>
          </div>
        </CardContent>
      )}
    </Card>
  )
}