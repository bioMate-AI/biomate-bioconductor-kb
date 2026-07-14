/**
 * Information Need Routing Tests
 *
 * Tests the mapping from 22 information need types to action category flags.
 * Verifies that inferActionsFromType() returns correct flags and that
 * the action-flag-based routing would invoke the right backends.
 *
 * Run: cd frontend && npx tsx server/test-information-needs.ts
 */

import { inferActionsFromType, type ActionCategories } from './galaxy-assistant';

// ============================================================================
// Test Helpers
// ============================================================================

let testCount = 0;
let passCount = 0;
let failCount = 0;

function assert(condition: boolean, label: string, detail?: string) {
  testCount++;
  if (condition) {
    passCount++;
    console.log(`  \u2713 ${label}`);
  } else {
    failCount++;
    console.log(`  \u2717 FAIL: ${label}${detail ? ` (${detail})` : ''}`);
  }
}

function header(title: string) {
  console.log('\n' + '='.repeat(72));
  console.log(`  ${title}`);
  console.log('='.repeat(72));
}

function printActions(type: string, actions: ActionCategories) {
  const flags = Object.entries(actions)
    .filter(([_, v]) => v)
    .map(([k]) => k.replace('needs', '').replace('Agent', ''))
    .join(', ');
  console.log(`  [${type}] -> ${flags}`);
}

// ============================================================================
// Information Need Test Matrix
// ============================================================================

interface NeedTestCase {
  type: string;
  label: string;
  expectedFlags: {
    toolSearch?: boolean;
    workflowGen?: boolean;
    workflowMod?: boolean;
    research?: boolean;
    benchmark?: boolean;
    dataset?: boolean;
    llm?: boolean;
  };
  description: string;
}

// NOTE (2026-07): expectations aligned with the action-flag routing redesign in
// galaxy-assistant.ts `inferActionsFromType` (commit c6fceb828, 2026-04-07).
// Two design decisions the original 2026-02 expectations predated:
//   1. workflow-generation-type intents (workflow_generation, data_format_conversion,
//      external_db_retrieval, visualization, multi_step_procedure) do NOT set
//      needsToolSearch — the backend's generate_workflow searches its own tool
//      index internally, so a separate frontend tool search is redundant.
//   2. comparison intents (result_comparison, comparative_methodology) route to the
//      ResearchAgent (literature/reasoning), NOT the BenchmarkAgent (harness runs).
// These stale expectations were masked for months because db.ts crashed this gate
// at import before it could run (fixed in the lazy-init change).
const testCases: NeedTestCase[] = [
  {
    type: 'workflow_generation',
    label: '1. Build/Run Analysis',
    expectedFlags: { toolSearch: false, workflowGen: true, llm: true },
    description: 'Run DE analysis on my RNA-seq data',
  },
  {
    type: 'workflow_modification',
    label: '2. Modify Workflow',
    expectedFlags: { toolSearch: true, workflowMod: true, llm: true },
    description: 'Add a QC step to the workflow',
  },
  {
    type: 'tool_search',
    label: '3. Find Tools',
    expectedFlags: { toolSearch: true, llm: true, workflowGen: false },
    description: 'What tools can do peak calling?',
  },
  {
    type: 'research_question',
    label: '4. Literature Search',
    expectedFlags: { research: true, llm: true, toolSearch: false },
    description: 'Search PubMed for CRISPR delivery methods',
  },
  {
    type: 'result_comparison',
    label: '5. Tool Comparison',
    expectedFlags: { research: true, benchmark: false, llm: true },
    description: 'How does Bowtie2 compare to BWA?',
  },
  {
    type: 'benchmark_query',
    label: '6. Performance Benchmarks',
    expectedFlags: { benchmark: true, llm: true },
    description: 'What is the accuracy of BWA-MEM on Illumina data?',
  },
  {
    type: 'dataset_inquiry',
    label: '7. Dataset Discovery',
    expectedFlags: { dataset: true, llm: true },
    description: 'What datasets do you have for mouse RNA-seq?',
  },
  {
    type: 'general_question',
    label: '8. General/Conversational',
    expectedFlags: { llm: true, toolSearch: false, research: false, benchmark: false },
    description: 'What is RNA-seq?',
  },
  {
    type: 'troubleshooting',
    label: '9. Troubleshooting',
    expectedFlags: { research: true, toolSearch: true, llm: true },
    description: 'My alignment rate is only 30%, what could be wrong?',
  },
  {
    type: 'experiment_design',
    label: '10. Experiment Design',
    expectedFlags: { research: true, llm: true },
    description: 'How should I design a CRISPR screen experiment?',
  },
  {
    type: 'data_interpretation',
    label: '11. Data Interpretation',
    expectedFlags: { research: true, llm: true },
    description: 'What do these volcano plot results mean?',
  },
  {
    type: 'protocol_guidance',
    label: '12. Protocol Guidance',
    expectedFlags: { research: true, llm: true },
    description: 'What is the protocol for ChIP-seq library prep?',
  },
  {
    type: 'parameter_optimization',
    label: '13. Parameter Optimization',
    expectedFlags: { benchmark: true, research: true, toolSearch: true, llm: true },
    description: 'What parameters should I use for BWA-MEM with short reads?',
  },
  {
    type: 'data_format_conversion',
    label: '14. Data Format/Conversion',
    expectedFlags: { toolSearch: false, workflowGen: true, llm: true },
    description: 'Convert my BAM file to FASTQ',
  },
  {
    type: 'external_db_retrieval',
    label: '15. External DB Retrieval',
    expectedFlags: { toolSearch: false, workflowGen: true, llm: true },
    description: 'Download the hg38 reference genome from UCSC',
  },
  {
    type: 'teaching_explanation',
    label: '16. Teaching/Explanation',
    expectedFlags: { llm: true, research: false },
    description: 'Explain the central dogma of molecular biology',
  },
  {
    type: 'methods_writing',
    label: '17. Methods Writing',
    expectedFlags: { research: true, llm: true },
    description: 'Help me write the methods section for RNA-seq analysis',
  },
  {
    type: 'visualization',
    label: '18. Visualization',
    expectedFlags: { toolSearch: false, workflowGen: true, llm: true },
    description: 'Create a heatmap of my gene expression data',
  },
  {
    type: 'comparative_methodology',
    label: '19. Comparative Methodology',
    expectedFlags: { research: true, benchmark: false, llm: true },
    description: 'Compare single-cell vs bulk RNA-seq approaches for tumor profiling',
  },
  {
    type: 'regulatory_compliance',
    label: '20. Regulatory/Compliance',
    expectedFlags: { research: true, llm: true },
    description: 'What are the FDA guidelines for NGS-based companion diagnostics?',
  },
  {
    type: 'cost_estimation',
    label: '21. Cost Estimation',
    expectedFlags: { benchmark: true, llm: true },
    description: 'How much does WGS cost per sample at 30x coverage?',
  },
  {
    type: 'multi_step_procedure',
    label: '22. Multi-Step Procedure',
    expectedFlags: { toolSearch: false, workflowGen: true, llm: true },
    description: 'Build a pipeline: QC, trimming, alignment, counting, DE',
  },
];

