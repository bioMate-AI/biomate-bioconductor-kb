/**
 * Simple test for chat endpoint
 */

async function testChatEndpoint() {
  console.log('\n=== Testing Chat Endpoint ===\n');

  const testCases = [
    {
      name: 'Basic RNA-seq query',
      message: 'I need help with RNA-seq analysis',
    },
    {
      name: 'Tool recommendation query',
      message: 'I want to perform quality control on my sequencing data',
    },
    {
      name: 'Workflow generation query',
      message: 'Create an RNA-seq analysis workflow for me',
    },
  ];

  for (const testCase of testCases) {
    console.log(`\n📝 Test: ${testCase.name}`);
    console.log(`   Message: "${testCase.message}"`);

    try {
      const response = await fetch('http://localhost:3000/api/chat', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          message: testCase.message,
          context: 'bioinformatics_workflow',
        }),
      });

      if (!response.ok) {
        console.log(`   ✗ HTTP ${response.status}: ${response.statusText}`);
        continue;
      }

      const data = await response.json();

      console.log(`   ✓ Response received`);
      console.log(`   Response length: ${data.response?.length || 0} chars`);
      console.log(`   Suggestions: ${data.suggestions?.length || 0}`);

      if (data.metadata) {
        console.log(`   Metadata:`);
        console.log(`     - Tool recommendations: ${data.metadata.recommendedTools?.length || 0}`);
        console.log(`     - Dataset recommendations: ${data.metadata.recommendedDatasets?.length || 0}`);
        console.log(`     - Workflow suggestion: ${data.metadata.workflowSuggestion ? 'Yes' : 'No'}`);

        if (data.metadata.recommendedTools && data.metadata.recommendedTools.length > 0) {
          console.log(`   Top 3 tools:`);
          data.metadata.recommendedTools.slice(0, 3).forEach((tool, i) => {
            console.log(`     ${i + 1}. ${tool.tool.name} (${Math.round(tool.relevanceScore * 100)}%)`);
          });
        }

        if (data.metadata.workflowSuggestion) {
          console.log(`   Workflow suggestion:`);
          console.log(`     Should generate: ${data.metadata.workflowSuggestion.shouldGenerate}`);
          console.log(`     Confidence: ${Math.round(data.metadata.workflowSuggestion.confidence * 100)}%`);
        }
      }

      if (data.workflow) {
        console.log(`   ✓ Workflow generated`);
        console.log(`     Success: ${data.workflow.success}`);
        console.log(`     Has .ga format: ${!!data.workflow.workflow_ga}`);
      }

      console.log(`   Preview: "${data.response?.substring(0, 100)}..."`);

    } catch (error) {
      console.log(`   ✗ Error: ${error.message}`);
    }
  }

  console.log('\n=== Test Complete ===\n');
}

testChatEndpoint()
  .then(() => process.exit(0))
  .catch(err => {
    console.error('Test failed:', err);
    process.exit(1);
  });
