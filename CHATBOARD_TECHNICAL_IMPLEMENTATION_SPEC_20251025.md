# BioMate Chatboard Technical Implementation Specification

**Document Version:** 1.0
**Date:** 2025-10-25
**Status:** Draft for Review

## Executive Summary

This document provides detailed technical specifications for implementing the Chatboard paradigm in BioMate, transforming the current chatbot interface into a multi-panel co-creation workspace optimized for knowledge-intensive bioinformatics workflows.

**Key Deliverables:**
- Multi-panel React workspace with workflow canvas, knowledge panel, and context panel
- Workspace state management with version control and audit trails
- Knowledge aggregation service integrating ToolUniverse and Claude Skills
- Real-time collaboration infrastructure
- Migration strategy from current implementation

---

## 1. Architecture Overview

### 1.1 System Components

```
┌─────────────────────────────────────────────────────────────────┐
│                    BioMate Chatboard Frontend                    │
│  ┌──────────────┬──────────────────────┬─────────────────────┐  │
│  │ Chat Panel   │ Workflow Canvas      │ Context Panel       │  │
│  │ (30% left)   │ (50% center)         │ (20% right)        │  │
│  │              │                      │                     │  │
│  │ Message UI   │ ReactFlow Graph      │ Dataset References  │  │
│  │ Intent Input │ Parameter Editors    │ Decision Logs       │  │
│  │ Follow-up    │ Tool Node Components │ Annotations        │  │
│  └──────────────┴──────────────────────┴─────────────────────┘  │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │ Knowledge Panel (20% bottom)                                 │ │
│  │ Literature | AI Suggestions | Tool Documentation            │ │
│  └─────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
                              │
                    WebSocket + REST API
                              │
┌─────────────────────────────────────────────────────────────────┐
│                  Express Middleware Layer                        │
│  • Workspace Service  • Knowledge Aggregation Service           │
│  • Version Control    • Collaboration Hub                       │
└─────────────────────────────────────────────────────────────────┘
                              │
┌─────────────────────────────────────────────────────────────────┐
│              Galaxy Python Backend (Port 8080)                   │
│  • Workflow Generation    • Tool Execution                      │
│  • Dataset Management     • Job Orchestration                   │
└─────────────────────────────────────────────────────────────────┘
```

### 1.2 Data Flow

**Workspace Creation Flow:**
```
User Intent → Chat Panel → WorkspaceService.createWorkspace()
           → GalaxyWorkflowGenerator.generate_workflow()
           → KnowledgeAggregator.gather_context()
           → Workspace State (with knowledge, workflow, context)
           → Multi-Panel UI Render
```

**User Edit Flow:**
```
Canvas Edit → WorkspaceService.updateWorkflow()
           → Version Control (create checkpoint)
           → Decision Log (record rationale)
           → Broadcast via WebSocket (if collaborative)
           → UI State Update
```

---

## 2. Frontend Implementation

### 2.1 File Structure

```
frontend/client/src/
├── components/
│   ├── chatboard/
│   │   ├── BioMateWorkspace.tsx          # Main workspace container
│   │   ├── ChatPanel.tsx                 # Left chat panel
│   │   ├── WorkflowCanvas.tsx            # Center workflow canvas
│   │   ├── KnowledgePanel.tsx            # Bottom knowledge panel
│   │   ├── ContextPanel.tsx              # Right context panel
│   │   ├── WorkflowStepNode.tsx          # Custom ReactFlow node
│   │   ├── ParameterEditor.tsx           # Inline parameter editing
│   │   └── CollaborativeCursor.tsx       # Real-time cursor display
│   └── (existing components)
├── hooks/
│   ├── useWorkspace.ts                   # Workspace state management
│   ├── useWebSocket.ts                   # WebSocket connection
│   └── useKnowledgePanel.ts              # Knowledge aggregation
├── services/
│   ├── workspace-service.ts              # Workspace CRUD operations
│   ├── knowledge-service.ts              # Knowledge fetching
│   └── collaboration-service.ts          # Real-time sync
└── types/
    ├── workspace.types.ts                # TypeScript interfaces
    └── knowledge.types.ts                # Knowledge types
```

### 2.2 Core Type Definitions

**File:** `frontend/client/src/types/workspace.types.ts`

```typescript
export interface BioMateWorkspace {
  id: string;
  userId: string;
  createdAt: string;
  updatedAt: string;

  // Chat conversation history
  conversation: Message[];

  // Workflow state (editable by user)
  workflow: {
    id: string;
    name: string;
    version: string;
    structure: WorkflowStep[];
    parameters: ParameterSet;
    validationStatus: 'valid' | 'invalid' | 'warning';
  };

  // Aggregated knowledge
  knowledge: {
    literature: LiteratureCitation[];
    toolDocs: ToolDocumentation[];
    suggestions: AISuggestion[];
    lastUpdated: string;
  };

  // Context and audit trail
  context: {
    datasets: DatasetReference[];
    decisions: DecisionLog[];
    notes: Annotation[];
    collaborators: Collaborator[];
  };

  // Version history
  history: WorkspaceVersion[];

  // Collaboration metadata
  isShared: boolean;
  permissions: WorkspacePermissions;
}

export interface WorkflowStep {
  id: string;
  toolId: string;
  toolName: string;
  toolVersion: string;
  position: { x: number; y: number };
  parameters: Record<string, any>;
  inputs: ConnectionMap;
  outputs: OutputDefinition[];
  metadata: {
    addedBy: 'ai' | 'user';
    addedAt: string;
    rationale?: string;
  };
}

export interface DecisionLog {
  id: string;
  timestamp: string;
  userId: string;
  action: 'parameter_change' | 'tool_replace' | 'step_add' | 'step_remove';
  target: string; // step ID or parameter path
  before: any;
  after: any;
  rationale: string;
  aiSuggested: boolean;
}

export interface LiteratureCitation {
  pmid?: string;
  doi?: string;
  title: string;
  authors: string[];
  journal: string;
  year: number;
  relevance: number; // 0-1 score
  snippet: string;
  relatedTools: string[]; // Tool IDs mentioned
}

export interface AISuggestion {
  id: string;
  type: 'parameter_optimization' | 'alternative_tool' | 'quality_check' | 'best_practice';
  severity: 'info' | 'warning' | 'critical';
  target: string; // Step ID or parameter path
  message: string;
  reasoning: string;
  actionable: boolean;
  suggestedFix?: any;
  relatedKnowledge?: string[]; // References to literature or docs
}
```

### 2.3 Main Workspace Component

**File:** `frontend/client/src/components/chatboard/BioMateWorkspace.tsx`

