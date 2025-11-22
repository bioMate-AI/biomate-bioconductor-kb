/**
 * V6 Hybrid Detector - Full 1000-Scenario Validation Test
 *
 * Tests V6 on all 1000 scenarios to validate production readiness
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

async function runFullTest() {
  console.log('='.repeat(80));
  console.log('V6 HYBRID MODE DETECTOR - FULL 1000-SCENARIO TEST');
  console.log('='.repeat(80));
  console.log();

  // Flatten all scenarios
  const allScenarios = [];
  testSuite.forEach(useCase => {
    useCase.scenarios.forEach(s => {
      allScenarios.push({
        ...s,
        useCase: useCase.domain
      });
    });
  });

  console.log(`Total scenarios: ${allScenarios.length}`);
  console.log();

  // Group by expertise
  const byExpertise = {
    beginner: allScenarios.filter(s => s.expertise === 'beginner'),
    intermediate: allScenarios.filter(s => s.expertise === 'intermediate'),
    expert: allScenarios.filter(s => s.expertise === 'expert')
  };

  console.log('Scenarios by expertise:');
  console.log(`  Beginner: ${byExpertise.beginner.length}`);
  console.log(`  Intermediate: ${byExpertise.intermediate.length}`);
  console.log(`  Expert: ${byExpertise.expert.length}`);
  console.log();

  // Initialize detectors
  const v6Detector = new HybridModeDetector(ANTHROPIC_API_KEY);

  // Results tracking
  const results = {
    v5: {
      passed: 0,
      failed: 0,
      failures: [],
      byExpertise: { beginner: 0, intermediate: 0, expert: 0 },
      byMode: { iterative: 0, legacy: 0 }
    },
    v6: {
      passed: 0,
      failed: 0,
      failures: [],
      byExpertise: { beginner: 0, intermediate: 0, expert: 0 },
      byMode: { iterative: 0, legacy: 0 }
    }
  };

  console.log('='.repeat(80));
  console.log('RUNNING TESTS...');
  console.log('='.repeat(80));
  console.log();

  const startTime = Date.now();
  let completed = 0;
  let lastProgressUpdate = 0;

  for (const scenario of allScenarios) {
    completed++;

    // Test V5
    const v5Result = determineWorkflowModeV5(scenario.q, { expertise: scenario.expertise });
    const v5Pass = v5Result.mode === scenario.e;

    if (v5Pass) {
      results.v5.passed++;
      results.v5.byExpertise[scenario.expertise]++;
      results.v5.byMode[scenario.e]++;
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
        results.v6.byExpertise[scenario.expertise]++;
        results.v6.byMode[scenario.e]++;
      } else {
        results.v6.failed++;
        results.v6.failures.push({
          ...scenario,
          got: v6Result.mode,
          reason: v6Result.reason,
          method: v6Result.method
        });
      }

      // Progress indicator every 50 scenarios
      if (completed - lastProgressUpdate >= 50) {
        const elapsed = (Date.now() - startTime) / 1000;
        const rate = completed / elapsed;
        const remaining = (allScenarios.length - completed) / rate;
        console.log(`Progress: ${completed}/${allScenarios.length} (${(completed/allScenarios.length*100).toFixed(1)}%) - ${rate.toFixed(1)} q/s - ETA ${Math.ceil(remaining)}s`);
        lastProgressUpdate = completed;
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
    await new Promise(resolve => setTimeout(resolve, 50));
  }

  const totalTime = (Date.now() - startTime) / 1000;
  const avgRate = allScenarios.length / totalTime;

  // Get V6 statistics
  const v6Stats = v6Detector.getStats();

  // Print results
  console.log();
  console.log('='.repeat(80));
  console.log('TEST RESULTS');
  console.log('='.repeat(80));
  console.log();

  console.log(`Test Duration: ${totalTime.toFixed(1)}s (${avgRate.toFixed(2)} queries/sec)`);
  console.log();

  console.log('V5 (Rule-based only):');
  console.log(`  Passed: ${results.v5.passed}/${allScenarios.length} (${(results.v5.passed/allScenarios.length*100).toFixed(1)}%)`);
  console.log(`  Failed: ${results.v5.failed}`);
  console.log(`  By Expertise: Beginner ${results.v5.byExpertise.beginner}/${byExpertise.beginner.length}, Intermediate ${results.v5.byExpertise.intermediate}/${byExpertise.intermediate.length}, Expert ${results.v5.byExpertise.expert}/${byExpertise.expert.length}`);
  console.log();

  console.log('V6 (Hybrid LLM + Rules):');
  console.log(`  Passed: ${results.v6.passed}/${allScenarios.length} (${(results.v6.passed/allScenarios.length*100).toFixed(1)}%)`);
  console.log(`  Failed: ${results.v6.failed}`);
  console.log(`  By Expertise: Beginner ${results.v6.byExpertise.beginner}/${byExpertise.beginner.length}, Intermediate ${results.v6.byExpertise.intermediate}/${byExpertise.intermediate.length}, Expert ${results.v6.byExpertise.expert}/${byExpertise.expert.length}`);
  console.log();

  console.log('V6 Statistics:');
  console.log(`  Fast Rule Decisions: ${v6Stats.fastRuleDecisions} (${v6Stats.fastRuleRate})`);
  console.log(`  LLM Decisions: ${v6Stats.llmDecisions} (${v6Stats.llmRate})`);
  console.log(`  Cache Hits: ${v6Stats.cacheHits} (${v6Stats.cacheHitRate})`);
  console.log();

  console.log('Improvement:');
  const improvement = results.v6.passed - results.v5.passed;
  const improvementPct = ((results.v6.passed/allScenarios.length - results.v5.passed/allScenarios.length) * 100).toFixed(1);
  console.log(`  ${improvement > 0 ? '+' : ''}${improvement} scenarios (${improvementPct > 0 ? '+' : ''}${improvementPct}%)`);
  console.log();

  // Calculate accuracy by expertise for each system
  console.log('='.repeat(80));
  console.log('ACCURACY BY EXPERTISE LEVEL');
  console.log('='.repeat(80));
  console.log();

  ['beginner', 'intermediate', 'expert'].forEach(expertise => {
    const total = byExpertise[expertise].length;
    const v5Correct = results.v5.byExpertise[expertise];
    const v6Correct = results.v6.byExpertise[expertise];

    console.log(`${expertise.charAt(0).toUpperCase() + expertise.slice(1)} (${total} scenarios):`);
    console.log(`  V5: ${v5Correct}/${total} (${(v5Correct/total*100).toFixed(1)}%)`);
    console.log(`  V6: ${v6Correct}/${total} (${(v6Correct/total*100).toFixed(1)}%)`);
    console.log(`  Improvement: ${v6Correct > v5Correct ? '+' : ''}${v6Correct - v5Correct} (${((v6Correct/total - v5Correct/total)*100).toFixed(1)}%)`);
    console.log();
  });

  // Detailed failure analysis for V6
  if (results.v6.failures.length > 0) {
    console.log('='.repeat(80));
    console.log(`V6 FAILURES (First 30 of ${results.v6.failures.length})`);
    console.log('='.repeat(80));
    console.log();

    results.v6.failures.slice(0, 30).forEach((f, idx) => {
      console.log(`${idx + 1}. [${f.expertise}] ${f.q}`);
      console.log(`   Expected: ${f.e}, Got: ${f.got} (${f.method})`);
      console.log(`   Use Case: ${f.useCase}`);
      console.log();
    });

    // Group failures by pattern
    console.log('='.repeat(80));
    console.log('FAILURE PATTERNS');
    console.log('='.repeat(80));
    console.log();

    const failurePatterns = {
      'Quick/Run + Tool (Beginner)': results.v6.failures.filter(f =>
        f.expertise === 'beginner' &&
        /quick.*with|run.*for/i.test(f.q) &&
        f.e === 'legacy'
      ),
      'Generate standard (Intermediate)': results.v6.failures.filter(f =>
        f.expertise === 'intermediate' &&
        /generate standard|standard.*workflow/i.test(f.q)
      ),
      'I need to X for Y': results.v6.failures.filter(f =>
        /I need to \w+ for/i.test(f.q) &&
        !/run|use|execute|modify/.test(f.q.toLowerCase())
      ),
      'Optimize parameters': results.v6.failures.filter(f =>
        /optimize.*parameters|optimize.*with/i.test(f.q)
      )
    };

    Object.entries(failurePatterns).forEach(([pattern, failures]) => {
      if (failures.length > 0) {
        console.log(`${pattern}: ${failures.length} failures`);
      }
    });
  }

  // Write summary to file
  const summaryPath = '/home/yzhang/biomate/auto_update/docs/hybrid_mode_detection_1000_test/v6_full_1000_results.json';
  const fs = require('fs');
  fs.writeFileSync(summaryPath, JSON.stringify({
    timestamp: new Date().toISOString(),
    totalScenarios: allScenarios.length,
    duration: totalTime,
    v5: {
      accuracy: (results.v5.passed/allScenarios.length*100).toFixed(2) + '%',
      passed: results.v5.passed,
      failed: results.v5.failed,
      byExpertise: {
        beginner: { correct: results.v5.byExpertise.beginner, total: byExpertise.beginner.length },
        intermediate: { correct: results.v5.byExpertise.intermediate, total: byExpertise.intermediate.length },
        expert: { correct: results.v5.byExpertise.expert, total: byExpertise.expert.length }
      }
    },
    v6: {
      accuracy: (results.v6.passed/allScenarios.length*100).toFixed(2) + '%',
      passed: results.v6.passed,
      failed: results.v6.failed,
      byExpertise: {
        beginner: { correct: results.v6.byExpertise.beginner, total: byExpertise.beginner.length },
        intermediate: { correct: results.v6.byExpertise.intermediate, total: byExpertise.intermediate.length },
        expert: { correct: results.v6.byExpertise.expert, total: byExpertise.expert.length }
      },
      stats: v6Stats
    },
    improvement: {
      absolute: improvement,
      percentage: improvementPct + '%'
    },
    v6Failures: results.v6.failures.slice(0, 50) // First 50 for analysis
  }, null, 2));

  console.log();
  console.log('='.repeat(80));
  console.log('TEST COMPLETE');
  console.log('='.repeat(80));
  console.log();
  console.log(`Results saved to: ${summaryPath}`);

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
  runFullTest()
    .then(results => {
      process.exit(results.v6.passed > results.v5.passed ? 0 : 1);
    })
    .catch(error => {
      console.error('Test failed:', error);
      process.exit(1);
    });
}

module.exports = { runFullTest };
