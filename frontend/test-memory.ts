/**
 * Memory System Test Script
 * Tests all memory repository operations
 */

import 'dotenv/config';
import { db, ltmSchema } from './server/db';
import { memoryService } from './server/memory-repository';
import { eq } from 'drizzle-orm';

async function testMemory() {
  console.log('Testing Memory System...\n');

  const testId = Date.now();

  // Test 1: Create a test user in ltm_users
  console.log('1. Creating test LTM user...');
  try {
    const testEmail = `test-memory-${testId}@biomate.test`;
    const user = await memoryService.users.getOrCreateUser(testEmail, {
      name: 'Test User',
      expertiseLevel: 'intermediate',
      researchDomain: 'genomics',
    });
    console.log('   Created user:', user.id, user.email);

    // Test 2: Create a project
    console.log('\n2. Creating test project...');
    const project = await memoryService.projects.createProject({
      userId: user.id,
      name: 'Test RNA-seq Project',
      description: 'Testing memory system',
      primaryDomain: 'transcriptomics',
      organisms: ['human', 'mouse'],
      dataModalities: ['RNA-seq'],
    });
    console.log('   Created project:', project.id, project.name);

    // Test 3: Create a session
    console.log('\n3. Creating session...');
    const session = await memoryService.sessions.createSession({
      userId: user.id,
      projectId: project.id,
    });
    console.log('   Created session:', session.id);

    // Test 4: Record an episode
    console.log('\n4. Recording episode...');
    const episode = await memoryService.episodes.recordEpisode({
      projectId: project.id,
      sessionId: session.id,
      userQuery: 'Help me analyze RNA-seq data',
      assistantResponse: 'I can help you with that. What organism is your data from?',
      userIntent: 'workflow_generation',
      toolsUsed: [{ tool_id: 'fastqc', parameters: {}, output_summary: 'QC check' }],
    });
    console.log('   Recorded episode:', episode.id);

    // Test 5: Update episode outcome
    console.log('\n5. Updating episode outcome...');
    const updatedEpisode = await memoryService.episodes.updateEpisodeOutcome(episode.id, {
      success: true,
      whatWorked: ['FastQC ran successfully'],
      lessonsLearned: ['Use FastQC before alignment'],
    });
    console.log('   Updated episode outcome:', updatedEpisode.outcomeSuccess);

    // Test 6: Record preference
    console.log('\n6. Recording user preference...');
    const pref = await memoryService.users.recordPreference({
      userId: user.id,
      preferenceType: 'tool_selection',
      preferenceKey: 'qc_tool',
      preferenceValue: { tool_id: 'fastqc', tool_name: 'FastQC' },
      learnedFrom: 'repeated_usage',
    });
    console.log('   Recorded preference:', pref.preferenceKey);

    // Test 7: Load user context
    console.log('\n7. Loading user context...');
    const userContext = await memoryService.users.loadUserContext(user.id);
    console.log('   User stats:', userContext.stats);
    console.log('   Preferences count:', userContext.preferences.length);

    // Test 8: Load project context
    console.log('\n8. Loading project context...');
    const projectContext = await memoryService.projects.loadProjectContext(project.id);
    console.log('   Project:', projectContext.project?.name);
    console.log('   Episodes count:', projectContext.recentEpisodes.length);

    // Test 9: Add project knowledge
    console.log('\n9. Adding project knowledge...');
    const knowledge = await memoryService.projects.addProjectKnowledge({
      projectId: project.id,
      knowledgeType: 'experimental_design',
      title: 'Sample Groups',
      content: 'Control vs Treatment, 3 replicates each',
      source: 'user_provided',
    });
    console.log('   Added knowledge:', knowledge.title);

    // Test 10: Create a procedure
    console.log('\n10. Creating procedure...');
    const procedure = await memoryService.procedures.createProcedure({
      projectId: project.id,
      name: 'RNA-seq QC Pipeline',
      triggerPattern: 'quality control RNA-seq',
      description: 'Run quality control on RNA-seq data',
      steps: [
        { order: 1, action: 'Run FastQC', tool_id: 'fastqc' },
        { order: 2, action: 'Run MultiQC', tool_id: 'multiqc' },
      ],
    });
    console.log('   Created procedure:', procedure.name);

    // Test 11: Find matching procedures
    console.log('\n11. Finding matching procedures...');
    const matchingProcedures = await memoryService.procedures.findMatchingProcedures(
      project.id,
      'I need to run quality control on my RNA-seq data'
    );
    console.log('   Found procedures:', matchingProcedures.length);

    // Test 12: Get similar episodes
    console.log('\n12. Getting similar episodes...');
    const similarEpisodes = await memoryService.episodes.getSimilarEpisodes(project.id, {
      intent: 'RNA-seq',
      limit: 5,
    });
    console.log('   Found similar episodes:', similarEpisodes.length);

    // Test 13: End session with summary
    console.log('\n13. Ending session with summary...');
    const endedSession = await memoryService.sessions.endSession(
      session.id,
      'Discussed RNA-seq analysis workflow and ran quality control',
      [{ decision: 'Use FastQC for initial QC', reason: 'Standard practice' }]
    );
    console.log('   Session ended, duration:', endedSession.durationSeconds, 'seconds');

    console.log('\n✓ All 13 tests passed!\n');

    // Cleanup: Delete test data
    console.log('Cleaning up test data...');
    await db.delete(ltmSchema.projectProcedures).where(eq(ltmSchema.projectProcedures.projectId, project.id));
    await db.delete(ltmSchema.projectKnowledge).where(eq(ltmSchema.projectKnowledge.projectId, project.id));
    await db.delete(ltmSchema.projectEpisodes).where(eq(ltmSchema.projectEpisodes.projectId, project.id));
    await db.delete(ltmSchema.userPreferences).where(eq(ltmSchema.userPreferences.userId, user.id));
    await db.delete(ltmSchema.sessions).where(eq(ltmSchema.sessions.id, session.id));
    await db.delete(ltmSchema.projects).where(eq(ltmSchema.projects.id, project.id));
    await db.delete(ltmSchema.ltmUsers).where(eq(ltmSchema.ltmUsers.id, user.id));
    console.log('   Cleanup complete.');

  } catch (error) {
    console.error('Test failed:', error);
    process.exit(1);
  }

  process.exit(0);
}

testMemory();
