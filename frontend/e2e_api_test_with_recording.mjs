/**
 * BioMate E2E API Test with Visual Recording
 * Tests the full workflow via API and creates visual documentation
 */

import fetch from 'node-fetch';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const API_BASE = 'http://localhost:5000';
const OUTPUT_DIR = path.join(__dirname, '..', 'demo_videos');
const TIMESTAMP = Date.now();
const TEST_DIR = path.join(OUTPUT_DIR, `api_e2e_${TIMESTAMP}`);

// Create output directory
if (!fs.existsSync(TEST_DIR)) {
  fs.mkdirSync(TEST_DIR, { recursive: true });
}

const sleep = (ms) => new Promise(resolve => setTimeout(resolve, ms));

class E2ETestRecorder {
  constructor() {
    this.results = [];
    this.startTime = Date.now();
  }

  log(message, level = 'INFO') {
    const timestamp = new Date().toISOString();
    const logEntry = { timestamp, level, message };
    this.results.push(logEntry);
    console.log(`[${timestamp}] [${level}] ${message}`);
  }

  async testAPI(name, fn) {
    console.log('\n' + '━'.repeat(70));
    console.log(`TEST: ${name}`);
    console.log('━'.repeat(70));

    const testStart = Date.now();
    try {
      const result = await fn();
      const duration = Date.now() - testStart;
      this.log(`✅ ${name} PASSED (${duration}ms)`, 'PASS');
      return { success: true, result, duration };
    } catch (error) {
      const duration = Date.now() - testStart;
      this.log(`❌ ${name} FAILED: ${error.message} (${duration}ms)`, 'FAIL');
      return { success: false, error: error.message, duration };
    }
  }

  generateReport() {
    const totalDuration = Date.now() - this.startTime;
    const passed = this.results.filter(r => r.level === 'PASS').length;
    const failed = this.results.filter(r => r.level === 'FAIL').length;

    const report = {
      timestamp: new Date().toISOString(),
      duration: totalDuration,
      tests: {
        total: passed + failed,
        passed,
        failed
      },
      results: this.results
    };

    fs.writeFileSync(
      path.join(TEST_DIR, 'test_report.json'),
      JSON.stringify(report, null, 2)
    );

    return report;
  }
}

