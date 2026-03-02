/**
 * Model Test Harness for Galaxy Assistant
 *
 * Compares output quality between different Claude models:
 * - claude-sonnet-4-5 (better quality, slower)
 * - claude-haiku-4-5 (faster, cheaper)
 *
 * Tests:
 * 1. Intent Classification Quality
 * 2. Tool Ranking Accuracy
 * 3. Response Generation Quality
 * 4. Thinking Mode Impact
 *
 * Run with: npx tsx server/model-test-harness.ts
 */

import Anthropic from '@anthropic-ai/sdk';
import { writeFileSync, mkdirSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';

// Results directory with timestamp
const __dirname = dirname(fileURLToPath(import.meta.url));
const RESULTS_DIR = join(__dirname, '__tests__', 'results');
const TIMESTAMP = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);

// Ensure results directory exists
mkdirSync(RESULTS_DIR, { recursive: true });

// Test configurations
const MODELS = {
  sonnet: 'claude-sonnet-4-5',
  haiku: 'claude-haiku-4-5',
};

interface TestCase {
  id: string;
  category: 'intent' | 'ranking' | 'response' | 'thinking' | 'consistency';
  prompt: string;
  expectedIntent?: string;
  expectedKeywords?: string[];
  description: string;
}

interface TestResult {
  testId: string;
  model: string;
  category: string;
  prompt: string;
  response: string;
  latencyMs: number;
  inputTokens: number;
  outputTokens: number;
  thinkingEnabled: boolean;
  error?: string;
}

