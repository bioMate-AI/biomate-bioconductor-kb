import { useState } from "react"
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription } from "@/components/ui/dialog"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Badge } from "@/components/ui/badge"
import { X } from "lucide-react"
import { projectService } from "@/lib/projects"
import { PROJECT_TEMPLATES, type ProjectTemplate } from "@/lib/project-templates"
import type { CreateProject } from "@shared/schema"

interface CreateProjectDialogProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  onProjectCreated?: (projectId: string) => void
}

const projectCategories = [
  "Bioinformatics",
  "Genomics", 
  "Proteomics",
  "Healthcare",
  "Research",
  "Data Analysis",
  "Machine Learning",
  "Other"
]

export function CreateProjectDialog({
  open,
  onOpenChange,
  onProjectCreated
}: CreateProjectDialogProps) {
  const [selectedTemplate, setSelectedTemplate] = useState<ProjectTemplate | null>(null)
  const [name, setName] = useState("")
  const [description, setDescription] = useState("")
  const [instructions, setInstructions] = useState("")
  const [category, setCategory] = useState("")
  const [tags, setTags] = useState<string[]>([])
  const [currentTag, setCurrentTag] = useState("")
  const [isSubmitting, setIsSubmitting] = useState(false)
  const [errors, setErrors] = useState<Record<string, string>>({})

  const applyTemplate = (template: ProjectTemplate | null) => {
    if (!template) {
      setSelectedTemplate(null)
      setName("")
      setDescription("")
      setInstructions("")
      setCategory("")
      setTags([])
      return
    }
    if (selectedTemplate?.id === template.id) {
      applyTemplate(null)
      return
    }
    setSelectedTemplate(template)
    setName(template.name)
    setDescription(template.description)
    setInstructions(template.researchGoal)
    setCategory(template.category)
    setTags(template.tags)
  }

  const handleAddTag = () => {
    const trimmedTag = currentTag.trim()
    if (trimmedTag && !tags.includes(trimmedTag)) {
      setTags([...tags, trimmedTag])
      setCurrentTag("")
    }
  }

  const handleRemoveTag = (tagToRemove: string) => {
    setTags(tags.filter(tag => tag !== tagToRemove))
  }

  const handleKeyPress = (e: React.KeyboardEvent) => {
    if (e.key === 'Enter') {
      e.preventDefault()
      handleAddTag()
    }
  }

  const validateForm = (): boolean => {
    const newErrors: Record<string, string> = {}
    
    if (!name.trim()) {
      newErrors.name = "Project name is required"
    }
    
    setErrors(newErrors)
    return Object.keys(newErrors).length === 0
  }

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    
    if (!validateForm()) return
    
    setIsSubmitting(true)
    
    try {
      const res = await fetch('/api/projects', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        credentials: 'include',
        body: JSON.stringify({
          name: name.trim(),
          description: description.trim() || undefined,
          researchGoal: instructions.trim() || undefined,
          category: category || undefined,
          tags: tags.length > 0 ? tags : undefined,
        }),
      })
      const data = await res.json()
      if (!res.ok) throw new Error(data.error || 'Failed to create project')

      // Reset form
      setName("")
      setDescription("")
      setInstructions("")
      setCategory("")
      setTags([])
      setCurrentTag("")
      setErrors({})

      onOpenChange(false)
      // Signal sidebar + any other listener to refresh the projects list
      window.dispatchEvent(new CustomEvent('biomate:projects-updated'))
      // Backend returns the project object directly (not wrapped in { project: ... })
      onProjectCreated?.(data.id || data.project?.id)

    } catch (error) {
      console.error('Error creating project:', error)
      setErrors({ submit: error instanceof Error ? error.message : "Failed to create project. Please try again." })
    } finally {
      setIsSubmitting(false)
    }
  }

  const handleCancel = () => {
    setSelectedTemplate(null)
    setName("")
    setDescription("")
    setInstructions("")
    setCategory("")
    setTags([])
    setCurrentTag("")
    setErrors({})
    onOpenChange(false)
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-2xl max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>Create a new project</DialogTitle>
          <DialogDescription>
            Set up a new project with its own chat history, documents, and background context.
          </DialogDescription>
        </DialogHeader>

        <form onSubmit={handleSubmit} className="space-y-6">
          {/* Template picker */}
          <div className="space-y-2">
            <Label className="text-sm font-medium">Start from a template</Label>
            <div className="flex flex-wrap gap-2">
              {/* Blank option */}
              <button
                type="button"
                onClick={() => applyTemplate(null)}
                data-testid="template-blank"
                style={{
                  width: 110, minHeight: 72, padding: '8px 10px',
                  borderRadius: 8, border: `1.5px solid ${!selectedTemplate ? 'hsl(var(--primary))' : 'hsl(var(--border))'}`,
                  background: !selectedTemplate ? 'hsl(var(--accent))' : 'transparent',
                  cursor: 'pointer', display: 'flex', flexDirection: 'column',
                  alignItems: 'center', justifyContent: 'center', gap: 4,
                  outline: !selectedTemplate ? '2px solid hsl(var(--primary))' : 'none',
                  outlineOffset: 2,
                }}
              >
                <span style={{ fontSize: 20 }}>📄</span>
                <span style={{ fontSize: 11, fontWeight: 500, textAlign: 'center', lineHeight: 1.2 }}>Blank</span>
              </button>

              {PROJECT_TEMPLATES.map((tpl) => (
                <button
                  key={tpl.id}
                  type="button"
                  onClick={() => applyTemplate(tpl)}
                  data-testid={`template-${tpl.id}`}
                  title={tpl.description}
                  style={{
                    width: 110, minHeight: 72, padding: '8px 10px',
                    borderRadius: 8, border: `1.5px solid ${selectedTemplate?.id === tpl.id ? 'hsl(var(--primary))' : 'hsl(var(--border))'}`,
                    background: selectedTemplate?.id === tpl.id ? 'hsl(var(--accent))' : 'transparent',
                    cursor: 'pointer', display: 'flex', flexDirection: 'column',
                    alignItems: 'center', justifyContent: 'center', gap: 4,
                    outline: selectedTemplate?.id === tpl.id ? '2px solid hsl(var(--primary))' : 'none',
                    outlineOffset: 2,
                  }}
                >
                  <span style={{ fontSize: 20 }}>{tpl.icon}</span>
                  <span style={{ fontSize: 10, fontWeight: 500, textAlign: 'center', lineHeight: 1.2, color: 'var(--foreground)' }}>
                    {tpl.name.length > 22 ? tpl.name.slice(0, 20) + '…' : tpl.name}
                  </span>
                </button>
              ))}
            </div>
            {selectedTemplate && (
              <p className="text-xs text-muted-foreground">
                Template applied — fields pre-filled. You can edit them before creating.
              </p>
            )}
          </div>

          {/* Project Name */}
          <div className="space-y-2">
            <Label htmlFor="project-name">What are you working on?</Label>
            <Input
              id="project-name"
              placeholder="Name your project"
              value={name}
              onChange={(e) => setName(e.target.value)}
              data-testid="input-project-name"
              className={errors.name ? "border-destructive" : ""}
            />
            {errors.name && (
              <p className="text-sm text-destructive">{errors.name}</p>
            )}
          </div>

          {/* Project Description */}
          <div className="space-y-2">
            <Label htmlFor="project-description">What are you trying to achieve?</Label>
            <Textarea
              id="project-description"
              placeholder="Describe your project, goals, subject, etc..."
              value={description}
              onChange={(e) => setDescription(e.target.value)}
              data-testid="textarea-project-description"
              className="min-h-[100px]"
            />
          </div>

          {/* Project Instructions */}
          <div className="space-y-2">
            <Label htmlFor="project-instructions">Background instructions (optional)</Label>
            <Textarea
              id="project-instructions"
              placeholder="Provide context, guidelines, or background information that will help the AI assistant understand your project better..."
              value={instructions}
              onChange={(e) => setInstructions(e.target.value)}
              data-testid="textarea-project-instructions"
              className="min-h-[120px]"
            />
            <p className="text-xs text-muted-foreground">
              This information will be included in all project conversations to provide context.
            </p>
          </div>

          {/* Category Selection */}
          <div className="space-y-2">
            <Label htmlFor="project-category">Category (optional)</Label>
            <Select value={category} onValueChange={setCategory}>
              <SelectTrigger data-testid="select-project-category">
                <SelectValue placeholder="Select a category" />
              </SelectTrigger>
              <SelectContent>
                {projectCategories.map((cat) => (
                  <SelectItem key={cat} value={cat}>
                    {cat}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>

          {/* Tags */}
          <div className="space-y-2">
            <Label htmlFor="project-tags">Tags (optional)</Label>
            <div className="flex gap-2">
              <Input
                id="project-tags"
                placeholder="Add tags..."
                value={currentTag}
                onChange={(e) => setCurrentTag(e.target.value)}
                onKeyPress={handleKeyPress}
                data-testid="input-project-tags"
                className="flex-1"
              />
              <Button
                type="button"
                variant="outline"
                onClick={handleAddTag}
                disabled={!currentTag.trim()}
                data-testid="button-add-tag"
              >
                Add
              </Button>
            </div>
            
            {tags.length > 0 && (
              <div className="flex flex-wrap gap-2 mt-2">
                {tags.map((tag, index) => (
                  <Badge key={index} variant="secondary" className="flex items-center gap-1">
                    {tag}
                    <Button
                      type="button"
                      variant="ghost"
                      size="sm"
                      className="h-auto p-0 hover:bg-transparent"
                      onClick={() => handleRemoveTag(tag)}
                      data-testid={`button-remove-tag-${tag}`}
                    >
                      <X className="w-3 h-3" />
                    </Button>
                  </Badge>
                ))}
              </div>
            )}
          </div>

          {/* Submit Error */}
          {errors.submit && (
            <div className="text-sm text-destructive bg-destructive/10 p-3 rounded-md">
              {errors.submit}
            </div>
          )}

          {/* Actions */}
          <div className="flex justify-end gap-3">
            <Button
              type="button"
              variant="outline"
              onClick={handleCancel}
              disabled={isSubmitting}
              data-testid="button-cancel-project"
            >
              Cancel
            </Button>
            <Button
              type="submit"
              disabled={isSubmitting || !name.trim()}
              data-testid="button-create-project"
            >
              {isSubmitting ? "Creating..." : "Create project"}
            </Button>
          </div>
        </form>
      </DialogContent>
    </Dialog>
  )
}