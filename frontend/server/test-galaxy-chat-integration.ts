/**
 * End-to-End Test: Galaxy Chat Integration
 *
 * Tests the complete flow:
 * 1. User sends chat message
 * 2. Galaxy Assistant processes message
 * 3. Tool recommendations generated
 * 4. Dataset recommendations generated
 * 5. Workflow generated (if applicable)
 * 6. Response returned with all metadata
 */

import { GalaxyAssistant } from './galaxy-assistant';
import { GalaxyAPIProxy } from './galaxy-api-proxy';

// Test configuration
const TEST_OPENAI_KEY = process.env.OPENAI_API_KEY || '';
const GALAXY_API_URL = process.env.GALAXY_API_URL || 'http://localhost:8000';

interface TestResult {
  testName: string;
  passed: boolean;
  message: string;
  details?: any;
  duration: number;
}

class GalaxyChatIntegrationTest {
  private galaxyAssistant: GalaxyAssistant;
  private results: TestResult[] = [];

  constructor() {
    const galaxyAPIProxy = new GalaxyAPIProxy({
      baseURL: GALAXY_API_URL,
      timeout: 30000,
    });

    this.galaxyAssistant = new GalaxyAssistant({
      openaiApiKey: TEST_OPENAI_KEY,
      galaxyAPIProxy,
    });
  }

  /**
   * Run all tests
   */
  async runAllTests() {
    console.log('\n=== Galaxy Chat Integration Tests ===\n');

    await this.testBasicChatResponse();
    await this.testToolRecommendations();
    await this.testDatasetRecommendations();
    await this.testWorkflowGeneration();
    await this.testCompleteFlow();

    this.printSummary();
  }

  /**
   * Test 1: Basic chat response
   */
  async testBasicChatResponse() {
    const startTime = Date.now();
    const testName = 'Basic Chat Response';

    try {
      console.log(`\n📝 Test: ${testName}`);
      console.log('   Sending message: "Hello, I need help with RNA-seq analysis"');

      const response = await this.galaxyAssistant.processMessage(
        'Hello, I need help with RNA-seq analysis',
        { conversationHistory: [] }
      );

      const passed = !!(
        response.message &&
        response.message.length > 0 &&
        response.suggestions &&
        response.suggestions.length > 0
      );

      const duration = Date.now() - startTime;

      this.results.push({
        testName,
        passed,
        message: passed
          ? `✓ Response received with ${response.message.length} chars and ${response.suggestions.length} suggestions`
          : '✗ Invalid response format',
        details: {
          responseLength: response.message.length,
          suggestionsCount: response.suggestions.length,
          hasMetadata: !!response.metadata,
        },
        duration,
      });

      console.log(this.results[this.results.length - 1].message);
      console.log(`   Response preview: "${response.message.substring(0, 100)}..."`);
      console.log(`   Duration: ${duration}ms`);

    } catch (error: any) {
      const duration = Date.now() - startTime;
      this.results.push({
        testName,
        passed: false,
        message: `✗ Error: ${error.message}`,
        duration,
      });
      console.log(this.results[this.results.length - 1].message);
    }
  }

  /**
   * Test 2: Tool recommendations
   */
  async testToolRecommendations() {
    const startTime = Date.now();
    const testName = 'Tool Recommendations';

    try {
      console.log(`\n🔧 Test: ${testName}`);
      console.log('   Sending message: "I want to perform quality control on my sequencing data"');

      const response = await this.galaxyAssistant.processMessage(
        'I want to perform quality control on my sequencing data',
        { conversationHistory: [] }
      );

      const hasToolRecommendations = response.recommendedTools && response.recommendedTools.length > 0;
      const passed = hasToolRecommendations;

      const duration = Date.now() - startTime;

      this.results.push({
        testName,
        passed,
        message: passed
          ? `✓ Received ${response.recommendedTools.length} tool recommendations`
          : '✗ No tool recommendations received',
        details: {
          toolCount: response.recommendedTools?.length || 0,
          tools: response.recommendedTools?.map(t => ({
            name: t.tool.name,
            relevanceScore: t.relevanceScore,
            category: t.tool.category,
          })),
        },
        duration,
      });

      console.log(this.results[this.results.length - 1].message);

      if (hasToolRecommendations) {
        console.log('   Top 3 tools:');
        response.recommendedTools.slice(0, 3).forEach((tool, i) => {
          console.log(`     ${i + 1}. ${tool.tool.name} (${Math.round(tool.relevanceScore * 100)}% match)`);
          console.log(`        Reasoning: ${tool.reasoning.substring(0, 80)}...`);
        });
      }
      console.log(`   Duration: ${duration}ms`);

    } catch (error: any) {
      const duration = Date.now() - startTime;
      this.results.push({
        testName,
        passed: false,
        message: `✗ Error: ${error.message}`,
        duration,
      });
      console.log(this.results[this.results.length - 1].message);
    }
  }

