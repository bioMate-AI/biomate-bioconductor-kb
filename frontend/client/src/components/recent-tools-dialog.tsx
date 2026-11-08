import { useState, useEffect } from "react"
import { t } from "@/lib/i18n"
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
  BarChart,
  Database,
  GitBranch,
  TrendingUp,
  Activity
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
            {t('dialogs.recent_title')}
          </DialogTitle>
        </DialogHeader>

        {/* Search and Filters */}
        <div className="px-6 pb-4 space-y-4">
          <div className="flex gap-4">
            <div className="relative flex-1">
              <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 w-4 h-4 text-muted-foreground" />
              <Input
                placeholder={t('dialogs.recent_search')}
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
                <SelectItem value="all">{t('dialogs.all_categories')}</SelectItem>
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
                <SelectItem value="recent">{t('dialogs.sort_recent')}</SelectItem>
                <SelectItem value="usage">{t('dialogs.sort_most_used')}</SelectItem>
                <SelectItem value="name">{t('dialogs.sort_name')}</SelectItem>
              </SelectContent>
            </Select>
          </div>
          
          {recentTools.length > 0 && (
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-4 text-sm text-muted-foreground">
                <span>{t('dialogs.tools_count', { shown: filteredTools.length, total: recentTools.length })}</span>
                <span>•</span>
                <span>{t('dialogs.total_usage', { n: recentTools.reduce((sum, tool) => sum + tool.usageCount, 0) })}</span>
              </div>
              <Button
                variant="outline"
                size="sm"
                onClick={handleClearAll}
                data-testid="button-clear-recent"
              >
                <Trash2 className="w-4 h-4 mr-2" />
                {t('dialogs.clear_all')}
              </Button>
            </div>
          )}
        </div>

        {/* Tools List */}
        <ScrollArea className="flex-1 px-6 pb-6">
          {filteredTools.length === 0 ? (
            <div className="text-center py-12">
              <Clock className="w-12 h-12 mx-auto mb-4 text-muted-foreground" />
              <h3 className="text-lg font-semibold mb-2">{t('dialogs.no_recent')}</h3>
              <p className="text-muted-foreground mb-4">
                {searchQuery || filterCategory !== "all"
                  ? t('dialogs.adjust_filters')
                  : t('dialogs.recent_empty_hint')}
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
                  {t('dialogs.clear_filters')}
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
                              <span>{t(tool.usageCount === 1 ? 'dialogs.times_one' : 'dialogs.times_other', { n: tool.usageCount })}</span>
                            </div>
                          </div>
                        </div>
                        <div className="flex items-center gap-2">
                          {/* "Star" and "View documentation" removed: both had no
                              real target (empty onClick). Opening a tool's details
                              is handled by card-click → onToolSelect. */}
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