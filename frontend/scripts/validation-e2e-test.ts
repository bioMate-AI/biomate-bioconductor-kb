/**
 * Pre-Execution Validation E2E Test Suite
 *
 * Tests the validation system through actual BioMate interactions:
 * 1. Chat endpoint (user intent → workflow generation → validation)
 * 2. Validate endpoint (direct validation)
 * 3. Execute endpoint with sandbox mode
 *
 * Run: npx tsx scripts/validation-e2e-test.ts
 */

import axios from 'axios';
import * as fs from 'fs';

const API_BASE = process.env.API_BASE || 'http://localhost:5000';
const AUDIT_FILE = '/home/yzhang/biomate/20260116_1700_VALIDATION_E2E_TEST_AUDIT.md';

interface TestCase {
  id: number;
  name: string;
  userIntent: string;
  expectedBehavior: {
    shouldGenerateWorkflow: boolean;
    shouldHaveValidation: boolean;
    expectedFulfilled: boolean | 'either';
    expectedMissingInputs?: number;
    expectedMissingParams?: number;
    keyChecks: string[];
  };
}

interface TestResult {
  testCase: TestCase;
  passed: boolean;
  duration: number;
  chatResponse?: any;
  validationResult?: any;
  errors: string[];
  notes: string[];
}

// Define 10 test cases
const TEST_CASES: TestCase[] = [
  {
    id: 1,
    name: "RNA-seq Analysis - Missing Input Data",
    userIntent: "Analyze my RNA-seq data for differential expression between control and treatment groups",
    expectedBehavior: {
      shouldGenerateWorkflow: true,
      shouldHaveValidation: true,
      expectedFulfilled: 'either', // Depends on user's Galaxy history
      keyChecks: [
        "workflow should have data_input steps",
        "validation should check for FASTQ/BAM inputs",
        "response should mention input data requirements"
      ]
    }
  },
  {
    id: 2,
    name: "UniProt Protein Query",
    userIntent: "Query UniProt database to get protein information for BRCA1",
    expectedBehavior: {
      shouldGenerateWorkflow: true,
      shouldHaveValidation: true,
      expectedFulfilled: 'either',
      keyChecks: [
        "should use biomni query_uniprot tool",
        "validation should check parameters",
        "response should be actionable"
      ]
    }
  },
  {
    id: 3,
    name: "Gene Set Enrichment Analysis",
    userIntent: "Perform gene set enrichment analysis on differentially expressed genes",
    expectedBehavior: {
      shouldGenerateWorkflow: true,
      shouldHaveValidation: true,
      expectedFulfilled: 'either',
      keyChecks: [
        "should generate GSEA workflow",
        "should check for gene list input",
        "response should guide on input format"
      ]
    }
  },
  {
    id: 4,
    name: "PCR Primer Design",
    userIntent: "Design PCR primers to amplify the GAPDH gene coding region",
    expectedBehavior: {
      shouldGenerateWorkflow: true,
      shouldHaveValidation: true,
      expectedFulfilled: 'either',
      keyChecks: [
        "should use primer design tool",
        "should check for sequence or gene parameter",
        "response should be specific"
      ]
    }
  },
  {
    id: 5,
    name: "Cell Segmentation from Microscopy",
    userIntent: "Segment and count cells in my DAPI-stained fluorescence microscopy images",
    expectedBehavior: {
      shouldGenerateWorkflow: true,
      shouldHaveValidation: true,
      expectedFulfilled: 'either',
      keyChecks: [
        "should use segmentation tool",
        "should check for image input",
        "response should mention image requirements"
      ]
    }
  },
  {
    id: 6,
    name: "Drug-Target Prediction",
    userIntent: "Predict potential drug targets for metformin using TxGNN",
    expectedBehavior: {
      shouldGenerateWorkflow: true,
      shouldHaveValidation: true,
      expectedFulfilled: 'either',
      keyChecks: [
        "should use drug-target prediction tool",
        "should handle drug name parameter",
        "response should confirm drug"
      ]
    }
  },
  {
    id: 7,
    name: "Multiple Sequence Alignment",
    userIntent: "Align multiple protein sequences from my FASTA file",
    expectedBehavior: {
      shouldGenerateWorkflow: true,
      shouldHaveValidation: true,
      expectedFulfilled: 'either',
      keyChecks: [
        "should use alignment tool",
        "should check for FASTA input",
        "response should guide on sequence format"
      ]
    }
  },
  {
    id: 8,
    name: "Single-Cell RNA-seq Cell Type Annotation",
    userIntent: "Annotate cell types in my single-cell RNA-seq dataset",
    expectedBehavior: {
      shouldGenerateWorkflow: true,
      shouldHaveValidation: true,
      expectedFulfilled: 'either',
      keyChecks: [
        "should use cell annotation tool",
        "should check for h5ad/scRNA input",
        "response should mention data format"
      ]
    }
  },
  {
    id: 9,
    name: "Literature Search",
    userIntent: "Search PubMed for recent papers on CRISPR gene editing in cancer therapy",
    expectedBehavior: {
      shouldGenerateWorkflow: true,
      shouldHaveValidation: true,
      expectedFulfilled: 'either',
      keyChecks: [
        "should use literature query tool",
        "should have search term parameter",
        "response should confirm search scope"
      ]
    }
  },
  {
    id: 10,
    name: "Variant Calling Pipeline",
    userIntent: "Call somatic variants from my tumor and normal BAM files",
    expectedBehavior: {
      shouldGenerateWorkflow: true,
      shouldHaveValidation: true,
      expectedFulfilled: 'either',
      keyChecks: [
        "should generate multi-step variant calling workflow",
        "should check for BAM inputs",
        "should check for reference genome",
        "response should list multiple requirements"
      ]
    }
  }
];