  /**
   * Test 3: Dataset recommendations
   */
  async testDatasetRecommendations() {
    const startTime = Date.now();
    const testName = 'Dataset Recommendations';

    try {
      console.log(`\n💾 Test: ${testName}`);
      console.log('   Sending message: "I need reference genome data for human"');

      const response = await this.galaxyAssistant.processMessage(
        'I need reference genome data for human',
        { conversationHistory: [] }
      );

      const hasDatasetRecommendations = response.recommendedDatasets && response.recommendedDatasets.length > 0;
      const passed = hasDatasetRecommendations;

      const duration = Date.now() - startTime;

      this.results.push({
        testName,
        passed,
        message: passed
          ? `✓ Received ${response.recommendedDatasets.length} dataset recommendations`
          : '✗ No dataset recommendations received',
        details: {
          datasetCount: response.recommendedDatasets?.length || 0,
          datasets: response.recommendedDatasets?.map(d => ({
            name: d.dataset.name,
            relevanceScore: d.relevanceScore,
            type: d.dataset.type,
          })),
        },
        duration,
      });

      console.log(this.results[this.results.length - 1].message);

      if (hasDatasetRecommendations) {
        console.log('   Top 3 datasets:');
        response.recommendedDatasets.slice(0, 3).forEach((dataset, i) => {
          console.log(`     ${i + 1}. ${dataset.dataset.name} (${Math.round(dataset.relevanceScore * 100)}% match)`);
          console.log(`        Type: ${dataset.dataset.type}`);
        });
      }
      console.log(`   Duration: ${duration}ms`);

    } catch (error: any) {
      const duration = Date.now() - startTime;
      this.results.push({
        testName,
        passed: false,
        message: `✗ Error: ${error.message}`,
        duration,
      });
      console.log(this.results[this.results.length - 1].message);
    }
  }

  /**
   * Test 4: Workflow generation
   */
  async testWorkflowGeneration() {
    const startTime = Date.now();
    const testName = 'Workflow Generation';

    try {
      console.log(`\n⚙️  Test: ${testName}`);
      console.log('   Sending message: "Create an RNA-seq analysis workflow for me"');

      const response = await this.galaxyAssistant.processMessage(
        'Create an RNA-seq analysis workflow for me',
        { conversationHistory: [] }
      );

      const hasWorkflowSuggestion = response.workflowSuggestion && response.workflowSuggestion.shouldGenerate;
      const hasGeneratedWorkflow = !!response.generatedWorkflow;
      const passed = hasWorkflowSuggestion;

      const duration = Date.now() - startTime;

      this.results.push({
        testName,
        passed,
        message: passed
          ? `✓ Workflow ${hasGeneratedWorkflow ? 'generated' : 'suggested'} with confidence ${Math.round((response.workflowSuggestion?.confidence || 0) * 100)}%`
          : '✗ No workflow suggestion',
        details: {
          shouldGenerate: response.workflowSuggestion?.shouldGenerate,
          confidence: response.workflowSuggestion?.confidence,
          hasWorkflow: hasGeneratedWorkflow,
          workflowIntent: response.workflowSuggestion?.userIntent,
        },
        duration,
      });

      console.log(this.results[this.results.length - 1].message);

      if (response.workflowSuggestion) {
        console.log(`   Workflow suggestion:`);
        console.log(`     Should generate: ${response.workflowSuggestion.shouldGenerate}`);
        console.log(`     Confidence: ${Math.round(response.workflowSuggestion.confidence * 100)}%`);
        console.log(`     User intent: ${response.workflowSuggestion.userIntent}`);
      }

      if (hasGeneratedWorkflow) {
        console.log(`   Generated workflow:`);
        console.log(`     Success: ${response.generatedWorkflow.success}`);
        console.log(`     Has .ga format: ${!!response.generatedWorkflow.workflow_ga}`);
      }

      console.log(`   Duration: ${duration}ms`);

    } catch (error: any) {
      const duration = Date.now() - startTime;
      this.results.push({
        testName,
        passed: false,
        message: `✗ Error: ${error.message}`,
        duration,
      });
      console.log(this.results[this.results.length - 1].message);
    }
  }

