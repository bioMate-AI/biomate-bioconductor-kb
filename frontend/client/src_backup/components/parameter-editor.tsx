import { useState, useEffect } from "react"
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter, DialogDescription } from "@/components/ui/dialog"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Switch } from "@/components/ui/switch"
import { Textarea } from "@/components/ui/textarea"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { Loader2, Settings, Package, Sparkles } from "lucide-react"
import { Badge } from "@/components/ui/badge"
import { Separator } from "@/components/ui/separator"
import type { ToolParameter, ToolSchema, ParameterTemplate } from "@shared/galaxy-types"

interface ParameterEditorProps {
  isOpen: boolean
  onClose: () => void
  toolId: string
  toolName: string
  currentParameters?: Record<string, any>
  onSave: (parameters: Record<string, any>) => void
}

export function ParameterEditor({
  isOpen,
  onClose,
  toolId,
  toolName,
  currentParameters = {},
  onSave
}: ParameterEditorProps) {
  const [parameters, setParameters] = useState<Record<string, any>>(currentParameters)
  const [toolSchema, setToolSchema] = useState<ToolSchema | null>(null)
  const [templates, setTemplates] = useState<ParameterTemplate[]>([])
  const [selectedTemplate, setSelectedTemplate] = useState<string | null>(null)
  const [loading, setLoading] = useState(false)
  const [loadingTemplates, setLoadingTemplates] = useState(false)
  const [error, setError] = useState<string | null>(null)

  // Fetch tool schema and templates from API
  useEffect(() => {
    if (isOpen && toolId) {
      fetchToolSchema()
      fetchParameterTemplates()
    }
  }, [isOpen, toolId])

  const fetchToolSchema = async () => {
    setLoading(true)
    setError(null)
    try {
      const response = await fetch(`/api/galaxy/tools/${encodeURIComponent(toolId)}/schema`)
      if (!response.ok) {
        throw new Error(`Failed to fetch tool schema: ${response.statusText}`)
      }
      const schema: ToolSchema = await response.json()
      setToolSchema(schema)

      // Initialize parameters with defaults
      const defaultParams: Record<string, any> = {}
      schema.inputs.forEach(input => {
        if (currentParameters[input.name] !== undefined) {
          defaultParams[input.name] = currentParameters[input.name]
        } else if (input.value !== undefined) {
          defaultParams[input.name] = input.value
        }
      })
      setParameters(defaultParams)
    } catch (err: any) {
      console.error('[ParameterEditor] Failed to fetch tool schema:', err)
      setError(err.message || 'Failed to load tool parameters')
    } finally {
      setLoading(false)
    }
  }

  const fetchParameterTemplates = async () => {
    setLoadingTemplates(true)
    try {
      const response = await fetch(`/api/parameter-templates/tool/${encodeURIComponent(toolId)}`)
      if (response.ok) {
        const data = await response.json()
        setTemplates(data.templates || [])
        console.log(`[ParameterEditor] Loaded ${data.templates?.length || 0} templates for ${toolId}`)
      }
    } catch (err: any) {
      console.error('[ParameterEditor] Failed to fetch parameter templates:', err)
      // Don't show error for templates - they're optional
    } finally {
      setLoadingTemplates(false)
    }
  }

  const applyTemplate = (template: ParameterTemplate) => {
    console.log(`[ParameterEditor] Applying template: ${template.use_case.name}`)
    setParameters({ ...template.parameters })
    setSelectedTemplate(template.id)
  }

  const handleSave = () => {
    onSave(parameters)
    onClose()
  }

  const renderParameterInput = (input: ToolParameter) => {
    const value = parameters[input.name]
    
    switch (input.type) {
      case 'text':
        return (
          <Input
            value={value || ''}
            onChange={(e) => setParameters({ ...parameters, [input.name]: e.target.value })}
            placeholder={input.help || ''}
          />
        )
      
      case 'integer':
      case 'float':
        return (
          <Input
            type="number"
            value={value || ''}
            onChange={(e) => setParameters({ ...parameters, [input.name]: input.type === 'integer' ? parseInt(e.target.value) : parseFloat(e.target.value) })}
            min={input.min}
            max={input.max}
            step={input.type === 'float' ? '0.01' : '1'}
          />
        )
      
      case 'boolean':
        return (
          <div className="flex items-center space-x-2">
            <Switch
              checked={!!value}
              onCheckedChange={(checked) => setParameters({ ...parameters, [input.name]: checked })}
            />
            <span className="text-sm text-muted-foreground">{value ? 'Enabled' : 'Disabled'}</span>
          </div>
        )
      
      case 'select':
        return (
          <Select
            value={value || ''}
            onValueChange={(val) => setParameters({ ...parameters, [input.name]: val })}
          >
            <SelectTrigger>
              <SelectValue placeholder={`Select ${input.label}`} />
            </SelectTrigger>
            <SelectContent>
              {input.options?.map((option) => (
                <SelectItem key={option.value} value={option.value}>
                  {option.label}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        )
      
      default:
        return (
          <Textarea
            value={value || ''}
            onChange={(e) => setParameters({ ...parameters, [input.name]: e.target.value })}
            placeholder={input.help || ''}
            className="min-h-[80px]"
          />
        )
    }
  }

  return (
    <Dialog open={isOpen} onOpenChange={onClose}>
      <DialogContent className="max-w-3xl max-h-[85vh] overflow-hidden flex flex-col">
        <DialogHeader>
          <div className="flex items-center gap-2">
            <Settings className="w-5 h-5" />
            <DialogTitle>Configure Parameters</DialogTitle>
          </div>
          <DialogDescription>
            {toolName} • Tool ID: {toolId}
          </DialogDescription>
        </DialogHeader>

        <Tabs defaultValue="configure" className="flex-1 overflow-hidden flex flex-col">
          <TabsList className="grid w-full grid-cols-2">
            <TabsTrigger value="configure">
              <Settings className="w-4 h-4 mr-2" />
              Configure
            </TabsTrigger>
            <TabsTrigger value="templates">
              <Package className="w-4 h-4 mr-2" />
              Templates {templates.length > 0 && `(${templates.length})`}
            </TabsTrigger>
          </TabsList>

          <TabsContent value="configure" className="flex-1 overflow-y-auto mt-4">
            {loading && (
              <div className="flex items-center justify-center py-8">
                <Loader2 className="w-6 h-6 animate-spin" />
                <span className="ml-2">Loading tool parameters...</span>
              </div>
            )}

            {error && (
              <div className="bg-destructive/10 text-destructive px-4 py-3 rounded-md">
                <p className="text-sm">{error}</p>
              </div>
            )}

            {toolSchema && !loading && (
              <div className="space-y-4 pr-2">
                {toolSchema.inputs.map((input) => (
                  <div key={input.name} className="space-y-2">
                    <div className="flex items-start justify-between gap-4">
                      <Label htmlFor={input.name} className="flex-shrink-0">
                        {input.label}
                        {!input.optional && <span className="text-destructive ml-1">*</span>}
                      </Label>
                      {input.help && (
                        <span className="text-xs text-muted-foreground text-right">
                          {input.help}
                        </span>
                      )}
                    </div>
                    {renderParameterInput(input)}
                  </div>
                ))}
              </div>
            )}
          </TabsContent>

          <TabsContent value="templates" className="flex-1 overflow-y-auto mt-4">
            {loadingTemplates && (
              <div className="flex items-center justify-center py-8">
                <Loader2 className="w-6 h-6 animate-spin" />
                <span className="ml-2">Loading templates...</span>
              </div>
            )}

            {!loadingTemplates && templates.length === 0 && (
              <div className="text-center py-8 text-muted-foreground">
                <Package className="w-12 h-12 mx-auto mb-4 opacity-50" />
                <p>No parameter templates available for this tool yet.</p>
                <p className="text-sm mt-2">Create one by saving your current parameters!</p>
              </div>
            )}

            {!loadingTemplates && templates.length > 0 && (
              <div className="space-y-3 pr-2">
                {templates.map((template) => (
                  <div
                    key={template.id}
                    className={`border rounded-lg p-4 cursor-pointer transition-colors hover:border-primary ${
                      selectedTemplate === template.id ? 'border-primary bg-primary/5' : ''
                    }`}
                    onClick={() => applyTemplate(template)}
                  >
                    <div className="flex items-start justify-between gap-4">
                      <div className="flex-1">
                        <div className="flex items-center gap-2 mb-2">
                          <h4 className="font-medium">{template.use_case.name}</h4>
                          {template.validated && (
                            <Badge variant="outline" className="bg-green-50 text-green-700 border-green-200">
                              <Sparkles className="w-3 h-3 mr-1" />
                              Validated
                            </Badge>
                          )}
                        </div>
                        <p className="text-sm text-muted-foreground mb-3">
                          {template.use_case.description}
                        </p>
                        {template.rationale && (
                          <p className="text-xs text-muted-foreground italic">
                            {template.rationale}
                          </p>
                        )}
                        <div className="flex flex-wrap gap-1 mt-2">
                          {template.use_case.tags.map((tag) => (
                            <Badge key={tag} variant="secondary" className="text-xs">
                              {tag}
                            </Badge>
                          ))}
                        </div>
                        {template.use_case.usage_count! > 0 && (
                          <div className="text-xs text-muted-foreground mt-2">
                            Used {template.use_case.usage_count} times •{' '}
                            {Math.round((template.use_case.success_rate || 0) * 100)}% success rate
                          </div>
                        )}
                      </div>
                      <Button
                        size="sm"
                        variant={selectedTemplate === template.id ? 'default' : 'outline'}
                        onClick={(e) => {
                          e.stopPropagation()
                          applyTemplate(template)
                        }}
                      >
                        {selectedTemplate === template.id ? 'Applied' : 'Apply'}
                      </Button>
                    </div>
                  </div>
                ))}
              </div>
            )}
          </TabsContent>
        </Tabs>

        <Separator className="my-4" />

        <DialogFooter>
          <Button variant="outline" onClick={onClose}>
            Cancel
          </Button>
          <Button onClick={handleSave} disabled={loading || !!error}>
            Save Parameters
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
