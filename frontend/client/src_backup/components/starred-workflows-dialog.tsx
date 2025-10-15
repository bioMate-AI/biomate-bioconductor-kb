import { useState, useEffect } from "react"
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { ScrollArea } from "@/components/ui/scroll-area"
import { Input } from "@/components/ui/input"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { starredWorkflowsService } from "@/lib/starred-workflows"
import type { StarredWorkflow } from "@shared/schema"
import { 
  Star, 
  Play, 
  Clock, 
  Search, 
  Filter,
  Trash2,
  ExternalLink,
  GitBranch
} from "lucide-react"
import { cn } from "@/lib/utils"

interface StarredWorkflowsDialogProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  onWorkflowSelect?: (workflow: StarredWorkflow) => void
}

export function StarredWorkflowsDialog({ 
  open, 
  onOpenChange, 
  onWorkflowSelect 
}: StarredWorkflowsDialogProps) {
  const [starredWorkflows, setStarredWorkflows] = useState<StarredWorkflow[]>([])
  const [searchQuery, setSearchQuery] = useState("")
  const [filterComplexity, setFilterComplexity] = useState<string>("all")
  const [filterType, setFilterType] = useState<string>("all")

  useEffect(() => {
    if (open) {
      loadStarredWorkflows()
    }
  }, [open])

  const loadStarredWorkflows = () => {
    const workflows = starredWorkflowsService.getAllStarred()
    setStarredWorkflows(workflows)
  }

  const handleUnstar = (workflowId: string) => {
    starredWorkflowsService.unstarWorkflow(workflowId)
    loadStarredWorkflows()
  }

  const handleWorkflowClick = (workflow: StarredWorkflow) => {
    onWorkflowSelect?.(workflow)
    onOpenChange(false)
  }


  const getWorkflowIcon = (workflowType: string) => {
    switch (workflowType.toLowerCase()) {
      case 'rna-seq': return GitBranch
      case 'genomics': return GitBranch
      case 'quality control': return Search
      default: return GitBranch
    }
  }

  const formatTimeAgo = (date: Date) => {
    const now = new Date()
    const diffMs = now.getTime() - new Date(date).getTime()
    const diffDays = Math.floor(diffMs / (1000 * 60 * 60 * 24))
    
    if (diffDays === 0) return 'Today'
    if (diffDays === 1) return 'Yesterday'
    if (diffDays < 7) return `${diffDays} days ago`
    if (diffDays < 30) return `${Math.floor(diffDays / 7)} weeks ago`
    return `${Math.floor(diffDays / 30)} months ago`
  }

  // Filter workflows based on search and filters
  const filteredWorkflows = starredWorkflows.filter(workflow => {
    const matchesSearch = workflow.title.toLowerCase().includes(searchQuery.toLowerCase()) ||
                         workflow.description.toLowerCase().includes(searchQuery.toLowerCase()) ||
                         workflow.workflowType.toLowerCase().includes(searchQuery.toLowerCase())
    
    const matchesComplexity = filterComplexity === "all" || workflow.complexity === filterComplexity
    const matchesType = filterType === "all" || workflow.workflowType.toLowerCase().includes(filterType.toLowerCase())
    
    return matchesSearch && matchesComplexity && matchesType
  })

  const workflowTypes = Array.from(new Set(starredWorkflows.map(w => w.workflowType)))

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-4xl max-h-[90vh] p-0">
        <DialogHeader className="p-6 pb-4">
          <DialogTitle className="flex items-center gap-2">
            <Star className="w-5 h-5 fill-yellow-400 text-yellow-400" />
            Starred Workflows
          </DialogTitle>
        </DialogHeader>

        {/* Search and Filters */}
        <div className="px-6 pb-4 space-y-4">
          <div className="flex gap-4">
            <div className="relative flex-1">
              <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 w-4 h-4 text-muted-foreground" />
              <Input
                placeholder="Search starred workflows..."
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                className="pl-10"
                data-testid="input-search-starred"
              />
            </div>
            <Select value={filterComplexity} onValueChange={setFilterComplexity}>
              <SelectTrigger className="w-40" data-testid="select-filter-complexity">
                <Filter className="w-4 h-4 mr-2" />
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="all">All Complexity</SelectItem>
                <SelectItem value="simple">Simple</SelectItem>
                <SelectItem value="intermediate">Intermediate</SelectItem>
                <SelectItem value="complex">Complex</SelectItem>
              </SelectContent>
            </Select>
            <Select value={filterType} onValueChange={setFilterType}>
              <SelectTrigger className="w-40" data-testid="select-filter-type">
                <Filter className="w-4 h-4 mr-2" />
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="all">All Types</SelectItem>
                {workflowTypes.map(type => (
                  <SelectItem key={type} value={type.toLowerCase()}>
                    {type}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
        </div>

        {/* Workflows List */}
        <ScrollArea className="flex-1 px-6 pb-6">
          {filteredWorkflows.length === 0 ? (
            <div className="text-center py-12">
              <Star className="w-12 h-12 mx-auto mb-4 text-muted-foreground" />
              <h3 className="text-lg font-semibold mb-2">No starred workflows found</h3>
              <p className="text-muted-foreground mb-4">
                {searchQuery || filterComplexity !== "all" || filterType !== "all" 
                  ? "Try adjusting your search or filters" 
                  : "Star your favorite workflows to access them quickly"}
              </p>
              {(searchQuery || filterComplexity !== "all" || filterType !== "all") && (
                <Button 
                  variant="outline" 
                  onClick={() => {
                    setSearchQuery("")
                    setFilterComplexity("all")
                    setFilterType("all")
                  }}
                  data-testid="button-clear-filters"
                >
                  Clear Filters
                </Button>
              )}
            </div>
          ) : (
            <div className="grid gap-4">
              {filteredWorkflows.map((workflow) => {
                const IconComponent = getWorkflowIcon(workflow.workflowType)
                return (
                  <Card 
                    key={workflow.id} 
                    className="hover-elevate cursor-pointer transition-colors"
                    onClick={() => handleWorkflowClick(workflow)}
                    data-testid={`card-starred-workflow-${workflow.id}`}
                  >
                    <CardHeader>
                      <div className="flex items-start justify-between">
                        <div className="flex items-start gap-3 flex-1">
                          <div className="p-2 rounded-lg bg-primary/10">
                            <IconComponent className="w-5 h-5 text-primary" />
                          </div>
                          <div className="flex-1 min-w-0">
                            <CardTitle className="text-lg flex items-center gap-2">
                              {workflow.title}
                              <Badge variant="secondary" className="text-xs">
                                {workflow.workflowType}
                              </Badge>
                            </CardTitle>
                            <CardDescription className="mt-1">
                              {workflow.description}
                            </CardDescription>
                          </div>
                        </div>
                        <div className="flex items-center gap-2">
                          <Button
                            variant="ghost"
                            size="sm"
                            onClick={(e) => {
                              e.stopPropagation()
                              handleUnstar(workflow.workflowId)
                            }}
                            data-testid={`button-unstar-${workflow.id}`}
                          >
                            <Trash2 className="w-4 h-4" />
                          </Button>
                          <Star className="w-4 h-4 fill-yellow-400 text-yellow-400" />
                        </div>
                      </div>
                    </CardHeader>
                    <CardContent>
                      <div className="flex items-center justify-between">
                        <div className="flex items-center gap-4">
                          {workflow.estimatedTime && (
                            <div className="flex items-center gap-1 text-sm text-muted-foreground">
                              <Clock className="w-4 h-4" />
                              {workflow.estimatedTime}
                            </div>
                          )}
                          <div className="text-sm text-muted-foreground">
                            Starred {formatTimeAgo(workflow.starredAt)}
                          </div>
                        </div>
                        <div className="flex items-center gap-2">
                          <Button 
                            variant="outline" 
                            size="sm"
                            onClick={(e) => {
                              e.stopPropagation()
                              // Open workflow in new tab or view
                            }}
                            data-testid={`button-view-workflow-${workflow.id}`}
                          >
                            <ExternalLink className="w-4 h-4 mr-2" />
                            View
                          </Button>
                          <Button 
                            size="sm"
                            onClick={(e) => {
                              e.stopPropagation()
                              handleWorkflowClick(workflow)
                            }}
                            data-testid={`button-run-workflow-${workflow.id}`}
                          >
                            <Play className="w-4 h-4 mr-2" />
                            Run
                          </Button>
                        </div>
                      </div>
                    </CardContent>
                  </Card>
                )
              })}
            </div>
          )}
        </ScrollArea>
      </DialogContent>
    </Dialog>
  )
}