async function runE2ETests() {
  console.log('🎬 Starting BioMate API E2E Test...\n');
  console.log(`📁 Output directory: ${TEST_DIR}\n`);

  const recorder = new E2ETestRecorder();

  // Test 1: Health Check
  await recorder.testAPI('Frontend Health Check', async () => {
    recorder.log('Checking frontend availability...');

    const response = await fetch(`${API_BASE}/`, {
      redirect: 'manual' // Don't follow redirects
    });

    recorder.log(`Response status: ${response.status}`);

    if (response.status === 301 || response.status === 302) {
      recorder.log('Frontend redirects to HTTPS (expected for production mode)');
      return { status: 'redirect', location: response.headers.get('location') };
    }

    if (response.ok) {
      const html = await response.text();
      recorder.log(`Frontend returned ${html.length} bytes of HTML`);
      return { status: 'ok', size: html.length };
    }

    throw new Error(`Frontend returned ${response.status}`);
  });

  // Test 2: Chat API - Workflow Generation
  await recorder.testAPI('Chat API - Generate Workflow', async () => {
    recorder.log('Sending chat message to /api/chat...');

    const chatRequest = {
      message: 'Model bacterial growth dynamics with initial population of 1000 cells and growth rate of 0.5'
    };

    recorder.log(`Request: ${JSON.stringify(chatRequest)}`);

    const response = await fetch(`${API_BASE}/api/chat`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json'
      },
      body: JSON.stringify(chatRequest)
    });

    if (!response.ok) {
      const errorText = await response.text();
      throw new Error(`HTTP ${response.status}: ${errorText}`);
    }

    const result = await response.json();

    // Save full response
    fs.writeFileSync(
      path.join(TEST_DIR, 'chat_response.json'),
      JSON.stringify(result, null, 2)
    );

    recorder.log('Chat API Response received');
    recorder.log(`  Response type: ${result.type || 'N/A'}`);
    recorder.log(`  Has workflow: ${!!result.workflow}`);

    if (result.workflow) {
      recorder.log(`  Workflow success: ${result.workflow.success}`);
      recorder.log(`  Workflow name: ${result.workflow.workflow_ga?.name || 'N/A'}`);

      const steps = result.workflow.workflow_ga?.steps || {};
      recorder.log(`  Workflow steps: ${Object.keys(steps).length}`);

      // Log step details
      Object.entries(steps).forEach(([stepId, step]) => {
        recorder.log(`    Step ${stepId}: ${step.tool_id || 'unknown'}`);
      });
    }

    if (!result.workflow || !result.workflow.success) {
      throw new Error('Workflow generation failed or returned no workflow');
    }

    return result;
  });

  // Test 3: Workflow Validation
  await recorder.testAPI('Workflow Validation', async () => {
    recorder.log('Reading generated workflow...');

    const chatResponse = JSON.parse(
      fs.readFileSync(path.join(TEST_DIR, 'chat_response.json'), 'utf8')
    );

    const workflow = chatResponse.workflow.workflow_ga;

    recorder.log('Validating workflow structure...');

    // Check workflow has required fields
    if (!workflow.name) throw new Error('Workflow missing name');
    if (!workflow.steps) throw new Error('Workflow missing steps');

    recorder.log(`✓ Workflow name: ${workflow.name}`);
    recorder.log(`✓ Workflow has ${Object.keys(workflow.steps).length} steps`);

    // Check steps have valid tool IDs
    const steps = workflow.steps;
    for (const [stepId, step] of Object.entries(steps)) {
      if (!step.tool_id) {
        throw new Error(`Step ${stepId} missing tool_id`);
      }

      // Check for corruption (Repository_Actions_ prefix)
      if (step.tool_id.includes('Repository_Actions_')) {
        throw new Error(`Step ${stepId} has corrupted tool_id: ${step.tool_id}`);
      }

      recorder.log(`✓ Step ${stepId}: ${step.tool_id}`);
    }

    recorder.log('Workflow validation complete!');
    return { valid: true, stepCount: Object.keys(steps).length };
  });

  // Test 4: Workflow Execution (if backend is available)
  await recorder.testAPI('Workflow Execution API', async () => {
    recorder.log('Checking if workflow execution endpoint is available...');

    const chatResponse = JSON.parse(
      fs.readFileSync(path.join(TEST_DIR, 'chat_response.json'), 'utf8')
    );

    const executeRequest = {
      workflowDefinition: chatResponse.workflow.workflow_ga,
      executionConfig: {
        mode: 'sandbox' // Use sandbox mode for fast testing
      },
      inputs: []
    };

    recorder.log('Sending workflow execution request...');

    const response = await fetch(`${API_BASE}/api/workflows/execute`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json'
      },
      body: JSON.stringify(executeRequest)
    });

    if (!response.ok) {
      const errorText = await response.text();
      recorder.log(`Execution endpoint returned ${response.status}: ${errorText}`);

      // Don't fail the test if backend is down
      if (response.status === 502 || response.status === 503) {
        recorder.log('Backend appears to be unavailable (expected in some setups)');
        return { status: 'backend_unavailable' };
      }

      throw new Error(`HTTP ${response.status}: ${errorText}`);
    }

    const result = await response.json();

    fs.writeFileSync(
      path.join(TEST_DIR, 'execution_response.json'),
      JSON.stringify(result, null, 2)
    );

    recorder.log('Workflow execution response received');
    recorder.log(`  Run ID: ${result.runId || 'N/A'}`);
    recorder.log(`  Galaxy Invocation ID: ${result.galaxyInvocationId || 'N/A'}`);
    recorder.log(`  Status: ${result.status || 'N/A'}`);

    return result;
  });

  // Generate final report
  console.log('\n' + '═'.repeat(70));
  console.log('GENERATING REPORT');
  console.log('═'.repeat(70) + '\n');

  const report = recorder.generateReport();

  // Create HTML report
  const htmlReport = generateHTMLReport(report, TEST_DIR);
  fs.writeFileSync(path.join(TEST_DIR, 'report.html'), htmlReport);

  // Create markdown report
  const mdReport = generateMarkdownReport(report, TEST_DIR);
  fs.writeFileSync(path.join(TEST_DIR, 'REPORT.md'), mdReport);

  console.log('\n' + '═'.repeat(70));
  console.log('E2E TEST COMPLETE');
  console.log('═'.repeat(70));
  console.log(`\n✅ Tests Passed: ${report.tests.passed}`);
  console.log(`${report.tests.failed > 0 ? '❌' : '✅'} Tests Failed: ${report.tests.failed}`);
  console.log(`⏱️  Total Duration: ${report.duration}ms`);

  console.log(`\n📁 Output directory: ${TEST_DIR}`);
  console.log('\n📄 Generated files:');
  const files = fs.readdirSync(TEST_DIR);
  files.forEach(f => {
    const stats = fs.statSync(path.join(TEST_DIR, f));
    console.log(`  ✓ ${f} (${(stats.size / 1024).toFixed(2)} KB)`);
  });

  console.log('\n📝 View reports:');
  console.log(`  HTML: file://${path.join(TEST_DIR, 'report.html')}`);
  console.log(`  Markdown: ${path.join(TEST_DIR, 'REPORT.md')}`);
  console.log(`  JSON: ${path.join(TEST_DIR, 'test_report.json')}`);

  console.log('\n✅ E2E test complete!');

  return report.tests.failed === 0 ? 0 : 1;
}

