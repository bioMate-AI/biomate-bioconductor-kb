import { useState, useRef, useEffect } from "react"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import {
  CheckCircle,
  Circle,
  Clock,
  AlertCircle,
  Play,
  Pause,
  RotateCcw,
  Settings,
  Trash2,
  ArrowRight
} from "lucide-react"
import { cn } from "@/lib/utils"
import { type WorkflowStep } from "./workflow-step"
import { ParameterEditor } from "./parameter-editor"

interface WorkflowGraphProps {
  steps: WorkflowStep[]
  onStepAction?: (stepId: string, action: 'run' | 'pause' | 'resume' | 'restart' | 'edit' | 'delete') => void
}

interface GraphNode {
  id: string
  step: WorkflowStep
  x: number
  y: number
  width: number
  height: number
}

interface GraphEdge {
  from: string
  to: string
}

export function WorkflowGraph({
  steps,
  onStepAction = (stepId, action) => console.log(`${action} triggered for step:`, stepId)
}: WorkflowGraphProps) {
  const [nodes, setNodes] = useState<GraphNode[]>([])
  const [edges, setEdges] = useState<GraphEdge[]>([])
  const [selectedNode, setSelectedNode] = useState<string | null>(null)
  const [editingStep, setEditingStep] = useState<WorkflowStep | null>(null)
  const svgRef = useRef<SVGSVGElement>(null)

  useEffect(() => {
    // Create nodes layout
    const nodeWidth = 280
    const nodeHeight = 120
    const horizontalSpacing = 350
    const verticalSpacing = 150
    
    const newNodes: GraphNode[] = steps.map((step, index) => ({
      id: step.id,
      step,
      x: 50 + (index % 3) * horizontalSpacing,
      y: 50 + Math.floor(index / 3) * verticalSpacing,
      width: nodeWidth,
      height: nodeHeight
    }))

    // Create edges (simple sequential flow for now)
    const newEdges: GraphEdge[] = []
    for (let i = 0; i < steps.length - 1; i++) {
      newEdges.push({
        from: steps[i].id,
        to: steps[i + 1].id
      })
    }

    setNodes(newNodes)
    setEdges(newEdges)
  }, [steps])

  const getStatusIcon = (status: WorkflowStep['status']) => {
    switch (status) {
      case 'pending': return Circle
      case 'running': return Clock
      case 'completed': return CheckCircle
      case 'error': return AlertCircle
      default: return Circle
    }
  }

  const getStatusColor = (status: WorkflowStep['status']) => {
    switch (status) {
      case 'pending': return 'text-muted-foreground'
      case 'running': return 'text-blue-500 animate-pulse'
      case 'completed': return 'text-green-500'
      case 'error': return 'text-red-500'
      default: return 'text-muted-foreground'
    }
  }

  const getNodeBorderColor = (status: WorkflowStep['status']) => {
    switch (status) {
      case 'pending': return 'border-muted'
      case 'running': return 'border-blue-500 shadow-lg shadow-blue-500/50'
      case 'completed': return 'border-green-500'
      case 'error': return 'border-red-500'
      default: return 'border-muted'
    }
  }

  const getNodeBackgroundColor = (status: WorkflowStep['status']) => {
    switch (status) {
      case 'pending': return 'bg-background'
      case 'running': return 'bg-blue-50 dark:bg-blue-950/30'
      case 'completed': return 'bg-green-50 dark:bg-green-950/30'
      case 'error': return 'bg-red-50 dark:bg-red-950/30'
      default: return 'bg-background'
    }
  }

  const getComplexityColor = (complexity: WorkflowStep['complexity']) => {
    switch (complexity) {
      case 'simple': return 'bg-green-500'
      case 'intermediate': return 'bg-yellow-500'
      case 'complex': return 'bg-red-500'
      default: return 'bg-gray-500'
    }
  }

  const renderEdges = () => {
    return edges.map((edge, index) => {
      const fromNode = nodes.find(n => n.id === edge.from)
      const toNode = nodes.find(n => n.id === edge.to)
      
      if (!fromNode || !toNode) return null

      const x1 = fromNode.x + fromNode.width
      const y1 = fromNode.y + fromNode.height / 2
      const x2 = toNode.x
      const y2 = toNode.y + toNode.height / 2

      return (
        <g key={index}>
          <defs>
            <marker
              id="arrowhead"
              markerWidth="10"
              markerHeight="7"
              refX="9"
              refY="3.5"
              orient="auto"
            >
              <polygon
                points="0 0, 10 3.5, 0 7"
                className="fill-muted-foreground"
              />
            </marker>
          </defs>
          <line
            x1={x1}
            y1={y1}
            x2={x2}
            y2={y2}
            stroke="hsl(var(--muted-foreground))"
            strokeWidth="2"
            markerEnd="url(#arrowhead)"
            className="opacity-60"
          />
        </g>
      )
    })
  }

  const renderNodes = () => {
    return nodes.map((node) => {
      const StatusIcon = getStatusIcon(node.step.status)
      const isSelected = selectedNode === node.id
      
      return (
        <foreignObject
          key={node.id}
          x={node.x}
          y={node.y}
          width={node.width}
          height={node.height}
          data-testid={`graph-node-${node.id}`}
        >
          <Card
            className={cn(
              "h-full cursor-pointer transition-all border-2",
              isSelected ? "ring-2 ring-primary" : "",
              getNodeBorderColor(node.step.status),
              getNodeBackgroundColor(node.step.status),
              node.step.status === 'running' ? "animate-pulse-subtle" : "",
              "hover:shadow-md"
            )}
            onClick={() => setSelectedNode(isSelected ? null : node.id)}
          >
            <CardHeader className="pb-2 space-y-1">
              <div className="flex items-center justify-between">
                <div className="flex items-center gap-2">
                  <StatusIcon className={cn("h-4 w-4", getStatusColor(node.step.status))} />
                  <Badge 
                    variant="secondary" 
                    className={cn("text-xs text-white", getComplexityColor(node.step.complexity))}
                  >
                    {node.step.complexity}
                  </Badge>
                </div>
                <Badge variant="outline" className="text-xs">
                  {node.step.estimatedTime || "~5 min"}
                </Badge>
              </div>
              <CardTitle className="text-sm line-clamp-2">{node.step.title}</CardTitle>
            </CardHeader>
            
            <CardContent className="pt-0">
              <p className="text-xs text-muted-foreground mb-3 line-clamp-2">
                {node.step.description}
              </p>
              <div className="text-xs text-muted-foreground mb-2">
                Tool: {node.step.tool}
              </div>
              
              {isSelected && (
                <div className="flex flex-wrap gap-1">
                  <Button
                    size="sm"
                    variant="outline"
                    onClick={(e) => {
                      e.stopPropagation()
                      onStepAction(node.id, 'run')
                    }}
                    disabled={node.step.status === 'running'}
                    data-testid={`button-graph-run-${node.id}`}
                  >
                    <Play className="w-3 h-3" />
                  </Button>
                  
                  {node.step.status === 'running' && (
                    <Button
                      size="sm"
                      variant="outline"
                      onClick={(e) => {
                        e.stopPropagation()
                        onStepAction(node.id, 'pause')
                      }}
                      data-testid={`button-graph-pause-${node.id}`}
                    >
                      <Pause className="w-3 h-3" />
                    </Button>
                  )}
                  
                  <Button
                    size="sm"
                    variant="outline"
                    onClick={(e) => {
                      e.stopPropagation()
                      onStepAction(node.id, 'restart')
                    }}
                    data-testid={`button-graph-restart-${node.id}`}
                  >
                    <RotateCcw className="w-3 h-3" />
                  </Button>
                  
                  <Button
                    size="sm"
                    variant="outline"
                    onClick={(e) => {
                      e.stopPropagation()
                      setEditingStep(node.step)
                    }}
                    data-testid={`button-graph-edit-${node.id}`}
                  >
                    <Settings className="w-3 h-3" />
                  </Button>
                  
                  <Button
                    size="sm"
                    variant="outline"
                    onClick={(e) => {
                      e.stopPropagation()
                      onStepAction(node.id, 'delete')
                    }}
                    data-testid={`button-graph-delete-${node.id}`}
                  >
                    <Trash2 className="w-3 h-3" />
                  </Button>
                </div>
              )}
            </CardContent>
          </Card>
        </foreignObject>
      )
    })
  }

  const handleSaveParameters = (parameters: Record<string, any>) => {
    if (editingStep) {
      // Update step parameters and notify parent
      onStepAction(editingStep.id, 'edit')
      // In a real implementation, would pass parameters to parent
      console.log('[WorkflowGraph] Saved parameters for', editingStep.id, parameters)
    }
  }

  const maxX = Math.max(...nodes.map(n => n.x + n.width), 0)
  const maxY = Math.max(...nodes.map(n => n.y + n.height), 0)

  return (
    <>
      <div className="w-full h-[600px] border rounded-lg overflow-auto bg-muted/20">
        <svg
          ref={svgRef}
          width={Math.max(maxX + 50, 800)}
          height={Math.max(maxY + 50, 600)}
          className="w-full h-full"
          data-testid="workflow-graph"
        >
          {renderEdges()}
          {renderNodes()}
        </svg>
      </div>

      {editingStep && (
        <ParameterEditor
          isOpen={!!editingStep}
          onClose={() => setEditingStep(null)}
          toolId={editingStep.tool}
          toolName={editingStep.title}
          currentParameters={editingStep.parameters || {}}
          onSave={handleSaveParameters}
        />
      )}
    </>
  )
}