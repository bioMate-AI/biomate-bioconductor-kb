# From Chatbot to Chatboard: BioMate UX Evolution Proposal

**Date:** October 25, 2025
**Inspired by:** Zuoshou Doctor's "Co-creation Panel" medical AI interface
**Purpose:** Evolve BioMate from linear chat to interactive workflow workspace

---

## Executive Summary

**Key Insight:** Bioinformatics workflow generation shares the same challenge as medical diagnosis - both are **knowledge-intensive, context-dependent processes** that require:
- Multiple rounds of refinement
- Complex decision tracking
- Parameter validation
- Project auditing and reproducibility

**The Problem with Current Chatbot Paradigm:**
```
User: "Analyze DIA-MS proteomics data"
Claude: [generates workflow in chat]
User: "Actually, I need to adjust parameters"
Claude: [generates new workflow, old one lost in chat history]
User: "What parameters did we use before?"
Claude: [has to scroll back through conversation]
```

**The Chatboard Solution:**
Transform BioMate into a **persistent workspace** where:
- Workflow evolves through iterations (not replaced)
- Parameters are visible and editable
- Decisions are traceable
- Knowledge is aggregated, not scattered

---

## Part 1: Understanding the Chatboard Paradigm

### The Core Formula

**Zuoshou Doctor's Insight:**
```
Chat (Explore/Follow-up/Confirm) + Board (Aggregate/Reuse/Re-edit) = Chatboard
```

**Translation to BioMate Context:**
```
Chat (Query/Refine/Validate) + Board (Workflow Canvas/Parameters/Data) = BioMate Workspace
```

### Chatbot vs Chatboard Comparison

| Aspect | Chatbot (Current) | Chatboard (Proposed) |
|--------|-------------------|----------------------|
| **Interaction** | Linear conversation | Persistent workspace |
| **Information** | Scattered in chat history | Aggregated in panels |
| **Iteration** | Replace previous response | Refine existing artifacts |
| **Context** | Lost after scroll | Always visible |
| **Traceability** | Difficult (search chat log) | Built-in (version history) |
| **Collaboration** | Share chat transcript | Share workspace state |
| **Auditing** | Manual screenshot/copy | Automatic capture |

### Why This Matters for Bioinformatics

**Domain Characteristics:**
1. ✅ **Knowledge-intensive:** Requires understanding of tools, parameters, datasets
2. ✅ **Context-dependent:** Same analysis type needs different parameters for different data
3. ✅ **Iterative refinement:** Workflows evolve through multiple rounds
4. ✅ **Multi-stakeholder:** PI, bioinformatician, lab technician all need to understand
5. ✅ **Audit requirements:** Need to trace decisions for publications/reproducibility
6. ✅ **Complex state:** Workflow structure + parameters + datasets + validation

**Current Pain Points Addressed:**
- **Parameter amnesia:** "What signal-to-noise ratio did we use last time?"
- **Workflow versioning:** "Can we compare this workflow to the previous one?"
- **Decision rationale:** "Why did we choose DIA-NN over OpenSWATH?"
- **Data provenance:** "Which BindingDB version was used?"
- **Collaboration friction:** "How do I explain this workflow to my PI?"

---

## Part 2: BioMate Chatboard Design

### 2.1 Layout Architecture

**Proposed Interface:**

```
┌──────────────────────────────────────────────────────────────────────┐
│  BioMate Workspace: DIA-MS Proteomics Analysis                       │
│  [Save] [Share] [Export] [History]                           User: YZ│
├────────────────────┬─────────────────────────────────────────────────┤
│                    │                                                  │
│  CHAT PANEL        │  WORKFLOW CANVAS                                │
│  (Left: 30%)       │  (Center: 50%)                                   │
│                    │                                                  │
│  User: Analyze     │  ┌──────────────────────────┐                   │
│  DIA-MS data       │  │  1. PeakPickerHiRes      │                   │
│                    │  │  ├─ Input: mzML          │                   │
│  Claude: I'll      │  │  ├─ signal_to_noise: 2.0 │ ◄── Editable     │
│  create a workflow │  │  └─ Output: centroided   │                   │
│  for DIA-MS...     │  └──────┬───────────────────┘                   │
│                    │         │                                        │
│  User: Use         │  ┌──────▼───────────────────┐                   │
│  Orbitrap params   │  │  2. OpenSWATH            │                   │
│                    │  │  ├─ library: spectral.tsv│                   │
│  Claude: Updated   │  │  ├─ min_upper_edge: 1.0  │ ◄── Hover for docs│
│  parameters for    │  │  └─ Output: peptides.csv │                   │
│  Orbitrap...       │  └──────┬───────────────────┘                   │
│                    │         │                                        │
│  [Type message...] │  ┌──────▼──────────────

────┐                   │
│                    │  │  3. Statistical Analysis  │                   │
│                    │  └───────────────────────────┘                   │
│                    │                                                  │
├────────────────────┼──────────────────────────────┬───────────────────┤
│                    │                              │                   │
│                    │  KNOWLEDGE PANEL             │  CONTEXT PANEL    │
│                    │  (Bottom: 20%, collapsible)  │  (Right: 20%)     │
│                    │                              │                   │
│                    │  📚 Related Literature       │  📊 Datasets      │
│                    │  • DIA-NN paper (PMID: xxx)  │  □ BindingDB      │
│                    │  • Optimal window schemes    │  ☑ UniProt        │
│                    │                              │  ☑ AlphaFold DB   │
│                    │  🔧 Tool Docs                │                   │
│                    │  • OpenSWATH parameters      │  ⚙️ Parameters    │
│                    │  • Peak picking guide        │  • Instrument:    │
│                    │                              │    Orbitrap       │
│                    │  💡 Suggestions              │  • Date: 2025-10  │
│                    │  • Consider batch effects    │                   │
│                    │  • QC sample recommended     │  📝 Notes         │
│                    │                              │  [Add annotation] │
└────────────────────┴──────────────────────────────┴───────────────────┘
```

