/**
 * 3-Tier Parameter Dialog Component
 *
 * Displays workflow step parameters in three tiers:
 * - Essential: 3-5 critical parameters (always visible)
 * - Common: Frequently used parameters (expandable)
 * - Advanced: All other parameters (collapsed by default)
 */

import { useState } from "react"
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
import {
  Collapsible,
  CollapsibleContent,
  CollapsibleTrigger,
} from "@/components/ui/collapsible"
import { Badge } from "@/components/ui/badge"
import { ChevronDown, ChevronRight, Info } from "lucide-react"
import { cn } from "@/lib/utils"
import { type WorkflowStep } from "./workflow-step"

interface ParameterDialogProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  step: WorkflowStep | null
  onSave: (stepId: string, parameters: Record<string, any>) => void
}

// Parameter tier classification
type ParameterTier = 'essential' | 'common' | 'advanced'

interface Parameter {
  name: string
  tier: ParameterTier
  type: 'text' | 'number' | 'boolean' | 'select'
  value: any
  description?: string
  options?: string[]
  required?: boolean
  min?: number
  max?: number
}

// Mock parameter schemas for different tools
// In production, these would come from Galaxy tool definitions
const toolParameterSchemas: Record<string, Parameter[]> = {
  'FastQC': [
    { name: 'Input format', tier: 'essential', type: 'select', value: 'FASTQ', options: ['FASTQ', 'BAM', 'SAM'], required: true },
    { name: 'Quality threshold', tier: 'essential', type: 'number', value: 20, min: 0, max: 40, description: 'Minimum quality score' },
    { name: 'Adapter trimming', tier: 'essential', type: 'select', value: 'Auto-detect', options: ['Auto-detect', 'Manual', 'None'] },
    { name: 'Kmer length', tier: 'common', type: 'number', value: 7, min: 2, max: 10, description: 'K-mer length for contamination analysis' },
    { name: 'Nogroup', tier: 'common', type: 'boolean', value: false, description: 'Disable grouping of bases' },
    { name: 'Limits file', tier: 'advanced', type: 'text', value: '', description: 'Custom limits specification file' },
    { name: 'Thread count', tier: 'advanced', type: 'number', value: 1, min: 1, max: 16 },
  ],
  'HISAT2': [
    { name: 'Reference genome', tier: 'essential', type: 'select', value: 'hg38', options: ['hg38', 'hg19', 'mm10', 'mm9'], required: true },
    { name: 'Splice-aware', tier: 'essential', type: 'boolean', value: true, description: 'Enable splice-aware alignment' },
    { name: 'Max intron length', tier: 'essential', type: 'number', value: 500000, min: 1000, max: 1000000 },
    { name: 'Min intron length', tier: 'common', type: 'number', value: 20, min: 1, max: 1000 },
    { name: 'Alignment mode', tier: 'common', type: 'select', value: 'end-to-end', options: ['end-to-end', 'local'] },
    { name: 'Sensitivity', tier: 'common', type: 'select', value: 'sensitive', options: ['very-fast', 'fast', 'sensitive', 'very-sensitive'] },
    { name: 'Max mismatch', tier: 'advanced', type: 'number', value: 2, min: 0, max: 10 },
    { name: 'Soft clipping', tier: 'advanced', type: 'boolean', value: true },
    { name: 'Thread count', tier: 'advanced', type: 'number', value: 4, min: 1, max: 32 },
  ],
  'featureCounts': [
    { name: 'Annotation', tier: 'essential', type: 'select', value: 'GENCODE v40', options: ['GENCODE v40', 'GENCODE v39', 'Ensembl'], required: true },
    { name: 'Feature type', tier: 'essential', type: 'select', value: 'exon', options: ['exon', 'gene', 'transcript'] },
    { name: 'Strand specificity', tier: 'essential', type: 'select', value: 'unstranded', options: ['unstranded', 'forward', 'reverse'] },
    { name: 'Min mapping quality', tier: 'common', type: 'number', value: 10, min: 0, max: 60 },
    { name: 'Count multi-mapping', tier: 'common', type: 'boolean', value: false },
    { name: 'Paired-end counting', tier: 'common', type: 'select', value: 'fragment', options: ['fragment', 'read'] },
    { name: 'Min overlap', tier: 'advanced', type: 'number', value: 1, min: 1, max: 100 },
    { name: 'Count chimeric', tier: 'advanced', type: 'boolean', value: false },
    { name: 'Thread count', tier: 'advanced', type: 'number', value: 1, min: 1, max: 16 },
  ],
}

