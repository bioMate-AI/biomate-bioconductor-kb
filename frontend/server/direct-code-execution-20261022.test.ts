/**
 * Regression test for the run_code fabrication bug (2026-10-22).
 *
 * Root cause: `_isDirectCodeExecutionQuery` ran its pipeline-exclusion regex over the WHOLE
 * message, so an explicit "Use run_code … Do NOT launch a Nextflow workflow" prompt (the BixBench
 * exec prompt) was misread as a pipeline request — the word "nextflow" inside the negated
 * directive tripped the exclusion → the direct-compute override never fired → a workflow card was
 * generated → hasRunnableWorkflow disabled run_code → the model printed code as text and
 * fabricated the answer. See docs/20261022_BIXBENCH_AISCIENTIST_RUN_FINDINGS.md.
 */
import { describe, it, expect } from 'vitest';
import { GalaxyAssistant } from './galaxy-assistant';

describe('_isDirectCodeExecutionQuery — negated-pipeline must not disable run_code', () => {
  // The method is a pure string predicate (does not use `this`), so call it via the prototype
  // with a bare receiver — avoids the constructor (which instantiates the Anthropic SDK and
  // throws in the jsdom test env).
  const fn = (GalaxyAssistant as any).prototype._isDirectCodeExecutionQuery as (m: string) => boolean;
  const isDirect = (m: string) => fn.call({}, m);

  it('treats "Use run_code … Do NOT launch a Nextflow workflow" as direct-compute', () => {
    // the exact shape of the BixBench exec prompt that regressed
    expect(isDirect(
      'Use run_code (Python) to extract the adjusted p-value for the DESeq2 result. ' +
      'Do NOT launch a Nextflow workflow. Reply with ONLY: ANSWER: <value>',
    )).toBe(true);
  });

  it('"compute the mean of [2,4,6,8], not a pipeline" is direct-compute (negated pipeline ignored)', () => {
    expect(isDirect('Use run_code to compute the mean of [2,4,6,8]. This is ad-hoc, not a pipeline.')).toBe(true);
  });

  it('a bare "do not generate a workflow" directive alone is direct-compute', () => {
    expect(isDirect('Parse this notebook and report the number. Do not generate a workflow.')).toBe(true);
  });

  it('still routes a GENUINE pipeline request away from direct-compute', () => {
    // explicit run_code phrasing absent, real pipeline ask → not direct-compute
    expect(isDirect('Run the nf-core/rnaseq pipeline on these FASTQ files')).toBe(false);
    // even with a code-block, a real DESeq2 *pipeline* ask (no no-workflow directive) stays guarded
    expect(isDirect('Run a full DESeq2 differential expression pipeline on my counts matrix')).toBe(false);
  });

  it('non-code conversational message is not direct-compute', () => {
    expect(isDirect('What is the capital of France?')).toBe(false);
  });
});
