/**
 * Memory Integration Layer
 *
 * Enhances the Galaxy Assistant with agentic memory capabilities:
 * - Loads user and project context at session start
 * - Records episodes after interactions
 * - Uses past episodes to improve responses
 * - Learns from corrections and successes
 */

import { memoryService } from './memory-repository';
import type { GalaxyAssistant, ChatContext, GalaxyAssistantResponse } from './galaxy-assistant';
import type {
  Session,
  Project,
  ProjectEpisode,
  UserPreference,
  ProjectProcedure,
} from '../shared/ltm-schema';

// Extended context with memory
export interface MemoryEnhancedContext extends ChatContext {
  // Memory session
  memorySessionId?: string;
  projectId?: string;

  // Loaded context (populated by loadMemoryContext)
  userMemory?: {
    preferences: UserPreference[];
    recentCorrections: any[];
    stats: { totalWorkflows: number; successRate: number };
  };
  projectMemory?: {
    project: Project;
    knowledge: any[];
    episodes: ProjectEpisode[];
    procedures: ProjectProcedure[];
    recentWorkflows: any[];
  };
}

// Response with episode tracking
export interface MemoryEnhancedResponse extends GalaxyAssistantResponse {
  episodeId?: number;
  memorySessionId?: string;
}

/**
 * Memory Integration Service
 * Wraps GalaxyAssistant to add memory capabilities
 */
export class MemoryIntegration {
  private assistant: GalaxyAssistant;

  constructor(assistant: GalaxyAssistant) {
    this.assistant = assistant;
  }

  /**
   * Initialize a memory-enhanced session
   */
  async initializeSession(
    userId: string,
    projectId?: string
  ): Promise<{
    session: Session;
    context: MemoryEnhancedContext;
  }> {
    const result = await memoryService.initializeSession(userId, projectId);

    const context: MemoryEnhancedContext = {
      memorySessionId: result.session.id,
      projectId,
      userId: userId as any,
    };

    // Load user memory
    if (result.userContext.user) {
      context.userMemory = {
        preferences: result.userContext.preferences,
        recentCorrections: result.userContext.recentCorrections,
        stats: result.userContext.stats,
      };
    }

    // Load project memory
    if (result.projectContext?.project) {
      context.projectMemory = {
        project: result.projectContext.project,
        knowledge: result.projectContext.knowledge,
        episodes: result.projectContext.recentEpisodes,
        procedures: result.projectContext.procedures,
        recentWorkflows: result.projectContext.recentWorkflows,
      };
    }

    return { session: result.session, context };
  }

  /**
   * Process message with memory enhancement
   */
  async processWithMemory(
    message: string,
    context: MemoryEnhancedContext
  ): Promise<MemoryEnhancedResponse> {
    // Step 1: Build memory-enhanced context
    const enhancedContext = await this.enhanceContextWithMemory(message, context);

    // Step 2: Check for matching procedures
    const matchingProcedures = await this.findMatchingProcedures(message, context);

    // Step 3: Get similar past episodes
    const similarEpisodes = await this.getSimilarEpisodes(message, context);

    // Step 4: Add memory hints to context
    enhancedContext.previousMessages = this.addMemoryHints(
      context.previousMessages || [],
      matchingProcedures,
      similarEpisodes,
      context.projectMemory?.knowledge || []
    );

    // Step 5: Process with the assistant
    const response = await this.assistant.processMessage(message, enhancedContext);

    // Step 6: Record the episode
    let episodeId: number | undefined;
    if (context.memorySessionId && context.projectId) {
      const episode = await this.recordEpisode(message, response, context);
      episodeId = episode?.id;
    }

    // Step 7: Learn from the interaction
    await this.learnFromInteraction(message, response, context);

    return {
      ...response,
      episodeId,
      memorySessionId: context.memorySessionId,
    };
  }

  /**
   * Update episode outcome after workflow execution
   */
  async recordOutcome(
    episodeId: number,
    outcome: {
      success: boolean;
      errorType?: string;
      errorMessage?: string;
    }
  ): Promise<void> {
    // Generate reflection
    const reflection = outcome.success
      ? { whatWorked: ['Workflow executed successfully'], lessonsLearned: ['Approach validated'] }
      : { whatFailed: [outcome.errorMessage || 'Execution failed'], lessonsLearned: ['Need to verify parameters'] };

    await memoryService.episodes.updateEpisodeOutcome(episodeId, {
      success: outcome.success,
      errorType: outcome.errorType,
      errorMessage: outcome.errorMessage,
      ...reflection,
    });

    console.log(`[MemoryIntegration] Recorded outcome for episode ${episodeId}: ${outcome.success ? 'success' : 'failure'}`);
  }