```typescript
import React, { useState, useEffect, useCallback } from 'react';
import { ChatPanel } from './ChatPanel';
import { WorkflowCanvas } from './WorkflowCanvas';
import { KnowledgePanel } from './KnowledgePanel';
import { ContextPanel } from './ContextPanel';
import { useWorkspace } from '../../hooks/useWorkspace';
import { useWebSocket } from '../../hooks/useWebSocket';
import type { BioMateWorkspace, DecisionLog, WorkflowStep } from '../../types/workspace.types';

export const BioMateWorkspace: React.FC = () => {
  const {
    workspace,
    loading,
    error,
    sendMessage,
    updateWorkflow,
    addDecisionLog,
    createCheckpoint
  } = useWorkspace();

  const { sendUpdate, onRemoteUpdate } = useWebSocket(workspace?.id);

  const [selectedStepId, setSelectedStepId] = useState<string | null>(null);
  const [showKnowledgePanel, setShowKnowledgePanel] = useState(true);

  // Handle user message from chat panel
  const handleUserMessage = useCallback(async (message: string) => {
    await sendMessage(message);
    // Workspace will update via hook subscription
  }, [sendMessage]);

  // Handle parameter changes on canvas
  const handleParameterChange = useCallback(async (
    stepId: string,
    paramName: string,
    newValue: any,
    rationale?: string
  ) => {
    const step = workspace?.workflow.structure.find(s => s.id === stepId);
    if (!step) return;

    const oldValue = step.parameters[paramName];

    // Log the decision
    const decisionLog: DecisionLog = {
      id: crypto.randomUUID(),
      timestamp: new Date().toISOString(),
      userId: workspace!.userId,
      action: 'parameter_change',
      target: `${stepId}.${paramName}`,
      before: oldValue,
      after: newValue,
      rationale: rationale || 'User manual edit',
      aiSuggested: false
    };

    await addDecisionLog(decisionLog);
    await updateWorkflow({
      stepId,
      updates: { parameters: { ...step.parameters, [paramName]: newValue } }
    });

    // Broadcast to collaborators
    if (workspace?.isShared) {
      sendUpdate({
        type: 'parameter_change',
        data: { stepId, paramName, newValue, decisionLog }
      });
    }
  }, [workspace, addDecisionLog, updateWorkflow, sendUpdate]);

  // Handle tool replacement
  const handleToolReplace = useCallback(async (
    stepId: string,
    newToolId: string,
    rationale: string
  ) => {
    const step = workspace?.workflow.structure.find(s => s.id === stepId);
    if (!step) return;

    const decisionLog: DecisionLog = {
      id: crypto.randomUUID(),
      timestamp: new Date().toISOString(),
      userId: workspace!.userId,
      action: 'tool_replace',
      target: stepId,
      before: { toolId: step.toolId, toolName: step.toolName },
      after: { toolId: newToolId },
      rationale,
      aiSuggested: false
    };

    await addDecisionLog(decisionLog);
    await updateWorkflow({
      stepId,
      updates: { toolId: newToolId }
    });

    // Create checkpoint for major changes
    await createCheckpoint(`Tool replaced: ${step.toolName} → ${newToolId}`);
  }, [workspace, addDecisionLog, updateWorkflow, createCheckpoint]);

  // Handle AI suggestion application
  const handleApplySuggestion = useCallback(async (suggestionId: string) => {
    const suggestion = workspace?.knowledge.suggestions.find(s => s.id === suggestionId);
    if (!suggestion || !suggestion.actionable) return;

    // Apply the suggested fix
    // (Implementation depends on suggestion type)

    // Log as AI-suggested decision
    const decisionLog: DecisionLog = {
      id: crypto.randomUUID(),
      timestamp: new Date().toISOString(),
      userId: workspace!.userId,
      action: suggestion.type.startsWith('parameter') ? 'parameter_change' : 'tool_replace',
      target: suggestion.target,
      before: null,
      after: suggestion.suggestedFix,
      rationale: `Applied AI suggestion: ${suggestion.message}`,
      aiSuggested: true
    };

    await addDecisionLog(decisionLog);
  }, [workspace, addDecisionLog]);

  // Subscribe to remote updates (collaborative editing)
  useEffect(() => {
    if (!workspace?.isShared) return;

    return onRemoteUpdate((update) => {
      // Handle updates from other collaborators
      console.log('Remote update:', update);
      // Workspace state will update via backend broadcast
    });
  }, [workspace?.isShared, onRemoteUpdate]);

  if (loading) {
    return <div className="loading-spinner">Loading workspace...</div>;
  }

  if (error) {
    return <div className="error-message">Error: {error}</div>;
  }

  if (!workspace) {
    return <div className="empty-state">Create a new workspace to get started</div>;
  }

  return (
    <div className="biomate-workspace">
      <div className="workspace-header">
        <h1>{workspace.workflow.name}</h1>
        <div className="workspace-actions">
          <button onClick={() => createCheckpoint('Manual checkpoint')}>
            💾 Save Version
          </button>
          <button onClick={() => setShowKnowledgePanel(!showKnowledgePanel)}>
            {showKnowledgePanel ? '🔽' : '🔼'} Knowledge
          </button>
        </div>
      </div>

      <div className="workspace-grid">
        <div className="chat-panel-container">
          <ChatPanel
            conversation={workspace.conversation}
            onSendMessage={handleUserMessage}
            isLoading={loading}
          />
        </div>

        <div className="workflow-canvas-container">
          <WorkflowCanvas
            workspace={workspace}
            selectedStepId={selectedStepId}
            onSelectStep={setSelectedStepId}
            onParameterChange={handleParameterChange}
            onToolReplace={handleToolReplace}
          />
        </div>

        <div className="context-panel-container">
          <ContextPanel
            context={workspace.context}
            history={workspace.history}
            onAddNote={(note) => {/* TODO */}}
          />
        </div>
      </div>

      {showKnowledgePanel && (
        <div className="knowledge-panel-container">
          <KnowledgePanel
            knowledge={workspace.knowledge}
            selectedStepId={selectedStepId}
            onApplySuggestion={handleApplySuggestion}
          />
        </div>
      )}
    </div>
  );
};
```

### 2.4 Workflow Canvas Component

**File:** `frontend/client/src/components/chatboard/WorkflowCanvas.tsx`

