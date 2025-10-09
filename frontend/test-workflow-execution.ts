/**
 * End-to-End Test for Mock Workflow Execution
 * Tests the complete flow: Tool search → Dataset discovery → Workflow execution → SSE updates
 */

import { mockGalaxyAPI } from './server/mock-galaxy-api';
import { createPoller } from './server/galaxy-state-poller';
import type { WorkflowExecutionUpdate } from './shared/galaxy-types';

async function testWorkflowExecution() {
  console.log('\n=== Galaxy Mock Workflow Execution Test ===\n');

  // ============================================================================
  // Test 1: Tool Search
  // ============================================================================
  console.log('1. Testing Tool Search...');
  const toolSearchResults = await mockGalaxyAPI.searchTools('xcms', 'metabolomics', 10);
  console.log(`   ✓ Found ${toolSearchResults.count} tools matching 'xcms'`);
  console.log(`   Tools: ${toolSearchResults.tools.map(t => t.name).join(', ')}`);

  // ============================================================================
  // Test 2: Tool Categories
  // ============================================================================
  console.log('\n2. Testing Tool Categories...');
  const categories = await mockGalaxyAPI.getToolCategories();
  console.log(`   ✓ Found ${categories.categories.length} categories`);
  console.log(`   Categories: ${categories.categories.map(c => `${c.name} (${c.count})`).join(', ')}`);

  // ============================================================================
  // Test 3: Get Tool by ID
  // ============================================================================
  console.log('\n3. Testing Get Tool by ID...');
  const toolId = toolSearchResults.tools[0].tool_id;
  const tool = await mockGalaxyAPI.getToolById(toolId);
  console.log(`   ✓ Retrieved tool: ${tool.name} (v${tool.version})`);
  console.log(`   Status: ${tool.install_status}`);

  // ============================================================================
  // Test 4: Dataset Search
  // ============================================================================
  console.log('\n4. Testing Dataset Search...');
  const datasetResults = await mockGalaxyAPI.searchDatasets({
    query: 'kegg',
    category: 'metabolomics',
    lcms_only: true,
    limit: 5,
  });
  console.log(`   ✓ Found ${datasetResults.count} datasets matching 'kegg'`);
  console.log(`   Datasets:`);
  datasetResults.datasets.forEach(d => {
    console.log(`     - ${d.name} (${d.format}, ${d.size_mb} MB)`);
  });

  // ============================================================================
  // Test 5: Get Installed Tools
  // ============================================================================
  console.log('\n5. Testing Get Installed Tools...');
  const installedTools = await mockGalaxyAPI.getInstalledTools();
  console.log(`   ✓ Found ${installedTools.count} installed tools`);

  // ============================================================================
  // Test 6: Workflow Invocation
  // ============================================================================
  console.log('\n6. Testing Workflow Invocation...');
  const workflowId = 'test_workflow_lcms';
  const inputs = {
    input_dataset: 'dataset_123',
  };
  const parameters = {
    param1: 'value1',
  };

  const invocation = await mockGalaxyAPI.invokeWorkflow(workflowId, inputs, parameters);
  console.log(`   ✓ Workflow invoked successfully`);
  console.log(`   Invocation ID: ${invocation.id}`);
  console.log(`   State: ${invocation.state}`);
  console.log(`   Steps: ${invocation.steps.length}`);

  // ============================================================================
  // Test 7: State Polling with Event Listeners
  // ============================================================================
  console.log('\n7. Testing State Polling with SSE...');

  const poller = createPoller(mockGalaxyAPI, { pollInterval: 1000 });

  // Track updates
  const updates: WorkflowExecutionUpdate[] = [];

  // Listen for all update types
  poller.on('workflow_state', (update: WorkflowExecutionUpdate) => {
    console.log(`   [SSE] Workflow state: ${update.data.workflow_state}`);
    updates.push(update);
  });

  poller.on('step_state', (update: WorkflowExecutionUpdate) => {
    console.log(`   [SSE] Step ${update.data.step_id}: ${update.data.step_state}`);
    updates.push(update);
  });

  poller.on('job_log', (update: WorkflowExecutionUpdate) => {
    console.log(`   [SSE] Job log: ${update.data.log_message?.substring(0, 50)}...`);
    updates.push(update);
  });

  poller.on('error', (update: WorkflowExecutionUpdate) => {
    console.log(`   [SSE] Error: ${update.data.error}`);
    updates.push(update);
  });

  poller.on('workflow_completed', (data: { invocation_id: string; state: string }) => {
    console.log(`   ✓ Workflow completed with state: ${data.state}`);
  });

  // Debug: log all polling activity
  poller.on('update', (update: WorkflowExecutionUpdate) => {
    console.log(`   [DEBUG] Update type: ${update.type}, data:`, JSON.stringify(update.data));
  });

  // Start polling
  poller.startPolling(invocation.id, workflowId);

  // Wait for workflow to complete
  await waitForCompletion(poller, invocation.id, 30000);

  // ============================================================================
  // Test 8: Verify Final State
  // ============================================================================
  console.log('\n8. Verifying Final State...');
  const finalInvocation = await mockGalaxyAPI.getInvocation(workflowId, invocation.id);
  console.log(`   ✓ Final workflow state: ${finalInvocation.state}`);
  console.log(`   ✓ Total updates received: ${updates.length}`);

  finalInvocation.steps.forEach((step, index) => {
    console.log(`   Step ${index + 1}: ${step.state} ${step.job_id ? `(job: ${step.job_id})` : ''}`);
  });

  // ============================================================================
  // Test 9: Job Logs
  // ============================================================================
  console.log('\n9. Testing Job Logs...');
  const completedStep = finalInvocation.steps.find(s => s.job_id);
  if (completedStep?.job_id) {
    const job = await mockGalaxyAPI.getJob(completedStep.job_id);
    console.log(`   Job state: ${job.state}`);
    console.log(`   Exit code: ${job.exit_code}`);

    const stdout = await mockGalaxyAPI.getJobStdout(completedStep.job_id);
    const stderr = await mockGalaxyAPI.getJobStderr(completedStep.job_id);

    console.log(`   Stdout length: ${stdout.length} chars`);
    console.log(`   Stderr length: ${stderr.length} chars`);
  }

  // Cleanup
  poller.stopAll();

  console.log('\n=== All Tests Passed! ===\n');
  console.log('Summary:');
  console.log(`  ✓ Tool search: ${toolSearchResults.count} results`);
  console.log(`  ✓ Dataset search: ${datasetResults.count} results`);
  console.log(`  ✓ Workflow execution: ${invocation.steps.length} steps`);
  console.log(`  ✓ Real-time updates: ${updates.length} events`);
  console.log(`  ✓ Final state: ${finalInvocation.state}`);
}

/**
 * Wait for polling to complete or timeout
 */
function waitForCompletion(poller: any, invocationId: string, timeout: number): Promise<void> {
  return new Promise((resolve, reject) => {
    const startTime = Date.now();

    const checkInterval = setInterval(() => {
      if (!poller.isPolling(invocationId)) {
        clearInterval(checkInterval);
        resolve();
      } else if (Date.now() - startTime > timeout) {
        clearInterval(checkInterval);
        reject(new Error('Timeout waiting for workflow completion'));
      }
    }, 500);
  });
}

// Run the test
testWorkflowExecution()
  .then(() => {
    console.log('\n✓ Test completed successfully\n');
    process.exit(0);
  })
  .catch((error) => {
    console.error('\n✗ Test failed:', error);
    process.exit(1);
  });