// Test cases covering different complexity levels
const TEST_CASES: TestCase[] = [
  // ============================================================
  // INTENT CLASSIFICATION TESTS - Core functionality
  // ============================================================
  {
    id: 'INTENT-001',
    category: 'intent',
    prompt: 'Hello, what can you do?',
    expectedIntent: 'general_question',
    description: 'Simple greeting - should NOT trigger tool search',
  },
  {
    id: 'INTENT-002',
    category: 'intent',
    prompt: 'I want to analyze RNA-seq data from mouse liver samples',
    expectedIntent: 'workflow_generation',
    expectedKeywords: ['rna-seq', 'mouse', 'liver'],
    description: 'Complex bioinformatics request - should trigger workflow',
  },
  {
    id: 'INTENT-003',
    category: 'intent',
    prompt: 'What tools are available for variant calling?',
    expectedIntent: 'tool_inquiry',
    expectedKeywords: ['variant', 'calling'],
    description: 'Tool inquiry - should search tools',
  },
  {
    id: 'INTENT-004',
    category: 'intent',
    prompt: 'Query UniProt for human insulin receptor',
    expectedIntent: 'workflow_generation',
    expectedKeywords: ['uniprot', 'insulin', 'receptor'],
    description: 'Database query - should trigger tool search and workflow',
  },
  {
    id: 'INTENT-005',
    category: 'intent',
    prompt: 'Align my FASTQ files to the human genome and call variants',
    expectedIntent: 'workflow_generation',
    expectedKeywords: ['align', 'fastq', 'genome', 'variants'],
    description: 'Multi-step analysis - should generate workflow',
  },

  // ============================================================
  // INTENT EDGE CASES - Ambiguous and tricky queries
  // ============================================================
  {
    id: 'INTENT-EDGE-001',
    category: 'intent',
    prompt: 'Thanks!',
    expectedIntent: 'general_question',
    description: 'Simple thanks - should NOT trigger anything',
  },
  {
    id: 'INTENT-EDGE-002',
    category: 'intent',
    prompt: 'Can you help me?',
    expectedIntent: 'general_question',
    description: 'Vague request - should ask for clarification',
  },
  {
    id: 'INTENT-EDGE-003',
    category: 'intent',
    prompt: 'BLAST',
    expectedIntent: 'workflow_generation',
    expectedKeywords: ['blast'],
    description: 'Single tool name - should trigger tool search',
  },
  {
    id: 'INTENT-EDGE-004',
    category: 'intent',
    prompt: 'I have some data',
    expectedIntent: 'general_question',
    description: 'Incomplete request - needs clarification',
  },
  {
    id: 'INTENT-EDGE-005',
    category: 'intent',
    prompt: 'Run FastQC on my samples and then trim adapters with Trimmomatic, align with BWA-MEM to hg38, call variants with GATK HaplotypeCaller, and annotate with SnpEff',
    expectedIntent: 'workflow_generation',
    expectedKeywords: ['fastqc', 'trimmomatic', 'bwa', 'gatk', 'snpeff'],
    description: 'Very long multi-tool request - should parse all tools',
  },
  {
    id: 'INTENT-EDGE-006',
    category: 'intent',
    prompt: 'What is CRISPR?',
    expectedIntent: 'general_question',
    description: 'Educational question - no tool needed',
  },
  {
    id: 'INTENT-EDGE-007',
    category: 'intent',
    prompt: 'Compare my treated vs control samples',
    expectedIntent: 'workflow_generation',
    expectedKeywords: ['compare', 'treated', 'control'],
    description: 'Implicit DE analysis request',
  },

  // ============================================================
  // DOMAIN-SPECIFIC INTENT TESTS - Different bioinformatics areas
  // ============================================================
  {
    id: 'INTENT-DOMAIN-001',
    category: 'intent',
    prompt: 'Predict protein structure for my amino acid sequence',
    expectedIntent: 'workflow_generation',
    expectedKeywords: ['protein', 'structure', 'amino acid'],
    description: 'Structural biology request',
  },
  {
    id: 'INTENT-DOMAIN-002',
    category: 'intent',
    prompt: 'Identify peaks in my ChIP-seq data',
    expectedIntent: 'workflow_generation',
    expectedKeywords: ['peaks', 'chip-seq'],
    description: 'Epigenomics request',
  },
  {
    id: 'INTENT-DOMAIN-003',
    category: 'intent',
    prompt: 'Cluster my single-cell RNA-seq data and find marker genes',
    expectedIntent: 'workflow_generation',
    expectedKeywords: ['single-cell', 'cluster', 'marker'],
    description: 'Single-cell analysis request',
  },
  {
    id: 'INTENT-DOMAIN-004',
    category: 'intent',
    prompt: 'Annotate metabolites from my LC-MS data',
    expectedIntent: 'workflow_generation',
    expectedKeywords: ['metabolites', 'lc-ms', 'annotate'],
    description: 'Metabolomics request',
  },
  {
    id: 'INTENT-DOMAIN-005',
    category: 'intent',
    prompt: 'Assemble my bacterial genome from Nanopore reads',
    expectedIntent: 'workflow_generation',
    expectedKeywords: ['assemble', 'bacterial', 'nanopore'],
    description: 'Long-read assembly request',
  },

  // ============================================================
  // TOOL RANKING TESTS - For evaluating ranking quality
  // ============================================================
  {
    id: 'RANK-001',
    category: 'ranking',
    prompt: 'I need to align short reads to a reference genome',
    description: 'Should rank BWA/Bowtie2 highest',
  },
  {
    id: 'RANK-002',
    category: 'ranking',
    prompt: 'Differential expression analysis of RNA-seq',
    description: 'Should rank DESeq2/edgeR/limma highest',
  },
  {
    id: 'RANK-003',
    category: 'ranking',
    prompt: 'Quality control of my sequencing data',
    description: 'Should rank FastQC/MultiQC highest',
  },

  // ============================================================
  // RESPONSE GENERATION TESTS - Quality comparison
  // ============================================================
  {
    id: 'RESP-001',
    category: 'response',
    prompt: 'Explain the difference between BWA and Bowtie2',
    description: 'Technical explanation - quality comparison',
  },
  {
    id: 'RESP-002',
    category: 'response',
    prompt: 'I have 10 GB of paired-end Illumina data. What preprocessing steps should I take?',
    description: 'Complex advice - requires domain knowledge',
  },
  {
    id: 'RESP-003',
    category: 'response',
    prompt: 'How do I interpret a p-value of 0.03 in my differential expression results?',
    description: 'Statistical interpretation - accuracy matters',
  },
  {
    id: 'RESP-004',
    category: 'response',
    prompt: 'What parameters should I use for STAR alignment of human RNA-seq data?',
    description: 'Specific parameter recommendation',
  },
  {
    id: 'RESP-005',
    category: 'response',
    prompt: 'My alignment rate is only 50%. What could be wrong?',
    description: 'Troubleshooting - diagnostic reasoning',
  },

  // ============================================================
  // THINKING MODE TESTS - Complex reasoning tasks
  // ============================================================
  {
    id: 'THINK-001',
    category: 'thinking',
    prompt: 'Design a complete metagenomics pipeline for analyzing gut microbiome samples from 50 patients',
    description: 'Complex planning task - thinking should help',
  },
  {
    id: 'THINK-002',
    category: 'thinking',
    prompt: 'What are the trade-offs between de novo assembly and reference-based assembly for my bacterial genome project?',
    description: 'Comparative analysis - thinking should improve quality',
  },
  {
    id: 'THINK-003',
    category: 'thinking',
    prompt: 'I have RNA-seq data from cancer patients with different treatment responses. How should I design my analysis to identify predictive biomarkers?',
    description: 'Complex experimental design - needs careful reasoning',
  },

  // ============================================================
  // CONSISTENCY TESTS - Same query, check for stable output
  // ============================================================
  {
    id: 'CONSIST-001',
    category: 'consistency',
    prompt: 'What file format does BWA accept as input?',
    description: 'Factual question - should be consistent',
  },
  {
    id: 'CONSIST-002',
    category: 'consistency',
    prompt: 'List the steps for RNA-seq analysis',
    description: 'Standard workflow - should be consistent',
  },
];