```typescript
import React, { useCallback, useMemo } from 'react';
import ReactFlow, {
  Node,
  Edge,
  Controls,
  Background,
  MiniMap,
  useNodesState,
  useEdgesState,
  addEdge,
  Connection
} from 'reactflow';
import 'reactflow/dist/style.css';
import { WorkflowStepNode } from './WorkflowStepNode';
import type { BioMateWorkspace } from '../../types/workspace.types';

interface WorkflowCanvasProps {
  workspace: BioMateWorkspace;
  selectedStepId: string | null;
  onSelectStep: (stepId: string | null) => void;
  onParameterChange: (stepId: string, param: string, value: any, rationale?: string) => void;
  onToolReplace: (stepId: string, newToolId: string, rationale: string) => void;
}

const nodeTypes = {
  workflowStep: WorkflowStepNode
};

export const WorkflowCanvas: React.FC<WorkflowCanvasProps> = ({
  workspace,
  selectedStepId,
  onSelectStep,
  onParameterChange,
  onToolReplace
}) => {
  // Convert workflow structure to ReactFlow nodes
  const initialNodes: Node[] = useMemo(() => {
    return workspace.workflow.structure.map(step => ({
      id: step.id,
      type: 'workflowStep',
      position: step.position,
      data: {
        step,
        isSelected: step.id === selectedStepId,
        onParameterChange: (param: string, value: any, rationale?: string) => {
          onParameterChange(step.id, param, value, rationale);
        },
        onToolReplace: (newToolId: string, rationale: string) => {
          onToolReplace(step.id, newToolId, rationale);
        }
      }
    }));
  }, [workspace.workflow.structure, selectedStepId, onParameterChange, onToolReplace]);

  // Convert workflow connections to ReactFlow edges
  const initialEdges: Edge[] = useMemo(() => {
    const edges: Edge[] = [];
    workspace.workflow.structure.forEach(step => {
      Object.entries(step.inputs).forEach(([inputName, connection]) => {
        if (connection.sourceStepId) {
          edges.push({
            id: `${connection.sourceStepId}-${step.id}`,
            source: connection.sourceStepId,
            target: step.id,
            sourceHandle: connection.sourceOutput,
            targetHandle: inputName,
            animated: workspace.workflow.validationStatus === 'valid'
          });
        }
      });
    });
    return edges;
  }, [workspace.workflow.structure, workspace.workflow.validationStatus]);

  const [nodes, setNodes, onNodesChange] = useNodesState(initialNodes);
  const [edges, setEdges, onEdgesChange] = useEdgesState(initialEdges);

  const onConnect = useCallback((params: Connection) => {
    setEdges((eds) => addEdge(params, eds));
    // TODO: Send connection update to backend
  }, [setEdges]);

  const onNodeClick = useCallback((event: React.MouseEvent, node: Node) => {
    onSelectStep(node.id);
  }, [onSelectStep]);

  return (
    <div className="workflow-canvas">
      <ReactFlow
        nodes={nodes}
        edges={edges}
        onNodesChange={onNodesChange}
        onEdgesChange={onEdgesChange}
        onConnect={onConnect}
        onNodeClick={onNodeClick}
        nodeTypes={nodeTypes}
        fitView
        attributionPosition="bottom-left"
      >
        <Controls />
        <MiniMap />
        <Background />
      </ReactFlow>

      <div className="canvas-overlay">
        <div className="validation-status">
          {workspace.workflow.validationStatus === 'valid' && (
            <span className="status-badge valid">✓ Valid Workflow</span>
          )}
          {workspace.workflow.validationStatus === 'invalid' && (
            <span className="status-badge invalid">✗ Invalid Workflow</span>
          )}
          {workspace.workflow.validationStatus === 'warning' && (
            <span className="status-badge warning">⚠ Warnings</span>
          )}
        </div>
      </div>
    </div>
  );
};
```

### 2.5 Knowledge Panel Component

**File:** `frontend/client/src/components/chatboard/KnowledgePanel.tsx`

```typescript
import React, { useState } from 'react';
import type { Knowledge, AISuggestion, LiteratureCitation } from '../../types/workspace.types';

interface KnowledgePanelProps {
  knowledge: Knowledge;
  selectedStepId: string | null;
  onApplySuggestion: (suggestionId: string) => void;
}

export const KnowledgePanel: React.FC<KnowledgePanelProps> = ({
  knowledge,
  selectedStepId,
  onApplySuggestion
}) => {
  const [activeTab, setActiveTab] = useState<'suggestions' | 'literature' | 'docs'>('suggestions');

  // Filter suggestions for selected step
  const relevantSuggestions = selectedStepId
    ? knowledge.suggestions.filter(s => s.target.startsWith(selectedStepId))
    : knowledge.suggestions;

  // Filter literature for selected step
  const relevantLiterature = selectedStepId
    ? knowledge.literature.filter(lit => {
        const step = /* get step by selectedStepId */;
        return lit.relatedTools.includes(step?.toolId || '');
      })
    : knowledge.literature;

  return (
    <div className="knowledge-panel">
      <div className="panel-header">
        <h3>Knowledge Base</h3>
        <div className="panel-tabs">
          <button
            className={activeTab === 'suggestions' ? 'active' : ''}
            onClick={() => setActiveTab('suggestions')}
          >
            💡 Suggestions ({relevantSuggestions.length})
          </button>
          <button
            className={activeTab === 'literature' ? 'active' : ''}
            onClick={() => setActiveTab('literature')}
          >
            📚 Literature ({relevantLiterature.length})
          </button>
          <button
            className={activeTab === 'docs' ? 'active' : ''}
            onClick={() => setActiveTab('docs')}
          >
            🔧 Tool Docs ({knowledge.toolDocs.length})
          </button>
        </div>
      </div>

      <div className="panel-content">
        {activeTab === 'suggestions' && (
          <SuggestionsTab
            suggestions={relevantSuggestions}
            onApply={onApplySuggestion}
          />
        )}
        {activeTab === 'literature' && (
          <LiteratureTab literature={relevantLiterature} />
        )}
        {activeTab === 'docs' && (
          <DocsTab docs={knowledge.toolDocs} />
        )}
      </div>
    </div>
  );
};

const SuggestionsTab: React.FC<{
  suggestions: AISuggestion[];
  onApply: (id: string) => void;
}> = ({ suggestions, onApply }) => {
  if (suggestions.length === 0) {
    return <div className="empty-state">No suggestions available</div>;
  }

  return (
    <div className="suggestions-list">
      {suggestions.map(suggestion => (
        <div
          key={suggestion.id}
          className={`suggestion-card ${suggestion.severity}`}
        >
          <div className="suggestion-header">
            <span className="suggestion-type">{suggestion.type.replace(/_/g, ' ')}</span>
            <span className="suggestion-severity">{suggestion.severity}</span>
          </div>
          <p className="suggestion-message">{suggestion.message}</p>
          <details className="suggestion-reasoning">
            <summary>Reasoning</summary>
            <p>{suggestion.reasoning}</p>
          </details>
          {suggestion.actionable && (
            <button
              className="apply-suggestion-btn"
              onClick={() => onApply(suggestion.id)}
            >
              Apply Fix
            </button>
          )}
        </div>
      ))}
    </div>
  );
};

const LiteratureTab: React.FC<{
  literature: LiteratureCitation[];
}> = ({ literature }) => {
  return (
    <div className="literature-list">
      {literature.map((citation, idx) => (
        <div key={idx} className="citation-card">
          <h4>{citation.title}</h4>
          <p className="citation-meta">
            {citation.authors.slice(0, 3).join(', ')}
            {citation.authors.length > 3 && ' et al.'} ({citation.year})
          </p>
          <p className="citation-journal">{citation.journal}</p>
          <p className="citation-snippet">{citation.snippet}</p>
          <div className="citation-actions">
            {citation.pmid && (
              <a href={`https://pubmed.ncbi.nlm.nih.gov/${citation.pmid}/`} target="_blank">
                PubMed
              </a>
            )}
            {citation.doi && (
              <a href={`https://doi.org/${citation.doi}`} target="_blank">
                DOI
              </a>
            )}
          </div>
        </div>
      ))}
    </div>
  );
};

const DocsTab: React.FC<{
  docs: any[]; // TODO: proper type
}> = ({ docs }) => {
  return (
    <div className="docs-list">
      {docs.map((doc, idx) => (
        <div key={idx} className="doc-card">
          <h4>{doc.toolName}</h4>
          <p>{doc.description}</p>
        </div>
      ))}
    </div>
  );
};
```

---

## 3. Backend Implementation

### 3.1 Express Middleware Structure

**File:** `frontend/server/workspace-service.ts`

```typescript
import { Router } from 'express';
import { v4 as uuidv4 } from 'uuid';
import axios from 'axios';
import type { BioMateWorkspace, DecisionLog, WorkspaceVersion } from '../client/src/types/workspace.types';

const router = Router();

// In-memory workspace storage (replace with database in production)
const workspaces = new Map<string, BioMateWorkspace>();

