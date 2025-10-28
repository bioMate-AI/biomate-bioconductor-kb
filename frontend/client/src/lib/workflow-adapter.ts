/**
 * Workflow Format Adapter
 *
 * Converts between different workflow formats:
 * - Demo workflows (simple UI format)
 * - Galaxy .ga format (complex nested format)
 * - Standard format (unified internal representation)
 */

export interface StandardWorkflow {
  id: string;
  name: string;
  description?: string;
  annotation?: string;
  steps: StandardStep[];
  metadata?: {
    galaxyHistoryId?: string;
    galaxyWorkflowId?: string;
    source?: 'demo' | 'galaxy' | 'user';
    type?: string;
  };
  galaxyFormat?: any; // Original Galaxy .ga if available
}

export interface StandardStep {
  id: string;
  name: string;
  tool: string; // Simple tool name for display
  toolId?: string; // Full Galaxy tool ID if available
  description?: string;
  type: 'input' | 'tool' | 'subworkflow' | 'data_input' | 'data_collection_input';
  status?: 'idle' | 'running' | 'completed' | 'failed';
  position?: { x: number; y: number };
  annotation?: string;
}

export class WorkflowAdapter {
  /**
   * Convert demo workflow to standard format
   */
  static fromDemoWorkflow(demo: any): StandardWorkflow {
    if (!demo) {
      throw new Error('Demo workflow is null or undefined');
    }

    const steps: StandardStep[] = (demo.steps || []).map((step: any, index: number) => ({
      id: step.id || `step${index}`,
      name: step.title || step.name || `Step ${index + 1}`,
      tool: step.tool || 'Unknown Tool',
      toolId: this.getGalaxyToolId(step.tool),
      description: step.description || '',
      type: 'tool' as const,
      status: step.status || 'idle',
      annotation: step.description
    }));

    return {
      id: demo.id || `workflow-${Date.now()}`,
      name: demo.title || demo.name || 'Untitled Workflow',
      description: demo.description,
      annotation: demo.description,
      steps,
      metadata: {
        source: 'demo',
        type: demo.type
      }
    };
  }

  /**
   * Convert Galaxy .ga format to standard format
   */
  static fromGalaxyGA(ga: any): StandardWorkflow {
    if (!ga) {
      throw new Error('Galaxy workflow is null or undefined');
    }

    // Galaxy .ga has steps as an object with numeric keys
    const stepsObject = ga.steps || {};
    const steps: StandardStep[] = Object.entries(stepsObject)
      .sort(([aKey], [bKey]) => parseInt(aKey) - parseInt(bKey))
      .map(([stepKey, stepData]: [string, any]) => {
        // Determine step type
        let type: StandardStep['type'] = 'tool';
        if (stepData.type === 'data_input') type = 'data_input';
        else if (stepData.type === 'data_collection_input') type = 'data_collection_input';
        else if (stepData.type === 'subworkflow') type = 'subworkflow';

        return {
          id: `step${stepKey}`,
          name: stepData.name || stepData.label || `Step ${parseInt(stepKey) + 1}`,
          tool: this.extractToolName(stepData.tool_id) || stepData.name || 'Unknown Tool',
          toolId: stepData.tool_id,
          description: stepData.annotation || '',
          type,
          status: 'idle',
          position: stepData.position,
          annotation: stepData.annotation
        };
      });

    return {
      id: ga.uuid || `workflow-${Date.now()}`,
      name: ga.name || 'Untitled Workflow',
      description: ga.annotation || '',
      annotation: ga.annotation,
      steps,
      metadata: {
        source: 'galaxy',
        galaxyWorkflowId: ga.uuid
      },
      galaxyFormat: ga
    };
  }

  /**
   * Convert standard format to Galaxy .ga format
   */
  static toGalaxyGA(standard: StandardWorkflow): any {
    // If we have the original Galaxy format, use it
    if (standard.galaxyFormat) {
      return standard.galaxyFormat;
    }

    // Otherwise, construct a minimal .ga format
    const steps: any = {};
    standard.steps.forEach((step, index) => {
      steps[index.toString()] = {
        id: index,
        name: step.name,
        tool_id: step.toolId || step.tool,
        type: step.type === 'data_input' || step.type === 'data_collection_input' ? step.type : 'tool',
        annotation: step.annotation || step.description,
        position: step.position || { x: index * 200, y: 100 }
      };
    });

    return {
      name: standard.name,
      annotation: standard.annotation || standard.description,
      'format-version': '0.1',
      steps,
      uuid: standard.id
    };
  }