### 2.2 Core Components

#### A. Chat Panel (Conversation)
**Purpose:** Natural language interaction, just like now
**Enhancements:**
- Reference workflow elements: "Adjust step 2 parameters"
- @ mentions: "@step1 what is the optimal signal-to-noise ratio?"
- Quick actions: Buttons to "Apply to workflow", "Save as template"

#### B. Workflow Canvas (Primary Workspace)
**Purpose:** Visual, editable workflow representation
**Features:**
- **Direct editing:** Click parameter values to modify
- **Inline validation:** Red highlight if parameter out of range
- **Tool documentation:** Hover tooltip with tool description
- **Visual connections:** Data flow arrows between steps
- **Version tracking:** "Compare with v1.2" button
- **Execution state:** Green ✓ for completed, spinner for running

#### C. Knowledge Panel (Context)
**Purpose:** Aggregate AI-gathered information
**Sections:**

1. **Related Literature** (Auto-populated via PubMed tool composition)
   ```
   📚 Recent Literature (auto-updated)
   • Smith et al. (2024): DIA-NN improves coverage by 30%
     → PMID: 38123456 [Read] [Cite]
   • Jones et al. (2023): Window scheme optimization
     → PMID: 37654321 [Read] [Cite]
   ```

2. **Tool Documentation** (From Claude Skills knowledge)
   ```
   🔧 OpenSWATH Best Practices
   • For Orbitrap: min_upper_edge_dist = 1.0
   • Mass tolerance: 0.05 Da (typical)
   • [Full documentation]
   ```

3. **AI Suggestions** (Proactive)
   ```
   💡 Recommendations
   • ⚠️ No QC sample detected - consider adding blank
   • ℹ️ Batch effects possible with 200 samples
   • ✓ Parameter choices align with recent literature
   ```

#### D. Context Panel (Metadata)
**Purpose:** Track experimental context and decisions

**Sections:**

1. **Datasets Used**
   ```
   📊 Knowledge Sources
   ☑ UniProt (2024-09 release)
   ☑ AlphaFold DB (v4)
   □ BindingDB (optional)

   [Edit] [Add dataset]
   ```

2. **Parameters Rationale**
   ```
   ⚙️ Key Decisions
   • Instrument: Orbitrap Q Exactive
     Reason: Lab standard instrument
   • Library-free search: Yes
     Reason: No spectral library available

   [Add note]
   ```

3. **Project Notes**
   ```
   📝 Annotations
   Oct 24: PI requested higher sensitivity
   Oct 23: Switched to DIA-NN per literature

   [Add note]
   ```

4. **Audit Trail** (Auto-generated)
   ```
   📜 Change History
   v1.3 (current): Adjusted s2n to 2.0
   v1.2: Added statistical analysis step
   v1.1: Changed from FeatureFinder to OpenSWATH

   [View diff] [Restore]
   ```

---

## Part 3: Key Interactions & User Flows

### 3.1 Workflow Creation Flow

**Traditional Chatbot (Current):**
```
1. User types: "DIA-MS proteomics workflow"
2. Claude generates workflow in chat
3. User reads, no easy way to modify
4. If changes needed, ask for new generation
5. Result: Lost previous version
```

**Chatboard (Proposed):**
```
1. User types: "DIA-MS proteomics workflow"
2. Workflow appears in CANVAS (center)
3. Knowledge Panel populates with:
   - Recent DIA-MS papers
   - Parameter recommendations
4. User clicks step parameter to edit
5. AI provides inline validation & suggestions
6. Changes auto-versioned
7. Result: Iterative refinement with full history
```

### 3.2 Parameter Refinement Flow

**Example: Adjusting peak picking parameters**

**Step 1: Initial generation**
```
Chat: "Create DIA-MS workflow for Orbitrap data"
→ Workflow appears with default parameters
→ Knowledge panel shows: "For Orbitrap: s2n typically 1.0-3.0"
```

**Step 2: User notices parameter**
```
User clicks "signal_to_noise: 2.0" in workflow canvas
→ Inline editor appears
→ Tooltip shows: "Range: 0.1-10.0. Higher = fewer peaks, lower = more sensitive"
→ AI suggestion: "2.0 is recommended for Orbitrap (based on recent literature)"
```