  /**
   * Test 5: Complete end-to-end flow
   */
  async testCompleteFlow() {
    const startTime = Date.now();
    const testName = 'Complete End-to-End Flow';

    try {
      console.log(`\n🔄 Test: ${testName}`);
      console.log('   Simulating complete user interaction...');

      const message = 'I have RNA-seq data from human samples and want to identify differentially expressed genes';
      const response = await this.galaxyAssistant.processMessage(message, {
        conversationHistory: [],
      });

      const hasResponse = !!response.message;
      const hasTools = response.recommendedTools && response.recommendedTools.length > 0;
      const hasDatasets = response.recommendedDatasets && response.recommendedDatasets.length > 0;
      const hasSuggestions = response.suggestions && response.suggestions.length > 0;
      const hasSources = !!response.sources;

      const passed = hasResponse && hasTools && hasSuggestions;

      const duration = Date.now() - startTime;

      this.results.push({
        testName,
        passed,
        message: passed
          ? `✓ Complete flow successful with all components`
          : '✗ Missing required components',
        details: {
          hasResponse,
          hasTools,
          hasDatasets,
          hasSuggestions,
          hasSources,
          toolCount: response.recommendedTools?.length || 0,
          datasetCount: response.recommendedDatasets?.length || 0,
          suggestionCount: response.suggestions?.length || 0,
          sources: response.sources,
        },
        duration,
      });

      console.log(this.results[this.results.length - 1].message);
      console.log(`   Components:`);
      console.log(`     ✓ Natural language response: ${hasResponse ? 'Yes' : 'No'}`);
      console.log(`     ✓ Tool recommendations: ${hasTools ? `${response.recommendedTools.length} tools` : 'No'}`);
      console.log(`     ✓ Dataset recommendations: ${hasDatasets ? `${response.recommendedDatasets.length} datasets` : 'No'}`);
      console.log(`     ✓ Follow-up suggestions: ${hasSuggestions ? `${response.suggestions.length} suggestions` : 'No'}`);
      console.log(`     ✓ Source attribution: ${hasSources ? 'Yes' : 'No'}`);

      if (response.sources) {
        console.log(`   Sources used:`);
        console.log(`     - Tool Search: ${response.sources.toolSearchUsed ? 'Yes' : 'No'}`);
        console.log(`     - Dataset RAG: ${response.sources.datasetRAGUsed ? 'Yes' : 'No'}`);
        console.log(`     - Workflow Generated: ${response.sources.workflowGenerated ? 'Yes' : 'No'}`);
      }

      console.log(`   Duration: ${duration}ms`);

    } catch (error: any) {
      const duration = Date.now() - startTime;
      this.results.push({
        testName,
        passed: false,
        message: `✗ Error: ${error.message}`,
        duration,
      });
      console.log(this.results[this.results.length - 1].message);
    }
  }

  /**
   * Print test summary
   */
  printSummary() {
    console.log('\n' + '='.repeat(60));
    console.log('Test Summary');
    console.log('='.repeat(60));

    const passed = this.results.filter(r => r.passed).length;
    const failed = this.results.filter(r => !r.passed).length;
    const totalDuration = this.results.reduce((sum, r) => sum + r.duration, 0);

    console.log(`\nTotal Tests: ${this.results.length}`);
    console.log(`Passed: ${passed} ✓`);
    console.log(`Failed: ${failed} ✗`);
    console.log(`Success Rate: ${Math.round((passed / this.results.length) * 100)}%`);
    console.log(`Total Duration: ${totalDuration}ms (${(totalDuration / 1000).toFixed(2)}s)`);

    console.log('\nDetailed Results:');
    this.results.forEach((result, i) => {
      const icon = result.passed ? '✓' : '✗';
      console.log(`  ${i + 1}. ${icon} ${result.testName}`);
      console.log(`     ${result.message}`);
      console.log(`     Duration: ${result.duration}ms`);
    });

    console.log('\n' + '='.repeat(60));

    if (failed === 0) {
      console.log('🎉 All tests passed!');
    } else {
      console.log(`⚠️  ${failed} test(s) failed. Check details above.`);
    }
    console.log('='.repeat(60) + '\n');
  }
}

// Run tests if executed directly
if (require.main === module) {
  const tester = new GalaxyChatIntegrationTest();
  tester.runAllTests()
    .then(() => {
      console.log('✓ Test suite completed');
      process.exit(0);
    })
    .catch(error => {
      console.error('✗ Test suite failed:', error);
      process.exit(1);
    });
}

export { GalaxyChatIntegrationTest };
