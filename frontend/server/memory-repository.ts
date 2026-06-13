/**
 * Long-Term Memory Repository
 *
 * Provides database access for the agentic memory system.
 * Implements the architecture from LONG_TERM_MEMORY_ARCHITECTURE_20251031.md
 * with agentic extensions for episodic memory and procedural learning.
 */

import { eq, and, desc, sql, gte, lte, or, like, inArray } from 'drizzle-orm';
import { db, ltmSchema } from './db';
import type {
  LtmUser, InsertLtmUser,
  Project, InsertProject,
  Session, InsertSession,
  ConversationMessage, InsertConversationMessage,
  UserPreference, InsertUserPreference,
  CorrectionLogEntry, InsertCorrectionLog,
  ProjectKnowledgeEntry, InsertProjectKnowledge,
  Workflow, InsertWorkflow,
  ProjectEpisode, InsertProjectEpisode,
  ProjectProcedure, InsertProjectProcedure,
} from '../shared/ltm-schema';

// ============================================================================
// User Memory Repository
// ============================================================================

export class UserMemoryRepository {
  /**
   * Ensure an ltm_users row exists for the given auth user ID.
   * Creates a new row with the specified ID (not a random UUID) if none exists.
   * This is required before inserting into any table that has a FK to ltm_users.id.
   */
  async ensureLtmUser(userId: string, email?: string, name?: string): Promise<void> {
    const existing = await db.query.ltmUsers.findFirst({
      where: eq(ltmSchema.ltmUsers.id, userId),
    });
    if (!existing) {
      await db.insert(ltmSchema.ltmUsers)
        .values({ id: userId, email: email || `${userId}@auto.biomate.internal`, name: name || undefined })
        .onConflictDoNothing();
    }
  }

  /**
   * Get or create user profile
   */
  async getOrCreateUser(email: string, data?: Partial<InsertLtmUser>): Promise<LtmUser> {
    const existing = await db.query.ltmUsers.findFirst({
      where: eq(ltmSchema.ltmUsers.email, email),
    });

    if (existing) {
      // Update last active
      await db.update(ltmSchema.ltmUsers)
        .set({ lastActive: new Date() })
        .where(eq(ltmSchema.ltmUsers.id, existing.id));
      return existing;
    }

    const [newUser] = await db.insert(ltmSchema.ltmUsers)
      .values({ email, ...data })
      .returning();

    return newUser;
  }

  /**
   * Get user by ID
   */
  async getUser(userId: string): Promise<LtmUser | null> {
    const user = await db.query.ltmUsers.findFirst({
      where: eq(ltmSchema.ltmUsers.id, userId),
    });
    return user || null;
  }

  /**
   * Update user profile
   */
  async updateUser(userId: string, data: Partial<InsertLtmUser>): Promise<LtmUser> {
    const [updated] = await db.update(ltmSchema.ltmUsers)
      .set({ ...data, lastActive: new Date() })
      .where(eq(ltmSchema.ltmUsers.id, userId))
      .returning();
    return updated;
  }

  /**
   * Get user preferences with context filtering
   */
  async getUserPreferences(
    userId: string,
    context?: { domain?: string; dataType?: string }
  ): Promise<UserPreference[]> {
    let query = db.select()
      .from(ltmSchema.userPreferences)
      .where(eq(ltmSchema.userPreferences.userId, userId))
      .orderBy(desc(ltmSchema.userPreferences.confidence));

    const preferences = await query;

    // Filter by context if provided
    if (context) {
      return preferences.filter(pref => {
        if (!pref.context) return true;
        const prefContext = pref.context as Record<string, string>;
        if (context.domain && prefContext.domain && prefContext.domain !== context.domain) {
          return false;
        }
        if (context.dataType && prefContext.data_type && prefContext.data_type !== context.dataType) {
          return false;
        }
        return true;
      });
    }

    return preferences;
  }

  /**
   * Record or update a user preference
   */
  async recordPreference(data: InsertUserPreference): Promise<UserPreference> {
    // Check for existing preference with same key and context
    const existing = await db.query.userPreferences.findFirst({
      where: and(
        eq(ltmSchema.userPreferences.userId, data.userId!),
        eq(ltmSchema.userPreferences.preferenceKey, data.preferenceKey)
      ),
    });

    if (existing) {
      // Update existing preference
      const [updated] = await db.update(ltmSchema.userPreferences)
        .set({
          preferenceValue: data.preferenceValue,
          usageCount: (existing.usageCount || 0) + 1,
          confidence: Math.min(1.0, (existing.confidence || 0.5) + 0.1),
          lastUsed: new Date(),
        })
        .where(eq(ltmSchema.userPreferences.id, existing.id))
        .returning();
      return updated;
    }

    // Create new preference
    const [newPref] = await db.insert(ltmSchema.userPreferences)
      .values(data)
      .returning();
    return newPref;
  }