export function ParameterDialog({
  open,
  onOpenChange,
  step,
  onSave,
}: ParameterDialogProps) {
  const [commonExpanded, setCommonExpanded] = useState(false)
  const [advancedExpanded, setAdvancedExpanded] = useState(false)

  // Get parameter schema for the step's tool
  const parameterSchema = step ? (toolParameterSchemas[step.tool] || []) : []

  // Initialize parameter values from step or schema defaults
  const [parameters, setParameters] = useState<Record<string, any>>(() => {
    const initial: Record<string, any> = {}
    parameterSchema.forEach(param => {
      initial[param.name] = step?.parameters?.[param.name] ?? param.value
    })
    return initial
  })

  // Group parameters by tier
  const essentialParams = parameterSchema.filter(p => p.tier === 'essential')
  const commonParams = parameterSchema.filter(p => p.tier === 'common')
  const advancedParams = parameterSchema.filter(p => p.tier === 'advanced')

  const handleParameterChange = (name: string, value: any) => {
    setParameters(prev => ({ ...prev, [name]: value }))
  }

  const handleSave = () => {
    if (step) {
      onSave(step.id, parameters)
      onOpenChange(false)
    }
  }

  const renderParameter = (param: Parameter) => {
    const value = parameters[param.name]

    return (
      <div key={param.name} className="space-y-2">
        <div className="flex items-center justify-between">
          <Label htmlFor={param.name} className="text-sm font-medium flex items-center gap-2">
            {param.name}
            {param.required && <Badge variant="destructive" className="text-xs">Required</Badge>}
          </Label>
          {param.description && (
            <div className="group relative">
              <Info className="w-4 h-4 text-muted-foreground cursor-help" />
              <div className="absolute right-0 top-6 w-64 p-2 bg-popover border rounded-md shadow-lg opacity-0 invisible group-hover:opacity-100 group-hover:visible transition-all z-50">
                <p className="text-xs text-muted-foreground">{param.description}</p>
              </div>
            </div>
          )}
        </div>

        {param.type === 'text' && (
          <Input
            id={param.name}
            type="text"
            value={value}
            onChange={(e) => handleParameterChange(param.name, e.target.value)}
            placeholder={`Enter ${param.name.toLowerCase()}`}
            data-testid={`parameter-input-${param.name.toLowerCase().replace(/\s+/g, '-')}`}
          />
        )}

        {param.type === 'number' && (
          <Input
            id={param.name}
            type="number"
            value={value}
            onChange={(e) => handleParameterChange(param.name, parseFloat(e.target.value) || 0)}
            min={param.min}
            max={param.max}
            data-testid={`parameter-input-${param.name.toLowerCase().replace(/\s+/g, '-')}`}
          />
        )}

        {param.type === 'boolean' && (
          <div className="flex items-center space-x-2">
            <Switch
              id={param.name}
              checked={value}
              onCheckedChange={(checked) => handleParameterChange(param.name, checked)}
              data-testid={`parameter-input-${param.name.toLowerCase().replace(/\s+/g, '-')}`}
            />
            <Label htmlFor={param.name} className="text-sm text-muted-foreground">
              {value ? 'Enabled' : 'Disabled'}
            </Label>
          </div>
        )}

        {param.type === 'select' && (
          <Select
            value={value}
            onValueChange={(val) => handleParameterChange(param.name, val)}
          >
            <SelectTrigger id={param.name} data-testid={`parameter-input-${param.name.toLowerCase().replace(/\s+/g, '-')}`}>
              <SelectValue placeholder={`Select ${param.name.toLowerCase()}`} />
            </SelectTrigger>
            <SelectContent>
              {param.options?.map(option => (
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

  if (!step) return null

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-2xl max-h-[80vh] overflow-y-auto" data-testid="parameter-dialog">
        <DialogHeader>
          <DialogTitle>Configure {step.title}</DialogTitle>
          <DialogDescription>
            Tool: <span className="font-medium">{step.tool}</span>
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-6 py-4">
          {/* Essential Parameters - Always Visible */}
          {essentialParams.length > 0 && (
            <div className="space-y-4">
              <div className="flex items-center gap-2">
                <Badge className="bg-blue-500">Essential</Badge>
                <span className="text-sm text-muted-foreground">
                  Critical parameters required for execution
                </span>
              </div>
              <div className="space-y-4 pl-2 border-l-2 border-blue-500">
                {essentialParams.map(renderParameter)}
              </div>
            </div>
          )}

          {/* Common Parameters - Expandable */}
          {commonParams.length > 0 && (
            <Collapsible open={commonExpanded} onOpenChange={setCommonExpanded}>
              <CollapsibleTrigger asChild>
                <Button variant="ghost" className="w-full justify-between p-0 h-auto">
                  <div className="flex items-center gap-2">
                    {commonExpanded ? (
                      <ChevronDown className="w-4 h-4" />
                    ) : (
                      <ChevronRight className="w-4 h-4" />
                    )}
                    <Badge variant="outline" className="bg-green-50">Common</Badge>
                    <span className="text-sm text-muted-foreground">
                      Frequently used parameters ({commonParams.length})
                    </span>
                  </div>
                </Button>
              </CollapsibleTrigger>
              <CollapsibleContent className="mt-4">
                <div className="space-y-4 pl-2 border-l-2 border-green-500">
                  {commonParams.map(renderParameter)}
                </div>
              </CollapsibleContent>
            </Collapsible>
          )}

          {/* Advanced Parameters - Collapsed by Default */}
          {advancedParams.length > 0 && (
            <Collapsible open={advancedExpanded} onOpenChange={setAdvancedExpanded}>
              <CollapsibleTrigger asChild>
                <Button variant="ghost" className="w-full justify-between p-0 h-auto">
                  <div className="flex items-center gap-2">
                    {advancedExpanded ? (
                      <ChevronDown className="w-4 h-4" />
                    ) : (
                      <ChevronRight className="w-4 h-4" />
                    )}
                    <Badge variant="outline" className="bg-orange-50">Advanced</Badge>
                    <span className="text-sm text-muted-foreground">
                      Advanced configuration ({advancedParams.length})
                    </span>
                  </div>
                </Button>
              </CollapsibleTrigger>
              <CollapsibleContent className="mt-4">
                <div className="space-y-4 pl-2 border-l-2 border-orange-500">
                  {advancedParams.map(renderParameter)}
                </div>
              </CollapsibleContent>
            </Collapsible>
          )}

          {parameterSchema.length === 0 && (
            <div className="text-center text-muted-foreground py-8">
              No parameters available for this tool
            </div>
          )}
        </div>

        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)} data-testid="button-cancel-parameters">
            Cancel
          </Button>
          <Button onClick={handleSave} data-testid="button-save-parameters">
            Save Parameters
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
