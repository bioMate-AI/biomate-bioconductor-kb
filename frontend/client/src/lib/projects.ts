import type { Project, CreateProject, ProjectDocument, ChatSession } from '@shared/schema';
import { chatHistoryService } from './chat-history';

// API client for memory service
const memoryAPI = {
  async getProjects(status?: string): Promise<Project[]> {
    const url = status ? `/api/memory/projects?status=${status}` : '/api/memory/projects';
    const res = await fetch(url, { credentials: 'include' });
    if (!res.ok) throw new Error('Failed to fetch projects');
    return res.json();
  },

  async getProject(projectId: string): Promise<any> {
    const res = await fetch(`/api/memory/projects/${projectId}`, { credentials: 'include' });
    if (!res.ok) throw new Error('Project not found');
    return res.json();
  },

  async createProject(data: any): Promise<Project> {
    const res = await fetch('/api/memory/projects', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      credentials: 'include',
      body: JSON.stringify(data),
    });
    if (!res.ok) throw new Error('Failed to create project');
    return res.json();
  },

  async updateProject(projectId: string, data: any): Promise<Project> {
    const res = await fetch(`/api/memory/projects/${projectId}`, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      credentials: 'include',
      body: JSON.stringify(data),
    });
    if (!res.ok) throw new Error('Failed to update project');
    return res.json();
  },

  async searchProjects(query: { domain?: string; tags?: string[]; text?: string }): Promise<Project[]> {
    const params = new URLSearchParams();
    if (query.domain) params.set('domain', query.domain);
    if (query.tags) params.set('tags', query.tags.join(','));
    if (query.text) params.set('text', query.text);
    const res = await fetch(`/api/memory/projects/search?${params}`, { credentials: 'include' });
    if (!res.ok) throw new Error('Failed to search projects');
    return res.json();
  },

  async addKnowledge(projectId: string, data: any): Promise<any> {
    const res = await fetch(`/api/memory/projects/${projectId}/knowledge`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      credentials: 'include',
      body: JSON.stringify(data),
    });
    if (!res.ok) throw new Error('Failed to add knowledge');
    return res.json();
  },

  async getEpisodes(projectId: string, query?: { intent?: string; tools?: string }): Promise<any[]> {
    const params = new URLSearchParams();
    if (query?.intent) params.set('intent', query.intent);
    if (query?.tools) params.set('tools', query.tools);
    const res = await fetch(`/api/memory/projects/${projectId}/episodes?${params}`, { credentials: 'include' });
    if (!res.ok) throw new Error('Failed to get episodes');
    return res.json();
  },

  async getProcedures(projectId: string): Promise<any[]> {
    const res = await fetch(`/api/memory/projects/${projectId}/procedures`, { credentials: 'include' });
    if (!res.ok) throw new Error('Failed to get procedures');
    return res.json();
  },
};

// Project management service with backend sync
class ProjectService {
  private storageKey = 'biomate-projects';
  private maxProjects = 100; // Keep up to 100 projects
  private useBackend = false; // Toggle for backend mode
  private syncPending = false;

  // Check if we should use backend (authenticated user)
  private async checkBackendAvailable(): Promise<boolean> {
    try {
      const res = await fetch('/api/auth/me', { credentials: 'include' });
      return res.ok;
    } catch {
      return false;
    }
  }

  // Enable backend sync
  async enableBackendSync(): Promise<boolean> {
    this.useBackend = await this.checkBackendAvailable();
    if (this.useBackend) {
      await this.syncToBackend();
    }
    return this.useBackend;
  }

  // Sync local projects to backend (one-time migration)
  private async syncToBackend(): Promise<void> {
    if (this.syncPending) return;
    this.syncPending = true;

    try {
      const localProjects = this.getLocalProjects();
      const backendProjects = await memoryAPI.getProjects();

      // Find local projects not in backend
      const backendIds = new Set(backendProjects.map(p => p.id));
      const toSync = localProjects.filter(p => !backendIds.has(p.id) && !p.id.startsWith('project-demo-'));

      for (const project of toSync) {
        try {
          await memoryAPI.createProject({
            name: project.name,
            description: project.description,
            instructions: project.instructions,
            category: project.category,
            tags: project.tags,
          });
          console.log(`[ProjectSync] Synced project: ${project.name}`);
        } catch (error) {
          console.error(`[ProjectSync] Failed to sync project ${project.name}:`, error);
        }
      }
    } finally {
      this.syncPending = false;
    }
  }

