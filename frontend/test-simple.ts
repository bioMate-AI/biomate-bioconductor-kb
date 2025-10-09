/**
 * Simple test to debug workflow execution
 */

import { mockGalaxyAPI } from './server/mock-galaxy-api';

async function sleep(ms: number) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

async function test() {
  console.log('Starting simple test...\n');

  // Invoke workflow
  const invocation = await mockGalaxyAPI.invokeWorkflow('test_wf', {}, {});
  console.log(`Invoked workflow: ${invocation.id}`);
  console.log(`Initial state: ${invocation.state}`);
  console.log(`Initial steps: ${invocation.steps.length}`);

  // Poll every second for 20 seconds
  for (let i = 0; i < 20; i++) {
    await sleep(1000);

    const current = await mockGalaxyAPI.getInvocation('test_wf', invocation.id);
    console.log(`\n[${i+1}s] State: ${current.state}, Steps: ${current.steps.length}`);

    current.steps.forEach((step, idx) => {
      console.log(`  Step ${idx+1}: ${step.state} ${step.job_id ? `(job: ${step.job_id})` : ''}`);
    });

    // Check if all steps are done
    if (current.steps.length > 0) {
      const allDone = current.steps.every(s => s.state === 'ok' || s.state === 'error');
      if (allDone) {
        console.log('\n✓ All steps completed!');
        break;
      }
    }
  }
}

test().catch(console.error);
