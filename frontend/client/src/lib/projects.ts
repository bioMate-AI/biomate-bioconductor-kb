import type { Project, CreateProject, ProjectDocument, ChatSession } from '@shared/schema';
import { chatHistoryService } from './chat-history';

// Project management service
class ProjectService {
  private storageKey = 'biomate-projects';
  private maxProjects = 100; // Keep up to 100 projects

  // Get all projects
  getAllProjects(): Project[] {
    try {
      const stored = localStorage.getItem(this.storageKey);
      if (!stored) return this.getDefaultProjects();
      const projects = JSON.parse(stored);
      // Sort by last activity (most recent first)
      return projects.sort((a: Project, b: Project) => 
        new Date(b.lastActivity).getTime() - new Date(a.lastActivity).getTime()
      );
    } catch (error) {
      console.error('Error loading projects:', error);
      return this.getDefaultProjects();
    }
  }

  // Get a specific project by ID
  getProject(id: string): Project | null {
    const projects = this.getAllProjects();
    return projects.find(project => project.id === id) || null;
  }

  // Create a new project
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

  // Update an existing project
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