  // Get local projects (localStorage)
  private getLocalProjects(): Project[] {
    try {
      const stored = localStorage.getItem(this.storageKey);
      if (!stored) return this.getDefaultProjects();
      return JSON.parse(stored);
    } catch {
      return this.getDefaultProjects();
    }
  }

  // Get all projects (sync version - uses local cache)
  getAllProjects(): Project[] {
    const projects = this.getLocalProjects();
    // Sort by last activity (most recent first)
    return projects.sort((a: Project, b: Project) =>
      new Date(b.lastActivity).getTime() - new Date(a.lastActivity).getTime()
    );
  }

  // Get all projects (async version - uses backend when available)
  async getAllProjectsAsync(): Promise<Project[]> {
    if (this.useBackend) {
      try {
        const backendProjects = await memoryAPI.getProjects();
        // Transform backend format to client format
        return backendProjects.map(p => this.transformBackendProject(p));
      } catch (error) {
        console.error('Backend fetch failed, using local:', error);
      }
    }
    return this.getAllProjects();
  }

  // Transform backend project to client format
  private transformBackendProject(backendProject: any): Project {
    return {
      id: backendProject.id,
      name: backendProject.name,
      description: backendProject.description || '',
      instructions: backendProject.instructions || backendProject.researchGoal,
      status: backendProject.status || 'active',
      category: backendProject.primaryDomain || backendProject.category,
      tags: backendProject.tags || [],
      progress: backendProject.progress || 0,
      createdAt: new Date(backendProject.createdAt),
      updatedAt: new Date(backendProject.updatedAt),
      lastActivity: new Date(backendProject.updatedAt),
      chatSessions: [],
      documents: [],
    };
  }

  // Get a specific project by ID (sync)
  getProject(id: string): Project | null {
    const projects = this.getAllProjects();
    return projects.find(project => project.id === id) || null;
  }

  // Get a specific project by ID with full context (async)
  async getProjectWithContext(id: string): Promise<{
    project: Project;
    knowledge: any[];
    episodes: any[];
    procedures: any[];
    recentWorkflows: any[];
  } | null> {
    if (this.useBackend) {
      try {
        const context = await memoryAPI.getProject(id);
        if (context.project) {
          return {
            project: this.transformBackendProject(context.project),
            knowledge: context.knowledge || [],
            episodes: context.recentEpisodes || [],
            procedures: context.procedures || [],
            recentWorkflows: context.recentWorkflows || [],
          };
        }
      } catch (error) {
        console.error('Failed to get project context:', error);
      }
    }
    // Fallback to local
    const project = this.getProject(id);
    return project ? { project, knowledge: [], episodes: [], procedures: [], recentWorkflows: [] } : null;
  }

  // Create a new project (sync - local only)
  createProject(projectData: CreateProject): Project {
    const newProject: Project = {
      ...projectData,
      id: `project-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`,
      status: "active",
      createdAt: new Date(),
      updatedAt: new Date(),
      lastActivity: new Date(),
      chatSessions: [],
      documents: [],
      tags: projectData.tags || [],
      progress: 0
    };

    const projects = this.getAllProjects();
    projects.unshift(newProject); // Add to beginning

    // Keep only the most recent projects
    if (projects.length > this.maxProjects) {
      projects.splice(this.maxProjects);
    }

    this.saveProjects(projects);
    return newProject;
  }

  // Create a new project (async - syncs with backend)
  async createProjectAsync(projectData: CreateProject & {
    researchGoal?: string;
    primaryDomain?: string;
    organisms?: string[];
    tissueTypes?: string[];
    conditions?: string[];
    dataModalities?: string[];
  }): Promise<Project> {
    // Create locally first
    const localProject = this.createProject(projectData);

    // Sync to backend if available
    if (this.useBackend) {
      try {
        const backendProject = await memoryAPI.createProject({
          name: projectData.name,
          description: projectData.description,
          researchGoal: projectData.researchGoal || projectData.instructions,
          instructions: projectData.instructions,
          primaryDomain: projectData.primaryDomain || projectData.category,
          organisms: projectData.organisms,
          tissueTypes: projectData.tissueTypes,
          conditions: projectData.conditions,
          dataModalities: projectData.dataModalities,
          category: projectData.category,
          tags: projectData.tags,
        });
        // Update local with backend ID
        this.updateProject(localProject.id, { id: backendProject.id } as any);
        return this.transformBackendProject(backendProject);
      } catch (error) {
        console.error('Failed to sync project to backend:', error);
      }
    }

    return localProject;
  }