// Create new workspace from user intent
router.post('/api/workspaces', async (req, res) => {
  const { userId, userIntent, datasets } = req.body;

  try {
    // Step 1: Generate workflow from Galaxy backend
    const workflowResponse = await axios.post('http://localhost:8080/api/ai/workflow', {
      user_input: userIntent,
      datasets: datasets || []
    });

    const galaxyWorkflow = workflowResponse.data;

    // Step 2: Aggregate knowledge using ToolUniverse and Claude Skills
    const knowledge = await aggregateKnowledge(userIntent, galaxyWorkflow);

    // Step 3: Create workspace
    const workspace: BioMateWorkspace = {
      id: uuidv4(),
      userId,
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
      conversation: [{
        id: uuidv4(),
        role: 'user',
        content: userIntent,
        timestamp: new Date().toISOString()
      }],
      workflow: {
        id: galaxyWorkflow.id,
        name: galaxyWorkflow.name,
        version: '1.0.0',
        structure: galaxyWorkflow.steps.map((step: any) => ({
          id: step.id,
          toolId: step.tool_id,
          toolName: step.tool_name,
          toolVersion: step.tool_version,
          position: step.position || { x: 0, y: 0 }, // TODO: Auto-layout
          parameters: step.state?.inputs || {},
          inputs: step.input_connections || {},
          outputs: step.outputs || [],
          metadata: {
            addedBy: 'ai',
            addedAt: new Date().toISOString(),
            rationale: step.annotation || ''
          }
        })),
        parameters: {},
        validationStatus: 'valid'
      },
      knowledge,
      context: {
        datasets: datasets || [],
        decisions: [],
        notes: [],
        collaborators: [{ userId, role: 'owner' }]
      },
      history: [{
        version: '1.0.0',
        timestamp: new Date().toISOString(),
        snapshot: null, // Store initial state
        message: 'Workspace created'
      }],
      isShared: false,
      permissions: { owner: userId, editors: [], viewers: [] }
    };

    workspaces.set(workspace.id, workspace);

    res.json(workspace);
  } catch (error) {
    console.error('Error creating workspace:', error);
    res.status(500).json({ error: 'Failed to create workspace' });
  }
});

// Get workspace by ID
router.get('/api/workspaces/:id', (req, res) => {
  const workspace = workspaces.get(req.params.id);
  if (!workspace) {
    return res.status(404).json({ error: 'Workspace not found' });
  }
  res.json(workspace);
});

// Update workflow within workspace
router.patch('/api/workspaces/:id/workflow', async (req, res) => {
  const workspace = workspaces.get(req.params.id);
  if (!workspace) {
    return res.status(404).json({ error: 'Workspace not found' });
  }

  const { stepId, updates } = req.body;

  // Find and update step
  const stepIndex = workspace.workflow.structure.findIndex(s => s.id === stepId);
  if (stepIndex === -1) {
    return res.status(404).json({ error: 'Step not found' });
  }

  workspace.workflow.structure[stepIndex] = {
    ...workspace.workflow.structure[stepIndex],
    ...updates
  };

  workspace.updatedAt = new Date().toISOString();

  // Validate workflow (optional)
  // workspace.workflow.validationStatus = await validateWorkflow(workspace.workflow);

  // Broadcast update to collaborators via WebSocket
  // broadcastUpdate(workspace.id, { type: 'workflow_update', data: updates });

  res.json(workspace);
});

// Add decision log
router.post('/api/workspaces/:id/decisions', (req, res) => {
  const workspace = workspaces.get(req.params.id);
  if (!workspace) {
    return res.status(404).json({ error: 'Workspace not found' });
  }

  const decision: DecisionLog = req.body;
  workspace.context.decisions.push(decision);
  workspace.updatedAt = new Date().toISOString();

  res.json(workspace);
});

// Create version checkpoint
router.post('/api/workspaces/:id/checkpoints', (req, res) => {
  const workspace = workspaces.get(req.params.id);
  if (!workspace) {
    return res.status(404).json({ error: 'Workspace not found' });
  }

  const { message } = req.body;

  const version: WorkspaceVersion = {
    version: `1.${workspace.history.length}.0`,
    timestamp: new Date().toISOString(),
    snapshot: JSON.parse(JSON.stringify(workspace)), // Deep copy
    message
  };

  workspace.history.push(version);
  workspace.updatedAt = new Date().toISOString();

  res.json(workspace);
});

// Knowledge aggregation helper
async function aggregateKnowledge(userIntent: string, workflow: any): Promise<any> {
  // TODO: Integrate ToolUniverse embedding search
  // TODO: Query PubMed for relevant literature
  // TODO: Fetch tool documentation from Claude Skills
  // TODO: Generate AI suggestions based on workflow analysis

  return {
    literature: [],
    toolDocs: [],
    suggestions: [],
    lastUpdated: new Date().toISOString()
  };
}

export default router;
```

### 3.2 Knowledge Aggregation Service

**File:** `frontend/server/knowledge-aggregation-service.ts`

```typescript
import axios from 'axios';
import type { Knowledge, LiteratureCitation, AISuggestion, ToolDocumentation } from '../client/src/types/workspace.types';

export class KnowledgeAggregationService {
  private tooluniverse: any; // TODO: Import ToolUniverse SDK
  private claudeSkills: Map<string, any>;

  constructor() {
    // Initialize ToolUniverse (assuming integration completed)
    // this.tooluniverse = new ToolUniverse();

    // Load Claude Skills from research_repos
    this.claudeSkills = new Map();
  }

  /**
   * Aggregate all knowledge sources for a workflow
   */
  async aggregateForWorkflow(userIntent: string, workflow: any): Promise<Knowledge> {
    const [literature, toolDocs, suggestions] = await Promise.all([
      this.fetchLiterature(userIntent, workflow),
      this.fetchToolDocumentation(workflow),
      this.generateAISuggestions(workflow)
    ]);

    return {
      literature,
      toolDocs,
      suggestions,
      lastUpdated: new Date().toISOString()
    };
  }

  /**
   * Fetch relevant literature from PubMed and other sources
   */
  private async fetchLiterature(
    userIntent: string,
    workflow: any
  ): Promise<LiteratureCitation[]> {
    const citations: LiteratureCitation[] = [];

    // Extract tool names from workflow
    const toolNames = workflow.steps.map((step: any) => step.tool_name);

    // Search PubMed for each tool
    for (const toolName of toolNames) {
      try {
        const query = `${toolName} bioinformatics`;
        const response = await axios.get('https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi', {
          params: {
            db: 'pubmed',
            term: query,
            retmax: 3,
            retmode: 'json'
          }
        });

        const pmids = response.data.esearchresult?.idlist || [];

        // Fetch details for each PMID
        for (const pmid of pmids) {
          const detailsResponse = await axios.get('https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esummary.fcgi', {
            params: {
              db: 'pubmed',
              id: pmid,
              retmode: 'json'
            }
          });

          const article = detailsResponse.data.result?.[pmid];
          if (article) {
            citations.push({
              pmid,
              title: article.title,
              authors: article.authors?.map((a: any) => a.name) || [],
              journal: article.fulljournalname || '',
              year: parseInt(article.pubdate?.split(' ')[0] || '2024'),
              relevance: 0.8, // TODO: Compute relevance score
              snippet: article.title, // TODO: Fetch abstract
              relatedTools: [toolName]
            });
          }
        }
      } catch (error) {
        console.error(`Error fetching literature for ${toolName}:`, error);
      }
    }

    // Sort by relevance
    return citations.sort((a, b) => b.relevance - a.relevance);
  }