  /**
   * End session with summary
   */
  async endSession(
    sessionId: string,
    summary: string,
    keyDecisions?: Array<{ decision: string; reason: string }>
  ): Promise<Session> {
    return memoryService.endSessionWithSummary(sessionId, summary, keyDecisions);
  }

  /**
   * Record a user correction for learning
   */
  async recordCorrection(
    userId: string,
    sessionId: string,
    projectId: string | undefined,
    correction: {
      suggestedApproach: any;
      correctedApproach: any;
      workflowContext: any;
      userExplanation?: string;
    }
  ): Promise<void> {
    await memoryService.users.recordCorrection({
      userId,
      sessionId,
      projectId,
      suggestedApproach: correction.suggestedApproach,
      correctedApproach: correction.correctedApproach,
      workflowContext: correction.workflowContext,
      userExplanation: correction.userExplanation,
    });

    console.log('[MemoryIntegration] Recorded correction for learning');
  }

  // ============================================================================
  // Private Methods
  // ============================================================================

  private async enhanceContextWithMemory(
    message: string,
    context: MemoryEnhancedContext
  ): Promise<MemoryEnhancedContext> {
    // If we don't have memory loaded yet, load it
    if (!context.userMemory && context.userId) {
      const userContext = await memoryService.users.loadUserContext(String(context.userId));
      if (userContext.user) {
        context.userMemory = {
          preferences: userContext.preferences,
          recentCorrections: userContext.recentCorrections,
          stats: userContext.stats,
        };
      }
    }

    if (!context.projectMemory && context.projectId) {
      const projectContext = await memoryService.projects.loadProjectContext(context.projectId);
      if (projectContext.project) {
        context.projectMemory = {
          project: projectContext.project,
          knowledge: projectContext.knowledge,
          episodes: projectContext.recentEpisodes,
          procedures: projectContext.procedures,
          recentWorkflows: projectContext.recentWorkflows,
        };
      }
    }

    return context;
  }

  private async findMatchingProcedures(
    message: string,
    context: MemoryEnhancedContext
  ): Promise<ProjectProcedure[]> {
    if (!context.projectId) return [];

    try {
      return await memoryService.procedures.findMatchingProcedures(context.projectId, message);
    } catch (error) {
      console.error('[MemoryIntegration] Error finding procedures:', error);
      return [];
    }
  }

  private async getSimilarEpisodes(
    message: string,
    context: MemoryEnhancedContext
  ): Promise<ProjectEpisode[]> {
    if (!context.projectId) return [];

    try {
      return await memoryService.episodes.getSimilarEpisodes(context.projectId, {
        intent: message,
        limit: 5,
      });
    } catch (error) {
      console.error('[MemoryIntegration] Error getting similar episodes:', error);
      return [];
    }
  }

  private addMemoryHints(
    messages: Array<{ role: 'user' | 'assistant'; content: string }>,
    procedures: ProjectProcedure[],
    episodes: ProjectEpisode[],
    knowledge: any[]
  ): Array<{ role: 'user' | 'assistant'; content: string }> {
    const hints: string[] = [];

    // Add relevant procedures
    if (procedures.length > 0) {
      const topProcedure = procedures[0];
      hints.push(`[Memory: Similar task previously handled with "${topProcedure.name}" (${Math.round((topProcedure.successRate || 0) * 100)}% success rate)]`);
    }

    // Add lessons from past episodes
    const successfulEpisodes = episodes.filter(e => e.outcomeSuccess);
    if (successfulEpisodes.length > 0) {
      const lessons = successfulEpisodes
        .flatMap(e => e.lessonsLearned || [])
        .slice(0, 2);
      if (lessons.length > 0) {
        hints.push(`[Memory: Past lessons - ${lessons.join('; ')}]`);
      }
    }

    // Add relevant knowledge
    const relevantKnowledge = knowledge.slice(0, 2);
    if (relevantKnowledge.length > 0) {
      const knowledgeHints = relevantKnowledge.map(k => k.title || k.content.substring(0, 50));
      hints.push(`[Memory: Project knowledge - ${knowledgeHints.join('; ')}]`);
    }

    // If we have hints, add them as a system message at the start
    if (hints.length > 0) {
      const memoryContext = {
        role: 'assistant' as const,
        content: `Context from memory:\n${hints.join('\n')}`,
      };
      return [memoryContext, ...messages];
    }

    return messages;
  }