// Intent classification system prompt
const INTENT_SYSTEM_PROMPT = `You are a bioinformatics intent analyzer. Analyze user messages and extract:
1. Intent type: workflow_generation, tool_inquiry, dataset_inquiry, general_question, or workflow_modification
2. Keywords for tool/dataset search (e.g., "RNA-seq", "metabolomics", "peak detection")
3. Whether tool search is needed
4. Whether dataset recommendations are needed
5. Confidence score (0-1)

IMPORTANT: The following should ALWAYS be classified as workflow_generation with needsToolSearch=true:
- Database queries: "query UniProt", "search PubMed", "BLAST", "fetch from KEGG", etc.
- Literature searches: "search for papers", "find articles", "PubMed search"
- Any request to run, execute, analyze, or process data
- Any mention of specific tools or databases (PubMed, NCBI, ChEMBL, etc.)

Only use general_question for conversational questions that don't require running any tools.

Respond in JSON format:
{
  "type": "workflow_generation",
  "keywords": ["rna-seq", "differential expression", "alignment"],
  "needsToolSearch": true,
  "needsDatasets": true,
  "confidence": 0.95
}`;

// Response generation system prompt
const RESPONSE_SYSTEM_PROMPT = `You are BioMate, an expert bioinformatics AI assistant powered by Galaxy.

Your capabilities:
- Access to 2,177 Galaxy tools (real-time search)
- Access to 100+ GB BioMNI dataset catalog
- Workflow generation with automatic tool/dataset selection

Style guide:
- Be concise and practical
- Recommend specific tools and datasets
- Explain workflow steps clearly
- Highlight key parameters and considerations`;

async function runIntentTest(
  claude: Anthropic,
  testCase: TestCase,
  model: string
): Promise<TestResult> {
  const startTime = Date.now();
  try {
    const completion = await claude.messages.create({
      model,
      max_tokens: 200,
      temperature: 0.3,
      system: INTENT_SYSTEM_PROMPT,
      messages: [{ role: 'user', content: testCase.prompt }],
    });

    const content = completion.content[0];
    const response = content.type === 'text' ? content.text : '';

    return {
      testId: testCase.id,
      model,
      category: testCase.category,
      prompt: testCase.prompt,
      response,
      latencyMs: Date.now() - startTime,
      inputTokens: completion.usage.input_tokens,
      outputTokens: completion.usage.output_tokens,
      thinkingEnabled: false,
    };
  } catch (error: any) {
    return {
      testId: testCase.id,
      model,
      category: testCase.category,
      prompt: testCase.prompt,
      response: '',
      latencyMs: Date.now() - startTime,
      inputTokens: 0,
      outputTokens: 0,
      thinkingEnabled: false,
      error: error.message,
    };
  }
}

