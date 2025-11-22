/**
 * V6 Hybrid Detector Validation Test
 *
 * Tests V6 on a strategic subset of 100 scenarios:
 * - All 4 major V5 failure patterns
 * - Representative samples from all expertise levels
 * - Mix of iterative/legacy expected modes
 */

const { HybridModeDetector } = require('./v6_hybrid_detector.js');
const { testSuite1000: testSuite } = require('./test_suite_1000_scenarios.js');

// Get API key from environment
const ANTHROPIC_API_KEY = process.env.ANTHROPIC_API_KEY;

if (!ANTHROPIC_API_KEY) {
  console.error('Error: ANTHROPIC_API_KEY environment variable not set');
  process.exit(1);
}

// =============================================================================
// Test Scenario Selection Strategy
// =============================================================================

/**
 * Select strategic subset of 100 scenarios
 *
 * Strategy:
 * 1. Include key failure patterns from V5 (40 scenarios)
 * 2. Sample diverse expertise levels (30/42/28 = beginner/intermediate/expert)
 * 3. Balance iterative/legacy modes (56/44 split)
 */
function selectTestSubset() {
  const allScenarios = [];
  testSuite.forEach(useCase => {
    useCase.scenarios.forEach(s => {
      allScenarios.push({
        ...s,
        useCase: useCase.domain
      });
    });
  });

  console.log(`Total scenarios available: ${allScenarios.length}`);

  // Pattern 1: "I need to X for Y" (incomplete sentences)
  const pattern1 = allScenarios.filter(s =>
    /I need to \w+ for/i.test(s.q) &&
    !/run|use|execute|modify/.test(s.q.toLowerCase())
  );

  // Pattern 2: Expert "Generate standard" (expertise mismatch)
  const pattern2 = allScenarios.filter(s =>
    s.expertise === 'expert' &&
    /generate standard|standard.*workflow/i.test(s.q)
  );

  // Pattern 3: "Optimize Tool parameters" (verb semantics)
  const pattern3 = allScenarios.filter(s =>
    /optimize.*parameters|optimize.*with/i.test(s.q)
  );

  // Pattern 4: Beginner "Quick X with Tool" (expertise context)
  const pattern4 = allScenarios.filter(s =>
    s.expertise === 'beginner' &&
    /quick.*with|run.*for/i.test(s.q) &&
    s.e === 'legacy'
  );

  console.log(`\nFailure Pattern Scenarios:`);
  console.log(`  Pattern 1 ("I need to X"): ${pattern1.length}`);
  console.log(`  Pattern 2 (Expert "standard"): ${pattern2.length}`);
  console.log(`  Pattern 3 ("Optimize"): ${pattern3.length}`);
  console.log(`  Pattern 4 (Beginner "quick"): ${pattern4.length}`);

  // Take samples from each pattern (max 10 each)
  const selectedPatterns = [
    ...pattern1.slice(0, 15),
    ...pattern2.slice(0, 10),
    ...pattern3.slice(0, 10),
    ...pattern4.slice(0, 15)
  ];

  // Remove duplicates
  const patternIds = new Set(selectedPatterns.map(s => s.id));

  // Add random samples to reach 100, ensuring expertise/mode balance
  const remaining = allScenarios.filter(s => !patternIds.has(s.id));

  // Sample by expertise
  const beginners = remaining.filter(s => s.expertise === 'beginner').slice(0, 15);
  const intermediates = remaining.filter(s => s.expertise === 'intermediate').slice(0, 20);
  const experts = remaining.filter(s => s.expertise === 'expert').slice(0, 15);

  const finalSelection = [
    ...selectedPatterns,
    ...beginners,
    ...intermediates,
    ...experts
  ].slice(0, 100);

  console.log(`\nFinal test subset: ${finalSelection.length} scenarios`);
  console.log(`  Beginners: ${finalSelection.filter(s => s.expertise === 'beginner').length}`);
  console.log(`  Intermediates: ${finalSelection.filter(s => s.expertise === 'intermediate').length}`);
  console.log(`  Experts: ${finalSelection.filter(s => s.expertise === 'expert').length}`);
  console.log(`  Expected Iterative: ${finalSelection.filter(s => s.e === 'iterative').length}`);
  console.log(`  Expected Legacy: ${finalSelection.filter(s => s.e === 'legacy').length}`);

  return finalSelection;
}

// =============================================================================
// V5 Detection Logic (for comparison)
// =============================================================================