  /**
   * Record a correction (learning from mistakes)
   */
  async recordCorrection(data: InsertCorrectionLog): Promise<CorrectionLogEntry> {
    const [correction] = await db.insert(ltmSchema.correctionLog)
      .values(data)
      .returning();
    return correction;
  }

  /**
   * Get user's correction history for learning
   */
  async getUserCorrections(
    userId: string,
    limit: number = 20
  ): Promise<CorrectionLogEntry[]> {
    return db.select()
      .from(ltmSchema.correctionLog)
      .where(eq(ltmSchema.correctionLog.userId, userId))
      .orderBy(desc(ltmSchema.correctionLog.createdAt))
      .limit(limit);
  }

  /**
   * Load complete user context for session initialization
   */
  async loadUserContext(userId: string): Promise<{
    user: LtmUser | null;
    preferences: UserPreference[];
    recentCorrections: CorrectionLogEntry[];
    recentSessions: Session[];
    stats: { totalWorkflows: number; successRate: number };
  }> {
    const user = await this.getUser(userId);
    if (!user) {
      return {
        user: null,
        preferences: [],
        recentCorrections: [],
        recentSessions: [],
        stats: { totalWorkflows: 0, successRate: 0 },
      };
    }

    const [preferences, recentCorrections, recentSessions] = await Promise.all([
      this.getUserPreferences(userId),
      this.getUserCorrections(userId, 10),
      db.select()
        .from(ltmSchema.sessions)
        .where(eq(ltmSchema.sessions.userId, userId))
        .orderBy(desc(ltmSchema.sessions.startedAt))
        .limit(5),
    ]);

    const successRate = user.totalWorkflows && user.totalWorkflows > 0
      ? (user.successfulWorkflows || 0) / user.totalWorkflows
      : 0;

    return {
      user,
      preferences,
      recentCorrections,
      recentSessions,
      stats: {
        totalWorkflows: user.totalWorkflows || 0,
        successRate,
      },
    };
  }
}

// ============================================================================
// Project Memory Repository
// ============================================================================

export class ProjectMemoryRepository {
  /**
   * Create a new project
   */
  async createProject(data: InsertProject): Promise<Project> {
    const [project] = await db.insert(ltmSchema.projects)
      .values(data)
      .returning();
    return project;
  }

  /**
   * Get project by ID
   */
  async getProject(projectId: string): Promise<Project | null> {
    const project = await db.query.projects.findFirst({
      where: eq(ltmSchema.projects.id, projectId),
    });
    return project || null;
  }

  /**
   * Get all projects for a user
   */
  async getUserProjects(
    userId: string,
    status?: 'active' | 'archived' | 'completed'
  ): Promise<Project[]> {
    const conditions = [eq(ltmSchema.projects.userId, userId)];
    if (status) {
      conditions.push(eq(ltmSchema.projects.status, status));
    }

    return db.select()
      .from(ltmSchema.projects)
      .where(and(...conditions))
      .orderBy(desc(ltmSchema.projects.updatedAt));
  }

  /**
   * Update project
   */
  async updateProject(projectId: string, data: Partial<InsertProject>): Promise<Project> {
    const [updated] = await db.update(ltmSchema.projects)
      .set({ ...data, updatedAt: new Date() })
      .where(eq(ltmSchema.projects.id, projectId))
      .returning();
    return updated;
  }

  /**
   * Archive a project (soft-delete via status='archived').
   * Keeps history + episodes intact for audit; just hides it from active lists.
   */
  async archiveProject(projectId: string): Promise<Project | null> {
    const [updated] = await db.update(ltmSchema.projects)
      .set({ status: 'archived', updatedAt: new Date() })
      .where(eq(ltmSchema.projects.id, projectId))
      .returning();
    return updated || null;
  }

  /**
   * Hard-delete a project. CASCADEs to episodes, procedures, project_knowledge
   * (per the FK definitions in 0012_ltm_schema.sql). chat_sessions.project_id
   * is set to NULL (ON DELETE SET NULL) so the conversation rows survive
   * but become project-less.
   *
   * Returns true if a row was deleted, false otherwise.
   */
  async deleteProject(projectId: string): Promise<boolean> {
    const result = await db.delete(ltmSchema.projects)
      .where(eq(ltmSchema.projects.id, projectId))
      .returning({ id: ltmSchema.projects.id });
    return result.length > 0;
  }

  /**
   * Add knowledge to project
   */
  async addProjectKnowledge(data: InsertProjectKnowledge): Promise<ProjectKnowledgeEntry> {
    const [knowledge] = await db.insert(ltmSchema.projectKnowledge)
      .values(data)
      .returning();
    return knowledge;
  }