  /**
   * Extract simple tool name from full Galaxy tool ID
   * Example: "toolshed.g2.bx.psu.edu/repos/devteam/fastqc/fastqc/0.72" → "FastQC"
   */
  private static extractToolName(toolId: string): string {
    if (!toolId) return '';

    // Try to extract from toolshed path
    const parts = toolId.split('/');
    if (parts.length >= 4) {
      // Format: toolshed.../repos/owner/tool_name/version
      const toolName = parts[parts.length - 2];
      return this.capitalizeToolName(toolName);
    }

    // If not a toolshed path, just clean up the ID
    return this.capitalizeToolName(toolId);
  }

  /**
   * Get full Galaxy tool ID from simple name (best effort mapping)
   */
  private static getGalaxyToolId(simpleName: string): string | undefined {
    const toolMapping: Record<string, string> = {
      'FastQC': 'toolshed.g2.bx.psu.edu/repos/devteam/fastqc/fastqc/0.72',
      'HISAT2': 'toolshed.g2.bx.psu.edu/repos/iuc/hisat2/hisat2/2.2.1',
      'featureCounts': 'toolshed.g2.bx.psu.edu/repos/iuc/featurecounts/featurecounts/2.0.1',
      'DESeq2': 'toolshed.g2.bx.psu.edu/repos/iuc/deseq2/deseq2/1.34.0',
      'XCMS': 'toolshed.g2.bx.psu.edu/repos/lecorguille/xcms_xcmsset/abims_xcms_xcmsSet/3.12.0',
      'DIA-NN': 'diann', // Placeholder - may not be in Galaxy
    };

    return toolMapping[simpleName];
  }

  /**
   * Capitalize tool name for display
   */
  private static capitalizeToolName(name: string): string {
    // Handle special cases
    const specialCases: Record<string, string> = {
      'fastqc': 'FastQC',
      'hisat2': 'HISAT2',
      'deseq2': 'DESeq2',
      'featurecounts': 'featureCounts',
      'xcms': 'XCMS'
    };

    const lower = name.toLowerCase();
    if (specialCases[lower]) {
      return specialCases[lower];
    }

    // Default: capitalize first letter
    return name.charAt(0).toUpperCase() + name.slice(1);
  }

  /**
   * Validate that a workflow has required fields
   */
  static validate(workflow: StandardWorkflow): { valid: boolean; errors: string[] } {
    const errors: string[] = [];

    if (!workflow.id) errors.push('Workflow ID is required');
    if (!workflow.name) errors.push('Workflow name is required');
    if (!workflow.steps || workflow.steps.length === 0) {
      errors.push('Workflow must have at least one step');
    }

    workflow.steps.forEach((step, index) => {
      if (!step.id) errors.push(`Step ${index}: ID is required`);
      if (!step.name) errors.push(`Step ${index}: Name is required`);
      if (!step.tool) errors.push(`Step ${index}: Tool is required`);
    });

    return {
      valid: errors.length === 0,
      errors
    };
  }
}

/**
 * Helper function to adapt workflow data from any source
 */
export function adaptWorkflow(data: any): StandardWorkflow {
  // Detect format and convert
  if (!data) {
    throw new Error('Workflow data is null or undefined');
  }

  // Check if it's already in standard format
  if (data.steps && Array.isArray(data.steps) && data.steps[0]?.type) {
    return data as StandardWorkflow;
  }

  // Check if it's a Galaxy .ga format (has steps as object with numeric keys)
  if (data.steps && typeof data.steps === 'object' && !Array.isArray(data.steps)) {
    return WorkflowAdapter.fromGalaxyGA(data);
  }

  // Assume it's a demo workflow
  return WorkflowAdapter.fromDemoWorkflow(data);
}