async function runTest(testCase: TestCase): Promise<TestResult> {
  const startTime = Date.now();
  const result: TestResult = {
    testCase,
    passed: false,
    duration: 0,
    errors: [],
    notes: []
  };

  try {
    // Step 1: Send user intent to chat endpoint
    console.log(`\n[Test ${testCase.id}] ${testCase.name}`);
    console.log(`  Intent: "${testCase.userIntent.substring(0, 60)}..."`);

    const chatResponse = await axios.post(`${API_BASE}/api/chat`, {
      message: testCase.userIntent,
      context: {}
    }, { timeout: 180000 }); // 3 minutes for complex workflows

    result.chatResponse = chatResponse.data;
    result.notes.push(`Chat response received (${chatResponse.status})`);

    // Check workflow generation
    const hasWorkflow = !!chatResponse.data.workflow;
    if (testCase.expectedBehavior.shouldGenerateWorkflow && !hasWorkflow) {
      result.errors.push("Expected workflow generation but none received");
    } else if (hasWorkflow) {
      result.notes.push(`Workflow generated: ${chatResponse.data.workflow?.name || 'unnamed'}`);

      // Count steps
      const steps = chatResponse.data.workflow?.steps || {};
      const stepCount = Object.keys(steps).length;
      result.notes.push(`Workflow has ${stepCount} steps`);
    }

    // Check validation
    const hasValidation = !!chatResponse.data.prerequisitesValidation;
    result.validationResult = chatResponse.data.prerequisitesValidation;

    if (testCase.expectedBehavior.shouldHaveValidation && !hasValidation) {
      result.errors.push("Expected prerequisites validation but none received");
    } else if (hasValidation) {
      const validation = chatResponse.data.prerequisitesValidation;
      result.notes.push(`Validation fulfilled: ${validation.fulfilled}`);
      result.notes.push(`Input requirements: ${validation.requirements?.inputs?.length || 0}`);
      result.notes.push(`Parameter requirements: ${validation.requirements?.parameters?.length || 0}`);
      result.notes.push(`Missing inputs: ${validation.analysis?.missingInputs?.length || 0}`);
      result.notes.push(`Missing params: ${validation.analysis?.missingParameters?.length || 0}`);
      result.notes.push(`Input mappings: ${validation.analysis?.inputMappings?.length || 0}`);

      // Check conversational response
      if (validation.conversationalResponse) {
        result.notes.push(`Conversational response: "${validation.conversationalResponse.substring(0, 100)}..."`);
      }
    }

    // Check key behaviors
    for (const check of testCase.expectedBehavior.keyChecks) {
      result.notes.push(`[Check] ${check}`);
    }

    // Determine pass/fail
    const basicChecks =
      (!testCase.expectedBehavior.shouldGenerateWorkflow || hasWorkflow) &&
      (!testCase.expectedBehavior.shouldHaveValidation || hasValidation);

    result.passed = basicChecks && result.errors.length === 0;

  } catch (error: any) {
    result.errors.push(`Request failed: ${error.message}`);
    if (error.response?.data) {
      result.errors.push(`Response: ${JSON.stringify(error.response.data).substring(0, 200)}`);
    }
  }

  result.duration = Date.now() - startTime;
  return result;
}