  /**
   * Get project knowledge base
   */
  async getProjectKnowledge(
    projectId: string,
    knowledgeType?: string
  ): Promise<ProjectKnowledgeEntry[]> {
    const conditions = [eq(ltmSchema.projectKnowledge.projectId, projectId)];
    if (knowledgeType) {
      conditions.push(eq(ltmSchema.projectKnowledge.knowledgeType, knowledgeType));
    }

    return db.select()
      .from(ltmSchema.projectKnowledge)
      .where(and(...conditions))
      .orderBy(desc(ltmSchema.projectKnowledge.relevanceScore));
  }

  /**
   * Load complete project context
   */
  async loadProjectContext(projectId: string): Promise<{
    project: Project | null;
    knowledge: ProjectKnowledgeEntry[];
    recentEpisodes: ProjectEpisode[];
    procedures: ProjectProcedure[];
    recentWorkflows: Workflow[];
  }> {
    const project = await this.getProject(projectId);
    if (!project) {
      return {
        project: null,
        knowledge: [],
        recentEpisodes: [],
        procedures: [],
        recentWorkflows: [],
      };
    }

    const [knowledge, recentEpisodes, procedures, recentWorkflows] = await Promise.all([
      this.getProjectKnowledge(projectId),
      db.select()
        .from(ltmSchema.projectEpisodes)
        .where(eq(ltmSchema.projectEpisodes.projectId, projectId))
        .orderBy(desc(ltmSchema.projectEpisodes.importanceScore))
        .limit(10),
      db.select()
        .from(ltmSchema.projectProcedures)
        .where(eq(ltmSchema.projectProcedures.projectId, projectId))
        .orderBy(desc(ltmSchema.projectProcedures.successRate)),
      db.select()
        .from(ltmSchema.workflows)
        .where(eq(ltmSchema.workflows.projectId, projectId))
        .orderBy(desc(ltmSchema.workflows.createdAt))
        .limit(10),
    ]);

    return {
      project,
      knowledge,
      recentEpisodes,
      procedures,
      recentWorkflows,
    };
  }

  /**
   * Search projects by domain or tags
   */
  async searchProjects(
    userId: string,
    query: { domain?: string; tags?: string[]; text?: string }
  ): Promise<Project[]> {
    const conditions = [eq(ltmSchema.projects.userId, userId)];

    if (query.domain) {
      conditions.push(eq(ltmSchema.projects.primaryDomain, query.domain));
    }

    let projects = await db.select()
      .from(ltmSchema.projects)
      .where(and(...conditions))
      .orderBy(desc(ltmSchema.projects.updatedAt));

    // Filter by tags (post-query filtering for array contains)
    if (query.tags && query.tags.length > 0) {
      projects = projects.filter(p =>
        p.tags && query.tags!.some(tag => p.tags!.includes(tag))
      );
    }

    // Filter by text search
    if (query.text) {
      const lowerText = query.text.toLowerCase();
      projects = projects.filter(p =>
        p.name.toLowerCase().includes(lowerText) ||
        (p.description && p.description.toLowerCase().includes(lowerText)) ||
        (p.researchGoal && p.researchGoal.toLowerCase().includes(lowerText))
      );
    }

    return projects;
  }
}

// ============================================================================
// Session Memory Repository
// ============================================================================

export class SessionMemoryRepository {
  /**
   * Create a new session
   */
  async createSession(data: InsertSession): Promise<Session> {
    const [session] = await db.insert(ltmSchema.sessions)
      .values(data)
      .returning();
    return session;
  }

  /**
   * Get session by ID
   */
  async getSession(sessionId: string): Promise<Session | null> {
    const session = await db.query.sessions.findFirst({
      where: eq(ltmSchema.sessions.id, sessionId),
    });
    return session || null;
  }

  /**
   * End session with summary
   */
  async endSession(
    sessionId: string,
    summary: string,
    keyDecisions?: Array<{ decision: string; reason: string }>
  ): Promise<Session> {
    const session = await this.getSession(sessionId);
    if (!session) throw new Error(`Session not found: ${sessionId}`);

    const durationSeconds = session.startedAt
      ? Math.floor((Date.now() - session.startedAt.getTime()) / 1000)
      : 0;

    const [updated] = await db.update(ltmSchema.sessions)
      .set({
        endedAt: new Date(),
        durationSeconds,
        summary,
        keyDecisions: keyDecisions as any,
      })
      .where(eq(ltmSchema.sessions.id, sessionId))
      .returning();

    return updated;
  }

  /**
   * C3b — Update session summary without closing the session.
   * Used when context is compressed to store a rolling summary of older turns.
   */
  async updateSessionSummary(sessionId: string, summary: string): Promise<void> {
    await db.update(ltmSchema.sessions)
      .set({ summary })
      .where(eq(ltmSchema.sessions.id, sessionId));
  }

