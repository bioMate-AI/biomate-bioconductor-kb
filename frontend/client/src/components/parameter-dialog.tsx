/**
 * 3-Tier Parameter Dialog Component
 *
 * Displays workflow step parameters in three tiers:
 * - Essential: 3-5 critical parameters (always visible)
 * - Common: Frequently used parameters (expandable)
 * - Advanced: All other parameters (collapsed by default)
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
import {
  Collapsible,
  CollapsibleContent,
  CollapsibleTrigger,
} from "@/components/ui/collapsible"
import { Badge } from "@/components/ui/badge"
import { ChevronDown, ChevronRight, Info } from "lucide-react"
import { cn, getSimpleToolName } from "@/lib/utils"
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

// Helper function to determine parameter tier based on Galaxy input metadata
function determineTier(input: any): ParameterTier {
  // Check for explicit tier marking in input metadata
  if (input.tier) {
    return input.tier as ParameterTier
  }

  // Essential tier: required parameters, common dataset inputs, critical configuration
  if (input.optional === false || input.required === true) {
    return 'essential'
  }

  const name = (input.name || input.label || '').toLowerCase()
  const description = (input.help || input.description || '').toLowerCase()

  // Essential: Reference genomes, input files, main tool settings
  if (name.includes('reference') || name.includes('genome') ||
      name.includes('input') || name.includes('annotation') ||
      name.includes('format') || name.includes('mode')) {
    return 'essential'
  }

  // Common: Quality thresholds, alignment settings, frequently used options
  if (name.includes('quality') || name.includes('threshold') ||
      name.includes('min') || name.includes('max') ||
      name.includes('sensitivity') || name.includes('strand') ||
      description.includes('commonly') || description.includes('frequently')) {
    return 'common'
  }

  // Advanced: Thread counts, advanced options, rarely changed settings
  if (name.includes('thread') || name.includes('cpu') ||
      name.includes('advanced') || name.includes('debug') ||
      description.includes('advanced') || description.includes('expert')) {
    return 'advanced'
  }

  // Default to common tier
  return 'common'
}

// Helper function to map Galaxy input types to parameter dialog types
function mapInputType(galaxyType: string): 'text' | 'number' | 'boolean' | 'select' {
  if (!galaxyType) {
    return 'text'
  }

  const type = galaxyType.toLowerCase()

  // Boolean types
  if (type === 'boolean' || type === 'bool' || type === 'checkbox') {
    return 'boolean'
  }

  // Number types
  if (type === 'integer' || type === 'int' || type === 'float' ||
      type === 'number' || type === 'decimal') {
    return 'number'
  }

  // Select types
  if (type === 'select' || type === 'enum' || type === 'choice' ||
      type === 'dropdown' || type === 'radio') {
    return 'select'
  }

  // Default to text for data, text, string, file, etc.
  return 'text'
}

// Helper function to get default value based on input type
function getDefaultValue(galaxyType: string): any {
  if (!galaxyType) {
    return ''
  }

  const type = galaxyType.toLowerCase()

  if (type === 'boolean' || type === 'bool' || type === 'checkbox') {
    return false
  }

  if (type === 'integer' || type === 'int' || type === 'float' ||
      type === 'number' || type === 'decimal') {
    return 0
  }

  if (type === 'select' || type === 'enum' || type === 'choice') {
    return ''
  }

  // Default to empty string for text types
  return ''
}

// Schema cache to avoid repeated API calls
const schemaCache = new Map<string, {
  schema: Parameter[] | null
  timestamp: number
  ttl: number // Time to live in milliseconds
}>()

const SCHEMA_CACHE_TTL = 5 * 60 * 1000 // 5 minutes

// Mock parameter schemas for different tools (fallback only)
// These are only used if API fails or tool not found
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
  'DESeq2': [
    { name: 'Design formula', tier: 'essential', type: 'text', value: '~ condition', required: true, description: 'Experimental design (e.g., ~ condition or ~ batch + condition)' },
    { name: 'Reference level', tier: 'essential', type: 'text', value: 'control', required: true, description: 'Control/reference condition name' },
    { name: 'Test type', tier: 'essential', type: 'select', value: 'Wald', options: ['Wald', 'LRT'], description: 'Statistical test to use' },
    { name: 'Alpha', tier: 'common', type: 'number', value: 0.05, min: 0.001, max: 0.5, description: 'Adjusted p-value cutoff for significance' },
    { name: 'Log2 fold change threshold', tier: 'common', type: 'number', value: 0, min: 0, max: 5, description: 'Minimum log2 fold change for significance' },
    { name: 'Independent filtering', tier: 'common', type: 'boolean', value: true, description: 'Filter genes with low counts automatically' },
    { name: 'Cook\'s cutoff', tier: 'common', type: 'boolean', value: true, description: 'Remove outliers using Cook\'s distance' },
    { name: 'Fit type', tier: 'advanced', type: 'select', value: 'parametric', options: ['parametric', 'local', 'mean'], description: 'Method for fitting dispersion' },
    { name: 'Outlier replacement', tier: 'advanced', type: 'boolean', value: true, description: 'Replace outliers with trimmed mean' },
    { name: 'Shrinkage method', tier: 'advanced', type: 'select', value: 'apeglm', options: ['apeglm', 'ashr', 'normal', 'none'], description: 'LFC shrinkage estimator' },
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
  const [parameterSchema, setParameterSchema] = useState<Parameter[]>([])
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  // Fetch parameter schema from API when step changes (with caching)
  useEffect(() => {
    if (!step || !step.tool) {
      setParameterSchema([])
      return
    }

    // Fetch schema from API (primary method)
    const fetchSchema = async () => {
      // Check cache first
      const cached = schemaCache.get(step.tool)
      if (cached && (Date.now() - cached.timestamp) < cached.ttl) {
        console.log(`[ParameterDialog] Using cached schema for ${step.tool}`)
        setParameterSchema(cached.schema || [])
        setError(null)
        setLoading(false)
        return
      }

      setLoading(true)
      setError(null)

      try {
        console.log(`[ParameterDialog] Fetching schema for tool: ${step.tool}`)
        // Don't encode the tool ID - the route expects it as path segments
        // For tool IDs with slashes (e.g., "toolshed.g2.bx.psu.edu/repos/devteam/fastqc/fastqc/0.72")
        const response = await fetch(`/api/galaxy/tools/${step.tool}/schema`)

        if (!response.ok) {
          console.warn(`[ParameterDialog] API returned ${response.status} for ${step.tool}`)

          // Fallback to hardcoded schema if API fails
          const hardcodedSchema = toolParameterSchemas[step.tool]
          if (hardcodedSchema) {
            console.log(`[ParameterDialog] Using hardcoded fallback schema for ${step.tool}`)

            // Cache the fallback schema (shorter TTL for fallbacks)
            schemaCache.set(step.tool, {
              schema: hardcodedSchema,
              timestamp: Date.now(),
              ttl: 60 * 1000 // 1 minute for fallback schemas
            })

            setParameterSchema(hardcodedSchema)
            setError(null)
          } else {
            // Cache 404 responses to avoid repeated requests
            if (response.status === 404) {
              schemaCache.set(step.tool, {
                schema: null,
                timestamp: Date.now(),
                ttl: 2 * 60 * 1000 // 2 minutes for 404s
              })
            }

            setParameterSchema([])
            // Don't show error for 404 - just means schema not available, which is expected
            if (response.status !== 404) {
              setError(`Schema not available (API returned ${response.status})`)
            } else {
              setError(null)
            }
          }
          return
        }

        const data = await response.json()
        console.log(`[ParameterDialog] Received schema for ${step.tool}:`, data)

        // Transform API response to Parameter[] format
        if (data.inputs && Array.isArray(data.inputs)) {
          const transformedParams: Parameter[] = data.inputs.map((input: any) => ({
            name: input.name || input.label || 'unknown',
            tier: determineTier(input),
            type: mapInputType(input.type),
            value: input.value || input.default || getDefaultValue(input.type),
            description: input.help || input.description || '',
            options: input.options || [],
            required: input.optional === false,
            min: input.min,
            max: input.max
          }))

          // Cache the schema
          schemaCache.set(step.tool, {
            schema: transformedParams,
            timestamp: Date.now(),
            ttl: SCHEMA_CACHE_TTL
          })

          setParameterSchema(transformedParams)
          setError(null)
        } else {
          setParameterSchema([])
          setError('Invalid schema format received from API')
        }
      } catch (err) {
        console.error(`[ParameterDialog] Error fetching schema for ${step.tool}:`, err)

        // Fallback to hardcoded schema on network error
        const hardcodedSchema = toolParameterSchemas[step.tool]
        if (hardcodedSchema) {
          console.log(`[ParameterDialog] Using hardcoded fallback schema for ${step.tool} after error`)

          // Cache the fallback schema (shorter TTL for fallbacks)
          schemaCache.set(step.tool, {
            schema: hardcodedSchema,
            timestamp: Date.now(),
            ttl: 60 * 1000 // 1 minute for fallback schemas
          })

          setParameterSchema(hardcodedSchema)
          setError(null)
        } else {
          // Cache the failure to avoid repeated network errors
          schemaCache.set(step.tool, {
            schema: null,
            timestamp: Date.now(),
            ttl: 30 * 1000 // 30 seconds for network errors
          })

          setParameterSchema([])
          setError(`Failed to load parameters: ${err instanceof Error ? err.message : 'Unknown error'}`)
        }
      } finally {
        setLoading(false)
      }
    }

    fetchSchema()
  }, [step?.tool])

  // Initialize parameter values from step or schema defaults
  const [parameters, setParameters] = useState<Record<string, any>>(() => {
    const initial: Record<string, any> = {}
    parameterSchema.forEach(param => {
      initial[param.name] = step?.parameters?.[param.name] ?? param.value
    })
    return initial
  })

  // Update parameters when schema changes
  useEffect(() => {
    const updated: Record<string, any> = {}
    parameterSchema.forEach(param => {
      updated[param.name] = step?.parameters?.[param.name] ?? param.value
    })
    setParameters(updated)
  }, [parameterSchema, step?.parameters])

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
          />
        )}

        {param.type === 'boolean' && (
          <div className="flex items-center space-x-2">
            <Switch
              id={param.name}
              checked={value}
              onCheckedChange={(checked) => handleParameterChange(param.name, checked)}
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
            <SelectTrigger id={param.name}>
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
      <DialogContent className="max-w-2xl max-h-[80vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>Configure {step.title}</DialogTitle>
          <DialogDescription>
            Tool: <span className="font-medium">{getSimpleToolName(step.tool)}</span>
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

          {loading && (
            <div className="text-center text-muted-foreground py-8">
              <div className="animate-spin w-8 h-8 border-4 border-primary border-t-transparent rounded-full mx-auto mb-2" />
              Loading parameters...
            </div>
          )}

          {!loading && error && (
            <div className="text-center py-8">
              <div className="text-yellow-600 mb-2">⚠️ {error}</div>
              <div className="text-sm text-muted-foreground">
                Schema may not be available for this tool yet.
                {step && step.tool && (
                  <div className="mt-2 text-xs">Tool: {getSimpleToolName(step.tool)}</div>
                )}
              </div>
            </div>
          )}

          {!loading && !error && parameterSchema.length === 0 && (
            <div className="text-center text-muted-foreground py-8">
              No parameters available for this tool
            </div>
          )}
        </div>

        <DialogFooter>
          <Button
            variant="outline"
            onClick={() => onOpenChange(false)}
            data-testid="parameter-dialog-cancel"
          >
            Cancel
          </Button>
          <Button
            onClick={handleSave}
            data-testid="parameter-dialog-save"
          >
            Save Parameters
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
