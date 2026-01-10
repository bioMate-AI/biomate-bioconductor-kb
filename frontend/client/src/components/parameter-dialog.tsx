/**
 * Simplified Parameter Dialog Component
 *
 * Clean, flat list of parameters with inline editing.
 * Required parameters shown first, then optional ones.
 */

import { useState, useEffect } from "react"
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Switch } from "@/components/ui/switch"
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select"
import { Badge } from "@/components/ui/badge"
import { ScrollArea } from "@/components/ui/scroll-area"
import { Separator } from "@/components/ui/separator"
import { Info, Loader2, Lightbulb } from "lucide-react"
import { getSimpleToolName } from "@/lib/utils"
import { type WorkflowStep } from "./workflow-step"
import { InlineRecommendation } from "./parameter-recommendation-badge"
import type { ParameterRecommendation } from "@shared/schema"

interface ParameterDialogProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  step: WorkflowStep | null
  onSave: (stepId: string, parameters: Record<string, any>) => void
  // Parameter recommendations keyed by "tool_id:param_name"
  recommendations?: Record<string, ParameterRecommendation>
}

interface Parameter {
  name: string
  type: 'text' | 'number' | 'boolean' | 'select'
  value: any
  description?: string
  options?: string[]
  required?: boolean
  min?: number
  max?: number
}

// Map Galaxy input types to simple types
function mapInputType(galaxyType: string): 'text' | 'number' | 'boolean' | 'select' {
  if (!galaxyType) return 'text'

  const type = galaxyType.toLowerCase()

  if (type === 'boolean' || type === 'bool' || type === 'checkbox') return 'boolean'
  if (type === 'integer' || type === 'int' || type === 'float' || type === 'number') return 'number'
  if (type === 'select' || type === 'enum' || type === 'choice') return 'select'

  return 'text'
}

// Fallback parameter definitions for common tools
const toolDefaults: Record<string, Parameter[]> = {
  'FastQC': [
    { name: 'Input format', type: 'select', value: 'FASTQ', options: ['FASTQ', 'BAM', 'SAM'], required: true },
    { name: 'Quality threshold', type: 'number', value: 20, min: 0, max: 40 },
  ],
  'HISAT2': [
    { name: 'Reference genome', type: 'select', value: 'hg38', options: ['hg38', 'hg19', 'mm10'], required: true },
    { name: 'Splice-aware', type: 'boolean', value: true },
  ],
}

