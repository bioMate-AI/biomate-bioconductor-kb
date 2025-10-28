/**
 * Unit tests for WorkflowAdapter
 * Run with: npx tsx test-workflow-adapter.ts
 */

import { WorkflowAdapter, adaptWorkflow, type StandardWorkflow } from './client/src/lib/workflow-adapter';

// Test data
const demoWorkflow = {
  id: 'demo-1',
  title: 'RNA-seq Analysis',
  description: 'Complete RNA-seq pipeline',
  type: 'rna-seq',
  steps: [
    {
      id: 'step1',
      title: 'Quality Control',
      description: 'Run FastQC',
      tool: 'FastQC',
      complexity: 'simple',
      estimatedTime: '5 min'
    },
    {
      id: 'step2',
      title: 'Alignment',
      description: 'Align with HISAT2',
      tool: 'HISAT2',
      complexity: 'intermediate',
      estimatedTime: '15 min'
    }
  ]
};

const galaxyWorkflow = {
  uuid: 'galaxy-uuid-123',
  name: 'RNA-seq DE Analysis',
  annotation: 'Differential expression workflow',
  'format-version': '0.1',
  steps: {
    '0': {
      id: 0,
      name: 'Input Dataset Collection',
      type: 'data_collection_input',
      tool_id: null,
      annotation: 'Input files',
      position: { x: 100, y: 100 }
    },
    '1': {
      id: 1,
      name: 'FastQC',
      type: 'tool',
      tool_id: 'toolshed.g2.bx.psu.edu/repos/devteam/fastqc/fastqc/0.72',
      annotation: 'Quality control',
      position: { x: 300, y: 100 }
    }
  }
};

// Test runner
class TestRunner {
  passed = 0;
  failed = 0;
  tests: Array<{ name: string; passed: boolean; error?: string }> = [];

  test(name: string, fn: () => void) {
    try {
      fn();
      this.passed++;
      this.tests.push({ name, passed: true });
      console.log(`✅ ${name}`);
    } catch (error: any) {
      this.failed++;
      this.tests.push({ name, passed: false, error: error.message });
      console.log(`❌ ${name}`);
      console.log(`   Error: ${error.message}`);
    }
  }

  assert(condition: boolean, message: string) {
    if (!condition) {
      throw new Error(message);
    }
  }

  assertEqual(actual: any, expected: any, message: string) {
    if (actual !== expected) {
      throw new Error(`${message}: expected ${expected}, got ${actual}`);
    }
  }

  assertDefined(value: any, message: string) {
    if (value === undefined || value === null) {
      throw new Error(`${message}: value is undefined or null`);
    }
  }

  summary() {
    console.log(`\n${'='.repeat(50)}`);
    console.log(`Test Results: ${this.passed} passed, ${this.failed} failed`);
    console.log(`${'='.repeat(50)}\n`);

    if (this.failed > 0) {
      console.log('Failed tests:');
      this.tests.filter(t => !t.passed).forEach(t => {
        console.log(`  - ${t.name}: ${t.error}`);
      });
      process.exit(1);
    } else {
      console.log('All tests passed! ✨');
      process.exit(0);
    }
  }
}

// Run tests
const runner = new TestRunner();

console.log('\n🧪 Running WorkflowAdapter Unit Tests\n');

runner.test('fromDemoWorkflow: converts basic structure', () => {
  const result = WorkflowAdapter.fromDemoWorkflow(demoWorkflow);

  runner.assertEqual(result.id, 'demo-1', 'ID should match');
  runner.assertEqual(result.name, 'RNA-seq Analysis', 'Name should match');
  runner.assertEqual(result.description, 'Complete RNA-seq pipeline', 'Description should match');
  runner.assertEqual(result.steps.length, 2, 'Should have 2 steps');
});

runner.test('fromDemoWorkflow: converts steps correctly', () => {
  const result = WorkflowAdapter.fromDemoWorkflow(demoWorkflow);

  const step1 = result.steps[0];
  runner.assertEqual(step1.id, 'step1', 'Step 1 ID should match');
  runner.assertEqual(step1.name, 'Quality Control', 'Step 1 name should match');
  runner.assertEqual(step1.tool, 'FastQC', 'Step 1 tool should match');
  runner.assertEqual(step1.type, 'tool', 'Step 1 type should be tool');
  runner.assertDefined(step1.toolId, 'Step 1 should have Galaxy tool ID');
});

runner.test('fromDemoWorkflow: handles missing optional fields', () => {
  const minimalDemo = {
    steps: [{ tool: 'FastQC' }]
  };

  const result = WorkflowAdapter.fromDemoWorkflow(minimalDemo);

  runner.assert(result.id.startsWith('workflow-'), 'Should generate ID');
  runner.assertEqual(result.name, 'Untitled Workflow', 'Should use default name');
  runner.assertEqual(result.steps[0].id, 'step0', 'Should generate step ID');
});

