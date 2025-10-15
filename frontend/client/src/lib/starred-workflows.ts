import type { StarredWorkflow } from '@shared/schema';

// Starred workflows management service
class StarredWorkflowsService {
  private storageKey = 'biomate-starred-workflows';
  
  // Get all starred workflows
  getAllStarred(): StarredWorkflow[] {
    try {
      const stored = localStorage.getItem(this.storageKey);
      if (!stored) return this.getDefaultStarred();
      return JSON.parse(stored);
    } catch (error) {
      console.error('Error loading starred workflows:', error);
      return this.getDefaultStarred();
    }
  }
  
  // Star a workflow
  starWorkflow(workflow: Omit<StarredWorkflow, 'id' | 'starredAt'>): StarredWorkflow {
    const starredWorkflow: StarredWorkflow = {
      ...workflow,
      id: `starred-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`,
      starredAt: new Date()
    };
    
    const starred = this.getAllStarred();
    // Check if already starred
    const existingIndex = starred.findIndex(s => s.workflowId === workflow.workflowId);
    if (existingIndex !== -1) {
      return starred[existingIndex]; // Already starred
    }
    
    starred.unshift(starredWorkflow);
    this.saveStarred(starred);
    return starredWorkflow;
  }
  
  // Unstar a workflow
  unstarWorkflow(workflowId: string): boolean {
    const starred = this.getAllStarred();
    const filteredStarred = starred.filter(s => s.workflowId !== workflowId);
    
    if (filteredStarred.length === starred.length) {
      return false; // Not found
    }
    
    this.saveStarred(filteredStarred);
    return true;
  }
  
  // Check if a workflow is starred
  isStarred(workflowId: string): boolean {
    const starred = this.getAllStarred();
    return starred.some(s => s.workflowId === workflowId);
  }
  
  // Get a specific starred workflow
  getStarred(workflowId: string): StarredWorkflow | null {
    const starred = this.getAllStarred();
    return starred.find(s => s.workflowId === workflowId) || null;
  }
  
  // Clear all starred workflows
  clearAll(): void {
    localStorage.removeItem(this.storageKey);
  }
  
  // Private helper methods
  private saveStarred(starred: StarredWorkflow[]): void {
    try {
      localStorage.setItem(this.storageKey, JSON.stringify(starred));
    } catch (error) {
      console.error('Error saving starred workflows:', error);
    }
  }
  
  private getDefaultStarred(): StarredWorkflow[] {
    return [
      {
        id: 'starred-default-1',
        workflowId: 'rna-seq-pipeline',
        title: 'RNA-seq Analysis Pipeline',
        description: 'Complete transcriptomic analysis from raw reads to differential expression',
        workflowType: 'RNA-seq',
        complexity: 'complex',
        estimatedTime: '45 min',
        starredAt: new Date(Date.now() - 86400000) // 1 day ago
      },
      {
        id: 'starred-default-2',
        workflowId: 'variant-calling-workflow',
        title: 'Variant Calling Workflow',
        description: 'SNP and indel discovery from sequencing data',
        workflowType: 'Genomics',
        complexity: 'complex',
        estimatedTime: '35 min',
        starredAt: new Date(Date.now() - 172800000) // 2 days ago
      },
      {
        id: 'starred-default-3',
        workflowId: 'qc-preprocessing',
        title: 'Quality Control & Preprocessing',
        description: 'Standard QC pipeline for sequencing data',
        workflowType: 'Quality Control',
        complexity: 'intermediate',
        estimatedTime: '15 min',
        starredAt: new Date(Date.now() - 259200000) // 3 days ago
      }
    ];
  }
}

export const starredWorkflowsService = new StarredWorkflowsService();