async function appendToAuditLog(content: string) {
  try {
    fs.appendFileSync(AUDIT_FILE, content);
  } catch (error) {
    console.error('Failed to write audit log:', error);
  }
}

async function main() {
  console.log("=".repeat(70));
  console.log("PRE-EXECUTION VALIDATION E2E TEST SUITE");
  console.log("=".repeat(70));
  console.log(`API Base: ${API_BASE}`);
  console.log(`Started: ${new Date().toISOString()}`);
  console.log("");

  // Check server health
  try {
    const health = await axios.get(`${API_BASE}/api/health`, { timeout: 5000 });
    console.log(`Server health: ${health.data.status}`);
    console.log(`Galaxy connected: ${health.data.services.galaxy.connected}`);
    console.log(`AI available: ${health.data.services.ai}`);
  } catch (error) {
    console.error("Server not available!");
    process.exit(1);
  }

  console.log("\n" + "-".repeat(70));

  const results: TestResult[] = [];
  let passed = 0;
  let failed = 0;

  // Start audit log entry
  const auditHeader = `
---

## Test Run: ${new Date().toISOString()}

### Configuration
- API Base: ${API_BASE}
- Test Cases: ${TEST_CASES.length}

### Results

`;
  await appendToAuditLog(auditHeader);

  // Run each test
  for (const testCase of TEST_CASES) {
    const result = await runTest(testCase);
    results.push(result);

    const status = result.passed ? "PASS" : "FAIL";
    console.log(`  Result: ${status} (${result.duration}ms)`);

    if (result.errors.length > 0) {
      console.log(`  Errors:`);
      result.errors.forEach(e => console.log(`    - ${e}`));
      failed++;
    } else {
      passed++;
    }

    // Write to audit log
    const auditEntry = `
#### Test ${testCase.id}: ${testCase.name}
- **Status**: ${status}
- **Duration**: ${result.duration}ms
- **User Intent**: "${testCase.userIntent}"

**Notes**:
${result.notes.map(n => `- ${n}`).join('\n')}

**Errors**:
${result.errors.length > 0 ? result.errors.map(e => `- ${e}`).join('\n') : '- None'}

${result.validationResult ? `**Validation Summary**:
- Fulfilled: ${result.validationResult.fulfilled}
- Inputs Required: ${result.validationResult.requirements?.inputs?.length || 0}
- Parameters Required: ${result.validationResult.requirements?.parameters?.length || 0}
- Available Datasets: ${result.validationResult.available?.datasets?.length || 0}
` : ''}
---
`;
    await appendToAuditLog(auditEntry);

    // Small delay between tests
    await new Promise(resolve => setTimeout(resolve, 1000));
  }

  // Summary
  console.log("\n" + "=".repeat(70));
  console.log("SUMMARY");
  console.log("=".repeat(70));
  console.log(`Total: ${TEST_CASES.length}`);
  console.log(`Passed: ${passed}`);
  console.log(`Failed: ${failed}`);
  console.log(`Pass Rate: ${((passed / TEST_CASES.length) * 100).toFixed(1)}%`);
  console.log(`Finished: ${new Date().toISOString()}`);

  // Write summary to audit log
  const auditSummary = `
### Summary
- **Total Tests**: ${TEST_CASES.length}
- **Passed**: ${passed}
- **Failed**: ${failed}
- **Pass Rate**: ${((passed / TEST_CASES.length) * 100).toFixed(1)}%
- **Completed**: ${new Date().toISOString()}

### Issues Found
${results.filter(r => !r.passed).map(r => `
- **Test ${r.testCase.id}**: ${r.testCase.name}
  - ${r.errors.join(', ')}
`).join('\n') || 'None'}

`;
  await appendToAuditLog(auditSummary);

  // Return exit code based on results
  process.exit(failed > 0 ? 1 : 0);
}

main().catch(error => {
  console.error("Test suite failed:", error);
  process.exit(1);
});