async function runResponseTest(
  claude: Anthropic,
  testCase: TestCase,
  model: string,
  enableThinking: boolean
): Promise<TestResult> {
  const startTime = Date.now();
  try {
    const apiOptions: any = {
      model,
      max_tokens: 4096,
      system: RESPONSE_SYSTEM_PROMPT,
      messages: [{ role: 'user', content: testCase.prompt }],
    };

    if (enableThinking) {
      apiOptions.thinking = {
        type: 'enabled',
        budget_tokens: 2000,
      };
    } else {
      apiOptions.temperature = 0.7;
    }

    const completion = await claude.messages.create(apiOptions);

    // Find text content (thinking mode returns [thinking, text])
    const textContent = completion.content.find(c => c.type === 'text');
    const response = textContent && textContent.type === 'text' ? textContent.text : '';

    return {
      testId: testCase.id,
      model,
      category: testCase.category,
      prompt: testCase.prompt,
      response,
      latencyMs: Date.now() - startTime,
      inputTokens: completion.usage.input_tokens,
      outputTokens: completion.usage.output_tokens,
      thinkingEnabled: enableThinking,
    };
  } catch (error: any) {
    return {
      testId: testCase.id,
      model,
      category: testCase.category,
      prompt: testCase.prompt,
      response: '',
      latencyMs: Date.now() - startTime,
      inputTokens: 0,
      outputTokens: 0,
      thinkingEnabled: enableThinking,
      error: error.message,
    };
  }
}

function parseIntentResponse(response: string): any {
  try {
    // Clean up JSON response
    let cleaned = response
      .replace(/^```+\s*json\s*\n?/gi, '')
      .replace(/\n?```+\s*$/gi, '')
      .trim();
    const jsonMatch = cleaned.match(/\{[\s\S]*\}/);
    if (jsonMatch) {
      return JSON.parse(jsonMatch[0]);
    }
    return null;
  } catch {
    return null;
  }
}

function evaluateIntentResult(
  result: TestResult,
  testCase: TestCase
): { correct: boolean; details: string } {
  if (result.error) {
    return { correct: false, details: `Error: ${result.error}` };
  }

  const parsed = parseIntentResponse(result.response);
  if (!parsed) {
    return { correct: false, details: 'Failed to parse JSON response' };
  }

  const intentCorrect = parsed.type === testCase.expectedIntent;
  const keywordsFound = testCase.expectedKeywords
    ? testCase.expectedKeywords.filter(kw =>
        parsed.keywords?.some((pk: string) => pk.toLowerCase().includes(kw.toLowerCase()))
      )
    : [];

  const keywordsScore = testCase.expectedKeywords
    ? keywordsFound.length / testCase.expectedKeywords.length
    : 1;

  return {
    correct: intentCorrect && keywordsScore >= 0.5,
    details: `Intent: ${parsed.type} (expected: ${testCase.expectedIntent}), Keywords: ${keywordsFound.length}/${testCase.expectedKeywords?.length || 0}`,
  };
}