  /**
   * Fetch tool documentation from Claude Skills
   */
  private async fetchToolDocumentation(workflow: any): Promise<ToolDocumentation[]> {
    const docs: ToolDocumentation[] = [];

    for (const step of workflow.steps) {
      // Check if tool has corresponding Claude Skill
      const skill = this.claudeSkills.get(step.tool_name.toLowerCase());
      if (skill) {
        docs.push({
          toolId: step.tool_id,
          toolName: step.tool_name,
          description: skill.description || '',
          bestPractices: skill.bestPractices || [],
          commonPitfalls: skill.commonPitfalls || [],
          examples: skill.examples || []
        });
      }
    }

    return docs;
  }

  /**
   * Generate AI suggestions for workflow optimization
   */
  private async generateAISuggestions(workflow: any): Promise<AISuggestion[]> {
    const suggestions: AISuggestion[] = [];

    // Example: Check for missing parameters
    for (const step of workflow.steps) {
      const requiredParams = step.tool_inputs?.filter((input: any) => !input.optional);
      const providedParams = Object.keys(step.state?.inputs || {});

      for (const param of requiredParams || []) {
        if (!providedParams.includes(param.name)) {
          suggestions.push({
            id: `${step.id}-missing-${param.name}`,
            type: 'parameter_optimization',
            severity: 'critical',
            target: step.id,
            message: `Missing required parameter: ${param.name}`,
            reasoning: `The tool ${step.tool_name} requires this parameter for proper execution.`,
            actionable: false,
            suggestedFix: null
          });
        }
      }
    }

    // TODO: Add more sophisticated checks using Claude API
    // - Parameter value validation
    // - Alternative tool suggestions
    // - Best practice recommendations

    return suggestions;
  }

  /**
   * Update knowledge for a specific step (called when user edits)
   */
  async updateForStep(stepId: string, toolName: string): Promise<Partial<Knowledge>> {
    // Fetch updated literature and docs for this specific tool
    const [literature, toolDocs] = await Promise.all([
      this.fetchLiterature(toolName, { steps: [{ tool_name: toolName }] }),
      this.fetchToolDocumentation({ steps: [{ tool_name: toolName, tool_id: '' }] })
    ]);

    return {
      literature,
      toolDocs,
      lastUpdated: new Date().toISOString()
    };
  }
}
```

---

## 4. Integration with Existing Systems

### 4.1 Galaxy Backend Integration Points

**File:** `backend/lib/galaxy/ai/chatboard_workspace_manager.py`

```python
from typing import Dict, List, Any, Optional
from datetime import datetime
import json

class ChatboardWorkspaceManager:
    """
    Manages workspace state and integrates with Galaxy workflow execution.
    Extends existing GalaxyWorkflowGenerator with workspace capabilities.
    """

    def __init__(self, galaxy_ai_instance):
        self.galaxy_ai = galaxy_ai_instance
        self.workspaces = {}  # In-memory storage (replace with DB)

    def create_workspace_from_intent(
        self,
        user_id: str,
        user_intent: str,
        datasets: List[str] = None
    ) -> Dict[str, Any]:
        """
        Create a new chatboard workspace from user intent.
        Calls existing workflow generation, then wraps result in workspace structure.
        """
        # Use existing workflow generation
        workflow_result = self.galaxy_ai.generate_workflow(
            user_input=user_intent,
            datasets=datasets or []
        )

        workspace_id = f"ws_{datetime.now().timestamp()}"

        workspace = {
            'id': workspace_id,
            'user_id': user_id,
            'created_at': datetime.now().isoformat(),
            'conversation': [{
                'role': 'user',
                'content': user_intent,
                'timestamp': datetime.now().isoformat()
            }],
            'workflow': self._convert_to_workspace_workflow(workflow_result),
            'knowledge': self._initialize_knowledge(workflow_result),
            'context': {
                'datasets': datasets or [],
                'decisions': [],
                'notes': []
            },
            'history': []
        }

        self.workspaces[workspace_id] = workspace
        return workspace

    def update_workflow_step(
        self,
        workspace_id: str,
        step_id: str,
        updates: Dict[str, Any],
        decision_log: Dict[str, Any]
    ) -> Dict[str, Any]:
        """
        Update a workflow step and log the decision.
        """
        workspace = self.workspaces.get(workspace_id)
        if not workspace:
            raise ValueError(f"Workspace {workspace_id} not found")

        # Find step and update
        for step in workspace['workflow']['structure']:
            if step['id'] == step_id:
                step.update(updates)
                break

        # Log decision
        workspace['context']['decisions'].append(decision_log)
        workspace['updated_at'] = datetime.now().isoformat()

        # Validate workflow
        is_valid = self._validate_workflow(workspace['workflow'])
        workspace['workflow']['validation_status'] = (
            'valid' if is_valid else 'invalid'
        )

        return workspace

    def execute_workspace_workflow(
        self,
        workspace_id: str,
        history_id: str
    ) -> Dict[str, Any]:
        """
        Execute the workflow from a workspace.
        Converts workspace workflow back to Galaxy workflow format.
        """
        workspace = self.workspaces.get(workspace_id)
        if not workspace:
            raise ValueError(f"Workspace {workspace_id} not found")

        # Convert workspace workflow to Galaxy workflow
        galaxy_workflow = self._convert_to_galaxy_workflow(
            workspace['workflow']
        )

        # Use existing Galaxy execution
        execution_result = self.galaxy_ai.execute_workflow(
            workflow=galaxy_workflow,
            history_id=history_id
        )

        # Create version checkpoint
        self._create_checkpoint(
            workspace_id,
            f"Executed workflow at {datetime.now().isoformat()}"
        )

        return execution_result

    def _convert_to_workspace_workflow(
        self,
        galaxy_workflow: Dict[str, Any]
    ) -> Dict[str, Any]:
        """Convert Galaxy workflow format to workspace format."""
        return {
            'id': galaxy_workflow.get('uuid', ''),
            'name': galaxy_workflow.get('name', 'Untitled Workflow'),
            'version': '1.0.0',
            'structure': [
                {
                    'id': str(step_id),
                    'toolId': step.get('tool_id', ''),
                    'toolName': step.get('name', ''),
                    'toolVersion': step.get('tool_version', ''),
                    'position': step.get('position', {'x': 0, 'y': 0}),
                    'parameters': step.get('tool_state', {}),
                    'inputs': step.get('input_connections', {}),
                    'outputs': step.get('outputs', []),
                    'metadata': {
                        'addedBy': 'ai',
                        'addedAt': datetime.now().isoformat(),
                        'rationale': step.get('annotation', '')
                    }
                }
                for step_id, step in galaxy_workflow.get('steps', {}).items()
            ],
            'parameters': {},
            'validation_status': 'valid'
        }

    def _convert_to_galaxy_workflow(
        self,
        workspace_workflow: Dict[str, Any]
    ) -> Dict[str, Any]:
        """Convert workspace format back to Galaxy workflow format."""
        steps = {}
        for idx, step in enumerate(workspace_workflow['structure']):
            steps[str(idx)] = {
                'id': idx,
                'tool_id': step['toolId'],
                'name': step['toolName'],
                'tool_version': step['toolVersion'],
                'type': 'tool',
                'position': step['position'],
                'tool_state': step['parameters'],
                'input_connections': step['inputs'],
                'outputs': step['outputs']
            }

        return {
            'name': workspace_workflow['name'],
            'steps': steps,
            'version': workspace_workflow['version']
        }

    def _initialize_knowledge(
        self,
        workflow: Dict[str, Any]
    ) -> Dict[str, Any]:
        """Initialize knowledge base for workflow."""
        # TODO: Call knowledge aggregation service
        return {
            'literature': [],
            'toolDocs': [],
            'suggestions': [],
            'lastUpdated': datetime.now().isoformat()
        }

    def _validate_workflow(self, workflow: Dict[str, Any]) -> bool:
        """Validate workflow structure and connections."""
        # TODO: Implement comprehensive validation
        return True

    def _create_checkpoint(self, workspace_id: str, message: str):
        """Create a version checkpoint."""
        workspace = self.workspaces[workspace_id]
        workspace['history'].append({
            'version': f"1.{len(workspace['history'])}.0",
            'timestamp': datetime.now().isoformat(),
            'snapshot': json.dumps(workspace),
            'message': message
        })