export function ParameterDialog({
  open,
  onOpenChange,
  step,
  onSave,
  recommendations = {},
}: ParameterDialogProps) {
  const [parameters, setParameters] = useState<Record<string, any>>({})
  const [parameterSchema, setParameterSchema] = useState<Parameter[]>([])
  const [loading, setLoading] = useState(false)
  const [appliedRecs, setAppliedRecs] = useState<Set<string>>(new Set())

  // Get recommendation for a parameter
  const getRecommendation = (paramName: string): ParameterRecommendation | undefined => {
    const key = step?.tool ? `${step.tool}:${paramName}` : paramName
    return recommendations[key] || recommendations[paramName]
  }

  // Apply a recommendation
  const applyRecommendation = (paramName: string, value: any) => {
    handleChange(paramName, value)
    setAppliedRecs(prev => new Set(prev).add(paramName))
  }

  // Apply all recommendations
  const applyAllRecommendations = () => {
    parameterSchema.forEach(param => {
      const rec = getRecommendation(param.name)
      if (rec) {
        handleChange(param.name, rec.recommended_value)
        setAppliedRecs(prev => new Set(prev).add(param.name))
      }
    })
  }

  // Count available recommendations
  const recommendationCount = parameterSchema.filter(p => getRecommendation(p.name)).length

  // Fetch or build parameter schema when step changes
  useEffect(() => {
    if (!step?.tool) {
      setParameterSchema([])
      return
    }

    const fetchSchema = async () => {
      setLoading(true)

      try {
        // Try to fetch from Galaxy API
        const response = await fetch(`/api/galaxy/tools/${encodeURIComponent(step.tool)}/schema`)

        if (response.ok) {
          const data = await response.json()

          if (data.inputs && Array.isArray(data.inputs)) {
            const schema: Parameter[] = data.inputs.map((input: any) => ({
              name: input.name || input.label || 'Unknown',
              type: mapInputType(input.type),
              value: input.value ?? input.default ?? '',
              description: input.help || input.description,
              options: input.options?.map((o: any) => o.value || o) || undefined,
              required: input.optional === false,
              min: input.min,
              max: input.max,
            }))

            setParameterSchema(schema)
            setLoading(false)
            return
          }
        }
      } catch (error) {
        console.log('[ParameterDialog] API fetch failed, using fallbacks')
      }

      // Use fallback or build from existing parameters
      const toolName = getSimpleToolName(step.tool)
      const fallback = toolDefaults[toolName] || []

      // Build schema from existing step parameters if available
      if (step.parameters && Object.keys(step.parameters).length > 0) {
        const fromParams: Parameter[] = Object.entries(step.parameters).map(([key, value]) => ({
          name: key,
          type: typeof value === 'boolean' ? 'boolean' : typeof value === 'number' ? 'number' : 'text',
          value: value,
          required: false,
        }))
        setParameterSchema(fromParams.length > 0 ? fromParams : fallback)
      } else {
        setParameterSchema(fallback)
      }

      setLoading(false)
    }

    fetchSchema()
  }, [step?.tool])

  // Initialize parameters from step or schema
  useEffect(() => {
    const initial: Record<string, any> = {}
    parameterSchema.forEach(param => {
      initial[param.name] = step?.parameters?.[param.name] ?? param.value
    })
    setParameters(initial)
  }, [parameterSchema, step?.parameters])

  const handleChange = (name: string, value: any) => {
    setParameters(prev => ({ ...prev, [name]: value }))
  }

  const handleSave = () => {
    if (step) {
      onSave(step.id, parameters)
      onOpenChange(false)
    }
  }

  // Separate required and optional parameters
  const requiredParams = parameterSchema.filter(p => p.required)
  const optionalParams = parameterSchema.filter(p => !p.required)

  if (!step) return null

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-lg">
        <DialogHeader>
          <div className="flex items-center justify-between">
            <DialogTitle className="flex items-center gap-2">
              Configure Step
            </DialogTitle>
            {recommendationCount > 0 && (
              <Button
                variant="outline"
                size="sm"
                className="h-7 text-xs"
                onClick={applyAllRecommendations}
              >
                <Lightbulb className="h-3 w-3 mr-1" />
                Apply All ({recommendationCount})
              </Button>
            )}
          </div>
          <DialogDescription>
            {step.title || getSimpleToolName(step.tool)}
          </DialogDescription>
        </DialogHeader>

        <ScrollArea className="max-h-[60vh] pr-4">
          {loading ? (
            <div className="flex items-center justify-center py-8">
              <Loader2 className="h-6 w-6 animate-spin text-muted-foreground" />
            </div>
          ) : parameterSchema.length === 0 ? (
            <p className="text-sm text-muted-foreground text-center py-8">
              No configurable parameters for this step.
            </p>
          ) : (
            <div className="space-y-4">
              {/* Required Parameters */}
              {requiredParams.length > 0 && (
                <>
                  <div className="flex items-center gap-2 text-sm text-muted-foreground">
                    <Badge variant="destructive" className="text-xs">Required</Badge>
                    <span>{requiredParams.length} parameter{requiredParams.length > 1 ? 's' : ''}</span>
                  </div>
                  {requiredParams.map(param => (
                    <ParameterInput
                      key={param.name}
                      param={param}
                      value={parameters[param.name]}
                      onChange={(value) => handleChange(param.name, value)}
                      recommendation={getRecommendation(param.name)}
                      onApplyRecommendation={(value) => applyRecommendation(param.name, value)}
                      isRecommendationApplied={appliedRecs.has(param.name)}
                    />
                  ))}
                </>
              )}

              {/* Optional Parameters */}
              {optionalParams.length > 0 && (
                <>
                  {requiredParams.length > 0 && <Separator className="my-4" />}
                  <div className="text-sm text-muted-foreground">
                    Optional ({optionalParams.length})
                  </div>
                  {optionalParams.map(param => (
                    <ParameterInput
                      key={param.name}
                      param={param}
                      value={parameters[param.name]}
                      onChange={(value) => handleChange(param.name, value)}
                      recommendation={getRecommendation(param.name)}
                      onApplyRecommendation={(value) => applyRecommendation(param.name, value)}
                      isRecommendationApplied={appliedRecs.has(param.name)}
                    />
                  ))}
                </>
              )}
            </div>
          )}
        </ScrollArea>

        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)}>
            Cancel
          </Button>
          <Button onClick={handleSave}>
            Save Changes
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}

// Individual parameter input component
function ParameterInput({
  param,
  value,
  onChange,
  recommendation,
  onApplyRecommendation,
  isRecommendationApplied = false
}: {
  param: Parameter
  value: any
  onChange: (value: any) => void
  recommendation?: ParameterRecommendation
  onApplyRecommendation?: (value: any) => void
  isRecommendationApplied?: boolean
}) {
  return (
    <div className="space-y-1.5">
      <div className="flex items-center justify-between">
        <Label htmlFor={param.name} className="text-sm">
          {param.name}
        </Label>
        <div className="flex items-center gap-2">
          {recommendation && (
            <InlineRecommendation
              recommendation={recommendation}
              onApply={onApplyRecommendation}
              isApplied={isRecommendationApplied}
            />
          )}
          {param.description && (
            <div className="group relative">
              <Info className="w-3.5 h-3.5 text-muted-foreground cursor-help" />
              <div className="absolute right-0 top-5 w-56 p-2 bg-popover border rounded-md shadow-lg opacity-0 invisible group-hover:opacity-100 group-hover:visible transition-all z-50 text-xs">
                {param.description}
              </div>
            </div>
          )}
        </div>
      </div>

      {param.type === 'text' && (
        <Input
          id={param.name}
          value={value || ''}
          onChange={(e) => onChange(e.target.value)}
          className="h-9"
        />
      )}

      {param.type === 'number' && (
        <Input
          id={param.name}
          type="number"
          value={value ?? ''}
          onChange={(e) => onChange(parseFloat(e.target.value) || 0)}
          min={param.min}
          max={param.max}
          className="h-9"
        />
      )}

      {param.type === 'boolean' && (
        <div className="flex items-center gap-2">
          <Switch
            id={param.name}
            checked={!!value}
            onCheckedChange={onChange}
          />
          <span className="text-xs text-muted-foreground">
            {value ? 'Enabled' : 'Disabled'}
          </span>
        </div>
      )}

      {param.type === 'select' && param.options && (
        <Select value={value || ''} onValueChange={onChange}>
          <SelectTrigger className="h-9">
            <SelectValue placeholder="Select..." />
          </SelectTrigger>
          <SelectContent>
            {param.options.map(option => (
              <SelectItem key={option} value={option}>
                {option}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
      )}
    </div>
  )
}
