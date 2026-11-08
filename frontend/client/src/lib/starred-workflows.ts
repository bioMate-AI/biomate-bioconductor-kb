import type { StarredWorkflow } from '@shared/schema';

// Starred workflows management service
class StarredWorkflowsService {
  private storageKey = 'biomate-starred-workflows';
  
  // Get all starred workflows.
  // Returns an empty list when the user has starred nothing — we never seed
  // fabricated demo workflows, because the dialog renders these as the user's
  // real stars. An empty account must show the honest "no starred workflows"
  // empty state.
  getAllStarred(): StarredWorkflow[] {
    try {
      const stored = localStorage.getItem(this.storageKey);
      if (!stored) return [];
      return JSON.parse(stored);
    } catch (error) {
      console.error('Error loading starred workflows:', error);
      return [];
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
  
  // NOTE: fabricated demo stars were removed — they were rendered as the user's
  // own starred workflows. An empty account must show the honest empty state.
}

export const starredWorkflowsService = new StarredWorkflowsService();