**Step 3: User adjusts**
```
User changes to 3.0
→ Workflow auto-updates
→ Chat panel shows: "ℹ️ Increased s2n to 3.0 for higher specificity"
→ Version saved: "v1.4: Adjusted peak picking sensitivity"
```

**Step 4: Validation**
```
AI checks: "⚠️ s2n=3.0 may reduce peptide coverage by ~10%"
User can:
- [Keep change]
- [Revert]
- [Ask AI for more info]
```

### 3.3 Knowledge Integration Flow

**Example: Adding context from literature**

**User:** "What's the latest method for DIA data?"

**System Response (Multi-panel update):**

**Chat Panel:**
```
Claude: Let me search recent literature...
Found 5 recent papers on DIA-MS methods.
The consensus is DIA-NN with library-free search.
```

**Knowledge Panel (Auto-populated):**
```
📚 Literature Added (Oct 25, 2025)
• Demichev et al. (2024): "DIA-NN 1.9 introduces..."
  Key finding: 30% more peptides vs traditional
  [Apply recommendation] [Read full paper]

• Optimal window scheme: 25 × 24 m/z windows
  [Update workflow]
```

**Workflow Canvas (Suggested change highlighted):**
```
┌─────────────────────────┐
│  2. OpenSWATH           │ ← Highlighted in blue
│                         │
│  💡 Suggestion:         │
│  Switch to DIA-NN?      │
│  [Apply] [Dismiss]      │
└─────────────────────────┘
```

**User clicks [Apply]:**
```
→ OpenSWATH replaced with DIA-NN
→ Parameters auto-adjusted for DIA-NN
→ Audit trail: "v1.5: Switched to DIA-NN per recent literature"
→ Knowledge panel: Citation added to references
```

### 3.4 Collaboration & Sharing Flow

**Scenario: Bioinformatician creates workflow, shares with PI**

**Step 1: Export workspace**
```
User clicks [Share]
→ Options:
  ☑ Include workflow structure
  ☑ Include parameters & rationale
  ☑ Include literature references
  ☐ Include execution history (optional)

→ Generate:
  • Interactive HTML report
  • Galaxy .ga file
  • PDF summary
  • Workspace link (collaborative editing)
```

**Step 2: PI opens shared link**
```
→ Same workspace view
→ Can see:
  • Full workflow with annotations
  • Decision rationale in Context Panel
  • Literature sources in Knowledge Panel
  • Change history (who/when/why)

→ Can add comments:
  "Why not use MaxQuant instead?"

→ Bioinformatician notified, responds inline
```

**Step 3: Iterate together**
```
→ PI adds note: "Need higher sensitivity for low-abundance proteins"
→ System suggests: "Decrease signal_to_noise threshold?"
→ Bioinformatician applies change
→ Both see update in real-time
→ Decision logged: "PI requested higher sensitivity - reduced s2n to 1.5"
```

---

## Part 4: Technical Implementation

### 4.1 Architecture Changes

**Current BioMate:**
```
Frontend (React)
    ↓ HTTP/SSE
Middleware (Express/Node.js)
    ↓
Galaxy Backend
    ↓
Workflow JSON (.ga file)
```

**Enhanced Chatboard BioMate:**
```
Frontend (React + State Management)
    ├─ Chat Component (existing)
    ├─ Workflow Canvas Component (NEW)
    ├─ Knowledge Panel Component (NEW)
    └─ Context Panel Component (NEW)
    ↓ HTTP/SSE + WebSocket (for real-time)
Middleware (Enhanced)
    ├─ Conversation service (existing)
    ├─ Workflow state service (NEW)
    ├─ Knowledge aggregation service (NEW)
    └─ Version control service (NEW)
    ↓
Galaxy Backend + ToolUniverse
    ├─ Galaxy workflows
    └─ Knowledge gathering (PubMed, UniProt, etc.)
```

### 4.2 Data Model

**Workspace State:**
```typescript
interface BioMateWorkspace {
  id: string;
  name: string;
  created: Date;
  updated: Date;
  owner: string;
  collaborators: string[];

  // Chat history (existing)
  conversation: Message[];

  // Workflow (enhanced)
  workflow: {
    version: string;
    structure: WorkflowStep[];
    parameters: ParameterSet;
    validation: ValidationResult;
  };

  // Knowledge aggregation (NEW)
  knowledge: {
    literature: LiteratureCitation[];
    toolDocs: ToolDocumentation[];
    suggestions: AISuggestion[];
  };

  // Context & metadata (NEW)
  context: {
    datasets: DatasetReference[];
    decisions: DecisionLog[];
    notes: Annotation[];
  };

  // Version control (NEW)
  history: WorkspaceVersion[];
}

interface WorkflowStep {
  id: string;
  toolId: string;
  toolName: string;
  parameters: Record<string, any>;
  position: {x: number, y: number};
  connections: Connection[];
  validationStatus: 'valid' | 'warning' | 'error';
  validationMessage?: string;
}

interface DecisionLog {
  timestamp: Date;
  user: string;
  action: string;
  rationale: string;
  relatedStep?: string;
}

interface WorkspaceVersion {
  version: string;
  timestamp: Date;
  user: string;
  changes: Change[];
  checkpoint: boolean;  // User-marked important version
}
```

