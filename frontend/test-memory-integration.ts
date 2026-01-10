/**
 * Memory Integration Test Script
 * Tests the memory integration layer with mock assistant
 */

import 'dotenv/config';
import { db, ltmSchema } from './server/db';
import { memoryService } from './server/memory-repository';
import { MemoryIntegration, buildMemoryContextPrompt } from './server/memory-integration';
import { eq } from 'drizzle-orm';

// Mock GalaxyAssistant for testing
const mockAssistant = {
  async processMessage(message: string, context: any) {
    return {
      message: `I understand you want to: ${message}`,
      suggestions: ['Next step 1', 'Next step 2'],
      recommendedTools: [
        { tool: { id: 'fastqc', name: 'FastQC' }, relevanceScore: 0.9, reasoning: 'QC tool' }
      ],
      workflowSuggestion: {
        shouldGenerate: true,
        userIntent: message,
        confidence: 0.8,
        reasoning: 'User wants workflow'
      },
      sources: {
        toolSearchUsed: true,
        datasetRAGUsed: false,
        workflowGenerated: false,
        thinkingUsed: false,
      }
    };
  }
};

async function testMemoryIntegration() {
  console.log('Testing Memory Integration Layer...\n');

  const testId = Date.now();
  const memoryIntegration = new MemoryIntegration(mockAssistant as any);

  try {
    // Step 1: Create test user and project
    console.log('1. Setting up test data...');
    const testEmail = `test-integration-${testId}@biomate.test`;
    const user = await memoryService.users.getOrCreateUser(testEmail, {
      name: 'Integration Test User',
      expertiseLevel: 'expert',
      researchDomain: 'proteomics',
    });
    console.log('   Created user:', user.id);

    const project = await memoryService.projects.createProject({
      userId: user.id,
      name: 'Integration Test Project',
      primaryDomain: 'proteomics',
      organisms: ['human'],
      dataModalities: ['DIA'],
    });
    console.log('   Created project:', project.id);

    // Step 2: Initialize memory session
    console.log('\n2. Initializing memory session...');
    const { session, context } = await memoryIntegration.initializeSession(user.id, project.id);
    console.log('   Session ID:', session.id);
    console.log('   Has user memory:', !!context.userMemory);
    console.log('   Has project memory:', !!context.projectMemory);

    // Step 3: Process message with memory
    console.log('\n3. Processing message with memory...');
    const response = await memoryIntegration.processWithMemory(
      'Analyze my DIA proteomics data',
      context
    );
    console.log('   Response message:', response.message.substring(0, 50) + '...');
    console.log('   Episode ID:', response.episodeId);
    console.log('   Memory session ID:', response.memorySessionId);

    // Step 4: Record outcome
    if (response.episodeId) {
      console.log('\n4. Recording episode outcome...');
      await memoryIntegration.recordOutcome(response.episodeId, {
        success: true,
      });
      console.log('   Outcome recorded successfully');
    }

    // Step 5: Test buildMemoryContextPrompt
    console.log('\n5. Building memory context prompt...');
    const prompt = buildMemoryContextPrompt(context);
    console.log('   Prompt length:', prompt.length, 'chars');
    console.log('   Prompt preview:', prompt.substring(0, 200) + '...');

    // Step 6: Process another message (should have memory hints)
    console.log('\n6. Processing second message with accumulated memory...');
    // Reload context to get the new episode
    const { context: context2 } = await memoryIntegration.initializeSession(user.id, project.id);
    const response2 = await memoryIntegration.processWithMemory(
      'Run quality control',
      context2
    );
    console.log('   Response:', response2.message.substring(0, 50) + '...');
    console.log('   Episode ID:', response2.episodeId);

    // Step 7: End session
    console.log('\n7. Ending session...');
    const endedSession = await memoryIntegration.endSession(
      session.id,
      'Tested DIA proteomics analysis',
      [{ decision: 'Used DIA-NN', reason: 'Best for DIA data' }]
    );
    console.log('   Session ended:', endedSession.id);

    console.log('\n✓ All integration tests passed!\n');

    // Cleanup
    console.log('Cleaning up test data...');
    await db.delete(ltmSchema.projectEpisodes).where(eq(ltmSchema.projectEpisodes.projectId, project.id));
    await db.delete(ltmSchema.userPreferences).where(eq(ltmSchema.userPreferences.userId, user.id));
    await db.delete(ltmSchema.sessions).where(eq(ltmSchema.sessions.projectId, project.id));
    await db.delete(ltmSchema.projects).where(eq(ltmSchema.projects.id, project.id));
    await db.delete(ltmSchema.ltmUsers).where(eq(ltmSchema.ltmUsers.id, user.id));
    console.log('   Cleanup complete.');

  } catch (error) {
    console.error('Integration test failed:', error);
    process.exit(1);
  }

  process.exit(0);
}

testMemoryIntegration();