function determineWorkflowModeV5(message, context = {}) {
  const intent = analyzeIntentV5(message);

  // Informational questions
  if (intent.isInformationalQuestion) {
    return { mode: 'legacy', reason: 'Informational question', confidence: 0.9 };
  }

  // Modification requests
  if (intent.isModification) {
    return { mode: 'legacy', reason: 'Modification request', confidence: 0.9 };
  }

  // Complex queries
  if (intent.isComplex) {
    return { mode: 'iterative', reason: 'Complex query', confidence: 0.8 };
  }

  // Simple and specific
  if (intent.isSimple && intent.confidence >= 0.8) {
    return { mode: 'legacy', reason: 'Simple specific query', confidence: intent.confidence };
  }

  // Analysis or comparison
  if (intent.type === 'analysis' || intent.type === 'comparison') {
    return { mode: 'iterative', reason: 'Analysis request', confidence: 0.7 };
  }

  // Default to iterative for ambiguous cases
  return {
    mode: 'iterative',
    reason: intent.confidence < 0.6 ? 'Low confidence' : 'General question',
    confidence: intent.confidence
  };
}

function analyzeIntentV5(message) {
  const lower = message.toLowerCase();

  // Informational questions
  const isInformationalQuestion = /^what (is|are|does|do|did)/i.test(message) ||
    /^(how|why|when|where) (is|are|does|do|did|can|will)/i.test(message);

  // Modifications
  const isModification = /modify|edit|change|update.*existing|adjust.*existing|my.*workflow|current workflow/i.test(message);

  // Complexity indicators
  const hasMultipleSteps = /and then|followed by|after that|next|finally/i.test(message);
  const mentionsMultipleTools = (message.match(/HISAT2|STAR|Kallisto|Salmon|DESeq2|edgeR|limma|GATK|Mutect2|Strelka2|FreeBayes|QIIME2|Kraken2|MetaPhlAn|Seurat|Scanpy/gi) || []).length > 1;
  const isComplex = hasMultipleSteps || mentionsMultipleTools || /complex|advanced|comprehensive|detailed/i.test(message);

  // Simplicity indicators
  const mentionsSpecificTools = /using (HISAT2|STAR|Kallisto|Salmon|DESeq2|edgeR|GATK4|Mutect2|Strelka2|FreeBayes|QIIME2|Kraken2|Seurat|Scanpy)/i.test(message);
  const hasSpecificParams = /--[\w-]+|=[\w\.]+/i.test(message);
  const isSimple = mentionsSpecificTools || hasSpecificParams || /quick|simple|basic|standard/i.test(lower);

  // Analysis type
  let type = 'general';
  if (isInformationalQuestion) type = 'informational';
  if (isModification) type = 'modification';
  if (/compare|versus|vs\b/i.test(message)) type = 'comparison';
  if (/analysis|analyze|process|run/i.test(lower)) type = 'analysis';

  // Confidence calculation
  let confidence = 0.5;
  if (mentionsSpecificTools) confidence += 0.2;
  if (hasSpecificParams) confidence += 0.2;
  if (/workflow|pipeline/.test(lower)) confidence = 0.9;
  if (isInformationalQuestion) confidence = 0.95;
  if (/build|create|generate/.test(lower)) confidence += 0.2;

  return {
    type,
    confidence: Math.min(confidence, 1.0),
    isComplex,
    isSimple,
    isInformationalQuestion,
    isModification
  };
}

// =============================================================================
// Test Runner
// =============================================================================

