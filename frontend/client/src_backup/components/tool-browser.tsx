import { useState } from "react"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Search, Filter, Dna, BarChart3, Database, FileText, Zap, Workflow } from "lucide-react"
import { ToolCategoryCard, type ToolCategory } from "./tool-category-card"

//todo: remove mock functionality
const mockCategories: ToolCategory[] = [
  {
    id: "genomics",
    name: "Genomics",
    description: "Tools for genome analysis, variant calling, and sequence manipulation",
    toolCount: 45,
    icon: Dna,
    color: "bg-blue-500",
    tags: ["Alignment", "Variant Calling", "Assembly", "Annotation"]
  },
  {
    id: "statistics",
    name: "Statistics", 
    description: "Statistical analysis and data visualization tools",
    toolCount: 28,
    icon: BarChart3,
    color: "bg-green-500",
    tags: ["Plotting", "Analysis", "R", "Python"]
  },
  {
    id: "data-sources",
    name: "Data Sources",
    description: "Import and export data from various sources and formats",
    toolCount: 32,
    icon: Database,
    color: "bg-purple-500", 
    tags: ["Import", "Export", "Databases", "APIs"]
  },
  {
    id: "text-manipulation", 
    name: "Text Manipulation",
    description: "Tools for processing and transforming text-based data",
    toolCount: 19,
    icon: FileText,
    color: "bg-orange-500",
    tags: ["Parsing", "Formatting", "Conversion", "Filtering"]
  },
  {
    id: "machine-learning",
    name: "Machine Learning",
    description: "AI and machine learning tools for data analysis",
    toolCount: 24,
    icon: Zap,
    color: "bg-pink-500",
    tags: ["Classification", "Clustering", "Prediction", "Neural Networks"]
  },
  {
    id: "workflows",
    name: "Workflows",
    description: "Pre-built analysis pipelines and workflow templates", 
    toolCount: 15,
    icon: Workflow,
    color: "bg-indigo-500",
    tags: ["RNA-seq", "ChIP-seq", "Pipeline", "Automation"]
  }
]

interface ToolBrowserProps {
  onCategorySelect?: (category: ToolCategory) => void
  onStartChat?: () => void
}

export function ToolBrowser({ 
  onCategorySelect = (cat) => console.log('Category selected:', cat.name),
  onStartChat = () => console.log('Start chat triggered')
}: ToolBrowserProps) {
  const [searchQuery, setSearchQuery] = useState("")
  const [selectedTags, setSelectedTags] = useState<string[]>([])

  const allTags = Array.from(new Set(mockCategories.flatMap(cat => cat.tags)))
  
  const filteredCategories = mockCategories.filter(category => {
    const matchesSearch = category.name.toLowerCase().includes(searchQuery.toLowerCase()) ||
                         category.description.toLowerCase().includes(searchQuery.toLowerCase()) ||
                         category.tags.some(tag => tag.toLowerCase().includes(searchQuery.toLowerCase()))
    
    const matchesTags = selectedTags.length === 0 || 
                       selectedTags.some(tag => category.tags.includes(tag))
    
    return matchesSearch && matchesTags
  })

  const toggleTag = (tag: string) => {
    setSelectedTags(prev => 
      prev.includes(tag) 
        ? prev.filter(t => t !== tag)
        : [...prev, tag]
    )
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="text-center space-y-4">
        <h1 className="text-3xl font-bold">Explore Tools</h1>
        <p className="text-muted-foreground max-w-2xl mx-auto">
          Discover powerful bioinformatics tools organized by category. Click on any category to see available tools, 
          or start a conversation to get personalized recommendations.
        </p>
        <Button onClick={onStartChat} data-testid="button-start-chat-from-browser">
          Start a Conversation Instead
        </Button>
      </div>

      {/* Search and Filters */}
      <Card>
        <CardHeader>
          <CardTitle className="text-lg">Find Tools</CardTitle>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="relative">
            <Search className="absolute left-3 top-3 h-4 w-4 text-muted-foreground" />
            <Input
              placeholder="Search categories, tools, or descriptions..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              className="pl-10"
              data-testid="input-search-tools"
            />
          </div>
          
          <div className="space-y-2">
            <div className="flex items-center gap-2">
              <Filter className="h-4 w-4 text-muted-foreground" />
              <span className="text-sm font-medium">Filter by tags:</span>
            </div>
            <div className="flex flex-wrap gap-2">
              {allTags.map((tag) => (
                <Badge
                  key={tag}
                  variant={selectedTags.includes(tag) ? "default" : "outline"}
                  className="cursor-pointer hover-elevate"
                  onClick={() => toggleTag(tag)}
                  data-testid={`badge-filter-${tag.toLowerCase().replace(/\s+/g, '-')}`}
                >
                  {tag}
                </Badge>
              ))}
              {selectedTags.length > 0 && (
                <Button
                  variant="ghost"
                  size="sm"
                  onClick={() => setSelectedTags([])}
                  data-testid="button-clear-filters"
                >
                  Clear all
                </Button>
              )}
            </div>
          </div>
        </CardContent>
      </Card>

      {/* Categories Grid */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
        {filteredCategories.map((category) => (
          <ToolCategoryCard 
            key={category.id} 
            category={category}
            onClick={onCategorySelect}
          />
        ))}
      </div>
      
      {filteredCategories.length === 0 && (
        <Card className="text-center py-12">
          <CardContent>
            <p className="text-muted-foreground">
              No tools found matching your search criteria. Try adjusting your search or clearing filters.
            </p>
          </CardContent>
        </Card>
      )}
    </div>
  )
}