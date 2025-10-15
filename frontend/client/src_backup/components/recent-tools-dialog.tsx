import { useState, useEffect } from "react"
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { ScrollArea } from "@/components/ui/scroll-area"
import { Input } from "@/components/ui/input"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { recentToolsService } from "@/lib/recent-tools"
import type { RecentTool } from "@shared/schema"
import { 
  Clock, 
  Search, 
  Filter,
  Trash2,
  ExternalLink,
  BarChart,
  Database,
  GitBranch,
  TrendingUp,
  Activity,
  Star
} from "lucide-react"
import { cn } from "@/lib/utils"

interface RecentToolsDialogProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  onToolSelect?: (tool: RecentTool) => void
}

export function RecentToolsDialog({ 
  open, 
  onOpenChange, 
  onToolSelect 
}: RecentToolsDialogProps) {
  const [recentTools, setRecentTools] = useState<RecentTool[]>([])
  const [searchQuery, setSearchQuery] = useState("")
  const [filterCategory, setFilterCategory] = useState<string>("all")
  const [sortBy, setSortBy] = useState<string>("recent")

  useEffect(() => {
    if (open) {
      loadRecentTools()
    }
  }, [open])

  const loadRecentTools = () => {
    const tools = recentToolsService.getAllRecent()
    setRecentTools(tools)
  }

  const handleRemoveTool = (toolId: string) => {
    recentToolsService.removeRecentTool(toolId)
    loadRecentTools()
  }

  const handleToolClick = (tool: RecentTool) => {
    // Update usage count
    recentToolsService.addRecentTool({
      toolId: tool.toolId,
      name: tool.name,
      description: tool.description,
      category: tool.category,
      complexity: tool.complexity
    })
    onToolSelect?.(tool)
    onOpenChange(false)
  }

  const handleClearAll = () => {
    recentToolsService.clearAll()
    loadRecentTools()
  }


  const getCategoryIcon = (category: string) => {
    switch (category.toLowerCase()) {
      case 'quality-control': return Search
      case 'alignment': return GitBranch
      case 'statistics': return BarChart
      case 'data-sources': return Database
      case 'genomics': return Activity
      default: return Search
    }
  }

  const formatTimeAgo = (date: Date) => {
    const now = new Date()
    const diffMs = now.getTime() - new Date(date).getTime()
    const diffHours = Math.floor(diffMs / (1000 * 60 * 60))
    const diffDays = Math.floor(diffMs / (1000 * 60 * 60 * 24))
    
    if (diffHours < 1) return 'Just now'
    if (diffHours < 24) return `${diffHours}h ago`
    if (diffDays < 7) return `${diffDays}d ago`
    return `${Math.floor(diffDays / 7)}w ago`
  }

  const formatCategory = (category: string) => {
    return category.split('-').map(word => 
      word.charAt(0).toUpperCase() + word.slice(1)
    ).join(' ')
  }

  // Filter and sort tools
  let filteredTools = recentTools.filter(tool => {
    const matchesSearch = tool.name.toLowerCase().includes(searchQuery.toLowerCase()) ||
                         tool.description.toLowerCase().includes(searchQuery.toLowerCase()) ||
                         tool.category.toLowerCase().includes(searchQuery.toLowerCase())
    
    const matchesComplexity = true
    const matchesCategory = filterCategory === "all" || tool.category === filterCategory
    
    return matchesSearch && matchesComplexity && matchesCategory
  })

  // Sort tools
  if (sortBy === "recent") {
    filteredTools = filteredTools.sort((a, b) => 
      new Date(b.lastUsed).getTime() - new Date(a.lastUsed).getTime()
    )
  } else if (sortBy === "usage") {
    filteredTools = filteredTools.sort((a, b) => b.usageCount - a.usageCount)
  } else if (sortBy === "name") {
    filteredTools = filteredTools.sort((a, b) => a.name.localeCompare(b.name))
  }

  const categories = Array.from(new Set(recentTools.map(t => t.category)))

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-4xl max-h-[90vh] p-0">
        <DialogHeader className="p-6 pb-4">
          <DialogTitle className="flex items-center gap-2">
            <Clock className="w-5 h-5" />
            Recent Tools
          </DialogTitle>
        </DialogHeader>

        {/* Search and Filters */}
        <div className="px-6 pb-4 space-y-4">
          <div className="flex gap-4">
            <div className="relative flex-1">
              <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 w-4 h-4 text-muted-foreground" />
              <Input
                placeholder="Search recent tools..."
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                className="pl-10"
                data-testid="input-search-recent"
              />
            </div>
            <Select value={filterCategory} onValueChange={setFilterCategory}>
              <SelectTrigger className="w-40" data-testid="select-filter-category">
                <Filter className="w-4 h-4 mr-2" />
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="all">All Categories</SelectItem>
                {categories.map(category => (
                  <SelectItem key={category} value={category}>
                    {formatCategory(category)}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
            <Select value={sortBy} onValueChange={setSortBy}>
              <SelectTrigger className="w-32" data-testid="select-sort">
                <TrendingUp className="w-4 h-4 mr-2" />
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="recent">Recent</SelectItem>
                <SelectItem value="usage">Most Used</SelectItem>
                <SelectItem value="name">Name</SelectItem>
              </SelectContent>
            </Select>
          </div>
          
          {recentTools.length > 0 && (
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-4 text-sm text-muted-foreground">
                <span>{filteredTools.length} of {recentTools.length} tools</span>
                <span>•</span>
                <span>Total usage: {recentTools.reduce((sum, tool) => sum + tool.usageCount, 0)}</span>
              </div>
              <Button
                variant="outline"
                size="sm"
                onClick={handleClearAll}
                data-testid="button-clear-recent"
              >
                <Trash2 className="w-4 h-4 mr-2" />
                Clear All
              </Button>
            </div>
          )}
        </div>

        {/* Tools List */}
        <ScrollArea className="flex-1 px-6 pb-6">
          {filteredTools.length === 0 ? (
            <div className="text-center py-12">
              <Clock className="w-12 h-12 mx-auto mb-4 text-muted-foreground" />
              <h3 className="text-lg font-semibold mb-2">No recent tools found</h3>
              <p className="text-muted-foreground mb-4">
                {searchQuery || filterCategory !== "all" 
                  ? "Try adjusting your search or filters" 
                  : "Start using bioinformatics tools and they'll appear here"}
              </p>
              {(searchQuery || filterCategory !== "all") && (
                <Button 
                  variant="outline" 
                  onClick={() => {
                    setSearchQuery("")
                    setFilterCategory("all")
                  }}
                  data-testid="button-clear-filters"
                >
                  Clear Filters
                </Button>
              )}
            </div>
          ) : (
            <div className="grid gap-3">
              {filteredTools.map((tool) => {
                const IconComponent = getCategoryIcon(tool.category)
                return (
                  <Card 
                    key={tool.id} 
                    className="hover-elevate cursor-pointer transition-colors"
                    onClick={() => handleToolClick(tool)}
                    data-testid={`card-recent-tool-${tool.id}`}
                  >
                    <CardContent className="p-4">
                      <div className="flex items-start justify-between">
                        <div className="flex items-start gap-3 flex-1">
                          <div className="p-2 rounded-lg bg-primary/10">
                            <IconComponent className="w-4 h-4 text-primary" />
                          </div>
                          <div className="flex-1 min-w-0">
                            <div className="flex items-center gap-2 mb-1">
                              <h4 className="font-semibold">{tool.name}</h4>
                              <Badge variant="secondary" className="text-xs">
                                {formatCategory(tool.category)}
                              </Badge>
                            </div>
                            <p className="text-sm text-muted-foreground mb-2">
                              {tool.description}
                            </p>
                            <div className="flex items-center gap-4 text-xs text-muted-foreground">
                              <span>Used {formatTimeAgo(tool.lastUsed)}</span>
                              <span>•</span>
                              <span>{tool.usageCount} time{tool.usageCount !== 1 ? 's' : ''}</span>
                            </div>
                          </div>
                        </div>
                        <div className="flex items-center gap-2">
                          <Button
                            variant="ghost"
                            size="sm"
                            onClick={(e) => {
                              e.stopPropagation()
                              // Add to starred tools
                            }}
                            data-testid={`button-star-tool-${tool.id}`}
                          >
                            <Star className="w-4 h-4" />
                          </Button>
                          <Button
                            variant="ghost"
                            size="sm"
                            onClick={(e) => {
                              e.stopPropagation()
                              handleRemoveTool(tool.toolId)
                            }}
                            data-testid={`button-remove-tool-${tool.id}`}
                          >
                            <Trash2 className="w-4 h-4" />
                          </Button>
                          <Button 
                            variant="outline" 
                            size="sm"
                            onClick={(e) => {
                              e.stopPropagation()
                              // Open tool documentation
                            }}
                            data-testid={`button-view-tool-${tool.id}`}
                          >
                            <ExternalLink className="w-4 h-4" />
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