async function runValidationTest() {
  console.log('='.repeat(80));
  console.log('V6 HYBRID MODE DETECTOR - VALIDATION TEST');
  console.log('='.repeat(80));
  console.log();

  // Select test subset
  const testScenarios = selectTestSubset();

  // Initialize detectors
  const v6Detector = new HybridModeDetector(ANTHROPIC_API_KEY);

  // Results tracking
  const results = {
    v5: { passed: 0, failed: 0, failures: [] },
    v6: { passed: 0, failed: 0, failures: [] }
  };

  console.log('\n' + '='.repeat(80));
  console.log('RUNNING TESTS...');
  console.log('='.repeat(80));
  console.log();

  let completed = 0;

  for (const scenario of testScenarios) {
    completed++;

    // Test V5
    const v5Result = determineWorkflowModeV5(scenario.q, { expertise: scenario.expertise });
    const v5Pass = v5Result.mode === scenario.e;

    if (v5Pass) {
      results.v5.passed++;
    } else {
      results.v5.failed++;
      results.v5.failures.push({
        ...scenario,
        got: v5Result.mode,
        reason: v5Result.reason
      });
    }

    // Test V6
    try {
      const v6Result = await v6Detector.determineMode(scenario.q, {
        expertise: scenario.expertise
      });
      const v6Pass = v6Result.mode === scenario.e;

      if (v6Pass) {
        results.v6.passed++;
      } else {
        results.v6.failed++;
        results.v6.failures.push({
          ...scenario,
          got: v6Result.mode,
          reason: v6Result.reason,
          method: v6Result.method
        });
      }

      // Progress indicator
      if (completed % 10 === 0) {
        console.log(`Progress: ${completed}/${testScenarios.length} (${(completed/testScenarios.length*100).toFixed(0)}%)`);
      }

    } catch (error) {
      console.error(`\nError testing scenario ${scenario.id}:`, error.message);
      results.v6.failed++;
      results.v6.failures.push({
        ...scenario,
        got: 'ERROR',
        reason: error.message
      });
    }

    // Small delay to avoid rate limits
    await new Promise(resolve => setTimeout(resolve, 100));
  }

  // Get V6 statistics
  const v6Stats = v6Detector.getStats();

  // Print results
  console.log('\n' + '='.repeat(80));
  console.log('TEST RESULTS');
  console.log('='.repeat(80));
  console.log();

  console.log('V5 (Rule-based only):');
  console.log(`  Passed: ${results.v5.passed}/${testScenarios.length} (${(results.v5.passed/testScenarios.length*100).toFixed(1)}%)`);
  console.log(`  Failed: ${results.v5.failed}`);
  console.log();

  console.log('V6 (Hybrid LLM + Rules):');
  console.log(`  Passed: ${results.v6.passed}/${testScenarios.length} (${(results.v6.passed/testScenarios.length*100).toFixed(1)}%)`);
  console.log(`  Failed: ${results.v6.failed}`);
  console.log();

  console.log('V6 Statistics:');
  console.log(`  Fast Rule Decisions: ${v6Stats.fastRuleDecisions} (${v6Stats.fastRuleRate})`);
  console.log(`  LLM Decisions: ${v6Stats.llmDecisions} (${v6Stats.llmRate})`);
  console.log(`  Cache Hits: ${v6Stats.cacheHits} (${v6Stats.cacheHitRate})`);
  console.log();

  console.log('Improvement:');
  const improvement = results.v6.passed - results.v5.passed;
  const improvementPct = ((results.v6.passed/testScenarios.length - results.v5.passed/testScenarios.length) * 100).toFixed(1);
  console.log(`  ${improvement > 0 ? '+' : ''}${improvement} scenarios (${improvementPct > 0 ? '+' : ''}${improvementPct}%)`);
  console.log();

  // Detailed failure analysis
  if (results.v6.failures.length > 0) {
    console.log('='.repeat(80));
    console.log('V6 FAILURES (First 20)');
    console.log('='.repeat(80));
    console.log();

    results.v6.failures.slice(0, 20).forEach((f, idx) => {
      console.log(`${idx + 1}. [${f.expertise}] ${f.q}`);
      console.log(`   Expected: ${f.e}`);
      console.log(`   Got: ${f.got} (${f.method})`);
      console.log(`   Reason: ${f.reason}`);
      console.log();
    });
  }

  // Pattern-specific analysis
  console.log('='.repeat(80));
  console.log('PATTERN-SPECIFIC RESULTS');
  console.log('='.repeat(80));
  console.log();

  const analyzePattern = (patternName, regex, otherConditions = () => true) => {
    const patternScenarios = testScenarios.filter(s => regex.test(s.q) && otherConditions(s));
    const v5PatternPass = patternScenarios.filter(s => {
      const result = determineWorkflowModeV5(s.q, { expertise: s.expertise });
      return result.mode === s.e;
    }).length;
    const v6PatternPass = patternScenarios.filter(s => {
      const failure = results.v6.failures.find(f => f.id === s.id);
      return !failure; // If not in failures, it passed
    }).length;

    console.log(`${patternName}:`);
    console.log(`  Scenarios: ${patternScenarios.length}`);
    console.log(`  V5: ${v5PatternPass}/${patternScenarios.length} (${(v5PatternPass/patternScenarios.length*100).toFixed(1)}%)`);
    console.log(`  V6: ${v6PatternPass}/${patternScenarios.length} (${(v6PatternPass/patternScenarios.length*100).toFixed(1)}%)`);
    console.log(`  Improvement: +${(v6PatternPass - v5PatternPass)} scenarios`);
    console.log();
  };

  analyzePattern(
    'Pattern 1: "I need to X for Y" (incomplete)',
    /I need to \w+ for/i,
    s => !/run|use|execute|modify/.test(s.q.toLowerCase())
  );

  analyzePattern(
    'Pattern 2: Expert "Generate standard"',
    /generate standard|standard.*workflow/i,
    s => s.expertise === 'expert'
  );

  analyzePattern(
    'Pattern 3: "Optimize Tool parameters"',
    /optimize.*parameters|optimize.*with/i
  );

  analyzePattern(
    'Pattern 4: Beginner "Quick X with Tool"',
    /quick.*with|run.*for/i,
    s => s.expertise === 'beginner' && s.e === 'legacy'
  );

  return {
    v5: results.v5,
    v6: results.v6,
    stats: v6Stats,
    improvement
  };
}

// =============================================================================
// Main
// =============================================================================

if (require.main === module) {
  runValidationTest()
    .then(results => {
      console.log('='.repeat(80));
      console.log('TEST COMPLETE');
      console.log('='.repeat(80));
      process.exit(results.v6.passed > results.v5.passed ? 0 : 1);
    })
    .catch(error => {
      console.error('Test failed:', error);
      process.exit(1);
    });
}

module.exports = { runValidationTest, selectTestSubset };