runner.test('fromGalaxyGA: converts basic structure', () => {
  const result = WorkflowAdapter.fromGalaxyGA(galaxyWorkflow);

  runner.assertEqual(result.id, 'galaxy-uuid-123', 'ID should match UUID');
  runner.assertEqual(result.name, 'RNA-seq DE Analysis', 'Name should match');
  runner.assertEqual(result.annotation, 'Differential expression workflow', 'Annotation should match');
  runner.assertEqual(result.steps.length, 2, 'Should have 2 steps');
});

runner.test('fromGalaxyGA: converts steps correctly', () => {
  const result = WorkflowAdapter.fromGalaxyGA(galaxyWorkflow);

  const step0 = result.steps[0];
  runner.assertEqual(step0.id, 'step0', 'Step 0 ID should be step0');
  runner.assertEqual(step0.name, 'Input Dataset Collection', 'Step 0 name should match');
  runner.assertEqual(step0.type, 'data_collection_input', 'Step 0 should be data input');

  const step1 = result.steps[1];
  runner.assertEqual(step1.id, 'step1', 'Step 1 ID should be step1');
  runner.assertEqual(step1.name, 'FastQC', 'Step 1 name should match');
  runner.assertEqual(step1.type, 'tool', 'Step 1 should be tool');
  runner.assertEqual(step1.tool, 'FastQC', 'Should extract tool name from ID');
  runner.assertEqual(step1.toolId, 'toolshed.g2.bx.psu.edu/repos/devteam/fastqc/fastqc/0.72', 'Should preserve full tool ID');
});

runner.test('toGalaxyGA: preserves original if available', () => {
  const standard = WorkflowAdapter.fromGalaxyGA(galaxyWorkflow);
  const converted = WorkflowAdapter.toGalaxyGA(standard);

  runner.assertEqual(converted.uuid, 'galaxy-uuid-123', 'Should preserve UUID');
  runner.assertEqual(converted.name, 'RNA-seq DE Analysis', 'Should preserve name');
  runner.assertDefined(converted.steps['0'], 'Should have step 0');
  runner.assertDefined(converted.steps['1'], 'Should have step 1');
});

runner.test('toGalaxyGA: constructs minimal format from demo', () => {
  const standard = WorkflowAdapter.fromDemoWorkflow(demoWorkflow);
  const converted = WorkflowAdapter.toGalaxyGA(standard);

  runner.assertEqual(converted.name, 'RNA-seq Analysis', 'Should use workflow name');
  runner.assertDefined(converted.steps['0'], 'Should have step 0');
  runner.assertDefined(converted.steps['1'], 'Should have step 1');
  runner.assertEqual(converted['format-version'], '0.1', 'Should have format version');
});

runner.test('adaptWorkflow: detects demo format', () => {
  const result = adaptWorkflow(demoWorkflow);

  runner.assertEqual(result.name, 'RNA-seq Analysis', 'Should convert demo workflow');
  runner.assertEqual(result.metadata?.source, 'demo', 'Should mark as demo source');
});

runner.test('adaptWorkflow: detects Galaxy format', () => {
  const result = adaptWorkflow(galaxyWorkflow);

  runner.assertEqual(result.name, 'RNA-seq DE Analysis', 'Should convert Galaxy workflow');
  runner.assertEqual(result.metadata?.source, 'galaxy', 'Should mark as galaxy source');
});

runner.test('validate: accepts valid workflow', () => {
  const standard = WorkflowAdapter.fromDemoWorkflow(demoWorkflow);
  const validation = WorkflowAdapter.validate(standard);

  runner.assert(validation.valid, 'Should be valid');
  runner.assertEqual(validation.errors.length, 0, 'Should have no errors');
});

runner.test('validate: rejects workflow without ID', () => {
  const invalid: any = { name: 'Test', steps: [{ id: 'step1', name: 'Step 1', tool: 'Tool1', type: 'tool' }] };
  const validation = WorkflowAdapter.validate(invalid);

  runner.assert(!validation.valid, 'Should be invalid');
  runner.assert(validation.errors.length > 0, 'Should have errors');
  runner.assert(validation.errors.some(e => e.includes('ID')), 'Should mention missing ID');
});

runner.test('validate: rejects workflow without steps', () => {
  const invalid: any = { id: '123', name: 'Test', steps: [] };
  const validation = WorkflowAdapter.validate(invalid);

  runner.assert(!validation.valid, 'Should be invalid');
  runner.assert(validation.errors.some(e => e.includes('at least one step')), 'Should mention missing steps');
});

runner.test('round-trip: demo -> standard -> Galaxy -> standard', () => {
  const standard1 = WorkflowAdapter.fromDemoWorkflow(demoWorkflow);
  const galaxy = WorkflowAdapter.toGalaxyGA(standard1);
  const standard2 = WorkflowAdapter.fromGalaxyGA(galaxy);

  runner.assertEqual(standard2.steps.length, standard1.steps.length, 'Should preserve step count');
  runner.assertEqual(standard2.steps[0].name, standard1.steps[0].name, 'Should preserve step names');
});

// Run summary
runner.summary();
