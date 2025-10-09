import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert"
import { CheckCircle2, AlertCircle, AlertTriangle, Info } from "lucide-react"

export interface DatasetMapping {
  dataset_id: string
  step_id: string
  input_name: string
  confidence: 'high' | 'medium' | 'low'
  reasoning: string
}

export interface ValidationResult {
  valid: boolean
  issues: string[]
  warnings: string[]
  suggestions: string[]
  mappings: DatasetMapping[]
}

interface DatasetValidationDialogProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  validation: ValidationResult | null
  onConfirm: () => void
  onEdit?: () => void
}

export function DatasetValidationDialog({
  open,
  onOpenChange,
  validation,
  onConfirm,
  onEdit
}: DatasetValidationDialogProps) {
  if (!validation) return null

  const hasIssues = validation.issues.length > 0
  const hasWarnings = validation.warnings.length > 0
  const hasSuggestions = validation.suggestions.length > 0

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-2xl max-h-[80vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            {validation.valid ? (
              <>
                <CheckCircle2 className="w-5 h-5 text-green-600" />
                Dataset Validation Complete
              </>
            ) : (
              <>
                <AlertCircle className="w-5 h-5 text-red-600" />
                Validation Issues Detected
              </>
            )}
          </DialogTitle>
          <DialogDescription>
            {validation.valid
              ? "Your datasets have been analyzed and mapped to workflow inputs."
              : "Some issues were detected with your dataset configuration."}
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-4 mt-4">
          {/* Critical Issues */}
          {hasIssues && (
            <Alert variant="destructive">
              <AlertCircle className="h-4 w-4" />
              <AlertTitle>Critical Issues</AlertTitle>
              <AlertDescription>
                <ul className="list-disc list-inside mt-2 space-y-1">
                  {validation.issues.map((issue, idx) => (
                    <li key={idx} className="text-sm">{issue}</li>
                  ))}
                </ul>
              </AlertDescription>
            </Alert>
          )}

          {/* Warnings */}
          {hasWarnings && (
            <Alert>
              <AlertTriangle className="h-4 w-4" />
              <AlertTitle>Warnings</AlertTitle>
              <AlertDescription>
                <ul className="list-disc list-inside mt-2 space-y-1">
                  {validation.warnings.map((warning, idx) => (
                    <li key={idx} className="text-sm">{warning}</li>
                  ))}
                </ul>
              </AlertDescription>
            </Alert>
          )}

          {/* Suggestions */}
          {hasSuggestions && (
            <Alert>
              <Info className="h-4 w-4" />
              <AlertTitle>Suggestions</AlertTitle>
              <AlertDescription>
                <ul className="list-disc list-inside mt-2 space-y-1">
                  {validation.suggestions.map((suggestion, idx) => (
                    <li key={idx} className="text-sm">{suggestion}</li>
                  ))}
                </ul>
              </AlertDescription>
            </Alert>
          )}

          {/* Dataset Mappings */}
          {validation.mappings.length > 0 && (
            <div className="border rounded-lg p-4">
              <h4 className="font-semibold mb-3 flex items-center gap-2">
                <CheckCircle2 className="w-4 h-4 text-green-600" />
                Proposed Dataset Mappings
              </h4>
              <div className="space-y-3">
                {validation.mappings.map((mapping, idx) => (
                  <div
                    key={idx}
                    className="flex items-start gap-3 p-3 bg-muted/50 rounded-md"
                  >
                    <div className="flex-1">
                      <div className="flex items-center gap-2 mb-1">
                        <span className="text-sm font-medium">
                          {mapping.dataset_id}
                        </span>
                        <span className="text-muted-foreground">→</span>
                        <span className="text-sm text-muted-foreground">
                          {mapping.input_name}
                        </span>
                        <Badge
                          variant={
                            mapping.confidence === 'high'
                              ? 'default'
                              : mapping.confidence === 'medium'
                              ? 'secondary'
                              : 'outline'
                          }
                          className={
                            mapping.confidence === 'high'
                              ? 'bg-green-100 text-green-700 border-green-200'
                              : mapping.confidence === 'medium'
                              ? 'bg-blue-100 text-blue-700 border-blue-200'
                              : 'bg-yellow-100 text-yellow-700 border-yellow-200'
                          }
                        >
                          {mapping.confidence} confidence
                        </Badge>
                      </div>
                      <p className="text-xs text-muted-foreground">
                        {mapping.reasoning}
                      </p>
                    </div>
                  </div>
                ))}
              </div>
            </div>
          )}
        </div>

        <DialogFooter className="mt-6">
          {!validation.valid || hasIssues ? (
            <>
              <Button variant="outline" onClick={() => onOpenChange(false)}>
                Cancel
              </Button>
              {onEdit && (
                <Button variant="secondary" onClick={onEdit}>
                  Edit Configuration
                </Button>
              )}
            </>
          ) : (
            <>
              {onEdit && (
                <Button variant="outline" onClick={onEdit}>
                  Edit Mappings
                </Button>
              )}
              <Button onClick={onConfirm}>
                Proceed with Workflow
              </Button>
            </>
          )}
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