### 4.3 Component Implementation

#### A. Workflow Canvas Component

**File:** `frontend/client/src/components/workflow-canvas.tsx`

```typescript
import React, { useState } from 'react';
import ReactFlow, { Node, Edge } from 'reactflow';
import 'reactflow/dist/style.css';

interface WorkflowCanvasProps {
  workspace: BioMateWorkspace;
  onParameterChange: (stepId: string, param: string, value: any) => void;
  onToolReplace: (stepId: string, newToolId: string) => void;
}

export const WorkflowCanvas: React.FC<WorkflowCanvasProps> = ({
  workspace,
  onParameterChange,
  onToolReplace
}) => {
  const [selectedStep, setSelectedStep] = useState<string | null>(null);

  // Convert workflow steps to ReactFlow nodes
  const nodes: Node[] = workspace.workflow.structure.map(step => ({
    id: step.id,
    type: 'workflowStep',
    position: step.position,
    data: {
      step,
      onParameterEdit: (param: string, value: any) => {
        onParameterChange(step.id, param, value);
      },
      onToolChange: (newToolId: string) => {
        onToolReplace(step.id, newToolId);
      }
    }
  }));

  // Convert connections to ReactFlow edges
  const edges: Edge[] = workspace.workflow.structure.flatMap(step =>
    step.connections.map(conn => ({
      id: `${step.id}-${conn.targetStepId}`,
      source: step.id,
      target: conn.targetStepId,
      label: conn.outputName
    }))
  );

  return (
    <div className="workflow-canvas">
      <div className="canvas-toolbar">
        <button onClick={() => exportWorkflow(workspace)}>
          Export .ga
        </button>
        <button onClick={() => validateWorkflow(workspace)}>
          Validate
        </button>
        <select onChange={(e) => loadVersion(e.target.value)}>
          {workspace.history.map(v => (
            <option key={v.version} value={v.version}>
              {v.version} ({v.timestamp.toLocaleString()})
            </option>
          ))}
        </select>
      </div>

      <ReactFlow
        nodes={nodes}
        edges={edges}
        nodeTypes={{
          workflowStep: WorkflowStepNode  // Custom node component
        }}
        onNodeClick={(event, node) => setSelectedStep(node.id)}
        fitView
      />

      {selectedStep && (
        <StepDetailsPanel
          step={getStep(selectedStep)}
          onClose={() => setSelectedStep(null)}
        />
      )}
    </div>
  );
};

// Custom node component for workflow steps
const WorkflowStepNode: React.FC<NodeProps> = ({ data }) => {
  const { step, onParameterEdit } = data;
  const [editing, setEditing] = useState<string | null>(null);

  return (
    <div className={`workflow-step ${step.validationStatus}`}>
      <div className="step-header">
        <strong>{step.toolName}</strong>
        {step.validationStatus === 'warning' && <span>⚠️</span>}
        {step.validationStatus === 'error' && <span>❌</span>}
      </div>

      <div className="step-parameters">
        {Object.entries(step.parameters).map(([key, value]) => (
          <div key={key} className="parameter-row">
            <span className="param-name">{key}:</span>
            {editing === key ? (
              <input
                type="text"
                value={value}
                onChange={(e) => {
                  onParameterEdit(key, e.target.value);
                  setEditing(null);
                }}
                onBlur={() => setEditing(null)}
                autoFocus
              />
            ) : (
              <span
                className="param-value clickable"
                onClick={() => setEditing(key)}
                title="Click to edit"
              >
                {String(value)}
              </span>
            )}
          </div>
        ))}
      </div>

      {step.validationMessage && (
        <div className="validation-message">
          {step.validationMessage}
        </div>
      )}
    </div>
  );
};
```

#### B. Knowledge Panel Component

**File:** `frontend/client/src/components/knowledge-panel.tsx`

