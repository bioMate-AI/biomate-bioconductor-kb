/**
 * V6 Hybrid Detector - Enhanced Evaluation with Latency & Cost Tracking
 *
 * Comprehensive evaluation matrix including:
 * - Accuracy (overall, by expertise, by mode)
 * - Latency (avg, p50, p95, p99, by method)
 * - Computational cost (per query, total, projections)
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
// Cost Constants (Claude Sonnet 4 pricing)
// =============================================================================

const PRICING = {
  // Claude Sonnet 4 pricing (per million tokens)
  inputTokens: 3.00,        // $3.00 per 1M input tokens
  outputTokens: 15.00,      // $15.00 per 1M output tokens

  // Prompt caching (90% discount on cached tokens)
  cachedInputTokens: 0.30,  // $0.30 per 1M cached tokens

  // Estimated tokens per query
  systemPromptTokens: 800,   // System prompt (cacheable)
  userPromptTokens: 150,     // User prompt + context
  outputTokens: 100,         // JSON response

  // V5 cost (rules-only)
  v5CostPerQuery: 0          // Free (no API calls)
};

// Calculate cost per query
function calculateQueryCost(cached = false) {
  const systemCost = cached
    ? (PRICING.systemPromptTokens / 1000000) * PRICING.cachedInputTokens
    : (PRICING.systemPromptTokens / 1000000) * PRICING.inputTokens;

  const userCost = (PRICING.userPromptTokens / 1000000) * PRICING.inputTokens;
  const outputCost = (PRICING.outputTokens / 1000000) * PRICING.outputTokens;

  return systemCost + userCost + outputCost;
}

const COST_PER_QUERY = {
  llmUncached: calculateQueryCost(false),  // ~$0.000027
  llmCached: calculateQueryCost(true),     // ~$0.000003
  fastRule: 0                               // Free
};

// =============================================================================
// V5 Detection Logic (for comparison)
// =============================================================================

function determineWorkflowModeV5(message, context = {}) {
  const intent = analyzeIntentV5(message);

  if (intent.isInformationalQuestion) {
    return { mode: 'legacy', reason: 'Informational question', confidence: 0.9 };
  }

  if (intent.isModification) {
    return { mode: 'legacy', reason: 'Modification request', confidence: 0.9 };
  }

  if (intent.isComplex) {
    return { mode: 'iterative', reason: 'Complex query', confidence: 0.8 };
  }

  if (intent.isSimple && intent.confidence >= 0.8) {
    return { mode: 'legacy', reason: 'Simple specific query', confidence: intent.confidence };
  }

  if (intent.type === 'analysis' || intent.type === 'comparison') {
    return { mode: 'iterative', reason: 'Analysis request', confidence: 0.7 };
  }

  return {
    mode: 'iterative',
    reason: intent.confidence < 0.6 ? 'Low confidence' : 'General question',
    confidence: intent.confidence
  };
}

function analyzeIntentV5(message) {
  const lower = message.toLowerCase();

  const isInformationalQuestion = /^what (is|are|does|do|did)/i.test(message) ||
    /^(how|why|when|where) (is|are|does|do|did|can|will)/i.test(message);

  const isModification = /modify|edit|change|update.*existing|adjust.*existing|my.*workflow|current workflow/i.test(message);

  const hasMultipleSteps = /and then|followed by|after that|next|finally/i.test(message);
  const mentionsMultipleTools = (message.match(/HISAT2|STAR|Kallisto|Salmon|DESeq2|edgeR|limma|GATK|Mutect2|Strelka2|FreeBayes|QIIME2|Kraken2|MetaPhlAn|Seurat|Scanpy/gi) || []).length > 1;
  const isComplex = hasMultipleSteps || mentionsMultipleTools || /complex|advanced|comprehensive|detailed/i.test(message);

  const mentionsSpecificTools = /using (HISAT2|STAR|Kallisto|Salmon|DESeq2|edgeR|GATK4|Mutect2|Strelka2|FreeBayes|QIIME2|Kraken2|Seurat|Scanpy)/i.test(message);
  const hasSpecificParams = /--[\w-]+|=[\w\.]+/i.test(message);
  const isSimple = mentionsSpecificTools || hasSpecificParams || /quick|simple|basic|standard/i.test(lower);

  let type = 'general';
  if (isInformationalQuestion) type = 'informational';
  if (isModification) type = 'modification';
  if (/compare|versus|vs\b/i.test(message)) type = 'comparison';
  if (/analysis|analyze|process|run/i.test(lower)) type = 'analysis';

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
// Enhanced Test Runner with Latency & Cost Tracking
// =============================================================================

async function runEnhancedEvaluation(sampleSize = null) {
  console.log('='.repeat(80));
  console.log('V6 ENHANCED EVALUATION - Accuracy, Latency & Cost Matrix');
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

  // Sample if requested
  const testScenarios = sampleSize
    ? allScenarios.slice(0, sampleSize)
    : allScenarios;

  console.log(`Total scenarios: ${testScenarios.length}`);
  if (sampleSize) {
    console.log(`(Sampled from ${allScenarios.length} total scenarios)`);
  }
  console.log();

  // Initialize detector
  const v6Detector = new HybridModeDetector(ANTHROPIC_API_KEY);

  // Enhanced results tracking
  const results = {
    v5: {
      passed: 0,
      failed: 0,
      failures: [],
      latencies: [],  // Track all latencies
      totalTime: 0
    },
    v6: {
      passed: 0,
      failed: 0,
      failures: [],
      latencies: [],
      fastRuleLatencies: [],
      llmLatencies: [],
      totalTime: 0,
      llmCalls: 0,
      fastRuleCalls: 0,
      cacheHits: 0
    }
  };

  console.log('='.repeat(80));
  console.log('RUNNING TESTS...');
  console.log('='.repeat(80));
  console.log();

  const overallStart = Date.now();
  let completed = 0;
  let lastProgressUpdate = 0;

  for (const scenario of testScenarios) {
    completed++;

    // =========================================================================
    // Test V5 with latency tracking
    // =========================================================================
    const v5Start = Date.now();
    const v5Result = determineWorkflowModeV5(scenario.q, { expertise: scenario.expertise });
    const v5Latency = Date.now() - v5Start;

    results.v5.latencies.push(v5Latency);
    results.v5.totalTime += v5Latency;

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

    // =========================================================================
    // Test V6 with latency tracking
    // =========================================================================
    try {
      const v6Start = Date.now();
      const v6Result = await v6Detector.determineMode(scenario.q, {
        expertise: scenario.expertise
      });
      const v6Latency = Date.now() - v6Start;

      results.v6.latencies.push(v6Latency);
      results.v6.totalTime += v6Latency;

      // Track by method
      if (v6Result.method === 'fast_rule') {
        results.v6.fastRuleCalls++;
        results.v6.fastRuleLatencies.push(v6Latency);
      } else {
        results.v6.llmCalls++;
        results.v6.llmLatencies.push(v6Latency);
      }

      const v6Pass = v6Result.mode === scenario.e;
      if (v6Pass) {
        results.v6.passed++;
      } else {
        results.v6.failed++;
        results.v6.failures.push({
          ...scenario,
          got: v6Result.mode,
          reason: v6Result.reason,
          method: v6Result.method,
          latency: v6Latency
        });
      }

      // Progress indicator every 50 scenarios
      if (completed - lastProgressUpdate >= 50) {
        const elapsed = (Date.now() - overallStart) / 1000;
        const rate = completed / elapsed;
        const remaining = (testScenarios.length - completed) / rate;
        const avgLatency = results.v6.totalTime / completed;
        console.log(`Progress: ${completed}/${testScenarios.length} (${(completed/testScenarios.length*100).toFixed(1)}%) - ${rate.toFixed(1)} q/s - Avg latency: ${avgLatency.toFixed(0)}ms - ETA ${Math.ceil(remaining)}s`);
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

  const totalDuration = (Date.now() - overallStart) / 1000;

  // Get V6 statistics
  const v6Stats = v6Detector.getStats();
  results.v6.cacheHits = v6Stats.cacheHits;

  // =========================================================================
  // Calculate Latency Percentiles
  // =========================================================================

  function calculatePercentiles(latencies) {
    if (latencies.length === 0) return { p50: 0, p95: 0, p99: 0, avg: 0, min: 0, max: 0 };

    const sorted = [...latencies].sort((a, b) => a - b);
    const p50 = sorted[Math.floor(sorted.length * 0.50)];
    const p95 = sorted[Math.floor(sorted.length * 0.95)];
    const p99 = sorted[Math.floor(sorted.length * 0.99)];
    const avg = latencies.reduce((a, b) => a + b, 0) / latencies.length;
    const min = sorted[0];
    const max = sorted[sorted.length - 1];

    return { p50, p95, p99, avg, min, max };
  }

  const v5Latency = calculatePercentiles(results.v5.latencies);
  const v6Latency = calculatePercentiles(results.v6.latencies);
  const v6FastRuleLatency = calculatePercentiles(results.v6.fastRuleLatencies);
  const v6LlmLatency = calculatePercentiles(results.v6.llmLatencies);

  // =========================================================================
  // Calculate Costs
  // =========================================================================

  const cacheHitRate = results.v6.llmCalls > 0
    ? results.v6.cacheHits / results.v6.llmCalls
    : 0;

  // Actual cost (accounting for cache hits)
  const llmCachedQueries = results.v6.cacheHits;
  const llmUncachedQueries = results.v6.llmCalls - results.v6.cacheHits;

  const v6TotalCost =
    (llmUncachedQueries * COST_PER_QUERY.llmUncached) +
    (llmCachedQueries * COST_PER_QUERY.llmCached) +
    (results.v6.fastRuleCalls * COST_PER_QUERY.fastRule);

  const v6AvgCost = v6TotalCost / testScenarios.length;

  // V5 cost
  const v5TotalCost = testScenarios.length * PRICING.v5CostPerQuery;
  const v5AvgCost = PRICING.v5CostPerQuery;

  // Projected costs with warm cache (80% hit rate)
  const warmCacheHitRate = 0.80;
  const v6ProjectedCost =
    (results.v6.llmCalls * (1 - warmCacheHitRate) * COST_PER_QUERY.llmUncached) +
    (results.v6.llmCalls * warmCacheHitRate * COST_PER_QUERY.llmCached);
  const v6ProjectedAvgCost = v6ProjectedCost / testScenarios.length;

  // =========================================================================
  // Print Results
  // =========================================================================

  console.log();
  console.log('='.repeat(80));
  console.log('EVALUATION RESULTS MATRIX');
  console.log('='.repeat(80));
  console.log();

  console.log(`Test Duration: ${totalDuration.toFixed(1)}s`);
  console.log();

  // Accuracy Results
  console.log('━'.repeat(80));
  console.log('ACCURACY METRICS');
  console.log('━'.repeat(80));
  console.log();

  console.log('V5 (Rule-based only):');
  console.log(`  Accuracy: ${results.v5.passed}/${testScenarios.length} (${(results.v5.passed/testScenarios.length*100).toFixed(1)}%)`);
  console.log();

  console.log('V6 (Hybrid LLM + Rules):');
  console.log(`  Accuracy: ${results.v6.passed}/${testScenarios.length} (${(results.v6.passed/testScenarios.length*100).toFixed(1)}%)`);
  console.log(`  Fast Rule Decisions: ${results.v6.fastRuleCalls} (${(results.v6.fastRuleCalls/testScenarios.length*100).toFixed(1)}%)`);
  console.log(`  LLM Decisions: ${results.v6.llmCalls} (${(results.v6.llmCalls/testScenarios.length*100).toFixed(1)}%)`);
  console.log();

  const improvement = results.v6.passed - results.v5.passed;
  const improvementPct = ((results.v6.passed/testScenarios.length - results.v5.passed/testScenarios.length) * 100).toFixed(1);
  console.log(`Improvement: ${improvement > 0 ? '+' : ''}${improvement} scenarios (${improvementPct > 0 ? '+' : ''}${improvementPct}%)`);
  console.log();

  // Latency Results
  console.log('━'.repeat(80));
  console.log('LATENCY METRICS (milliseconds)');
  console.log('━'.repeat(80));
  console.log();

  console.log('V5 Latency:');
  console.log(`  Average:  ${v5Latency.avg.toFixed(2)}ms`);
  console.log(`  Median:   ${v5Latency.p50.toFixed(2)}ms`);
  console.log(`  P95:      ${v5Latency.p95.toFixed(2)}ms`);
  console.log(`  P99:      ${v5Latency.p99.toFixed(2)}ms`);
  console.log(`  Range:    ${v5Latency.min.toFixed(2)}ms - ${v5Latency.max.toFixed(2)}ms`);
  console.log();

  console.log('V6 Overall Latency:');
  console.log(`  Average:  ${v6Latency.avg.toFixed(2)}ms`);
  console.log(`  Median:   ${v6Latency.p50.toFixed(2)}ms`);
  console.log(`  P95:      ${v6Latency.p95.toFixed(2)}ms`);
  console.log(`  P99:      ${v6Latency.p99.toFixed(2)}ms`);
  console.log(`  Range:    ${v6Latency.min.toFixed(2)}ms - ${v6Latency.max.toFixed(2)}ms`);
  console.log();

  console.log('V6 Fast Rule Latency:');
  console.log(`  Average:  ${v6FastRuleLatency.avg.toFixed(2)}ms`);
  console.log(`  Median:   ${v6FastRuleLatency.p50.toFixed(2)}ms`);
  console.log(`  P95:      ${v6FastRuleLatency.p95.toFixed(2)}ms`);
  console.log();

  console.log('V6 LLM Latency:');
  console.log(`  Average:  ${v6LlmLatency.avg.toFixed(2)}ms`);
  console.log(`  Median:   ${v6LlmLatency.p50.toFixed(2)}ms`);
  console.log(`  P95:      ${v6LlmLatency.p95.toFixed(2)}ms`);
  console.log(`  P99:      ${v6LlmLatency.p99.toFixed(2)}ms`);
  console.log();

  console.log(`Latency Overhead: ${((v6Latency.avg / v5Latency.avg - 1) * 100).toFixed(1)}% average increase`);
  console.log();

  // Cost Results
  console.log('━'.repeat(80));
  console.log('COMPUTATIONAL COST METRICS');
  console.log('━'.repeat(80));
  console.log();

  console.log('V5 Cost:');
  console.log(`  Per Query:    $${v5AvgCost.toFixed(6)}`);
  console.log(`  Total (${testScenarios.length} queries): $${v5TotalCost.toFixed(4)}`);
  console.log();

  console.log('V6 Cost (Current - Cold Cache):');
  console.log(`  Cache Hit Rate: ${(cacheHitRate * 100).toFixed(1)}%`);
  console.log(`  Per Query:      $${v6AvgCost.toFixed(6)}`);
  console.log(`  Total (${testScenarios.length} queries):   $${v6TotalCost.toFixed(4)}`);
  console.log(`  Breakdown:`);
  console.log(`    - Fast Rules: ${results.v6.fastRuleCalls} × $0 = $0.00`);
  console.log(`    - LLM (uncached): ${llmUncachedQueries} × $${COST_PER_QUERY.llmUncached.toFixed(6)} = $${(llmUncachedQueries * COST_PER_QUERY.llmUncached).toFixed(4)}`);
  console.log(`    - LLM (cached): ${llmCachedQueries} × $${COST_PER_QUERY.llmCached.toFixed(6)} = $${(llmCachedQueries * COST_PER_QUERY.llmCached).toFixed(4)}`);
  console.log();

  console.log('V6 Projected Cost (Warm Cache - 80% Hit Rate):');
  console.log(`  Per Query:      $${v6ProjectedAvgCost.toFixed(6)}`);
  console.log(`  Total (${testScenarios.length} queries):   $${v6ProjectedCost.toFixed(4)}`);
  console.log();

  // Scale projections
  console.log('━'.repeat(80));
  console.log('COST PROJECTIONS AT SCALE');
  console.log('━'.repeat(80));
  console.log();

  const scales = [
    { label: '1K queries/day', queries: 1000 },
    { label: '10K queries/day', queries: 10000 },
    { label: '100K queries/day', queries: 100000 },
    { label: '1M queries/month', queries: 1000000 }
  ];

  scales.forEach(scale => {
    const v5Cost = scale.queries * v5AvgCost;
    const v6ColdCost = scale.queries * v6AvgCost;
    const v6WarmCost = scale.queries * v6ProjectedAvgCost;

    console.log(`${scale.label}:`);
    console.log(`  V5: $${v5Cost.toFixed(2)}`);
    console.log(`  V6 (cold): $${v6ColdCost.toFixed(2)}`);
    console.log(`  V6 (warm 80%): $${v6WarmCost.toFixed(2)}`);
    console.log();
  });

  // Comprehensive Summary Table
  console.log('━'.repeat(80));
  console.log('COMPREHENSIVE EVALUATION MATRIX');
  console.log('━'.repeat(80));
  console.log();

  console.log('┌─────────────────────────┬──────────────┬──────────────┬────────────────┐');
  console.log('│ Metric                  │ V5 (Rules)   │ V6 (Hybrid)  │ Improvement    │');
  console.log('├─────────────────────────┼──────────────┼──────────────┼────────────────┤');
  console.log(`│ Accuracy                │ ${(results.v5.passed/testScenarios.length*100).toFixed(1).padEnd(12)}%│ ${(results.v6.passed/testScenarios.length*100).toFixed(1).padEnd(12)}%│ ${improvementPct.padEnd(14)}%│`);
  console.log(`│ Avg Latency             │ ${v5Latency.avg.toFixed(1).padEnd(10)}ms │ ${v6Latency.avg.toFixed(1).padEnd(10)}ms │ +${((v6Latency.avg - v5Latency.avg)/v5Latency.avg*100).toFixed(0).padEnd(13)}%│`);
  console.log(`│ P95 Latency             │ ${v5Latency.p95.toFixed(1).padEnd(10)}ms │ ${v6Latency.p95.toFixed(1).padEnd(10)}ms │ ${'-'.padEnd(14)} │`);
  console.log(`│ Cost per Query          │ $${v5AvgCost.toFixed(6).padEnd(11)} │ $${v6ProjectedAvgCost.toFixed(6).padEnd(11)} │ ${'-'.padEnd(14)} │`);
  console.log(`│ Cost (1M queries/month) │ $${(v5AvgCost * 1000000).toFixed(2).padEnd(11)} │ $${(v6ProjectedAvgCost * 1000000).toFixed(2).padEnd(11)} │ +$${((v6ProjectedAvgCost - v5AvgCost) * 1000000).toFixed(2).padEnd(12)} │`);
  console.log('└─────────────────────────┴──────────────┴──────────────┴────────────────┘');
  console.log();

  // Save results
  const fs = require('fs');
  const summaryPath = '/home/yzhang/biomate/auto_update/docs/hybrid_mode_detection_1000_test/v6_enhanced_evaluation_results.json';

  fs.writeFileSync(summaryPath, JSON.stringify({
    timestamp: new Date().toISOString(),
    testSize: testScenarios.length,
    duration: totalDuration,
    accuracy: {
      v5: {
        passed: results.v5.passed,
        failed: results.v5.failed,
        accuracy: (results.v5.passed / testScenarios.length * 100).toFixed(2) + '%'
      },
      v6: {
        passed: results.v6.passed,
        failed: results.v6.failed,
        accuracy: (results.v6.passed / testScenarios.length * 100).toFixed(2) + '%',
        fastRuleCalls: results.v6.fastRuleCalls,
        llmCalls: results.v6.llmCalls
      },
      improvement: {
        absolute: improvement,
        percentage: improvementPct + '%'
      }
    },
    latency: {
      v5: v5Latency,
      v6: {
        overall: v6Latency,
        fastRule: v6FastRuleLatency,
        llm: v6LlmLatency
      }
    },
    cost: {
      v5: {
        perQuery: v5AvgCost,
        total: v5TotalCost
      },
      v6: {
        perQuery: v6AvgCost,
        perQueryProjected: v6ProjectedAvgCost,
        total: v6TotalCost,
        totalProjected: v6ProjectedCost,
        cacheHitRate: (cacheHitRate * 100).toFixed(1) + '%'
      }
    },
    projections: {
      '1K_queries_day': {
        v5: v5AvgCost * 1000,
        v6_warm: v6ProjectedAvgCost * 1000
      },
      '1M_queries_month': {
        v5: v5AvgCost * 1000000,
        v6_warm: v6ProjectedAvgCost * 1000000
      }
    }
  }, null, 2));

  console.log('━'.repeat(80));
  console.log(`Results saved to: ${summaryPath}`);
  console.log('━'.repeat(80));

  return results;
}

// =============================================================================
// Main
// =============================================================================

if (require.main === module) {
  // Allow sample size as command line argument
  const sampleSize = process.argv[2] ? parseInt(process.argv[2]) : null;

  runEnhancedEvaluation(sampleSize)
    .then(results => {
      process.exit(0);
    })
    .catch(error => {
      console.error('Test failed:', error);
      process.exit(1);
    });
}

module.exports = { runEnhancedEvaluation };