```

### 4.2 Database Schema Extension

**File:** `backend/lib/galaxy/ai/chatboard_schema.sql`

```sql
-- Workspace table
CREATE TABLE IF NOT EXISTS chatboard_workspaces (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    workflow_id TEXT,
    is_shared BOOLEAN DEFAULT FALSE,
    FOREIGN KEY (workflow_id) REFERENCES stored_workflow(id)
);

-- Conversation history
CREATE TABLE IF NOT EXISTS chatboard_conversations (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    workspace_id TEXT NOT NULL,
    role TEXT NOT NULL,  -- 'user' or 'assistant'
    content TEXT NOT NULL,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (workspace_id) REFERENCES chatboard_workspaces(id)
);

-- Decision logs
CREATE TABLE IF NOT EXISTS chatboard_decisions (
    id TEXT PRIMARY KEY,
    workspace_id TEXT NOT NULL,
    user_id TEXT NOT NULL,
    action TEXT NOT NULL,  -- 'parameter_change', 'tool_replace', etc.
    target TEXT NOT NULL,  -- step ID or parameter path
    before_value TEXT,
    after_value TEXT,
    rationale TEXT,
    ai_suggested BOOLEAN DEFAULT FALSE,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (workspace_id) REFERENCES chatboard_workspaces(id)
);

-- Knowledge base cache
CREATE TABLE IF NOT EXISTS chatboard_knowledge (
    workspace_id TEXT NOT NULL,
    type TEXT NOT NULL,  -- 'literature', 'tool_doc', 'suggestion'
    content TEXT NOT NULL,  -- JSON blob
    last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (workspace_id) REFERENCES chatboard_workspaces(id)
);

-- Version history
CREATE TABLE IF NOT EXISTS chatboard_versions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    workspace_id TEXT NOT NULL,
    version TEXT NOT NULL,
    snapshot TEXT NOT NULL,  -- JSON blob of full workspace state
    message TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (workspace_id) REFERENCES chatboard_workspaces(id)
);

-- Collaboration metadata
CREATE TABLE IF NOT EXISTS chatboard_collaborators (
    workspace_id TEXT NOT NULL,
    user_id TEXT NOT NULL,
    role TEXT NOT NULL,  -- 'owner', 'editor', 'viewer'
    joined_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (workspace_id, user_id),
    FOREIGN KEY (workspace_id) REFERENCES chatboard_workspaces(id)
);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_workspace_user ON chatboard_workspaces(user_id);
CREATE INDEX IF NOT EXISTS idx_conversation_workspace ON chatboard_conversations(workspace_id);
CREATE INDEX IF NOT EXISTS idx_decision_workspace ON chatboard_decisions(workspace_id);
CREATE INDEX IF NOT EXISTS idx_decision_timestamp ON chatboard_decisions(timestamp);
```

---

## 5. Real-Time Collaboration

### 5.1 WebSocket Server Setup

**File:** `frontend/server/websocket-server.ts`

```typescript
import { Server as WebSocketServer } from 'ws';
import { Server as HTTPServer } from 'http';

interface CollaborationUpdate {
  workspaceId: string;
  userId: string;
  type: 'parameter_change' | 'tool_replace' | 'cursor_move' | 'step_select';
  data: any;
  timestamp: string;
}

export class ChatboardWebSocketServer {
  private wss: WebSocketServer;
  private workspaceClients: Map<string, Set<any>>; // workspace ID -> Set of clients

  constructor(server: HTTPServer) {
    this.wss = new WebSocketServer({ server, path: '/ws/chatboard' });
    this.workspaceClients = new Map();

    this.wss.on('connection', (ws, req) => {
      console.log('New WebSocket connection');

      ws.on('message', (message: string) => {
        try {
          const data = JSON.parse(message);
          this.handleMessage(ws, data);
        } catch (error) {
          console.error('Error parsing WebSocket message:', error);
        }
      });

      ws.on('close', () => {
        this.handleDisconnect(ws);
      });
    });
  }

  private handleMessage(ws: any, data: any) {
    switch (data.type) {
      case 'join_workspace':
        this.joinWorkspace(ws, data.workspaceId, data.userId);
        break;

      case 'leave_workspace':
        this.leaveWorkspace(ws, data.workspaceId);
        break;

      case 'workspace_update':
        this.broadcastUpdate(data.workspaceId, data, ws);
        break;

      case 'cursor_update':
        this.broadcastCursor(data.workspaceId, data, ws);
        break;
    }
  }

  private joinWorkspace(ws: any, workspaceId: string, userId: string) {
    if (!this.workspaceClients.has(workspaceId)) {
      this.workspaceClients.set(workspaceId, new Set());
    }

    ws.workspaceId = workspaceId;
    ws.userId = userId;

    const clients = this.workspaceClients.get(workspaceId)!;
    clients.add(ws);

    // Notify other clients about new collaborator
    this.broadcastUpdate(workspaceId, {
      type: 'collaborator_joined',
      userId,
      timestamp: new Date().toISOString()
    }, ws);

    console.log(`User ${userId} joined workspace ${workspaceId}`);
  }

  private leaveWorkspace(ws: any, workspaceId: string) {
    const clients = this.workspaceClients.get(workspaceId);
    if (clients) {
      clients.delete(ws);

      if (ws.userId) {
        this.broadcastUpdate(workspaceId, {
          type: 'collaborator_left',
          userId: ws.userId,
          timestamp: new Date().toISOString()
        }, ws);
      }
    }
  }

  private handleDisconnect(ws: any) {
    if (ws.workspaceId) {
      this.leaveWorkspace(ws, ws.workspaceId);
    }
  }

  private broadcastUpdate(workspaceId: string, update: any, sender?: any) {
    const clients = this.workspaceClients.get(workspaceId);
    if (!clients) return;

    const message = JSON.stringify(update);

    clients.forEach(client => {
      if (client !== sender && client.readyState === 1) { // OPEN state
        client.send(message);
      }
    });
  }

  private broadcastCursor(workspaceId: string, cursorData: any, sender: any) {
    const clients = this.workspaceClients.get(workspaceId);
    if (!clients) return;

    const message = JSON.stringify({
      type: 'cursor_update',
      userId: sender.userId,
      ...cursorData
    });

    clients.forEach(client => {
      if (client !== sender && client.readyState === 1) {
        client.send(message);
      }
    });
  }
}
```

### 5.2 Frontend WebSocket Hook

**File:** `frontend/client/src/hooks/useWebSocket.ts`

```typescript
import { useEffect, useRef, useCallback } from 'react';

