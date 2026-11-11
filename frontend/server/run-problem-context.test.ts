import { describe, expect, it } from 'vitest';
import { asksAboutRunProblem, runErrorSummary, runFailureExplanation } from './galaxy-assistant';

// External users asked "why is the run failing?" (3×) and got literature answers; the failure reasons
// recorded on their runs were "Could not resolve Nextflow script …" and, for nf-core/mag, a log whose
// only user-facing line was "Caused by:". Run-problem turns now get the runs WITH a specific error line.
describe('asksAboutRunProblem', () => {
  it.each([
    'why is the run failing?',
    'My workflow keeps failing after 2 minutes',
    'the job is stuck at 0%',
    'What does this error mean?',
    '为什么任务失败了？',
    '工作流运行报错',
  ])('%s → true', m => expect(asksAboutRunProblem(m)).toBe(true));
  it.each([
    'Run DESeq2 on my counts',
    'What is the failure rate of CAR-T therapy?',
    'Find papers on sepsis single-cell data',
  ])('%s → false', m => expect(asksAboutRunProblem(m)).toBe(false));
});

describe('runErrorSummary', () => {
  it('reports the failed Nextflow process and the specific message, never a bare "Caused by:"', () => {
    const e = {
      error: 'Caused by:',
      nextflowLog: [
        "ERROR ~ Error executing process > 'METABAT2'",
        'Caused by:',
        'Nov-01 15:04:00.238 [main] DEBUG nextflow.util.RetryConfig - Missing nextflow session',
        "  Process `METABAT2` terminated with an error exit status (1) — input file assembly.fa is empty",
      ],
      processes: [{ id: '1', name: 'METABAT2', status: 'FAILED' }],
    };
    const s = runErrorSummary(e);
    expect(s).toContain('process METABAT2 failed');
    expect(s).toContain('input file assembly.fa is empty');
    expect(s).not.toMatch(/^Caused by/);
  });
  it('uses the submit-time error when there was no run', () => {
    expect(runErrorSummary({ error: "Nextflow execution failed (404): Could not resolve Nextflow script 'nfcore/diaproteomics/main.nf'." }))
      .toContain('Could not resolve Nextflow script');
  });
  it('says so when nothing was recorded', () => {
    expect(runErrorSummary({ error: 'Caused by:' })).toMatch(/no recorded error message/);
  });
});

// Issue #3 (2026-11-09): "why is the run failing?" must get a plain-language cause +
// the input at fault + a next action in ONE message — composed from the run's real
// error, not a generic "failed" / "resume from last step". runFailureExplanation is
// what the assistant relays (and what the recent-runs-with-errors block carries).
describe('runFailureExplanation', () => {
  it('explains a bad-contrast failure with cause + at-fault column + next action', () => {
    const e = {
      status: 'failed',
      error: 'The following contrast variables are not present in the sample sheet: condition',
      processes: [{ id: '1', name: 'DIFFERENTIALABUNDANCE', status: 'FAILED' }],
    };
    const reply = runFailureExplanation(e)!;
    expect(reply).toMatch(/Why it failed:/);
    expect(reply).toMatch(/condition/);           // the specific at-fault column
    expect(reply).toMatch(/sample ?sheet/i);
    expect(reply).toMatch(/Next:/);               // concrete next action
    expect(reply).not.toMatch(/resume from (?:the )?last step/i);
    expect(reply).not.toMatch(/^failed$/i);
  });

  it('explains a missing-input-file failure and names the file', () => {
    const reply = runFailureExplanation({
      status: 'error',
      nextflowLog: ['No such file or directory: /data/SRR999_R1.fastq.gz'],
    })!;
    expect(reply).toMatch(/could not be found/i);
    expect(reply).toMatch(/SRR999_R1\.fastq\.gz/);
    expect(reply).toMatch(/Next:/);
  });

  it('does not invent a cause for an unknown error — shows the step + raw error', () => {
    const reply = runFailureExplanation({
      status: 'failed',
      error: "Error executing process > 'MYSTERY'\nopaque failure with no rule",
    })!;
    expect(reply).toMatch(/MYSTERY/);
    expect(reply).toMatch(/Error:/);
    expect(reply).toMatch(/investigate|can't pin/i);
  });

  it('returns null for a run that did not fail', () => {
    expect(runFailureExplanation({ status: 'completed' })).toBeNull();
  });
});

import { replyLanguageNote } from './galaxy-assistant';
describe('replyLanguageNote', () => {
  it('names Chinese for a Chinese request even with English attachment blocks after it', () => {
    const m = '请帮我比较两组细胞活力并画图\n\n[Attached files: cell_viability.csv]\n[Uploaded datasets: cell_viability.csv: dataset_id=u1, galaxy_dataset_id=g1]';
    expect(replyLanguageNote(m)).toContain('Chinese');
  });
  it('names Russian / Japanese / Korean by script', () => {
    expect(replyLanguageNote('найди эволюцию генов у рыб')).toContain('Russian');
    expect(replyLanguageNote('この遺伝子の発現を解析してください')).toContain('Japanese');
    expect(replyLanguageNote('이 데이터를 분석해 주세요')).toContain('Korean');
  });
  it('falls back to the general rule for Latin-script languages', () => {
    expect(replyLanguageNote("scrivimi l'abstract per ESTRO 2027")).toMatch(/language of the user's own words above/);
    expect(replyLanguageNote('Run DESeq2 on my counts')).toMatch(/language of the user's own words above/);
  });
});