// ============================================================================
// Run Tests
// ============================================================================

function runInformationNeedTests() {
  console.log('\n\u2554' + '\u2550'.repeat(70) + '\u2557');
  console.log('\u2551         Information Need Routing Test Matrix                       \u2551');
  console.log('\u255A' + '\u2550'.repeat(70) + '\u255D');

  header('Action Category Flag Mapping (22 information need types)');

  for (const tc of testCases) {
    console.log(`\n  ${tc.label}: "${tc.description}"`);
    const actions = inferActionsFromType(tc.type);
    printActions(tc.type, actions);

    const ef = tc.expectedFlags;

    if (ef.toolSearch !== undefined) {
      assert(actions.needsToolSearch === ef.toolSearch,
        `${tc.type}: needsToolSearch = ${ef.toolSearch}`,
        `got ${actions.needsToolSearch}`);
    }
    if (ef.workflowGen !== undefined) {
      assert(actions.needsWorkflowGeneration === ef.workflowGen,
        `${tc.type}: needsWorkflowGeneration = ${ef.workflowGen}`,
        `got ${actions.needsWorkflowGeneration}`);
    }
    if (ef.workflowMod !== undefined) {
      assert(actions.needsWorkflowModification === ef.workflowMod,
        `${tc.type}: needsWorkflowModification = ${ef.workflowMod}`,
        `got ${actions.needsWorkflowModification}`);
    }
    if (ef.research !== undefined) {
      assert(actions.needsResearchAgent === ef.research,
        `${tc.type}: needsResearchAgent = ${ef.research}`,
        `got ${actions.needsResearchAgent}`);
    }
    if (ef.benchmark !== undefined) {
      assert(actions.needsBenchmarkAgent === ef.benchmark,
        `${tc.type}: needsBenchmarkAgent = ${ef.benchmark}`,
        `got ${actions.needsBenchmarkAgent}`);
    }
    if (ef.dataset !== undefined) {
      assert(actions.needsDatasetAccess === ef.dataset,
        `${tc.type}: needsDatasetAccess = ${ef.dataset}`,
        `got ${actions.needsDatasetAccess}`);
    }
    if (ef.llm !== undefined) {
      assert(actions.needsLLMReasoning === ef.llm,
        `${tc.type}: needsLLMReasoning = ${ef.llm}`,
        `got ${actions.needsLLMReasoning}`);
    }
  }

  // Additional: verify unknown types default properly
  header('Edge Cases: Unknown Information Need Types');

  const unknownTypes = ['protein_folding_prediction', 'grant_writing', 'lab_inventory'];
  for (const type of unknownTypes) {
    const actions = inferActionsFromType(type);
    printActions(type, actions);
    assert(actions.needsLLMReasoning === true, `${type}: defaults to LLM reasoning`);
    assert(actions.needsToolSearch === false, `${type}: no tool search by default`);
    assert(actions.needsResearchAgent === false, `${type}: no research by default`);
    assert(actions.needsBenchmarkAgent === false, `${type}: no benchmark by default`);
    assert(actions.needsWorkflowGeneration === false, `${type}: no workflow gen by default`);
  }

  // Verify all actions are composable (no mutual exclusion)
  header('Composability: Multiple Agents Can Be Invoked');

  const paramOpt = inferActionsFromType('parameter_optimization');
  const activeAgents = Object.entries(paramOpt).filter(([_, v]) => v).length;
  assert(activeAgents === 4, `parameter_optimization activates 4 agents (got ${activeAgents})`);

  const compMeth = inferActionsFromType('comparative_methodology');
  const compAgents = Object.entries(compMeth).filter(([_, v]) => v).length;
  // comparative_methodology routes to ResearchAgent + LLM (2 agents). It does
  // NOT invoke the BenchmarkAgent — comparing methodologies is a literature/
  // reasoning task, not a benchmark-harness run (see inferActionsFromType).
  assert(compAgents === 2, `comparative_methodology activates 2 agents (got ${compAgents})`);

  // Summary
  console.log('\n' + '='.repeat(72));
  console.log(`  Results: ${passCount}/${testCount} passed, ${failCount} failed`);
  console.log('='.repeat(72));

  if (failCount > 0) {
    process.exit(1);
  }
}

runInformationNeedTests();