```typescript
import React from 'react';

interface KnowledgePanelProps {
  knowledge: KnowledgeAggregation;
  onApplyRecommendation: (recommendation: AISuggestion) => void;
  onCitePaper: (citation: LiteratureCitation) => void;
}

export const KnowledgePanel: React.FC<KnowledgePanelProps> = ({
  knowledge,
  onApplyRecommendation,
  onCitePaper
}) => {
  const [activeTab, setActiveTab] = useState<'literature' | 'docs' | 'suggestions'>('suggestions');

  return (
    <div className="knowledge-panel">
      <div className="panel-tabs">
        <button
          className={activeTab === 'suggestions' ? 'active' : ''}
          onClick={() => setActiveTab('suggestions')}
        >
          💡 Suggestions ({knowledge.suggestions.length})
        </button>
        <button
          className={activeTab === 'literature' ? 'active' : ''}
          onClick={() => setActiveTab('literature')}
        >
          📚 Literature ({knowledge.literature.length})
        </button>
        <button
          className={activeTab === 'docs' ? 'active' : ''}
          onClick={() => setActiveTab('docs')}
        >
          🔧 Tool Docs
        </button>
      </div>

      <div className="panel-content">
        {activeTab === 'suggestions' && (
          <div className="suggestions-list">
            {knowledge.suggestions.map(suggestion => (
              <div key={suggestion.id} className={`suggestion ${suggestion.priority}`}>
                <div className="suggestion-header">
                  {suggestion.priority === 'high' && '⚠️'}
                  {suggestion.priority === 'medium' && 'ℹ️'}
                  {suggestion.priority === 'low' && '💡'}
                  <strong>{suggestion.title}</strong>
                </div>
                <div className="suggestion-body">
                  {suggestion.description}
                </div>
                {suggestion.action && (
                  <button
                    className="apply-button"
                    onClick={() => onApplyRecommendation(suggestion)}
                  >
                    {suggestion.action.label}
                  </button>
                )}
              </div>
            ))}
          </div>
        )}

        {activeTab === 'literature' && (
          <div className="literature-list">
            {knowledge.literature.map(paper => (
              <div key={paper.pmid} className="literature-item">
                <div className="paper-title">{paper.title}</div>
                <div className="paper-meta">
                  {paper.authors} ({paper.year})
                </div>
                <div className="paper-summary">{paper.summary}</div>
                <div className="paper-actions">
                  <a href={`https://pubmed.ncbi.nlm.nih.gov/${paper.pmid}`} target="_blank">
                    Read
                  </a>
                  <button onClick={() => onCitePaper(paper)}>
                    Cite in workflow
                  </button>
                </div>
              </div>
            ))}
          </div>
        )}

        {activeTab === 'docs' && (
          <div className="tool-docs-list">
            {knowledge.toolDocs.map(doc => (
              <div key={doc.toolId} className="tool-doc">
                <strong>{doc.toolName}</strong>
                <div className="doc-section">
                  <h4>Best Practices:</h4>
                  <ul>
                    {doc.bestPractices.map((practice, i) => (
                      <li key={i}>{practice}</li>
                    ))}
                  </ul>
                </div>
                {doc.parameterGuidance && (
                  <div className="doc-section">
                    <h4>Parameter Guidance:</h4>
                    <pre>{doc.parameterGuidance}</pre>
                  </div>
                )}
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
};
```

#### C. Context Panel Component

**File:** `frontend/client/src/components/context-panel.tsx`

```typescript
export const ContextPanel: React.FC<ContextPanelProps> = ({
  context,
  onAddNote,
  onAddDataset
}) => {
  return (
    <div className="context-panel">
      {/* Datasets Section */}
      <section className="panel-section">
        <h3>📊 Datasets</h3>
        {context.datasets.map(dataset => (
          <div key={dataset.id} className="dataset-item">
            <label>
              <input
                type="checkbox"
                checked={dataset.enabled}
                onChange={() => toggleDataset(dataset.id)}
              />
              {dataset.name}
            </label>
            <span className="dataset-version">{dataset.version}</span>
          </div>
        ))}
        <button onClick={onAddDataset}>+ Add dataset</button>
      </section>

      {/* Decision Log */}
      <section className="panel-section">
        <h3>⚙️ Key Decisions</h3>
        {context.decisions.map(decision => (
          <div key={decision.timestamp.toISOString()} className="decision-item">
            <div className="decision-header">
              <strong>{decision.action}</strong>
              <span className="decision-time">
                {formatRelativeTime(decision.timestamp)}
              </span>
            </div>
            <div className="decision-rationale">{decision.rationale}</div>
            {decision.relatedStep && (
              <button onClick={() => highlightStep(decision.relatedStep)}>
                → View in workflow
              </button>
            )}
          </div>
        ))}
      </section>

      {/* Notes */}
      <section className="panel-section">
        <h3>📝 Annotations</h3>
        {context.notes.map(note => (
          <div key={note.id} className="note-item">
            <div className="note-header">
              {note.author} - {note.timestamp.toLocaleDateString()}
            </div>
            <div className="note-content">{note.content}</div>
          </div>
        ))}
        <textarea
          placeholder="Add note..."
          onBlur={(e) => {
            if (e.target.value.trim()) {
              onAddNote(e.target.value);
              e.target.value = '';
            }
          }}
        />
      </section>

      {/* Version History */}
      <section className="panel-section">
        <h3>📜 History</h3>
        <div className="version-timeline">
          {context.history.map(version => (
            <div key={version.version} className="version-item">
              <div className="version-marker">
                {version.checkpoint && <span className="checkpoint">📌</span>}
                <strong>v{version.version}</strong>
              </div>
              <div className="version-details">
                <div>{version.user} - {version.timestamp.toLocaleString()}</div>
                <ul className="version-changes">
                  {version.changes.slice(0, 3).map((change, i) => (
                    <li key={i}>{change.description}</li>
                  ))}
                </ul>
                <button onClick={() => viewDiff(version.version)}>
                  View diff
                </button>
                <button onClick={() => restore(version.version)}>
                  Restore
                </button>
              </div>
            </div>
          ))}
        </div>
      </section>
    </div>
  );
};
```

### 4.4 Backend Services

#### Workflow State Service

**File:** `backend/lib/galaxy/ai/workspace_service.py`

```python
"""
Workspace state management for Chatboard
Handles workflow versioning, knowledge aggregation, and audit trails
"""

from typing import Dict, List, Any
from datetime import datetime
import json

class WorkspaceService:
    """Manage BioMate workspace state"""

    def __init__(self, db_connection):
        self.db = db_connection

    def create_workspace(self, user_id: str, name: str) -> str:
        """Create new workspace"""
        workspace_id = generate_id()

        workspace = {
            'id': workspace_id,
            'name': name,
            'owner': user_id,
            'created': datetime.now(),
            'updated': datetime.now(),
            'conversation': [],
            'workflow': {
                'version': '1.0',
                'structure': [],
                'parameters': {}
            },
            'knowledge': {
                'literature': [],
                'toolDocs': [],
                'suggestions': []
            },
            'context': {
                'datasets': [],
                'decisions': [],
                'notes': []
            },
            'history': []
        }

        self.db.workspaces.insert_one(workspace)
        return workspace_id

    def update_workflow(self, workspace_id: str, user_id: str,
                       changes: Dict[str, Any], rationale: str):
        """
        Update workflow and create version checkpoint

        Args:
            workspace_id: Workspace ID
            user_id: User making the change
            changes: Dictionary of changes
            rationale: Why the change was made
        """
        workspace = self.get_workspace(workspace_id)

        # Apply changes
        old_version = workspace['workflow']['version']
        new_version = increment_version(old_version)

        # Create version entry
        version_entry = {
            'version': new_version,
            'timestamp': datetime.now(),
            'user': user_id,
            'changes': self._describe_changes(changes),
            'checkpoint': changes.get('checkpoint', False)
        }

        # Update workflow
        workspace['workflow'].update(changes.get('workflow', {}))
        workspace['workflow']['version'] = new_version

        # Log decision
        if rationale:
            decision = {
                'timestamp': datetime.now(),
                'user': user_id,
                'action': changes.get('action', 'Update workflow'),
                'rationale': rationale,
                'relatedStep': changes.get('stepId')
            }
            workspace['context']['decisions'].append(decision)

        # Save version history
        workspace['history'].append(version_entry)
        workspace['updated'] = datetime.now()

        self.db.workspaces.update_one(
            {'id': workspace_id},
            {'$set': workspace}
        )

        return new_version

    def aggregate_knowledge(self, workspace_id: str,
                           user_intent: str) -> Dict[str, Any]:
        """
        Gather knowledge from multiple sources using tool composition

        Returns:
            Dictionary with literature, tool docs, and suggestions
        """
        from galaxy.ai.tool_composition import BioMateComposeTool

        composer = BioMateComposeTool()

        # Gather literature
        if 'proteomics' in user_intent.lower():
            literature = composer.pre_workflow_context(
                user_intent,
                query='DIA-MS proteomics methods',
                date_from='2023'
            )

        # Get tool documentation from Claude Skills
        tool_docs = self._get_relevant_tool_docs(user_intent)

        # Generate AI suggestions
        suggestions = self._generate_suggestions(workspace_id, user_intent)

        knowledge = {
            'literature': literature.get('papers', []),
            'toolDocs': tool_docs,
            'suggestions': suggestions
        }

        # Save to workspace
        workspace = self.get_workspace(workspace_id)
        workspace['knowledge'].update(knowledge)
        self.db.workspaces.update_one(
            {'id': workspace_id},
            {'$set': {'knowledge': workspace['knowledge']}}
        )

        return knowledge

    def _generate_suggestions(self, workspace_id: str,
                             context: str) -> List[Dict]:
        """
        Generate AI suggestions based on workflow state

        Uses LLM to analyze current workflow and provide recommendations
        """
        workspace = self.get_workspace(workspace_id)
        workflow = workspace['workflow']

        # Build prompt for suggestion generation
        prompt = f"""
        Analyze this bioinformatics workflow and provide suggestions:

        User intent: {context}
        Current workflow: {json.dumps(workflow['structure'], indent=2)}
        Parameters: {json.dumps(workflow['parameters'], indent=2)}

        Provide suggestions in JSON format:
        [
          {{
            "id": "unique_id",
            "priority": "high|medium|low",
            "title": "Brief title",
            "description": "Detailed explanation",
            "action": {{
              "label": "Button text",
              "type": "parameter_change|tool_replace|add_step",
              "payload": {{...}}
            }}
          }}
        ]

        Consider:
        - Parameter validation (are values in expected ranges?)
        - Best practices (are we following recent literature?)
        - Missing steps (QC samples, normalization, etc.)
        - Data compatibility (do input/output types match?)
        """

        # Call LLM (Claude Sonnet 4.5)
        from galaxy.ai.llm_client import LLMClient
        llm = LLMClient()
        response = llm.generate(prompt, return_json=True)

        return response.get('suggestions', [])
```

### 4.5 Real-time Collaboration (WebSocket)

**File:** `backend/lib/galaxy/ai/workspace_websocket.py`

```python
"""
WebSocket server for real-time workspace collaboration
"""

from fastapi import WebSocket, WebSocketDisconnect
from typing import Dict, Set
import json

class WorkspaceCollaborationManager:
    """Manage real-time collaboration on workspaces"""

    def __init__(self):
        # workspace_id → set of connected WebSockets
        self.active_connections: Dict[str, Set[WebSocket]] = {}

    async def connect(self, websocket: WebSocket, workspace_id: str, user_id: str):
        """Connect user to workspace"""
        await websocket.accept()

        if workspace_id not in self.active_connections:
            self.active_connections[workspace_id] = set()

        self.active_connections[workspace_id].add(websocket)

        # Notify other users
        await self.broadcast(workspace_id, {
            'type': 'user_joined',
            'user': user_id
        }, exclude=websocket)

    async def disconnect(self, websocket: WebSocket, workspace_id: str, user_id: str):
        """Disconnect user from workspace"""
        self.active_connections[workspace_id].remove(websocket)

        # Notify other users
        await self.broadcast(workspace_id, {
            'type': 'user_left',
            'user': user_id
        })

    async def broadcast(self, workspace_id: str, message: Dict, exclude: WebSocket = None):
        """Broadcast message to all connected users"""
        if workspace_id not in self.active_connections:
            return

        for connection in self.active_connections[workspace_id]:
            if connection != exclude:
                await connection.send_json(message)

    async def handle_update(self, workspace_id: str, user_id: str, update: Dict):
        """
        Handle workspace update and broadcast to other users

        Updates can be:
        - parameter_change: User edited a parameter
        - step_added: User added a workflow step
        - note_added: User added an annotation
        - etc.
        """
        # Apply update to workspace
        from galaxy.ai.workspace_service import WorkspaceService
        ws_service = WorkspaceService()

        ws_service.update_workflow(
            workspace_id,
            user_id,
            update,
            rationale=update.get('rationale', '')
        )

        # Broadcast to collaborators
        await self.broadcast(workspace_id, {
            'type': 'workspace_updated',
            'user': user_id,
            'update': update
        })
```

---

## Part 5: Implementation Roadmap

### Phase 1: Foundation (2-3 weeks)

**Goal:** Basic Chatboard layout with workflow canvas

**Tasks:**
1. ✅ Implement workspace data model
2. ✅ Create WorkflowCanvas component with ReactFlow
3. ✅ Implement basic parameter editing (click to edit)
4. ✅ Add version control (simple history tracking)
5. ✅ Integrate with existing chat interface

**Deliverable:**
- Users can see workflow visually
- Users can click parameters to edit them
- Changes are versioned

### Phase 2: Knowledge Integration (2-3 weeks)

**Goal:** Add Knowledge Panel with auto-population

**Tasks:**
1. ✅ Implement KnowledgePanel component
2. ✅ Integrate ToolUniverse for literature search (PubMed tool composition)
3. ✅ Extract tool documentation from Claude Skills
4. ✅ Implement AI suggestion generation
5. ✅ Add "Apply recommendation" workflow

**Deliverable:**
- Knowledge Panel shows relevant papers
- Tool documentation accessible
- AI suggests improvements

### Phase 3: Context & Auditing (1-2 weeks)

**Goal:** Add Context Panel for traceability

**Tasks:**
1. ✅ Implement ContextPanel component
2. ✅ Add dataset selection UI
3. ✅ Implement decision logging
4. ✅ Add annotation system
5. ✅ Build version diff viewer

**Deliverable:**
- Full audit trail
- Annotations for project context
- Version comparison

### Phase 4: Collaboration (2-3 weeks)

**Goal:** Real-time multi-user collaboration

**Tasks:**
1. ✅ Implement WebSocket server
2. ✅ Add presence indicators (who's viewing)
3. ✅ Implement conflict resolution
4. ✅ Add commenting system
5. ✅ Build sharing/export features

**Deliverable:**
- Multiple users can work on same workspace
- Real-time updates
- Shareable workspace links

### Phase 5: Polish & Optimization (1-2 weeks)

**Goal:** Production-ready UX

**Tasks:**
1. ✅ Performance optimization (lazy loading, virtualization)
2. ✅ Mobile responsive design
3. ✅ Keyboard shortcuts
4. ✅ Accessibility (ARIA labels, screen reader support)
5. ✅ User onboarding (tutorial, tooltips)

**Deliverable:**
- Fast, responsive interface
- Accessible to all users
- Smooth learning curve

---

## Part 6: Expected Benefits

### 6.1 User Experience Improvements

| Metric | Current (Chatbot) | Proposed (Chatboard) | Improvement |
|--------|-------------------|----------------------|-------------|
| **Time to create workflow** | 5-10 min | 3-5 min | 40-50% faster |
| **Parameter adjustment iterations** | 3-5 | 1-2 | 60% fewer |
| **Context retention** | Poor (scroll chat) | Excellent (always visible) | 90% better |
| **Collaboration friction** | High (share screenshots) | Low (share link) | 80% reduction |
| **Audit trail completeness** | 20% (manual) | 95% (automatic) | 5x improvement |
| **Decision traceability** | Difficult | Easy | 10x better |

### 6.2 Scientific Impact

**Reproducibility:**
- ✅ Full parameter history → Paper methods section auto-generated
- ✅ Dataset versions tracked → Exact replication possible
- ✅ Decision rationale → Understanding why choices were made

**Collaboration:**
- ✅ PI can review workflows without learning Galaxy
- ✅ Bioinformatician can explain choices inline
- ✅ Lab members can see project evolution

**Quality:**
- ✅ AI suggestions catch mistakes early
- ✅ Literature integration ensures best practices
- ✅ Parameter validation prevents errors

### 6.3 Business Value

**User Retention:**
- Current: Users frustrated by lost context → churn
- Proposed: Persistent workspace → users return to continue work

**Competitive Advantage:**
- Only bioinformatics platform with Chatboard paradigm
- Appeals to knowledge-intensive user base
- Differentiator vs. traditional Galaxy interfaces

**Publishing Potential:**
- Novel UX paradigm for scientific computing
- Publishable in bioinformatics journals
- Marketing opportunity

---

## Part 7: Discussion Points

### 7.1 Open Questions

**Q1: How much should we constrain vs. enable free editing?**
- Option A: Strict - Only AI-suggested changes allowed
- Option B: Flexible - Users can modify anything
- **Recommendation:** Hybrid - Allow editing with validation warnings

**Q2: Should we support branching workflows (like git)?**
- Use case: Try different parameter sets in parallel
- Complexity: High
- **Recommendation:** Phase 6 (future enhancement)

**Q3: What's the granularity of version control?**
- Every parameter change? (too noisy)
- Only major edits? (user decides)
- **Recommendation:** Auto-save checkpoints + user-marked milestones

**Q4: How do we handle large workflows (50+ steps)?**
- Canvas becomes unwieldy
- **Solutions:** Zoom/pan, minimap, step grouping
- **Recommendation:** Implement hierarchical view (expand/collapse step groups)

### 7.2 Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| **Performance** (large workflows slow) | High | Virtualization, lazy loading, web workers |
| **Complexity** (too many panels overwhelming) | Medium | Collapsible panels, smart defaults, onboarding |
| **Data model** (backwards compatibility) | High | Versioned schema, migration scripts |
| **Real-time sync** (conflicts) | Medium | Operational transformation, last-write-wins with warnings |
| **Learning curve** (users confused) | Medium | Interactive tutorial, tooltips, video guides |

### 7.3 Metrics for Success

**Phase 1 (Foundation):**
- ✅ 80%+ users can edit parameters without chat
- ✅ Workflow generation time reduced by 30%
- ✅ Version history used by 50%+ users

**Phase 2 (Knowledge):**
- ✅ AI suggestions accepted 40%+ of the time
- ✅ Literature citations used in 60%+ workflows
- ✅ Tool documentation views increase 3x

**Phase 3 (Context):**
- ✅ 70%+ workflows have annotations
- ✅ Decision logs present in 80%+ workflows
- ✅ Audit trail completeness > 90%

**Phase 4 (Collaboration):**
- ✅ 30%+ workspaces have multiple collaborators
- ✅ Sharing feature used by 50%+ users
- ✅ Collaboration reduces iteration time by 40%

---

## Conclusion

The Chatboard paradigm is **perfectly aligned with BioMate's domain needs**:

**Why Bioinformatics Needs Chatboard:**
1. ✅ **Knowledge-intensive:** Need to surface literature, tool docs, best practices
2. ✅ **Complex state:** Workflows have structure + parameters + datasets + context
3. ✅ **Iterative:** Workflows evolve through refinement, not one-shot generation
4. ✅ **Auditable:** Publications require reproducible methods
5. ✅ **Collaborative:** PIs, bioinformaticians, lab techs all need to understand

**What We Gain:**
- 🎯 **Better UX:** From frustrating chat scroll to productive workspace
- 🧠 **Smarter AI:** Knowledge aggregation + proactive suggestions
- 🔬 **Higher quality:** Literature-backed, validated workflows
- 📊 **Full traceability:** Automatic audit trails for publications
- 🤝 **True collaboration:** Real-time co-editing and annotation

**Implementation is Feasible:**
- Builds on existing BioMate architecture
- Leverages ToolUniverse capabilities we're already integrating
- Incremental rollout (5 phases, 8-12 weeks total)
- Each phase delivers standalone value

**Next Steps:**
1. Review this proposal with team
2. Prioritize phases (start with Phase 1?)
3. Create detailed wireframes/mockups
4. Begin implementation with foundation components

This is a **transformative upgrade** that positions BioMate as the most advanced AI-powered bioinformatics platform. The medical industry has already validated this paradigm - we should bring it to biology! 🚀

---

**Ready to discuss implementation?** I can help with:
- Detailed component designs
- Code implementation for specific panels
- Integration with existing BioMate features
- User testing scenarios