  private async recordEpisode(
    message: string,
    response: GalaxyAssistantResponse,
    context: MemoryEnhancedContext
  ): Promise<ProjectEpisode | null> {
    if (!context.projectId || !context.memorySessionId) return null;

    try {
      const episode = await memoryService.episodes.recordEpisode({
        projectId: context.projectId,
        sessionId: context.memorySessionId,
        userQuery: message,
        assistantResponse: response.message,
        userIntent: response.workflowSuggestion?.userIntent,
        toolsUsed: response.recommendedTools?.map(t => ({
          tool_id: t.tool.id,
          parameters: {},
          output_summary: t.reasoning,
        })),
        workflowGenerated: response.sources.workflowGenerated,
      });

      console.log(`[MemoryIntegration] Recorded episode ${episode.id}`);
      return episode;
    } catch (error) {
      console.error('[MemoryIntegration] Error recording episode:', error);
      return null;
    }
  }

  private async learnFromInteraction(
    message: string,
    response: GalaxyAssistantResponse,
    context: MemoryEnhancedContext
  ): Promise<void> {
    // Learn tool preferences
    if (response.recommendedTools && response.recommendedTools.length > 0 && context.userMemory) {
      const topTool = response.recommendedTools[0];

      // Check if this is a frequently used tool
      const existingPref = context.userMemory.preferences.find(
        p => p.preferenceKey === `tool:${topTool.tool.id}`
      );

      if (!existingPref && context.userId) {
        // Record new tool preference (low confidence initially)
        await memoryService.users.recordPreference({
          userId: String(context.userId),
          preferenceType: 'tool_selection',
          preferenceKey: `tool:${topTool.tool.id}`,
          preferenceValue: { tool_id: topTool.tool.id, tool_name: topTool.tool.name },
          context: { intent: message.substring(0, 100) },
          learnedFrom: 'repeated_usage',
          confidence: 0.3,
        });
      }
    }
  }
}

/**
 * Build memory context string for prompts
 */
export function buildMemoryContextPrompt(context: MemoryEnhancedContext): string {
  const sections: string[] = [];

  // User context
  if (context.userMemory) {
    const userStats = context.userMemory.stats;
    sections.push(`## User Context
- Experience Level: ${userStats.totalWorkflows > 20 ? 'Expert' : userStats.totalWorkflows > 5 ? 'Intermediate' : 'Beginner'}
- Workflow Success Rate: ${Math.round(userStats.successRate * 100)}%
- Previous Workflows: ${userStats.totalWorkflows}`);

    // Add preferences
    if (context.userMemory.preferences.length > 0) {
      const prefs = context.userMemory.preferences
        .filter(p => (p.confidence || 0) > 0.5)
        .slice(0, 5)
        .map(p => `- ${p.preferenceKey}: ${JSON.stringify(p.preferenceValue)}`)
        .join('\n');
      if (prefs) {
        sections.push(`## User Preferences\n${prefs}`);
      }
    }

    // Add recent corrections (to avoid repeating mistakes)
    if (context.userMemory.recentCorrections.length > 0) {
      const corrections = context.userMemory.recentCorrections
        .slice(0, 3)
        .map(c => `- Suggested: ${JSON.stringify(c.suggestedApproach)} → Corrected: ${JSON.stringify(c.correctedApproach)}`)
        .join('\n');
      sections.push(`## Recent Corrections (avoid these mistakes)\n${corrections}`);
    }
  }

  // Project context
  if (context.projectMemory?.project) {
    const project = context.projectMemory.project;
    sections.push(`## Project Context
- Name: ${project.name}
- Domain: ${project.primaryDomain || 'Not specified'}
- Research Goal: ${project.researchGoal || project.description || 'Not specified'}
- Organisms: ${project.organisms?.join(', ') || 'Not specified'}
- Data Types: ${project.dataModalities?.join(', ') || 'Not specified'}`);

    // Add project knowledge
    if (context.projectMemory.knowledge.length > 0) {
      const knowledge = context.projectMemory.knowledge
        .slice(0, 5)
        .map(k => `- [${k.knowledgeType}] ${k.title || k.content.substring(0, 100)}`)
        .join('\n');
      sections.push(`## Project Knowledge\n${knowledge}`);
    }
  }

  return sections.join('\n\n');
}

// Singleton factory
let memoryIntegrationInstance: MemoryIntegration | null = null;

export function createMemoryIntegration(assistant: GalaxyAssistant): MemoryIntegration {
  if (!memoryIntegrationInstance) {
    memoryIntegrationInstance = new MemoryIntegration(assistant);
  }
  return memoryIntegrationInstance;
}

export function getMemoryIntegration(): MemoryIntegration | null {
  return memoryIntegrationInstance;
}