  // Update an existing project (sync)
  updateProject(projectId: string, updates: Partial<Project>): Project | null {
    const projects = this.getAllProjects();
    const projectIndex = projects.findIndex(p => p.id === projectId);

    if (projectIndex === -1) return null;

    projects[projectIndex] = {
      ...projects[projectIndex],
      ...updates,
      updatedAt: new Date(),
      lastActivity: new Date()
    };

    this.saveProjects(projects);
    return projects[projectIndex];
  }

  // Delete a project and its associated chat sessions
  deleteProject(projectId: string): boolean {
    const project = this.getProject(projectId);
    if (!project) return false;

    // Delete associated chat sessions
    project.chatSessions.forEach(sessionId => {
      chatHistoryService.deleteSession(sessionId);
    });

    // Remove project from storage
    const projects = this.getAllProjects();
    const filteredProjects = projects.filter(p => p.id !== projectId);

    if (filteredProjects.length === projects.length) return false;

    this.saveProjects(filteredProjects);
    return true;
  }

  // Create a new chat session within a project
  createProjectChatSession(projectId: string, title?: string): ChatSession | null {
    const project = this.getProject(projectId);
    if (!project) return null;

    // Create a new chat session with project context
    const chatSession = chatHistoryService.createNewSession();
    
    // Update chat session title and add project context
    const projectTitle = title || `${project.name} Discussion`;
    const updatedSession = chatHistoryService.updateSession(chatSession.id, {
      title: projectTitle,
      messages: [{
        id: "project-welcome",
        content: `Hello! I'm ready to help you with your project "${project.name}". ${project.instructions ? `\n\nProject Instructions: ${project.instructions}` : ''}\n\nWhat would you like to work on today?`,
        role: "assistant",
        timestamp: new Date(),
        suggestions: [
          "Continue previous work",
          "Analyze project data",
          "Build new workflow",
          "Review project progress"
        ]
      }]
    });

    if (!updatedSession) return null;

    // Associate chat session with project
    this.updateProject(projectId, {
      chatSessions: [...project.chatSessions, chatSession.id]
    });

    return updatedSession;
  }

  // Get all chat sessions for a project
  getProjectChatSessions(projectId: string): ChatSession[] {
    const project = this.getProject(projectId);
    if (!project) return [];

    return project.chatSessions
      .map(sessionId => chatHistoryService.getSession(sessionId))
      .filter((session): session is ChatSession => session !== null)
      .sort((a, b) => new Date(b.lastActivity).getTime() - new Date(a.lastActivity).getTime());
  }

  // Add a document to a project
  addDocument(projectId: string, document: Omit<ProjectDocument, 'id' | 'uploadedAt'>): ProjectDocument | null {
    const project = this.getProject(projectId);
    if (!project) return null;

    const newDocument: ProjectDocument = {
      ...document,
      id: `doc-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`,
      uploadedAt: new Date()
    };

    const updatedDocuments = [...project.documents, newDocument];
    this.updateProject(projectId, { documents: updatedDocuments });

    return newDocument;
  }

  // Remove a document from a project
  removeDocument(projectId: string, documentId: string): boolean {
    const project = this.getProject(projectId);
    if (!project) return false;

    const filteredDocuments = project.documents.filter(doc => doc.id !== documentId);
    
    if (filteredDocuments.length === project.documents.length) return false;

    this.updateProject(projectId, { documents: filteredDocuments });
    return true;
  }

  // Search projects by name, description, or tags
  searchProjects(query: string): Project[] {
    const allProjects = this.getAllProjects();
    const lowercaseQuery = query.toLowerCase();

    return allProjects.filter(project => 
      project.name.toLowerCase().includes(lowercaseQuery) ||
      (project.description && project.description.toLowerCase().includes(lowercaseQuery)) ||
      project.tags.some(tag => tag.toLowerCase().includes(lowercaseQuery))
    );
  }

  // Get projects by status
  getProjectsByStatus(status: Project['status']): Project[] {
    return this.getAllProjects().filter(project => project.status === status);
  }

  // Get projects by category
  getProjectsByCategory(category: string): Project[] {
    return this.getAllProjects().filter(project => project.category === category);
  }

  // Archive a project (set status to archived)
  archiveProject(projectId: string): Project | null {
    return this.updateProject(projectId, { status: 'archived' });
  }

  // Restore an archived project (set status to active)
  restoreProject(projectId: string): Project | null {
    return this.updateProject(projectId, { status: 'active' });
  }

