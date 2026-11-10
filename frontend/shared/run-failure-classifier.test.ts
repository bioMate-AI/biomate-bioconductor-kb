import { describe, expect, it } from 'vitest';
import { classifyRunFailure, formatRunFailureReply } from './run-failure-classifier';

describe('classifyRunFailure — plain-language cause + remediation per class', () => {
  it('bad contrast: contrasts file references a column not in the sample sheet', () => {
    const exp = classifyRunFailure(
      "ERROR ~ The following contrast variables are not present in the sample sheet: condition\n" +
      "Caused by: process 'DIFFERENTIALABUNDANCE' terminated with an error exit status (1)",
    );
    expect(exp.klass).toBe('bad_contrast');
    expect(exp.known).toBe(true);
    expect(exp.cause).toMatch(/condition/);
    expect(exp.cause).toMatch(/sample ?sheet/i);
    expect(exp.nextAction).toMatch(/match|add|column/i);
  });

  it('missing column: expected column absent from the input table', () => {
    const exp = classifyRunFailure("Error: column 'gene_id' not found in counts matrix");
    expect(exp.klass).toBe('missing_column');
    expect(exp.cause).toMatch(/gene_id/);
    expect(exp.culprit).toMatch(/gene_id/);
  });

  it('missing input file: path does not exist', () => {
    const exp = classifyRunFailure("No such file or directory: /data/samples/SRR123_R1.fastq.gz");
    expect(exp.klass).toBe('missing_input_file');
    expect(exp.cause).toMatch(/could not be found/i);
    expect(exp.culprit).toMatch(/SRR123_R1\.fastq\.gz/);
    expect(exp.nextAction).toMatch(/exists|path|re-?upload/i);
  });

  it('empty input: a required input file is empty', () => {
    const exp = classifyRunFailure(
      "Process `METABAT2` terminated with an error exit status (1) — input file assembly.fa is empty",
      { process: 'METABAT2' },
    );
    expect(exp.klass).toBe('empty_input');
    expect(exp.culprit).toBe('assembly.fa');
    expect(exp.nextAction).toMatch(/non-empty|upload|replace/i);
  });

  it('out of memory: exit 137 / killed', () => {
    const exp = classifyRunFailure(
      "Error executing process > 'STAR_ALIGN'\nCommand terminated with an error exit status (137)",
    );
    expect(exp.klass).toBe('out_of_memory');
    expect(exp.cause).toMatch(/memory/i);
    expect(exp.nextAction).toMatch(/memory|instance|subset|downsample/i);
  });

  it('container/tool: command not found (exit 127)', () => {
    const exp = classifyRunFailure(
      "Error executing process > 'SALMON_QUANT'\n.command.sh: line 3: salmon: command not found\nexit status (127)",
    );
    expect(exp.klass).toBe('container_tool');
    expect(exp.cause).toMatch(/tool or container|command|image/i);
    expect(exp.nextAction).toMatch(/report|environment|container/i);
  });

  it('workflow not found: mis-routed nf-core path (the real U-MOFA 404)', () => {
    const exp = classifyRunFailure(
      "Nextflow execution failed (404): Could not resolve Nextflow script 'nfcore/diaproteomics/main.nf'.",
    );
    expect(exp.klass).toBe('workflow_not_found');
    expect(exp.cause).toMatch(/could not be loaded|does not exist|unavailable/i);
    expect(exp.culprit).toMatch(/diaproteomics/);
  });

  it('bad parameter: missing required parameter', () => {
    const exp = classifyRunFailure("ERROR: Missing required parameter --genome");
    expect(exp.klass).toBe('bad_parameter');
    expect(exp.nextAction).toMatch(/param/i);
  });

  it('UNKNOWN: never invents a cause — reports the step and surfaces the raw error', () => {
    const exp = classifyRunFailure(
      "Error executing process > 'MYSTERY_STEP'\nSome opaque failure nobody has a rule for",
    );
    expect(exp.klass).toBe('unknown');
    expect(exp.known).toBe(false);
    expect(exp.cause).toBe('');
    expect(exp.process).toBe('MYSTERY_STEP');
    const reply = formatRunFailureReply(exp);
    expect(reply).toMatch(/MYSTERY_STEP/);
    expect(reply).toMatch(/can't pin a specific cause|investigate/i);
    expect(reply).toMatch(/Error:/); // raw error shown, not hidden
  });

  it('no recorded error: says so, does not guess', () => {
    const exp = classifyRunFailure('Caused by:');
    expect(exp.known).toBe(false);
    expect(exp.nextAction).toMatch(/no error message was captured|task log/i);
  });
});

describe('formatRunFailureReply — one message with cause + at-fault + next action', () => {
  it('composes a legible reply a first-time user can act on', () => {
    const exp = classifyRunFailure(
      "The following contrast variables are not present in the sample sheet: condition",
    );
    const reply = formatRunFailureReply(exp);
    expect(reply).toMatch(/Why it failed:/);
    expect(reply).toMatch(/Next:/);
    expect(reply).toMatch(/condition/);
    // not a bare "failed" / "resume" answer
    expect(reply).not.toMatch(/^failed$/i);
    expect(reply).not.toMatch(/resume from (?:the )?last step/i);
  });
});
