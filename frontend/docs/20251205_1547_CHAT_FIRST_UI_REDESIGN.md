# Chat-First UI Redesign

**Date**: 2025-12-05 15:47
**Branch**: `new_framework_platform`
**Status**: Implemented

## Overview

Redesigned the BioMate UI from a split-panel layout to a **chat-first** approach where workflows appear as inline artifacts within the chat conversation. This eliminates duplication and provides a more streamlined user experience.

## Problem Statement

The previous UI had several issues:

1. **Information Duplication**: Workflow steps displayed in both:
   - Chat messages (inline preview cards)
   - Separate workflow panel (right side, 40% width)
   - Required keeping two views in sync

2. **Complex Parameter Configuration**: 3-tier system required multiple clicks:
   - Essential tier (always visible)
   - Common tier (expandable)
   - Advanced tier (collapsed by default)
   - Too much cognitive overhead

3. **Split Attention**: Users had to mentally map between chat context and workflow panel

## Solution: Chat-First Approach

### Design Principles

- **Single Source of Truth**: Workflow appears in one place only - as an inline artifact
- **Progressive Disclosure**: Collapsed by default, expand to see details
- **Minimal Friction**: Run button visible immediately, parameters one click away
- **Contextual**: Workflow stays with the conversation that created it

### New Layout

```
┌─────────────────────────────────────────┐
│ bioMate                    [History ▾]  │
├─────────────────────────────────────────┤
│                                         │
│ User: "Analyze my RNA-seq data"         │
│                                         │
│ Assistant: "I'll create a workflow..."  │
│                                         │
│ ┌─────────────────────────────────────┐ │
│ │ 📋 RNA-seq Analysis         [▼] [▶] │ │  ← Collapsible workflow artifact
│ │ 3 steps • 85% confidence            │ │
│ ├─────────────────────────────────────┤ │
│ │ ① FASTQC Quality Check    ✓   [⚙️] │ │  ← Step with status + config
│ │ ② HISAT2 Alignment        ⏳  [⚙️] │ │
│ │ ③ FeatureCounts           ○   [⚙️] │ │
│ └─────────────────────────────────────┘ │
│                                         │
│ User: "Use stricter quality threshold"  │
│                                         │
│ [Type a message...]                     │
└─────────────────────────────────────────┘
```

## Files Changed

### New Components

#### `workflow-artifact.tsx`
New component for inline workflow display.

**Features:**
- Collapsible card with workflow summary
- Step list with status icons (pending/running/completed/error)
- Run/Stop buttons
- Parameter configuration via gear icon
- Progress bar during execution
- Expandable step details (parameters, inputs)

**Props:**
```typescript
interface WorkflowArtifactProps {
  workflow: { name?: string; annotation?: string; steps?: any }
  steps: WorkflowStep[]
  confidence?: number
  onRun?: () => void
  onStop?: () => void
  onParameterChange?: (stepId: string, params: Record<string, any>) => void
  isRunning?: boolean
  progress?: number
}
```

### Modified Components

#### `chat-with-artifacts.tsx`
**Before:** Split-panel layout with ResizablePanelGroup (60/40 chat/workflow)
**After:** Full-width chat, removed workflow panel entirely

Key changes:
- Removed `ResizablePanelGroup`, `ResizablePanel`, `ResizableHandle`
- Removed `EnhancedWorkflowBuilder` integration
- Removed `useWorkflowSync` hook usage
- Added workflow execution handlers passed to ChatInterface
- Simplified from ~290 lines to ~110 lines

#### `chat-message.tsx`
**Before:** Basic workflow card with "Open in Workflow Builder" button
**After:** Full `WorkflowArtifact` component inline

Key changes:
- Added import for `WorkflowArtifact`
- Added props: `onRunWorkflow`, `onStopWorkflow`, `onParameterChange`, `isWorkflowRunning`, `workflowProgress`
- Replaced 40-line workflow card with single `WorkflowArtifact` component

#### `chat-interface.tsx`
Added workflow execution props to interface:
```typescript
interface ChatInterfaceProps {
  // ... existing props
  onRunWorkflow?: () => void
  onStopWorkflow?: () => void
  onParameterChange?: (stepId: string, params: Record<string, any>) => void
  isWorkflowRunning?: boolean
  workflowProgress?: number
}
```

Props passed through to `ChatMessage` components.

#### `parameter-dialog.tsx`
**Before:** 3-tier collapsible system (Essential/Common/Advanced)
**After:** Simple flat list (Required/Optional)

Key changes:
- Removed tier classification logic (`determineTier` function)
- Removed `Collapsible` wrappers for each tier
- Simplified to two groups: Required and Optional
- Reduced from ~600 lines to ~330 lines
- Cleaner, more scannable UI

## Component Hierarchy

```
ChatWithArtifacts
└── ChatInterface
    └── ChatMessage (for each message)
        └── WorkflowArtifact (when message has workflow)
            └── ParameterDialog (when editing step)
```

## Data Flow

```
1. User sends message
   ↓
2. AI generates workflow (stored in message.metadata)
   ↓
3. ChatMessage renders WorkflowArtifact
   ↓
4. User clicks Run → onRunWorkflow → execution starts
   ↓
5. User clicks gear → ParameterDialog opens
   ↓
6. User saves parameters → onParameterChange → updates message.metadata
```

## Migration Notes

### Removed Dependencies
- `useWorkflowSync` hook no longer used in ChatWithArtifacts
- `EnhancedWorkflowBuilder` no longer rendered (still exists for other uses)

### Backward Compatibility
- Existing chat sessions with workflows will still render
- Workflow data structure unchanged (stored in `message.metadata`)
- API contracts unchanged

## Testing Checklist

- [ ] New chat generates workflow as inline artifact
- [ ] Workflow collapses/expands correctly
- [ ] Run button triggers execution
- [ ] Stop button stops execution
- [ ] Parameter dialog opens from gear icon
- [ ] Parameter changes persist
- [ ] Progress bar updates during execution
- [ ] Step status icons update correctly
- [ ] Mobile responsiveness maintained

## Future Improvements

1. **Inline Parameter Editing**: Edit parameters directly on step cards without dialog
2. **Workflow Versioning**: Show diff when AI suggests modifications
3. **Step Reordering**: Drag-and-drop steps within artifact
4. **Batch Operations**: Run/configure multiple steps at once