  /**
   * Add message to session
   */
  async addMessage(data: InsertConversationMessage): Promise<ConversationMessage> {
    const [message] = await db.insert(ltmSchema.conversationMessages)
      .values(data)
      .returning();

    // Update session message count
    if (data.sessionId) {
      await db.update(ltmSchema.sessions)
        .set({
          messageCount: sql`${ltmSchema.sessions.messageCount} + 1`,
          totalTokens: data.tokenCount
            ? sql`${ltmSchema.sessions.totalTokens} + ${data.tokenCount}`
            : ltmSchema.sessions.totalTokens,
        })
        .where(eq(ltmSchema.sessions.id, data.sessionId));
    }

    return message;
  }

  /**
   * Get session messages
   */
  async getSessionMessages(sessionId: string, limit?: number): Promise<ConversationMessage[]> {
    let query = db.select()
      .from(ltmSchema.conversationMessages)
      .where(eq(ltmSchema.conversationMessages.sessionId, sessionId))
      .orderBy(ltmSchema.conversationMessages.createdAt);

    if (limit) {
      query = query.limit(limit) as any;
    }

    return query;
  }

  /**
   * Get recent sessions for a user
   */
  async getRecentSessions(userId: string, limit: number = 10): Promise<Session[]> {
    return db.select()
      .from(ltmSchema.sessions)
      .where(eq(ltmSchema.sessions.userId, userId))
      .orderBy(desc(ltmSchema.sessions.startedAt))
      .limit(limit);
  }

  /**
   * Get sessions for a project
   */
  async getProjectSessions(projectId: string): Promise<Session[]> {
    return db.select()
      .from(ltmSchema.sessions)
      .where(eq(ltmSchema.sessions.projectId, projectId))
      .orderBy(desc(ltmSchema.sessions.startedAt));
  }
}

// ============================================================================
// Episodic Memory Repository (Agentic)
// ============================================================================

export class EpisodicMemoryRepository {
  /**
   * Record an episode (interaction + outcome)
   */
  async recordEpisode(data: InsertProjectEpisode): Promise<ProjectEpisode> {
    const [episode] = await db.insert(ltmSchema.projectEpisodes)
      .values(data)
      .returning();
    return episode;
  }

  /**
   * Get similar episodes for retrieval-augmented reasoning
   */
  async getSimilarEpisodes(
    projectId: string,
    query: { intent?: string; toolsUsed?: string[]; limit?: number }
  ): Promise<ProjectEpisode[]> {
    let episodes = await db.select()
      .from(ltmSchema.projectEpisodes)
      .where(eq(ltmSchema.projectEpisodes.projectId, projectId))
      .orderBy(desc(ltmSchema.projectEpisodes.importanceScore));

    // Filter by tools used (post-query)
    if (query.toolsUsed && query.toolsUsed.length > 0) {
      episodes = episodes.filter(ep => {
        if (!ep.toolsUsed) return false;
        const tools = ep.toolsUsed as Array<{ tool_id: string }>;
        return query.toolsUsed!.some(t =>
          tools.some(used => used.tool_id === t)
        );
      });
    }

    // Filter by intent similarity (basic text match)
    if (query.intent) {
      const lowerIntent = query.intent.toLowerCase();
      episodes = episodes.filter(ep =>
        (ep.userIntent && ep.userIntent.toLowerCase().includes(lowerIntent)) ||
        ep.userQuery.toLowerCase().includes(lowerIntent)
      );
    }

    return episodes.slice(0, query.limit || 10);
  }

  /**
   * Get successful episodes for learning
   */
  async getSuccessfulEpisodes(projectId: string, limit: number = 20): Promise<ProjectEpisode[]> {
    return db.select()
      .from(ltmSchema.projectEpisodes)
      .where(and(
        eq(ltmSchema.projectEpisodes.projectId, projectId),
        eq(ltmSchema.projectEpisodes.outcomeSuccess, true)
      ))
      .orderBy(desc(ltmSchema.projectEpisodes.importanceScore))
      .limit(limit);
  }

  /**
   * Get recent episodes across all of a user's projects (user-scoped retrieval for memory injection).
   * Joins through projects table to find episodes belonging to the user.
   */
  async getRecentUserEpisodes(userId: string, limit: number = 10): Promise<ProjectEpisode[]> {
    const userProjects = await db.select({ id: ltmSchema.projects.id })
      .from(ltmSchema.projects)
      .where(eq(ltmSchema.projects.userId, userId));
    if (!userProjects.length) return [];
    const projectIds = userProjects.map(p => p.id).filter(Boolean) as string[];
    if (!projectIds.length) return [];
    return db.select()
      .from(ltmSchema.projectEpisodes)
      .where(inArray(ltmSchema.projectEpisodes.projectId, projectIds))
      .orderBy(
        desc(ltmSchema.projectEpisodes.importanceScore),
        desc(ltmSchema.projectEpisodes.createdAt)
      )
      .limit(limit);
  }