async function runTestHarness() {
  console.log('='.repeat(80));
  console.log('BioMate Model Test Harness');
  console.log('='.repeat(80));
  console.log();

  const apiKey = process.env.ANTHROPIC_API_KEY;
  if (!apiKey) {
    console.error('ERROR: ANTHROPIC_API_KEY environment variable not set');
    process.exit(1);
  }

  const claude = new Anthropic({ apiKey });
  const results: TestResult[] = [];
  const evaluations: Array<{
    testId: string;
    model: string;
    thinkingEnabled: boolean;
    correct?: boolean;
    details?: string;
    latencyMs: number;
    tokens: { input: number; output: number };
  }> = [];

  // Run Intent Tests
  console.log('Running Intent Classification Tests...');
  console.log('-'.repeat(40));

  for (const testCase of TEST_CASES.filter(t => t.category === 'intent')) {
    console.log(`\nTest ${testCase.id}: ${testCase.description}`);

    for (const [modelName, modelId] of Object.entries(MODELS)) {
      console.log(`  Testing with ${modelName}...`);
      const result = await runIntentTest(claude, testCase, modelId);
      results.push(result);

      const evaluation = evaluateIntentResult(result, testCase);
      evaluations.push({
        testId: testCase.id,
        model: modelName,
        thinkingEnabled: false,
        correct: evaluation.correct,
        details: evaluation.details,
        latencyMs: result.latencyMs,
        tokens: { input: result.inputTokens, output: result.outputTokens },
      });

      console.log(`    ${evaluation.correct ? '✓' : '✗'} ${evaluation.details}`);
      console.log(`    Latency: ${result.latencyMs}ms | Tokens: ${result.inputTokens}→${result.outputTokens}`);
    }
  }

  // Run Ranking Tests
  console.log('\n');
  console.log('Running Tool Ranking Tests...');
  console.log('-'.repeat(40));

  for (const testCase of TEST_CASES.filter(t => t.category === 'ranking')) {
    console.log(`\nTest ${testCase.id}: ${testCase.description}`);

    for (const [modelName, modelId] of Object.entries(MODELS)) {
      console.log(`  Testing with ${modelName}...`);
      const result = await runResponseTest(claude, testCase, modelId, false);
      results.push(result);
      evaluations.push({
        testId: testCase.id,
        model: modelName,
        thinkingEnabled: false,
        latencyMs: result.latencyMs,
        tokens: { input: result.inputTokens, output: result.outputTokens },
      });
      console.log(`    Latency: ${result.latencyMs}ms | Tokens: ${result.inputTokens}→${result.outputTokens}`);
      console.log(`    Response length: ${result.response.length} chars`);
    }
  }

  // Run Consistency Tests (run each query 3 times)
  console.log('\n');
  console.log('Running Consistency Tests (3 runs each)...');
  console.log('-'.repeat(40));

  for (const testCase of TEST_CASES.filter(t => t.category === 'consistency')) {
    console.log(`\nTest ${testCase.id}: ${testCase.description}`);

    for (const [modelName, modelId] of Object.entries(MODELS)) {
      console.log(`  Testing with ${modelName} (3 runs)...`);
      const runs: TestResult[] = [];
      for (let i = 0; i < 3; i++) {
        const result = await runResponseTest(claude, testCase, modelId, false);
        result.testId = `${testCase.id}-run${i + 1}`;
        runs.push(result);
        results.push(result);
      }
      const avgLatency = runs.reduce((sum, r) => sum + r.latencyMs, 0) / runs.length;
      const responseLengths = runs.map(r => r.response.length);
      const avgLength = responseLengths.reduce((a, b) => a + b, 0) / responseLengths.length;
      const lengthVariance = Math.sqrt(responseLengths.reduce((sum, l) => sum + Math.pow(l - avgLength, 2), 0) / responseLengths.length);

      evaluations.push({
        testId: testCase.id,
        model: modelName,
        thinkingEnabled: false,
        latencyMs: avgLatency,
        tokens: { input: runs[0].inputTokens, output: runs.reduce((sum, r) => sum + r.outputTokens, 0) / runs.length },
        details: `Length variance: ${lengthVariance.toFixed(0)} chars`,
      });
      console.log(`    Avg Latency: ${avgLatency.toFixed(0)}ms | Length variance: ${lengthVariance.toFixed(0)} chars`);
    }
  }

  // Run Response Tests (with and without thinking)
  console.log('\n');
  console.log('Running Response Generation Tests...');
  console.log('-'.repeat(40));

  for (const testCase of TEST_CASES.filter(t => t.category === 'response' || t.category === 'thinking')) {
    console.log(`\nTest ${testCase.id}: ${testCase.description}`);

    for (const [modelName, modelId] of Object.entries(MODELS)) {
      // Test without thinking
      console.log(`  Testing with ${modelName} (no thinking)...`);
      const resultNoThink = await runResponseTest(claude, testCase, modelId, false);
      results.push(resultNoThink);
      evaluations.push({
        testId: testCase.id,
        model: modelName,
        thinkingEnabled: false,
        latencyMs: resultNoThink.latencyMs,
        tokens: { input: resultNoThink.inputTokens, output: resultNoThink.outputTokens },
      });
      console.log(`    Latency: ${resultNoThink.latencyMs}ms | Tokens: ${resultNoThink.inputTokens}→${resultNoThink.outputTokens}`);
      console.log(`    Response length: ${resultNoThink.response.length} chars`);

      // Test with thinking (only for Sonnet - Haiku may not support it)
      if (modelName === 'sonnet') {
        console.log(`  Testing with ${modelName} (thinking enabled)...`);
        const resultThink = await runResponseTest(claude, testCase, modelId, true);
        results.push(resultThink);
        evaluations.push({
          testId: testCase.id,
          model: modelName,
          thinkingEnabled: true,
          latencyMs: resultThink.latencyMs,
          tokens: { input: resultThink.inputTokens, output: resultThink.outputTokens },
        });
        console.log(`    Latency: ${resultThink.latencyMs}ms | Tokens: ${resultThink.inputTokens}→${resultThink.outputTokens}`);
        console.log(`    Response length: ${resultThink.response.length} chars`);
      }
    }
  }

  // Summary
  console.log('\n');
  console.log('='.repeat(80));
  console.log('SUMMARY');
  console.log('='.repeat(80));

  // Intent accuracy by model (includes edge cases and domain tests)
  const allIntentCategories = ['intent'];
  const intentEvals = evaluations.filter(e => {
    const testCase = TEST_CASES.find(t => t.id === e.testId);
    return testCase?.category === 'intent';
  });

  console.log('\n--- INTENT CLASSIFICATION ---');
  for (const modelName of Object.keys(MODELS)) {
    const modelEvals = intentEvals.filter(e => e.model === modelName);
    const correct = modelEvals.filter(e => e.correct).length;
    const avgLatency = modelEvals.reduce((sum, e) => sum + e.latencyMs, 0) / modelEvals.length;

    // Breakdown by subcategory
    const coreTests = modelEvals.filter(e => e.testId.startsWith('INTENT-0'));
    const edgeTests = modelEvals.filter(e => e.testId.startsWith('INTENT-EDGE'));
    const domainTests = modelEvals.filter(e => e.testId.startsWith('INTENT-DOMAIN'));

    console.log(`\n${modelName.toUpperCase()}:`);
    console.log(`  Overall Accuracy: ${correct}/${modelEvals.length} (${((correct / modelEvals.length) * 100).toFixed(1)}%)`);
    if (coreTests.length > 0) {
      const coreCorrect = coreTests.filter(e => e.correct).length;
      console.log(`    Core Tests: ${coreCorrect}/${coreTests.length}`);
    }
    if (edgeTests.length > 0) {
      const edgeCorrect = edgeTests.filter(e => e.correct).length;
      console.log(`    Edge Cases: ${edgeCorrect}/${edgeTests.length}`);
    }
    if (domainTests.length > 0) {
      const domainCorrect = domainTests.filter(e => e.correct).length;
      console.log(`    Domain Tests: ${domainCorrect}/${domainTests.length}`);
    }
    console.log(`  Avg Latency: ${avgLatency.toFixed(0)}ms`);
  }

  // Tool Ranking comparison
  const rankingEvals = evaluations.filter(e => TEST_CASES.find(t => t.id === e.testId)?.category === 'ranking');
  if (rankingEvals.length > 0) {
    console.log('\n--- TOOL RANKING ---');
    for (const modelName of Object.keys(MODELS)) {
      const modelEvals = rankingEvals.filter(e => e.model === modelName);
      const avgLatency = modelEvals.reduce((sum, e) => sum + e.latencyMs, 0) / modelEvals.length;
      console.log(`  ${modelName}: ${avgLatency.toFixed(0)}ms avg`);
    }
  }

  // Consistency comparison
  const consistencyEvals = evaluations.filter(e => TEST_CASES.find(t => t.id === e.testId)?.category === 'consistency');
  if (consistencyEvals.length > 0) {
    console.log('\n--- CONSISTENCY ---');
    for (const modelName of Object.keys(MODELS)) {
      const modelEvals = consistencyEvals.filter(e => e.model === modelName);
      const avgLatency = modelEvals.reduce((sum, e) => sum + e.latencyMs, 0) / modelEvals.length;
      const variances = modelEvals.map(e => parseInt(e.details?.match(/variance: (\d+)/)?.[1] || '0'));
      const avgVariance = variances.reduce((a, b) => a + b, 0) / variances.length;
      console.log(`  ${modelName}: ${avgLatency.toFixed(0)}ms avg, ${avgVariance.toFixed(0)} char variance`);
    }
  }

  // Response generation latency comparison
  const responseEvals = evaluations.filter(
    e => TEST_CASES.find(t => t.id === e.testId)?.category === 'response' ||
         TEST_CASES.find(t => t.id === e.testId)?.category === 'thinking'
  );

  console.log('\n--- RESPONSE GENERATION ---');
  for (const modelName of Object.keys(MODELS)) {
    const modelEvals = responseEvals.filter(e => e.model === modelName && !e.thinkingEnabled);
    const avgLatency = modelEvals.reduce((sum, e) => sum + e.latencyMs, 0) / modelEvals.length;
    console.log(`  ${modelName}: ${avgLatency.toFixed(0)}ms avg`);
  }

  const sonnetThinkingEvals = responseEvals.filter(e => e.model === 'sonnet' && e.thinkingEnabled);
  if (sonnetThinkingEvals.length > 0) {
    const avgLatency = sonnetThinkingEvals.reduce((sum, e) => sum + e.latencyMs, 0) / sonnetThinkingEvals.length;
    console.log(`  sonnet (thinking): ${avgLatency.toFixed(0)}ms avg`);
  }

  // Cost comparison
  console.log('\n--- COST COMPARISON (estimated) ---');
  const sonnetIntentTokens = intentEvals.filter(e => e.model === 'sonnet').reduce((sum, e) => sum + e.tokens.input + e.tokens.output, 0);
  const haikuIntentTokens = intentEvals.filter(e => e.model === 'haiku').reduce((sum, e) => sum + e.tokens.input + e.tokens.output, 0);
  // Sonnet: $3/1M input, $15/1M output | Haiku: $0.25/1M input, $1.25/1M output
  console.log(`  Intent (Sonnet): ~${(sonnetIntentTokens * 0.000015).toFixed(4)} USD for ${intentEvals.filter(e => e.model === 'sonnet').length} tests`);
  console.log(`  Intent (Haiku):  ~${(haikuIntentTokens * 0.00000125).toFixed(4)} USD for ${intentEvals.filter(e => e.model === 'haiku').length} tests`);
  console.log(`  Haiku is ~${((sonnetIntentTokens * 0.000015) / (haikuIntentTokens * 0.00000125)).toFixed(1)}x cheaper for intent classification`);

  // Save detailed results to file with timestamp
  const reportPath = join(RESULTS_DIR, `model_test_results_${TIMESTAMP}.json`);
  writeFileSync(
    reportPath,
    JSON.stringify({ results, evaluations, timestamp: new Date().toISOString() }, null, 2)
  );
  console.log(`\nDetailed results saved to: ${reportPath}`);

  // Save response comparisons for manual review with timestamp
  const comparisonPath = join(RESULTS_DIR, `model_response_comparison_${TIMESTAMP}.md`);
  let comparison = '# Model Response Comparison\n\n';
  comparison += `Generated: ${new Date().toISOString()}\n\n`;

  // Add ranking tests to comparison
  comparison += '# Tool Ranking Tests\n\n';
  for (const testCase of TEST_CASES.filter(t => t.category === 'ranking')) {
    comparison += `## ${testCase.id}: ${testCase.description}\n\n`;
    comparison += `**Prompt:** ${testCase.prompt}\n\n`;

    const testResults = results.filter(r => r.testId === testCase.id);
    for (const result of testResults) {
      comparison += `### ${result.model}\n\n`;
      comparison += `- Latency: ${result.latencyMs}ms\n`;
      comparison += `- Tokens: ${result.inputTokens} → ${result.outputTokens}\n\n`;
      comparison += `**Response:**\n\n${result.response}\n\n`;
      comparison += '---\n\n';
    }
  }

  // Add response generation tests
  comparison += '# Response Generation Tests\n\n';
  for (const testCase of TEST_CASES.filter(t => t.category === 'response' || t.category === 'thinking')) {
    comparison += `## ${testCase.id}: ${testCase.description}\n\n`;
    comparison += `**Prompt:** ${testCase.prompt}\n\n`;

    const testResults = results.filter(r => r.testId === testCase.id);
    for (const result of testResults) {
      comparison += `### ${result.model}${result.thinkingEnabled ? ' (thinking)' : ''}\n\n`;
      comparison += `- Latency: ${result.latencyMs}ms\n`;
      comparison += `- Tokens: ${result.inputTokens} → ${result.outputTokens}\n\n`;
      comparison += `**Response:**\n\n${result.response}\n\n`;
      comparison += '---\n\n';
    }
  }

  // Add consistency tests
  comparison += '# Consistency Tests\n\n';
  for (const testCase of TEST_CASES.filter(t => t.category === 'consistency')) {
    comparison += `## ${testCase.id}: ${testCase.description}\n\n`;
    comparison += `**Prompt:** ${testCase.prompt}\n\n`;

    for (const modelName of Object.keys(MODELS)) {
      comparison += `### ${modelName}\n\n`;
      const runs = results.filter(r => r.testId.startsWith(testCase.id) && r.model === MODELS[modelName as keyof typeof MODELS]);
      for (let i = 0; i < runs.length; i++) {
        comparison += `**Run ${i + 1}:** ${runs[i].latencyMs}ms, ${runs[i].response.length} chars\n\n`;
      }
      comparison += '---\n\n';
    }
  }

  writeFileSync(comparisonPath, comparison);
  console.log(`Response comparison saved to: ${comparisonPath}`);
}

// Run if executed directly
runTestHarness().catch(console.error);