interface WebSocketMessage {
  type: string;
  data: any;
  timestamp: string;
}

export function useWebSocket(workspaceId: string | undefined) {
  const ws = useRef<WebSocket | null>(null);
  const reconnectTimer = useRef<NodeJS.Timeout | null>(null);
  const listeners = useRef<Set<(message: WebSocketMessage) => void>>(new Set());

  useEffect(() => {
    if (!workspaceId) return;

    const connect = () => {
      const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
      const wsUrl = `${protocol}//${window.location.host}/ws/chatboard`;

      ws.current = new WebSocket(wsUrl);

      ws.current.onopen = () => {
        console.log('WebSocket connected');
        // Join workspace
        ws.current?.send(JSON.stringify({
          type: 'join_workspace',
          workspaceId,
          userId: 'current-user-id' // TODO: Get from auth context
        }));
      };

      ws.current.onmessage = (event) => {
        try {
          const message = JSON.parse(event.data);
          listeners.current.forEach(listener => listener(message));
        } catch (error) {
          console.error('Error parsing WebSocket message:', error);
        }
      };

      ws.current.onclose = () => {
        console.log('WebSocket disconnected, reconnecting...');
        reconnectTimer.current = setTimeout(connect, 3000);
      };

      ws.current.onerror = (error) => {
        console.error('WebSocket error:', error);
      };
    };

    connect();

    return () => {
      if (ws.current) {
        ws.current.close();
      }
      if (reconnectTimer.current) {
        clearTimeout(reconnectTimer.current);
      }
    };
  }, [workspaceId]);

  const sendUpdate = useCallback((update: any) => {
    if (ws.current?.readyState === WebSocket.OPEN) {
      ws.current.send(JSON.stringify({
        type: 'workspace_update',
        workspaceId,
        ...update,
        timestamp: new Date().toISOString()
      }));
    }
  }, [workspaceId]);

  const onRemoteUpdate = useCallback((callback: (message: WebSocketMessage) => void) => {
    listeners.current.add(callback);
    return () => {
      listeners.current.delete(callback);
    };
  }, []);

  return { sendUpdate, onRemoteUpdate };
}
```

---

## 6. Migration Strategy

### 6.1 Phase 1: Foundation (Weeks 1-2)

**Objectives:**
- Set up multi-panel UI structure
- Implement basic workflow canvas with ReactFlow
- Create workspace data model

**Tasks:**
1. Create new React components in `frontend/client/src/components/chatboard/`
2. Set up workspace state management with hooks
3. Integrate existing chat interface into ChatPanel component
4. Display existing workflow generation results on WorkflowCanvas
5. Add basic parameter viewing (no editing yet)

**Verification:**
- Users can create workspace from intent
- Workflow displays correctly on canvas
- Chat panel shows conversation history

### 6.2 Phase 2: Editing & Knowledge (Weeks 3-4)

**Objectives:**
- Enable inline parameter editing
- Implement knowledge aggregation
- Add decision logging

**Tasks:**
1. Build ParameterEditor component with validation
2. Implement workspace update API endpoints
3. Create KnowledgeAggregationService
4. Integrate PubMed literature search
5. Add basic AI suggestions (missing parameters, validation errors)
6. Implement decision logging system

**Verification:**
- Users can edit parameters inline on canvas
- Knowledge panel shows relevant literature
- All edits are logged with rationale

### 6.3 Phase 3: Context & Auditing (Weeks 5-6)

**Objectives:**
- Add context panel with audit trail
- Implement version control
- Enable workflow comparison

**Tasks:**
1. Build ContextPanel component
2. Implement version checkpoint system
3. Add decision log visualization
4. Create workflow diff viewer
5. Add dataset reference tracking
6. Implement annotation system

**Verification:**
- Users can view full decision history
- Version checkpoints can be created and restored
- Context panel shows relevant metadata

### 6.4 Phase 4: Collaboration (Weeks 7-8)

**Objectives:**
- Enable real-time collaboration
- Add WebSocket infrastructure
- Implement cursor tracking

**Tasks:**
1. Set up WebSocket server
2. Implement workspace subscription system
3. Add collaborative cursor display
4. Implement conflict resolution for simultaneous edits
5. Add collaborator presence indicators
6. Create sharing permission system

**Verification:**
- Multiple users can edit same workspace
- Changes sync in real-time
- No data conflicts occur

### 6.5 Phase 5: Polish & Optimization (Weeks 9-10)

**Objectives:**
- Performance optimization
- Accessibility improvements
- User testing and refinement

**Tasks:**
1. Optimize ReactFlow rendering performance
2. Add keyboard shortcuts
3. Implement accessibility features (ARIA labels, keyboard navigation)
4. Add loading states and error boundaries
5. Create user onboarding flow
6. Performance profiling and optimization

**Verification:**
- Application meets WCAG 2.1 AA standards
- Smooth performance with large workflows (50+ steps)
- Positive user feedback from testing

---

## 7. Testing Strategy

### 7.1 Unit Tests

**Test Coverage:**
- Workspace state management hooks
- Knowledge aggregation service
- Decision logging system
- Workflow validation logic

**Example Test:**

```typescript
// frontend/client/src/hooks/__tests__/useWorkspace.test.ts
import { renderHook, act } from '@testing-library/react-hooks';
import { useWorkspace } from '../useWorkspace';

describe('useWorkspace', () => {
  it('should create workspace from user intent', async () => {
    const { result } = renderHook(() => useWorkspace());

    await act(async () => {
      await result.current.createWorkspace({
        userId: 'test-user',
        userIntent: 'Analyze DIA-LCMS proteomics data',
        datasets: []
      });
    });

    expect(result.current.workspace).toBeDefined();
    expect(result.current.workspace?.workflow.structure.length).toBeGreaterThan(0);
  });

  it('should log decision when parameter changes', async () => {
    const { result } = renderHook(() => useWorkspace());

    // ... create workspace first ...

    await act(async () => {
      await result.current.updateWorkflow({
        stepId: 'step-1',
        updates: { parameters: { threshold: 0.5 } }
      });
    });

    expect(result.current.workspace?.context.decisions.length).toBe(1);
    expect(result.current.workspace?.context.decisions[0].action).toBe('parameter_change');
  });
});
```

### 7.2 Integration Tests

**Test Scenarios:**
- End-to-end workspace creation flow
- Knowledge aggregation with external APIs
- Real-time collaboration with multiple clients
- Version control and checkpoint restoration

**Example E2E Test:**

```typescript
// backend/tests/e2e_ui/test_cases/test_chatboard_workspace.py
import pytest
from playwright.sync_api import Page, expect