  /**
   * Get failed episodes for learning
   */
  async getFailedEpisodes(projectId: string, limit: number = 20): Promise<ProjectEpisode[]> {
    return db.select()
      .from(ltmSchema.projectEpisodes)
      .where(and(
        eq(ltmSchema.projectEpisodes.projectId, projectId),
        eq(ltmSchema.projectEpisodes.outcomeSuccess, false)
      ))
      .orderBy(desc(ltmSchema.projectEpisodes.createdAt))
      .limit(limit);
  }

  /**
   * Update episode outcome (after workflow execution)
   */
  async updateEpisodeOutcome(
    episodeId: number,
    outcome: {
      success: boolean;
      errorType?: string;
      errorMessage?: string;
      whatWorked?: string[];
      whatFailed?: string[];
      lessonsLearned?: string[];
    }
  ): Promise<ProjectEpisode> {
    const [updated] = await db.update(ltmSchema.projectEpisodes)
      .set({
        outcomeSuccess: outcome.success,
        errorOccurred: !outcome.success,
        errorType: outcome.errorType,
        errorMessage: outcome.errorMessage,
        whatWorked: outcome.whatWorked,
        whatFailed: outcome.whatFailed,
        lessonsLearned: outcome.lessonsLearned,
        importanceScore: outcome.success ? 0.6 : 0.8, // Failures are more important to remember
      })
      .where(eq(ltmSchema.projectEpisodes.id, episodeId))
      .returning();
    return updated;
  }

  /**
   * Consolidate episodes into procedures (memory consolidation)
   */
  async consolidateEpisodes(projectId: string): Promise<{
    episodesProcessed: number;
    patternsFound: number;
  }> {
    // Get successful episodes with similar patterns
    const episodes = await this.getSuccessfulEpisodes(projectId, 50);

    // Group by user intent pattern
    const intentGroups = new Map<string, ProjectEpisode[]>();
    for (const ep of episodes) {
      const intent = ep.userIntent || 'unknown';
      const existing = intentGroups.get(intent) || [];
      existing.push(ep);
      intentGroups.set(intent, existing);
    }

    // Find patterns with 3+ occurrences
    let patternsFound = 0;
    for (const [intent, group] of intentGroups) {
      if (group.length >= 3) {
        patternsFound++;
        // Could create/update procedures here
        console.log(`[EpisodicMemory] Found pattern: "${intent}" with ${group.length} occurrences`);
      }
    }

    return {
      episodesProcessed: episodes.length,
      patternsFound,
    };
  }

  /**
   * Increment access count (for importance decay)
   */
  async accessEpisode(episodeId: number): Promise<void> {
    await db.update(ltmSchema.projectEpisodes)
      .set({
        accessCount: sql`${ltmSchema.projectEpisodes.accessCount} + 1`,
        lastAccessed: new Date(),
      })
      .where(eq(ltmSchema.projectEpisodes.id, episodeId));
  }
}

// ============================================================================
// Procedural Memory Repository (Agentic)
// ============================================================================

export class ProceduralMemoryRepository {
  /**
   * Create a learned procedure
   */
  async createProcedure(data: InsertProjectProcedure): Promise<ProjectProcedure> {
    const [procedure] = await db.insert(ltmSchema.projectProcedures)
      .values(data)
      .returning();
    return procedure;
  }

  /**
   * Get procedure by ID
   */
  async getProcedure(procedureId: number): Promise<ProjectProcedure | null> {
    const procedure = await db.query.projectProcedures.findFirst({
      where: eq(ltmSchema.projectProcedures.id, procedureId),
    });
    return procedure || null;
  }

  /**
   * Find matching procedures for a trigger
   */
  async findMatchingProcedures(
    projectId: string,
    trigger: string
  ): Promise<ProjectProcedure[]> {
    const procedures = await db.select()
      .from(ltmSchema.projectProcedures)
      .where(eq(ltmSchema.projectProcedures.projectId, projectId))
      .orderBy(desc(ltmSchema.projectProcedures.successRate));

    // Match trigger patterns
    const lowerTrigger = trigger.toLowerCase();
    return procedures.filter(p =>
      lowerTrigger.includes(p.triggerPattern.toLowerCase()) ||
      p.triggerPattern.toLowerCase().includes(lowerTrigger)
    );
  }

  /**
   * Get high-success procedures
   */
  async getReliableProcedures(
    projectId: string,
    minSuccessRate: number = 0.7
  ): Promise<ProjectProcedure[]> {
    return db.select()
      .from(ltmSchema.projectProcedures)
      .where(and(
        eq(ltmSchema.projectProcedures.projectId, projectId),
        gte(ltmSchema.projectProcedures.successRate, minSuccessRate)
      ))
      .orderBy(desc(ltmSchema.projectProcedures.successRate));
  }

