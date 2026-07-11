import { useState, useMemo, useEffect } from "react"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import { ScrollArea } from "@/components/ui/scroll-area"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { 
  Search, 
  Plus, 
  FolderOpen, 
  Clock, 
  Tag, 
  Archive,
  MoreVertical,
  CheckCircle,
  Circle
} from "lucide-react"
import { projectService } from "@/lib/projects"
import { CreateProjectDialog } from "@/components/create-project-dialog"
import { getTemplateByTag } from "@/lib/project-templates"
import type { Project } from "@shared/schema"
import { cn } from "@/lib/utils"

interface ProjectsPageProps {
  onProjectSelect?: (projectId: string) => void
}

export default function ProjectsPage({ onProjectSelect }: ProjectsPageProps) {
  const [searchQuery, setSearchQuery] = useState("")
  const [sortBy, setSortBy] = useState<"activity" | "created" | "name">("activity")
  const [filterStatus, setFilterStatus] = useState<"all" | "active" | "completed" | "archived">("all")
  const [showCreateDialog, setShowCreateDialog] = useState(false)
  const [allProjects, setAllProjects] = useState<Project[]>([])
  const [loadingProjects, setLoadingProjects] = useState(true)

  // Load from backend API; fall back to localStorage demo data
  useEffect(() => {
    const load = async () => {
      try {
        const res = await fetch('/api/memory/projects', { credentials: 'include' })
        if (res.ok) {
          const data = await res.json()
          const projects: Project[] = (Array.isArray(data) ? data : []).map((p: any) => ({
            id: p.id,
            name: p.name,
            description: p.description || '',
            instructions: p.researchGoal || p.instructions || '',
            status: (p.status || 'active') as Project['status'],
            category: p.primaryDomain || p.category || null,
            tags: p.tags || [],
            progress: p.progress || 0,
            createdAt: new Date(p.createdAt),
            updatedAt: new Date(p.updatedAt || p.createdAt),
            lastActivity: new Date(p.updatedAt || p.createdAt),
            chatSessions: [],
            documents: [],
          }))
          setAllProjects(projects.length > 0 ? projects : projectService.getAllProjects())
        } else {
          setAllProjects(projectService.getAllProjects())
        }
      } catch {
        setAllProjects(projectService.getAllProjects())
      } finally {
        setLoadingProjects(false)
      }
    }
    load()
  }, [])

  // Filter and sort projects
  const filteredProjects = useMemo(() => {
    let projects = allProjects

    // Filter by search query — filter from API-loaded state, not localStorage
    if (searchQuery.trim()) {
      const q = searchQuery.toLowerCase()
      projects = projects.filter(p =>
        p.name.toLowerCase().includes(q) ||
        (p.description || '').toLowerCase().includes(q) ||
        (p.tags || []).some(t => t.toLowerCase().includes(q))
      )
    }

    // Filter by status
    if (filterStatus !== "all") {
      projects = projects.filter(p => p.status === filterStatus)
    }

    // Sort projects
    return projects.sort((a, b) => {
      switch (sortBy) {
        case "name":
          return a.name.localeCompare(b.name)
        case "created":
          return new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime()
        case "activity":
        default:
          return new Date(b.lastActivity).getTime() - new Date(a.lastActivity).getTime()
      }
    })
  }, [allProjects, searchQuery, sortBy, filterStatus])

  const handleProjectCreated = async (projectId: string) => {
    // Re-fetch from backend to get the new project in the list
    try {
      const res = await fetch('/api/memory/projects', { credentials: 'include' })
      if (res.ok) {
        const data = await res.json()
        const projects: Project[] = (Array.isArray(data) ? data : []).map((p: any) => ({
          id: p.id, name: p.name, description: p.description || '',
          instructions: p.researchGoal || p.instructions || '',
          status: (p.status || 'active') as Project['status'],
          category: p.primaryDomain || p.category || null,
          tags: p.tags || [], progress: p.progress || 0,
          createdAt: new Date(p.createdAt), updatedAt: new Date(p.updatedAt || p.createdAt),
          lastActivity: new Date(p.updatedAt || p.createdAt), chatSessions: [], documents: [],
        }))
        setAllProjects(projects)
      }
    } catch {
      setAllProjects(projectService.getAllProjects())
    }
    onProjectSelect?.(projectId)
  }

  const getRelativeTime = (date: Date): string => {
    const now = new Date()
    const diffMs = now.getTime() - new Date(date).getTime()
    const diffDays = Math.floor(diffMs / (1000 * 60 * 60 * 24))
    
    if (diffDays === 0) return 'Today'
    if (diffDays === 1) return 'Yesterday'
    if (diffDays < 7) return `${diffDays} days ago`
    if (diffDays < 30) return `${Math.floor(diffDays / 7)} weeks ago`
    if (diffDays < 365) return `${Math.floor(diffDays / 30)} months ago`
    return `${Math.floor(diffDays / 365)} years ago`
  }

  const getStatusIcon = (status: Project['status']) => {
    switch (status) {
      case 'completed':
        return <CheckCircle className="w-4 h-4 text-green-600" />
      case 'archived':
        return <Archive className="w-4 h-4 text-gray-500" />
      default:
        return <Circle className="w-4 h-4 text-blue-600" />
    }
  }

  const getStatusColor = (status: Project['status']) => {
    switch (status) {
      case 'completed':
        return 'bg-green-100 text-green-700 dark:bg-green-900 dark:text-green-300'
      case 'archived':
        return 'bg-gray-100 text-gray-700 dark:bg-gray-900 dark:text-gray-300'
      default:
        return 'bg-blue-100 text-blue-700 dark:bg-blue-900 dark:text-blue-300'
    }
  }

  return (
    <div className="h-full flex flex-col">
      {/* Header */}
      <div className="border-b border-border p-6">
        <div className="flex items-center justify-between mb-4">
          <h1 className="text-2xl font-bold">Projects</h1>
          <Button 
            onClick={() => setShowCreateDialog(true)}
            data-testid="button-new-project-page"
          >
            <Plus className="w-4 h-4 mr-2" />
            New project
          </Button>
        </div>

        {/* Search and Filters */}
        <div className="flex gap-4 items-center">
          <div className="relative flex-1 max-w-md">
            <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 w-4 h-4 text-muted-foreground" />
            <Input
              placeholder="Search projects..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              className="pl-10"
              data-testid="input-search-projects"
            />
          </div>

          <Select value={sortBy} onValueChange={(value: any) => setSortBy(value)}>
            <SelectTrigger className="w-40" data-testid="select-sort-projects">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="activity">Recent activity</SelectItem>
              <SelectItem value="created">Date created</SelectItem>
              <SelectItem value="name">Name</SelectItem>
            </SelectContent>
          </Select>

          <Select value={filterStatus} onValueChange={(value: any) => setFilterStatus(value)}>
            <SelectTrigger className="w-32" data-testid="select-filter-status">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="all">All</SelectItem>
              <SelectItem value="active">Active</SelectItem>
              <SelectItem value="completed">Completed</SelectItem>
              <SelectItem value="archived">Archived</SelectItem>
            </SelectContent>
          </Select>
        </div>
      </div>

      {/* Projects Grid */}
      <div className="flex-1 p-6">
        {loadingProjects ? (
          <div className="text-center py-12">
            <div className="w-8 h-8 border-2 border-primary border-t-transparent rounded-full animate-spin mx-auto mb-4" />
            <p className="text-muted-foreground">Loading projects…</p>
          </div>
        ) : filteredProjects.length === 0 ? (
          <div className="text-center py-12">
            <FolderOpen className="w-12 h-12 text-muted-foreground mx-auto mb-4" />
            <h3 className="text-lg font-medium mb-2">
              {searchQuery ? "No projects found" : "No projects yet"}
            </h3>
            <p className="text-muted-foreground mb-4">
              {searchQuery
                ? "Try adjusting your search or filters"
                : "Create your first project to get started with organized research"
              }
            </p>
            {!searchQuery && (
              <Button onClick={() => setShowCreateDialog(true)}>
                <Plus className="w-4 h-4 mr-2" />
                Create your first project
              </Button>
            )}
          </div>
        ) : (
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
            {filteredProjects.map((project) => (
              <Card 
                key={project.id} 
                className="hover-elevate cursor-pointer"
                onClick={() => onProjectSelect?.(project.id)}
                data-testid={`card-project-${project.id}`}
              >
                <CardHeader className="pb-3">
                  <div className="flex items-start justify-between">
                    <div className="flex items-center gap-2">
                      {getStatusIcon(project.status)}
                      {(() => { const tpl = getTemplateByTag(project.tags || []); return tpl ? <span title={tpl.name}>{tpl.icon}</span> : null })()}
                      <CardTitle className="text-lg leading-tight">{project.name}</CardTitle>
                    </div>
                    <Button variant="ghost" size="sm" className="h-8 w-8 p-0">
                      <MoreVertical className="w-4 h-4" />
                    </Button>
                  </div>
                  
                  {project.description && (
                    <CardDescription className="line-clamp-2">
                      {project.description}
                    </CardDescription>
                  )}
                  {(((project as any).sessionCount ?? 0) > 0 || ((project as any).runCount ?? 0) > 0) && (
                    <div className="flex gap-2 text-xs text-muted-foreground mt-1">
                      {(project as any).sessionCount > 0 && (
                        <span>{(project as any).sessionCount} chat{(project as any).sessionCount !== 1 ? 's' : ''}</span>
                      )}
                      {(project as any).sessionCount > 0 && (project as any).runCount > 0 && <span>·</span>}
                      {(project as any).runCount > 0 && (
                        <span>{(project as any).runCount} run{(project as any).runCount !== 1 ? 's' : ''}</span>
                      )}
                    </div>
                  )}
                </CardHeader>

                <CardContent className="pt-0">
                  {/* Progress Bar */}
                  {project.progress > 0 && (
                    <div className="mb-3">
                      <div className="flex items-center justify-between text-sm mb-1">
                        <span className="text-muted-foreground">Progress</span>
                        <span className="font-medium">{project.progress}%</span>
                      </div>
                      <div className="w-full bg-secondary rounded-full h-2">
                        <div 
                          className="bg-primary h-2 rounded-full transition-all duration-300" 
                          style={{ width: `${project.progress}%` }}
                        />
                      </div>
                    </div>
                  )}

                  {/* Category and Status */}
                  <div className="flex items-center gap-2 mb-3">
                    {project.category && (
                      <Badge variant="outline" className="text-xs">
                        {project.category}
                      </Badge>
                    )}
                    <Badge 
                      variant="secondary" 
                      className={cn("text-xs", getStatusColor(project.status))}
                    >
                      {project.status}
                    </Badge>
                  </div>

                  {/* Tags */}
                  {project.tags.length > 0 && (
                    <div className="flex flex-wrap gap-1 mb-3">
                      {project.tags.slice(0, 3).map((tag) => (
                        <Badge key={tag} variant="secondary" className="text-xs">
                          <Tag className="w-3 h-3 mr-1" />
                          {tag}
                        </Badge>
                      ))}
                      {project.tags.length > 3 && (
                        <Badge variant="secondary" className="text-xs">
                          +{project.tags.length - 3}
                        </Badge>
                      )}
                    </div>
                  )}

                  {/* Footer */}
                  <div className="flex items-center justify-between text-sm text-muted-foreground">
                    <div className="flex items-center gap-1">
                      <Clock className="w-3 h-3" />
                      {getRelativeTime(project.lastActivity)}
                    </div>
                    <div>
                      {project.chatSessions.length} chat{project.chatSessions.length !== 1 ? 's' : ''}
                    </div>
                  </div>
                </CardContent>
              </Card>
            ))}
          </div>
        )}
      </div>

      {/* Create Project Dialog */}
      <CreateProjectDialog
        open={showCreateDialog}
        onOpenChange={setShowCreateDialog}
        onProjectCreated={handleProjectCreated}
      />
    </div>
  )
}