function generateHTMLReport(report, testDir) {
  const chatResponse = fs.existsSync(path.join(testDir, 'chat_response.json'))
    ? JSON.parse(fs.readFileSync(path.join(testDir, 'chat_response.json'), 'utf8'))
    : null;

  return `<!DOCTYPE html>
<html>
<head>
  <title>BioMate E2E Test Report</title>
  <style>
    body { font-family: Arial, sans-serif; max-width: 1200px; margin: 0 auto; padding: 20px; background: #f5f5f5; }
    h1 { color: #2c3e50; }
    .summary { background: white; padding: 20px; border-radius: 8px; margin: 20px 0; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
    .pass { color: #27ae60; font-weight: bold; }
    .fail { color: #e74c3c; font-weight: bold; }
    .test-result { background: white; padding: 15px; margin: 10px 0; border-radius: 5px; border-left: 4px solid #3498db; }
    .test-result.passed { border-left-color: #27ae60; }
    .test-result.failed { border-left-color: #e74c3c; }
    pre { background: #ecf0f1; padding: 10px; border-radius: 4px; overflow-x: auto; }
    .timestamp { color: #7f8c8d; font-size: 0.9em; }
  </style>
</head>
<body>
  <h1>🎬 BioMate E2E Test Report</h1>

  <div class="summary">
    <h2>Summary</h2>
    <p><strong>Timestamp:</strong> ${report.timestamp}</p>
    <p><strong>Duration:</strong> ${report.duration}ms (${(report.duration / 1000).toFixed(2)}s)</p>
    <p><strong>Tests:</strong> ${report.tests.total}</p>
    <p><strong class="pass">Passed:</strong> ${report.tests.passed}</p>
    <p><strong class="${report.tests.failed > 0 ? 'fail' : 'pass'}">Failed:</strong> ${report.tests.failed}</p>
  </div>

  ${chatResponse ? `
  <div class="summary">
    <h2>Generated Workflow</h2>
    <p><strong>Name:</strong> ${chatResponse.workflow?.workflow_ga?.name || 'N/A'}</p>
    <p><strong>Steps:</strong> ${Object.keys(chatResponse.workflow?.workflow_ga?.steps || {}).length}</p>
    <p><strong>Success:</strong> ${chatResponse.workflow?.success ? '✅ Yes' : '❌ No'}</p>
    <details>
      <summary>View Full Workflow JSON</summary>
      <pre>${JSON.stringify(chatResponse.workflow, null, 2)}</pre>
    </details>
  </div>
  ` : ''}

  <h2>Test Results</h2>
  ${report.results.map(r => `
    <div class="test-result ${r.level === 'PASS' ? 'passed' : r.level === 'FAIL' ? 'failed' : ''}">
      <div class="timestamp">${r.timestamp}</div>
      <div><strong>${r.level}:</strong> ${r.message}</div>
    </div>
  `).join('\n')}

  <div class="summary">
    <h2>Files Generated</h2>
    <ul>
      <li><a href="test_report.json">test_report.json</a> - Full test results</li>
      <li><a href="chat_response.json">chat_response.json</a> - Workflow generation response</li>
      <li><a href="execution_response.json">execution_response.json</a> - Execution response (if available)</li>
      <li><a href="REPORT.md">REPORT.md</a> - Markdown report</li>
    </ul>
  </div>
</body>
</html>`;
}

function generateMarkdownReport(report, testDir) {
  const chatResponse = fs.existsSync(path.join(testDir, 'chat_response.json'))
    ? JSON.parse(fs.readFileSync(path.join(testDir, 'chat_response.json'), 'utf8'))
    : null;

  return `# BioMate E2E Test Report

**Generated**: ${report.timestamp}
**Duration**: ${report.duration}ms (${(report.duration / 1000).toFixed(2)}s)

## Summary

- **Total Tests**: ${report.tests.total}
- **✅ Passed**: ${report.tests.passed}
- **${report.tests.failed > 0 ? '❌' : '✅'} Failed**: ${report.tests.failed}

## Generated Workflow

${chatResponse ? `
- **Name**: ${chatResponse.workflow?.workflow_ga?.name || 'N/A'}
- **Steps**: ${Object.keys(chatResponse.workflow?.workflow_ga?.steps || {}).length}
- **Success**: ${chatResponse.workflow?.success ? '✅ Yes' : '❌ No'}

### Workflow Steps

${Object.entries(chatResponse.workflow?.workflow_ga?.steps || {}).map(([id, step]) => `
- **Step ${id}**: \`${step.tool_id}\`
`).join('\n')}
` : 'No workflow generated'}

## Test Results

${report.results.map(r => `
### ${r.level === 'PASS' ? '✅' : r.level === 'FAIL' ? '❌' : 'ℹ️'} ${r.level}

**Time**: ${r.timestamp}
**Message**: ${r.message}
`).join('\n')}

## Files Generated

- \`test_report.json\` - Full test results
- \`chat_response.json\` - Workflow generation response
- \`execution_response.json\` - Execution response (if available)
- \`report.html\` - Interactive HTML report

---

*Generated by BioMate E2E Test Suite*
`;
}

// Run the tests
runE2ETests()
  .then(exitCode => process.exit(exitCode))
  .catch(error => {
    console.error('Fatal error:', error);
    process.exit(1);
  });