  /**
   * Record procedure usage and update success rate
   */
  async recordUsage(procedureId: number, success: boolean): Promise<ProjectProcedure> {
    const procedure = await this.getProcedure(procedureId);
    if (!procedure) throw new Error(`Procedure not found: ${procedureId}`);

    const timesUsed = (procedure.timesUsed || 0) + 1;
    const currentSuccessCount = (procedure.successRate || 0) * (procedure.timesUsed || 0);
    const newSuccessRate = (currentSuccessCount + (success ? 1 : 0)) / timesUsed;

    const [updated] = await db.update(ltmSchema.projectProcedures)
      .set({
        timesUsed,
        successRate: newSuccessRate,
        lastUsed: new Date(),
        updatedAt: new Date(),
      })
      .where(eq(ltmSchema.projectProcedures.id, procedureId))
      .returning();

    return updated;
  }

  /**
   * Update procedure steps
   */
  async updateProcedure(
    procedureId: number,
    data: Partial<InsertProjectProcedure>
  ): Promise<ProjectProcedure> {
    const [updated] = await db.update(ltmSchema.projectProcedures)
      .set({ ...data, updatedAt: new Date() })
      .where(eq(ltmSchema.projectProcedures.id, procedureId))
      .returning();
    return updated;
  }
}

// ============================================================================
// Workflow Memory Repository
// ============================================================================

export class WorkflowMemoryRepository {
  /**
   * Save workflow to history
   */
  async saveWorkflow(data: InsertWorkflow): Promise<Workflow> {
    const [workflow] = await db.insert(ltmSchema.workflows)
      .values(data)
      .returning();
    return workflow;
  }

  /**
   * Get workflow by ID
   */
  async getWorkflow(workflowId: string): Promise<Workflow | null> {
    const workflow = await db.query.workflows.findFirst({
      where: eq(ltmSchema.workflows.id, workflowId),
    });
    return workflow || null;
  }

  /**
   * Update workflow status
   */
  async updateWorkflowStatus(
    workflowId: string,
    status: string,
    data?: {
      executionId?: string;
      success?: boolean;
      errorMessage?: string;
    }
  ): Promise<Workflow> {
    const updateData: Partial<InsertWorkflow> & { status: string } = {
      status,
      updatedAt: new Date(),
    };

    if (data?.executionId) updateData.executionId = data.executionId;
    if (data?.success !== undefined) updateData.success = data.success;
    if (data?.errorMessage) updateData.errorMessage = data.errorMessage;

    if (status === 'executing') {
      updateData.executionStartedAt = new Date();
    } else if (status === 'completed' || status === 'failed') {
      updateData.executionCompletedAt = new Date();
    }

    const [updated] = await db.update(ltmSchema.workflows)
      .set(updateData)
      .where(eq(ltmSchema.workflows.id, workflowId))
      .returning();

    // Update user workflow count if completed
    if (status === 'completed' || status === 'failed') {
      const workflow = await this.getWorkflow(workflowId);
      if (workflow?.userId) {
        await db.update(ltmSchema.ltmUsers)
          .set({
            totalWorkflows: sql`${ltmSchema.ltmUsers.totalWorkflows} + 1`,
            successfulWorkflows: status === 'completed'
              ? sql`${ltmSchema.ltmUsers.successfulWorkflows} + 1`
              : ltmSchema.ltmUsers.successfulWorkflows,
          })
          .where(eq(ltmSchema.ltmUsers.id, workflow.userId));
      }
    }

    return updated;
  }

  /**
   * Get user's workflow history
   */
  async getUserWorkflows(
    userId: string,
    options?: { status?: string; limit?: number }
  ): Promise<Workflow[]> {
    const conditions = [eq(ltmSchema.workflows.userId, userId)];
    if (options?.status) {
      conditions.push(eq(ltmSchema.workflows.status, options.status));
    }

    let query = db.select()
      .from(ltmSchema.workflows)
      .where(and(...conditions))
      .orderBy(desc(ltmSchema.workflows.createdAt));

    if (options?.limit) {
      query = query.limit(options.limit) as any;
    }

    return query;
  }

  /**
   * Get similar workflows for template reuse
   */
  async findSimilarWorkflows(
    query: { domain?: string; dataType?: string; goal?: string }
  ): Promise<Workflow[]> {
    const conditions: any[] = [];

    if (query.domain) {
      conditions.push(eq(ltmSchema.workflows.domain, query.domain));
    }
    if (query.dataType) {
      conditions.push(eq(ltmSchema.workflows.dataType, query.dataType));
    }

    let workflows = await db.select()
      .from(ltmSchema.workflows)
      .where(conditions.length > 0 ? and(...conditions) : undefined)
      .orderBy(desc(ltmSchema.workflows.createdAt))
      .limit(50);

    // Filter by goal similarity
    if (query.goal) {
      const lowerGoal = query.goal.toLowerCase();
      workflows = workflows.filter(w =>
        w.analysisGoal && w.analysisGoal.toLowerCase().includes(lowerGoal)
      );
    }

    return workflows.slice(0, 10);
  }
}

