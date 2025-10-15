/**
 * Parameter Preview Dialog
 *
 * Displays LLM-generated parameters for dataset query tools with confidence scores.
 * Allows users to review and edit parameters before workflow execution.
 */

import { useState } from "react"
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle
} from "@/components/ui/dialog"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Badge } from "@/components/ui/badge"
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle
} from "@/components/ui/card"
import {
  AlertCircle,
  CheckCircle2,
  AlertTriangle,
  Info,
  Edit2,
  Save,
  X
} from "lucide-react"
import { cn } from "@/lib/utils"

export interface GeneratedParameter {
  step_id: number
  tool_id: string
  tool_name: string
  parameters: Record<string, any>
  confidence: number
  reasoning: string
}

interface ParameterPreviewDialogProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  generatedParameters: GeneratedParameter[]
  onConfirm: (editedParameters: GeneratedParameter[]) => void
  onCancel: () => void
}

export function ParameterPreviewDialog({
  open,
  onOpenChange,
  generatedParameters,
  onConfirm,
  onCancel
}: ParameterPreviewDialogProps) {
  const [editedParams, setEditedParams] = useState<GeneratedParameter[]>(generatedParameters)
  const [editingParam, setEditingParam] = useState<string | null>(null)

  // Update local state when props change
  useState(() => {
    setEditedParams(generatedParameters)
  })

  const handleParameterChange = (
    stepId: number,
    paramName: string,
    newValue: any
  ) => {
    setEditedParams(prev => prev.map(param => {
      if (param.step_id === stepId) {
        return {
          ...param,
          parameters: {
            ...param.parameters,
            [paramName]: newValue
          }
        }
      }
      return param
    }))
  }

  const getConfidenceBadge = (confidence: number) => {
    if (confidence >= 0.8) {
      return (
        <Badge variant="default" className="bg-green-500 hover:bg-green-600">
          <CheckCircle2 className="w-3 h-3 mr-1" />
          High ({(confidence * 100).toFixed(0)}%)
        </Badge>
      )
    } else if (confidence >= 0.6) {
      return (
        <Badge variant="secondary" className="bg-yellow-500 hover:bg-yellow-600 text-white">
          <AlertTriangle className="w-3 h-3 mr-1" />
          Medium ({(confidence * 100).toFixed(0)}%)
        </Badge>
      )
    } else {
      return (
        <Badge variant="destructive">
          <AlertCircle className="w-3 h-3 mr-1" />
          Low ({(confidence * 100).toFixed(0)}%)
        </Badge>
      )
    }
  }

  const hasLowConfidence = generatedParameters.some(p => p.confidence < 0.7)

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-3xl max-h-[80vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <Info className="w-5 h-5 text-blue-500" />
            Review Generated Parameters
          </DialogTitle>
          <DialogDescription>
            The AI has inferred these parameter values from your request.
            Please review and edit if needed before proceeding.
          </DialogDescription>
        </DialogHeader>

        {hasLowConfidence && (
          <Card className="border-yellow-300 bg-yellow-50">
            <CardContent className="pt-4">
              <div className="flex items-start gap-2">
                <AlertTriangle className="w-5 h-5 text-yellow-600 mt-0.5" />
                <div className="text-sm text-yellow-800">
                  <strong>Low Confidence Detected:</strong> Some parameters have low confidence scores.
                  Please review them carefully and adjust as needed.
                </div>
              </div>
            </CardContent>
          </Card>
        )}

        <div className="space-y-4">
          {editedParams.map((param, idx) => (
            <Card
              key={`${param.step_id}-${param.tool_id}`}
              className={cn(
                "transition-all",
                param.confidence < 0.7 && "border-yellow-300 bg-yellow-50/50"
              )}
            >
              <CardHeader className="pb-3">
                <div className="flex items-start justify-between">
                  <div className="space-y-1">
                    <CardTitle className="text-base font-semibold">
                      Step {param.step_id + 1}: {param.tool_name}
                    </CardTitle>
                    <CardDescription className="text-xs">
                      Tool ID: {param.tool_id}
                    </CardDescription>
                  </div>
                  {getConfidenceBadge(param.confidence)}
                </div>
              </CardHeader>

              <CardContent className="space-y-3">
                {/* Reasoning */}
                <div className="text-sm text-muted-foreground bg-muted p-2 rounded-md">
                  <strong>Reasoning:</strong> {param.reasoning}
                </div>

                {/* Parameters */}
                <div className="space-y-2">
                  <Label className="text-sm font-semibold">Parameters:</Label>
                  <div className="space-y-2">
                    {Object.entries(param.parameters).map(([key, value]) => {
                      const editKey = `${param.step_id}-${key}`
                      const isEditing = editingParam === editKey

                      return (
                        <div
                          key={key}
                          className="flex items-center gap-2 p-2 rounded-md hover:bg-muted/50 transition-colors"
                        >
                          <div className="flex-1 grid grid-cols-[120px_1fr] gap-2 items-center">
                            <Label className="text-xs font-mono text-muted-foreground">
                              {key}
                            </Label>
                            {isEditing ? (
                              <div className="flex items-center gap-1">
                                <Input
                                  value={value as string}
                                  onChange={(e) => handleParameterChange(
                                    param.step_id,
                                    key,
                                    e.target.value
                                  )}
                                  className="h-7 text-sm"
                                  autoFocus
                                />
                                <Button
                                  size="sm"
                                  variant="ghost"
                                  className="h-7 w-7 p-0"
                                  onClick={() => setEditingParam(null)}
                                >
                                  <Save className="w-3 h-3" />
                                </Button>
                                <Button
                                  size="sm"
                                  variant="ghost"
                                  className="h-7 w-7 p-0"
                                  onClick={() => {
                                    setEditedParams(generatedParameters)
                                    setEditingParam(null)
                                  }}
                                >
                                  <X className="w-3 h-3" />
                                </Button>
                              </div>
                            ) : (
                              <div className="flex items-center justify-between group">
                                <code className="text-xs bg-muted px-2 py-1 rounded flex-1">
                                  {String(value)}
                                </code>
                                <Button
                                  size="sm"
                                  variant="ghost"
                                  className="h-7 w-7 p-0 opacity-0 group-hover:opacity-100 transition-opacity"
                                  onClick={() => setEditingParam(editKey)}
                                >
                                  <Edit2 className="w-3 h-3" />
                                </Button>
                              </div>
                            )}
                          </div>
                        </div>
                      )
                    })}
                  </div>
                </div>
              </CardContent>
            </Card>
          ))}
        </div>

        <DialogFooter className="gap-2">
          <Button
            variant="outline"
            onClick={() => {
              setEditedParams(generatedParameters)
              setEditingParam(null)
              onCancel()
            }}
          >
            Cancel
          </Button>
          <Button
            onClick={() => {
              onConfirm(editedParams)
              setEditingParam(null)
            }}
            className="bg-blue-600 hover:bg-blue-700"
          >
            <CheckCircle2 className="w-4 h-4 mr-2" />
            Confirm & Generate Workflow
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