  // Update project progress
  updateProgress(projectId: string, progress: number): Project | null {
    const clampedProgress = Math.max(0, Math.min(100, progress));
    const status = clampedProgress === 100 ? 'completed' : 'active';
    return this.updateProject(projectId, { progress: clampedProgress, status });
  }

  // Private methods
  private saveProjects(projects: Project[]): void {
    try {
      localStorage.setItem(this.storageKey, JSON.stringify(projects));
    } catch (error) {
      console.error('Error saving projects:', error);
    }
  }

  // ============================================================================
  // Project Memory Methods (Backend Only)
  // ============================================================================

  // Add knowledge to a project
  async addProjectKnowledge(projectId: string, data: {
    knowledgeType: 'dataset_info' | 'experimental_design' | 'analysis_approach' | 'key_finding' | 'technical_note';
    title?: string;
    content: string;
    source?: 'user_provided' | 'claude_inferred' | 'workflow_result';
  }): Promise<any | null> {
    if (!this.useBackend) {
      console.warn('Backend not available for project knowledge');
      return null;
    }
    try {
      return await memoryAPI.addKnowledge(projectId, data);
    } catch (error) {
      console.error('Failed to add project knowledge:', error);
      return null;
    }
  }

  // Get project episodes (past interactions)
  async getProjectEpisodes(projectId: string, query?: {
    intent?: string;
    tools?: string;
  }): Promise<any[]> {
    if (!this.useBackend) return [];
    try {
      return await memoryAPI.getEpisodes(projectId, query);
    } catch (error) {
      console.error('Failed to get project episodes:', error);
      return [];
    }
  }

  // Get project procedures (learned workflows)
  async getProjectProcedures(projectId: string): Promise<any[]> {
    if (!this.useBackend) return [];
    try {
      return await memoryAPI.getProcedures(projectId);
    } catch (error) {
      console.error('Failed to get project procedures:', error);
      return [];
    }
  }

  // Search projects with advanced filters
  async searchProjectsAdvanced(query: {
    domain?: string;
    tags?: string[];
    text?: string;
  }): Promise<Project[]> {
    if (this.useBackend) {
      try {
        const results = await memoryAPI.searchProjects(query);
        return results.map(p => this.transformBackendProject(p));
      } catch (error) {
        console.error('Backend search failed:', error);
      }
    }
    // Fallback to local search
    if (query.text) {
      return this.searchProjects(query.text);
    }
    return this.getAllProjects();
  }

  private getDefaultProjects(): Project[] {
    // Create some example projects to get users started
    const now = new Date();
    const daysAgo = (days: number) => new Date(now.getTime() - days * 24 * 60 * 60 * 1000);

    return [
      {
        id: "project-demo-1",
        name: "biomate AI",
        description: "Aiming to build online-platform with LLM backed agent pipelines to accelerate life science.",
        instructions: "This project focuses on developing an AI-powered bioinformatics platform that makes complex genomic analysis accessible through conversational interfaces. The platform should integrate various bioinformatics tools and provide automated workflow generation.",
        status: "active",
        category: "Bioinformatics",
        tags: ["AI", "genomics", "platform", "automation"],
        progress: 65,
        createdAt: daysAgo(30),
        updatedAt: daysAgo(1),
        lastActivity: daysAgo(1),
        chatSessions: [],
        documents: [
          {
            id: "doc-1",
            name: "Project Requirements",
            type: "text",
            content: "# BioMate AI Platform Requirements\n\n## Core Features\n- Conversational AI interface\n- Automated workflow generation\n- Integration with bioinformatics tools\n- Cloud-based data processing",
            format: "markdown",
            uploadedAt: daysAgo(25),
            description: "Initial requirements document"
          }
        ]
      },
      {
        id: "project-demo-2", 
        name: "LIS",
        description: "Build a better LIS than epic and the soft company, using LLM-based agent pipelines; quickly prototype it and commercialize it.",
        instructions: "Laboratory Information System (LIS) modernization project using AI agents. Focus on improving workflow efficiency, reducing manual data entry, and providing intelligent insights for laboratory operations.",
        status: "active",
        category: "Healthcare",
        tags: ["LIS", "laboratory", "healthcare", "AI-agents"],
        progress: 25,
        createdAt: daysAgo(14),
        updatedAt: daysAgo(2),
        lastActivity: daysAgo(2),
        chatSessions: [],
        documents: []
      }
    ];
  }
}

// Export singleton instance
export const projectService = new ProjectService();

// Export memory API for direct access
export { memoryAPI };