// ============================================================================
// Unified Memory Service
// ============================================================================

export class MemoryService {
  public users: UserMemoryRepository;
  public projects: ProjectMemoryRepository;
  public sessions: SessionMemoryRepository;
  public episodes: EpisodicMemoryRepository;
  public procedures: ProceduralMemoryRepository;
  public workflows: WorkflowMemoryRepository;

  constructor() {
    this.users = new UserMemoryRepository();
    this.projects = new ProjectMemoryRepository();
    this.sessions = new SessionMemoryRepository();
    this.episodes = new EpisodicMemoryRepository();
    this.procedures = new ProceduralMemoryRepository();
    this.workflows = new WorkflowMemoryRepository();
  }

  /**
   * Initialize session with full context
   */
  async initializeSession(
    userId: string,
    projectId?: string
  ): Promise<{
    session: Session;
    userContext: Awaited<ReturnType<UserMemoryRepository['loadUserContext']>>;
    projectContext: Awaited<ReturnType<ProjectMemoryRepository['loadProjectContext']>> | null;
  }> {
    // Create session
    const session = await this.sessions.createSession({
      userId,
      projectId,
    });

    // Load user context
    const userContext = await this.users.loadUserContext(userId);

    // Load project context if provided
    let projectContext = null;
    if (projectId) {
      projectContext = await this.projects.loadProjectContext(projectId);
    }

    return { session, userContext, projectContext };
  }

  /**
   * Record complete interaction (message + episode)
   */
  async recordInteraction(data: {
    sessionId: string;
    projectId?: string;
    userMessage: string;
    assistantResponse: string;
    userIntent?: string;
    toolsUsed?: Array<{ tool_id: string; parameters?: any; output_summary?: string }>;
    workflowGenerated?: boolean;
    workflowId?: string;
  }): Promise<{ userMessage: ConversationMessage; assistantMessage: ConversationMessage; episode?: ProjectEpisode }> {
    // Record user message
    const userMessage = await this.sessions.addMessage({
      sessionId: data.sessionId,
      role: 'user',
      content: data.userMessage,
    });

    // Record assistant message
    const assistantMessage = await this.sessions.addMessage({
      sessionId: data.sessionId,
      role: 'assistant',
      content: data.assistantResponse,
      toolsUsed: data.toolsUsed as any,
    });

    // Record episode if project context
    let episode: ProjectEpisode | undefined;
    if (data.projectId) {
      episode = await this.episodes.recordEpisode({
        projectId: data.projectId,
        sessionId: data.sessionId,
        userQuery: data.userMessage,
        assistantResponse: data.assistantResponse,
        userIntent: data.userIntent,
        toolsUsed: data.toolsUsed as any,
        workflowGenerated: data.workflowGenerated || false,
        workflowId: data.workflowId,
      });
    }

    return { userMessage, assistantMessage, episode };
  }

  /**
   * End session with AI-generated summary
   */
  async endSessionWithSummary(
    sessionId: string,
    summary: string,
    keyDecisions?: Array<{ decision: string; reason: string }>
  ): Promise<Session> {
    return this.sessions.endSession(sessionId, summary, keyDecisions);
  }

  /**
   * Cold-refresh dataset recovery within a project.
   *
   * When a user opens a fresh chat session in a project where they have
   * prior sessions with attached datasets, surface those datasets so
   * the LLM can pick up where they left off — without the user having
   * to re-attach files. Policy (docs/20260612_DATASET_STORAGE_AND_SESSION_BOUNDARIES.md):
   *
   *   - Only within the same project — never cross-project, never
   *     user-scoped fallback.
   *   - Excludes the current session (datasets attached this turn are
   *     handled by the normal session path).
   *   - Last 14 days only — older work is presumed archived intent.
   *   - Capped at 20 datasets; DISTINCT by id (dedupes when a dataset
   *     was attached to multiple sister sessions).
   *
   * The returned entries carry `recovered: true` so the prompt block
   * can label them distinctly ("from earlier sessions in this project")
   * — the LLM should not claim the user just attached them in the
   * current conversation.
   *
   * Returns [] on any DB error (chat must not break).
   */
  async recoverProjectDatasets(
    projectId: string,
    currentChatSessionId: string,
  ): Promise<Array<{ id: string; name: string; type: string; recovered: true; sourceSessionId: string; lastActivity: string }>> {
    if (!projectId || !currentChatSessionId) return [];
    try {
      const { pool } = await import('./db');
      const rows = await pool.query(
        `SELECT DISTINCT ON (d->>'id')
           d->>'id'   AS id,
           d->>'name' AS name,
           COALESCE(d->>'type', 'unknown') AS type,
           cs.session_id AS source_session_id,
           cs.last_activity
         FROM chat_sessions cs,
              jsonb_array_elements(cs.datasets) d
         WHERE cs.project_id = $1
           AND cs.session_id != $2
           AND cs.last_activity > NOW() - INTERVAL '14 days'
           AND jsonb_array_length(cs.datasets) > 0
         ORDER BY d->>'id', cs.last_activity DESC
         LIMIT 20`,
        [projectId, currentChatSessionId],
      );
      return (rows.rows || [])
        .filter((r: any) => r.id && r.name)
        .map((r: any) => ({
          id: String(r.id),
          name: String(r.name),
          type: String(r.type || 'unknown'),
          recovered: true as const,
          sourceSessionId: String(r.source_session_id),
          lastActivity: r.last_activity ? new Date(r.last_activity).toISOString() : '',
        }));
    } catch (e: any) {
      console.warn('[MemoryService] recoverProjectDatasets failed:', e?.message ?? e);
      return [];
    }
  }

