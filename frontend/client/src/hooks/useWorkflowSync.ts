/**
 * Workflow Sync Hook
 *
 * Manages bidirectional synchronization between:
 * - Chat interface (workflow generation from conversation)
 * - Workflow builder (visual workflow editing)
 *
 * Ensures both views stay in sync when:
 * - Chat generates a new workflow
 * - User modifies workflow in workflow builder
 * - Workflow execution state changes
 */

import { useState, useCallback, useEffect } from 'react';
import type { WorkflowStep } from '../components/workflow-step';

export interface WorkflowSyncState {
  // Current workflow
  workflowId: string | null;
  workflowName: string;
  workflowSteps: WorkflowStep[];

  // Source of truth
  source: 'chat' | 'manual' | null;

  // Metadata from Galaxy Assistant
  recommendedTools?: Array<{
    tool_id: string;
    name: string;
    relevanceScore: number;
    reasoning: string;
  }>;

  recommendedDatasets?: Array<{
    dataset_id: string;
    name: string;
    relevanceScore: number;
    reasoning: string;
  }>;

  // Generation metadata
  generatedAt?: string;
  userIntent?: string;
}

export interface WorkflowSyncActions {
  // Set workflow from chat generation
  setWorkflowFromChat: (workflow: any, metadata?: any) => void;

  // Update workflow from manual editing
  updateWorkflow: (steps: WorkflowStep[]) => void;

  // Update single step
  updateStep: (stepId: string, updates: Partial<WorkflowStep>) => void;

  // Add new step
  addStep: (step: WorkflowStep) => void;

  // Remove step
  removeStep: (stepId: string) => void;

  // Clear workflow
  clearWorkflow: () => void;

  // Get current workflow state
  getWorkflowState: () => WorkflowSyncState;
}

const initialState: WorkflowSyncState = {
  workflowId: null,
  workflowName: '',
  workflowSteps: [],
  source: null,
};

export function useWorkflowSync() {
  const [state, setState] = useState<WorkflowSyncState>(initialState);

  /**
   * Set workflow from chat generation
   */
  const setWorkflowFromChat = useCallback((workflow: any, metadata?: any) => {
    console.log('[WorkflowSync] Setting workflow from chat:', workflow);

    // Parse Galaxy .ga format if provided
    let steps: WorkflowStep[] = [];
    let workflowName = '';

    if (workflow?.workflow_ga) {
      // Galaxy .ga JSON format
      const ga = workflow.workflow_ga;
      workflowName = ga.name || ga.annotation || 'Generated Workflow';

      // Extract steps from Galaxy format
      steps = Object.entries(ga.steps || {}).map(([stepId, stepData]: [string, any]) => ({
        id: stepId,
        title: stepData.label || stepData.name || `Step ${stepId}`,
        description: stepData.annotation || '',
        status: 'pending' as const,
        tool: stepData.tool_id || stepData.type,
        parameters: stepData.tool_state || {},
        complexity: 'intermediate' as const,
        estimatedTime: '5 min',
      }));
    } else if (workflow?.steps) {
      // Simple format
      workflowName = workflow.name || workflow.title || 'Generated Workflow';

      // Convert steps to array if it's an object (Galaxy .ga format)
      const stepsArray = Array.isArray(workflow.steps)
        ? workflow.steps
        : Object.values(workflow.steps);

      steps = stepsArray.map((step: any, index: number) => ({
        id: step.id || `step-${index}`,
        title: step.title || step.name || `Step ${index + 1}`,
        description: step.description || '',
        status: step.status || 'pending' as const,
        tool: step.tool || step.tool_id || 'Unknown',
        parameters: step.parameters || {},
        complexity: step.complexity || 'intermediate' as const,
        estimatedTime: step.estimatedTime || '5 min',
      }));
    }

    setState({
      workflowId: workflow.id || `workflow-${Date.now()}`,
      workflowName,
      workflowSteps: steps,
      source: 'chat',
      recommendedTools: metadata?.recommendedTools,
      recommendedDatasets: metadata?.recommendedDatasets,
      generatedAt: new Date().toISOString(),
      userIntent: metadata?.userIntent || metadata?.workflowSuggestion?.userIntent,
    });
  }, []);

  /**
   * Update workflow from manual editing
   */
  const updateWorkflow = useCallback((steps: WorkflowStep[]) => {
    console.log('[WorkflowSync] Updating workflow from manual edit:', steps.length, 'steps');

    setState(prev => ({
      ...prev,
      workflowSteps: steps,
      source: prev.source || 'manual',
    }));
  }, []);

  /**
   * Update single step
   */
  const updateStep = useCallback((stepId: string, updates: Partial<WorkflowStep>) => {
    console.log('[WorkflowSync] Updating step:', stepId, updates);

    setState(prev => ({
      ...prev,
      workflowSteps: prev.workflowSteps.map(step =>
        step.id === stepId ? { ...step, ...updates } : step
      ),
    }));
  }, []);

  /**
   * Add new step
   */
  const addStep = useCallback((step: WorkflowStep) => {
    console.log('[WorkflowSync] Adding step:', step);

    setState(prev => ({
      ...prev,
      workflowSteps: [...prev.workflowSteps, step],
      source: prev.source || 'manual',
    }));
  }, []);

  /**
   * Remove step
   */
  const removeStep = useCallback((stepId: string) => {
    console.log('[WorkflowSync] Removing step:', stepId);

    setState(prev => ({
      ...prev,
      workflowSteps: prev.workflowSteps.filter(step => step.id !== stepId),
    }));
  }, []);

  /**
   * Clear workflow
   */
  const clearWorkflow = useCallback(() => {
    console.log('[WorkflowSync] Clearing workflow');
    setState(initialState);
  }, []);

  /**
   * Get current workflow state
   */
  const getWorkflowState = useCallback(() => {
    return state;
  }, [state]);

  // Log state changes for debugging
  useEffect(() => {
    console.log('[WorkflowSync] State updated:', {
      workflowId: state.workflowId,
      stepCount: state.workflowSteps.length,
      source: state.source,
      hasRecommendedTools: !!state.recommendedTools,
      hasRecommendedDatasets: !!state.recommendedDatasets,
    });
  }, [state]);

  return {
    // State
    workflowState: state,

    // Actions
    setWorkflowFromChat,
    updateWorkflow,
    updateStep,
    addStep,
    removeStep,
    clearWorkflow,
    getWorkflowState,

    // Computed
    hasWorkflow: state.workflowSteps.length > 0,
    isFromChat: state.source === 'chat',
  };
}