def test_create_and_edit_workspace(page: Page):
    """Test full chatboard workflow creation and editing"""

    # Navigate to BioMate
    page.goto("http://localhost:3000")

    # Enter user intent
    page.fill('[data-testid="user-intent-input"]', 'Analyze proteomics data')
    page.click('[data-testid="generate-workflow-btn"]')

    # Wait for workspace to load
    page.wait_for_selector('[data-testid="workflow-canvas"]')

    # Verify workflow appears on canvas
    workflow_steps = page.locator('[data-testid="workflow-step"]')
    expect(workflow_steps).to_have_count_greater_than(0)

    # Click on first step
    workflow_steps.first.click()

    # Edit parameter
    page.fill('[data-testid="param-input-threshold"]', '0.75')
    page.press('[data-testid="param-input-threshold"]', 'Enter')

    # Verify decision log appears
    page.click('[data-testid="context-panel-tab-decisions"]')
    decision_log = page.locator('[data-testid="decision-log-entry"]').first
    expect(decision_log).to_contain_text('parameter_change')

    # Check knowledge panel
    page.click('[data-testid="knowledge-panel-tab-literature"]')
    literature_items = page.locator('[data-testid="literature-citation"]')
    expect(literature_items).to_have_count_greater_than(0)
```

### 7.3 Performance Tests

**Metrics:**
- Workspace creation time < 3 seconds
- Canvas rendering time for 50 steps < 1 second
- WebSocket message latency < 100ms
- Knowledge aggregation < 5 seconds

**Load Testing:**
- 100 concurrent users editing workspaces
- 1000 workspaces stored in database
- Real-time collaboration with 10 users per workspace

---

## 8. Deployment Considerations

### 8.1 Infrastructure Requirements

**Frontend:**
- Node.js 18+
- React 18+
- ReactFlow library
- WebSocket support

**Backend:**
- Python 3.9+
- FastAPI or Flask for REST API
- WebSocket library (e.g., python-socketio)
- PostgreSQL or SQLite for workspace storage

**External Services:**
- PubMed E-utilities API (no API key required for low volume)
- ToolUniverse embedding search (local or hosted)
- Claude API for AI suggestions

### 8.2 Environment Variables

```bash
# .env
NODE_ENV=production
REACT_APP_API_URL=http://localhost:8080
REACT_APP_WS_URL=ws://localhost:8080

GALAXY_API_KEY=your_key_here
ANTHROPIC_API_KEY=your_key_here
PUBMED_API_KEY=optional

# Database
DATABASE_URL=postgresql://user:password@localhost:5432/biomate
# or
DATABASE_PATH=/path/to/biomate.db

# ToolUniverse
TOOLUNIVERSE_EMBEDDING_MODEL=all-MiniLM-L6-v2
TOOLUNIVERSE_CACHE_DIR=/path/to/cache
```

### 8.3 Docker Configuration

**File:** `docker-compose.chatboard.yml`

```yaml
version: '3.8'

services:
  biomate-frontend:
    build:
      context: ./frontend
      dockerfile: Dockerfile
    ports:
      - "3000:3000"
    environment:
      - REACT_APP_API_URL=http://biomate-backend:8080
      - REACT_APP_WS_URL=ws://biomate-backend:8080
    depends_on:
      - biomate-backend

  biomate-backend:
    build:
      context: ./backend
      dockerfile: Dockerfile
    ports:
      - "8080:8080"
    environment:
      - DATABASE_URL=postgresql://biomate:password@postgres:5432/biomate
      - ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}
    volumes:
      - ./backend/data:/app/data
    depends_on:
      - postgres

  postgres:
    image: postgres:15
    environment:
      - POSTGRES_USER=biomate
      - POSTGRES_PASSWORD=password
      - POSTGRES_DB=biomate
    volumes:
      - postgres-data:/var/lib/postgresql/data

volumes:
  postgres-data:
```

---

## 9. Success Metrics

### 9.1 User Engagement Metrics

- **Workspace Creation Rate:** % of sessions that create workspaces
- **Edit Frequency:** Average number of edits per workspace
- **Knowledge Panel Usage:** % of sessions that interact with knowledge panel
- **Collaboration Rate:** % of workspaces shared with collaborators
- **Version Checkpoint Usage:** Average checkpoints per workspace

### 9.2 System Performance Metrics

- **Workspace Load Time:** < 2 seconds (p95)
- **Parameter Edit Latency:** < 200ms (p95)
- **Knowledge Aggregation Time:** < 5 seconds (p95)
- **WebSocket Message Latency:** < 100ms (p95)
- **System Uptime:** > 99.9%

### 9.3 Quality Metrics

- **Workflow Validation Accuracy:** > 95%
- **Literature Relevance Score:** > 0.7 (user-rated)
- **AI Suggestion Acceptance Rate:** > 30%
- **Decision Log Completion Rate:** > 80% (% with rationale)

---

## 10. Future Enhancements

### 10.1 Advanced Features (Post-Launch)

1. **AI Co-Pilot:**
   - Proactive workflow optimization suggestions
   - Automatic parameter tuning based on dataset characteristics
   - Predictive tool recommendations

2. **Template Library:**
   - Save workspaces as reusable templates
   - Community-shared workflow patterns
   - Domain-specific starting points (e.g., "RNA-Seq Analysis Template")

3. **Advanced Visualizations:**
   - Data flow preview
   - Expected output size estimation
   - Resource usage prediction

4. **Integration with External Tools:**
   - Import workflows from CWL/WDL formats
   - Export to Jupyter notebooks
   - Connect with external data repositories (SRA, ENA, etc.)

5. **Enhanced Collaboration:**
   - Comments and discussions on specific steps
   - @mentions and notifications
   - Role-based access control

### 10.2 Research Opportunities

1. **Adaptive Learning:**
   - Learn from user edit patterns
   - Personalized workflow recommendations
   - Domain-specific suggestion models

2. **Provenance Tracking:**
   - Full lineage tracking from raw data to publication
   - Automated methods section generation
   - Reproducibility score calculation

3. **Cross-Workspace Analysis:**
   - Identify common patterns across projects
   - Recommend workflows based on similar datasets
   - Community knowledge aggregation

---

## 11. Appendices

### 11.1 API Reference

**POST /api/workspaces**
Create new workspace from user intent

**GET /api/workspaces/:id**
Retrieve workspace by ID

**PATCH /api/workspaces/:id/workflow**
Update workflow within workspace

**POST /api/workspaces/:id/decisions**
Add decision log entry

**POST /api/workspaces/:id/checkpoints**
Create version checkpoint

**GET /api/workspaces/:id/knowledge**
Fetch aggregated knowledge

**WS /ws/chatboard**
WebSocket endpoint for real-time collaboration

### 11.2 Component Props Reference

See inline TypeScript interfaces in section 2.2-2.5

### 11.3 Database Schema Reference

See section 4.2 for complete SQL schema

---

## Conclusion

This technical specification provides a comprehensive blueprint for implementing the Chatboard paradigm in BioMate. The multi-panel workspace design transforms the traditional chatbot interface into a co-creation environment optimized for knowledge-intensive bioinformatics workflows.

**Key Implementation Principles:**
1. **Incremental Migration:** Build on existing infrastructure without disrupting current functionality
2. **User-Centric Design:** Prioritize transparency, control, and reproducibility
3. **Knowledge Integration:** Seamlessly incorporate literature, documentation, and AI suggestions
4. **Collaboration-Ready:** Design for real-time multi-user editing from the start
5. **Audit-Focused:** Comprehensive decision logging and version control

**Next Steps:**
1. Review and approve technical specification
2. Set up development environment and project structure
3. Begin Phase 1 implementation (Foundation)
4. Conduct weekly progress reviews and user testing

---

**Document Status:** Ready for Review
**Estimated Implementation Time:** 10 weeks (with 2-person team)
**Estimated Effort:** ~400 engineering hours