  /**
   * Bridge the chat-stream sessionId (text, e.g. "memw-1781314…") to
   * an LTM sessions row (uuid id). Idempotent: find-or-create by
   * chat_session_id (UNIQUE, added in 0016_ltm_sessions_chat_link.sql).
   *
   * Why this exists: memory-integration's recordEpisode writes
   * project_episodes.session_id which is uuid, FK → sessions.id. If we
   * pass the text chat-stream sessionId straight through, the insert
   * fails (silently, since it's wrapped in try/catch) and episodes get
   * dropped. See 2026-06-13 audit.
   *
   * Returns the LTM session UUID for the caller to use as
   * context.memorySessionId. Returns null on any DB error so chat
   * degrades gracefully (no episodes, but chat works).
   */
  async ensureChatLtmSession(
    userId: string,
    chatSessionId: string,
    projectId?: string | null,
  ): Promise<string | null> {
    if (!userId || !chatSessionId) return null;
    try {
      const existing = await db.query.sessions.findFirst({
        where: eq((ltmSchema.sessions as any).chatSessionId, chatSessionId),
      });
      if (existing) return existing.id;
      const [created] = await db.insert(ltmSchema.sessions)
        .values({
          userId,
          projectId: projectId ?? undefined,
          // @ts-ignore — chat_session_id added by migration 0016; drizzle
          // schema in ltm-schema.ts may not declare it yet, but the DB
          // column is real. Falls back gracefully via the returning() id.
          chatSessionId,
        } as any)
        .returning();
      return created?.id ?? null;
    } catch (e: any) {
      console.warn('[MemoryService] ensureChatLtmSession failed:', e?.message ?? e);
      return null;
    }
  }

  /**
   * Idempotently ensure the ltm_users row for this auth user exists.
   * User-scoped memory (preferences, corrections, episodes) needs this
   * row to exist regardless of whether the chat is project-scoped, so
   * it's called on every chat-stream request and from project CRUD
   * endpoints. Safe and cheap (UPSERT with ON CONFLICT DO NOTHING).
   */
  async ensureLtmUser(userId: string, email?: string, name?: string): Promise<void> {
    if (!userId) return;
    try {
      await this.users.ensureLtmUser(userId, email, name);
    } catch (e: any) {
      console.warn('[MemoryService] ensureLtmUser failed:', e?.message ?? e);
    }
  }

  /**
   * Resolve the project this chat should be associated with, OR null
   * if it shouldn't be associated with any project.
   *
   * Policy (docs/20260612_DATASET_STORAGE_AND_SESSION_BOUNDARIES.md):
   * NOT every chat lives in a project. We do NOT auto-create. The
   * client either explicitly sends a projectId or the chat is
   * project-less. Memory-integration's project-scoped paths gate on
   * context.projectId and correctly no-op when null.
   */
  async resolveProjectForChat(clientProjectId?: string | null): Promise<string | null> {
    return clientProjectId || null;
  }

  /**
   * @deprecated Renamed and split.
   * Kept as a thin wrapper for any internal call site we missed —
   * NEVER call from chat-stream. Per policy, chats can have no project.
   */
  async ensureDefaultProject(userId: string, email?: string, name?: string): Promise<string | null> {
    await this.ensureLtmUser(userId, email, name);
    if (!userId) return null;
    try {
      const existing = await this.projects.getUserProjects(userId, 'active');
      return existing.length > 0 ? existing[0].id : null;
    } catch (e: any) {
      console.warn('[MemoryService] ensureDefaultProject (legacy) failed:', e?.message ?? e);
      return null;
    }
  }
}

// Singleton instance
export const memoryService = new MemoryService();
