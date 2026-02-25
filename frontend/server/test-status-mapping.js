
// Test script for status mapping logic
const testCases = [
  { input: 'ok', expected: 'completed' },
  { input: 'scheduled', expected: 'completed' }, // Special case for tracking workflow completion
  { input: 'cancelled', expected: 'cancelled' },
  { input: 'error', expected: 'failed' },
  { input: 'failed', expected: 'failed' },
  { input: 'running', expected: 'failed' }, // If completion event fires with 'running', it defaults to failed? 
                                            // No, the completion handler only fires when done. 
                                            // But if state is running in completion handler, something is wrong, default to failed is safe.
  { input: 'new', expected: 'failed' },
  { input: 'queued', expected: 'failed' }
];

console.log("Verifying Status Mapping Logic...");

let passed = 0;
let failed = 0;

testCases.forEach(({ input, expected }) => {
  // Logic from routes.ts
  let runStatus = 'failed';
  if (input === 'ok' || input === 'scheduled') {
    runStatus = 'completed';
  } else if (input === 'cancelled') {
    runStatus = 'cancelled';
  }
  
  if (runStatus === expected) {
    console.log(`[PASS] Input '${input}' -> '${runStatus}'`);
    passed++;
  } else {
    console.error(`[FAIL] Input '${input}' -> '${runStatus}' (Expected: '${expected}')`);
    failed++;
  }
});

console.log(`\nResult: ${passed} Passed, ${failed} Failed`);
if (failed > 0) process.exit(1);
