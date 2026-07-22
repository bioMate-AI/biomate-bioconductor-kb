import { describe, it, expect } from 'vitest';
import { stripNarratedToolCalls, StreamToolCallFilter } from './galaxy-assistant';

// Regression for the "reading PDF leaks tool internals" bug: the model sometimes
// NARRATES a tool call as prose text (Anthropic <function_calls>/<invoke> XML plus
// ad-hoc PyPDF2 code) instead of emitting a structured tool_use block, and that raw
// text leaked into the user-visible answer. Both the whole-text sanitizer and the
// streaming filter must strip it while preserving the real answer.

const LEAK = [
  'Let me extract the methods.',
  '<function_calls>',
  '<invoke name="run_code">',
  '<parameter name="code">import PyPDF2',
  "lines = text.split('\\n')",
  'print(text[:5000])</parameter>',
  '</invoke>',
  '</function_calls>',
  '',
  'Based on the attached paper, the protein purification protocol is: Ni-NTA affinity capture followed by TEV cleavage.',
].join('\n');

const REAL_ANSWER = 'Based on the attached paper, the protein purification protocol is: Ni-NTA affinity capture followed by TEV cleavage.';

describe('stripNarratedToolCalls', () => {
  it('removes a narrated <function_calls> block but keeps the real answer', () => {
    const out = stripNarratedToolCalls(LEAK);
    expect(out).not.toContain('<function_calls');
    expect(out).not.toContain('<invoke');
    expect(out).not.toContain('PyPDF2');
    expect(out).toContain('Ni-NTA affinity capture');
  });

  it('is a no-op for clean text', () => {
    const clean = 'The gene TP53 is a tumor suppressor. See [1].';
    expect(stripNarratedToolCalls(clean)).toBe(clean);
  });

  it('does not eat prose containing a bare < comparison', () => {
    const t = 'hERG IC50 < 10 µM is a flag; keep it.';
    expect(stripNarratedToolCalls(t)).toBe(t);
  });

  it('strips an unclosed opener that runs to the end', () => {
    const t = 'Reading now.\n<invoke name="read_file">\n<parameter name="dataset_id">abc';
    const out = stripNarratedToolCalls(t);
    expect(out).toBe('Reading now.');
  });

  it('strips orphan closing tags', () => {
    const t = 'Answer here.</function_calls>';
    expect(stripNarratedToolCalls(t)).toBe('Answer here.');
  });
});

describe('StreamToolCallFilter', () => {
  // Feed the leak one small chunk at a time (simulating token deltas) and assert
  // the reassembled stream contains the answer and none of the tool-call XML/code.
  function runStream(text: string, chunkSize: number): string {
    const f = new StreamToolCallFilter();
    let out = '';
    for (let i = 0; i < text.length; i += chunkSize) {
      out += f.push(text.slice(i, i + chunkSize));
    }
    out += f.flush();
    return out;
  }

  for (const chunk of [1, 3, 7, 50]) {
    it(`suppresses the leak across ${chunk}-char chunks`, () => {
      const out = runStream(LEAK, chunk);
      expect(out).not.toContain('<function_calls');
      expect(out).not.toContain('<invoke');
      expect(out).not.toContain('PyPDF2');
      expect(out).toContain('Ni-NTA affinity capture');
    });
  }

  it('passes clean streamed text through unchanged', () => {
    const clean = 'The answer is 42, computed from the counts matrix.';
    expect(runStream(clean, 4)).toBe(clean);
  });

  it('does not corrupt a bare < comparison mid-stream', () => {
    const t = 'padj < 0.05 and log2FC > 1.5 are the thresholds.';
    expect(runStream(t, 2)).toBe(t);
  });
});

describe('multi-block / multi-round leak scenarios', () => {
  // Reading MULTIPLE files in one turn produces several narrated tool calls.
  it('strips several interleaved <function_calls> blocks, keeps every answer segment', () => {
    const t = [
      'First, paper A.',
      '<function_calls><invoke name="read_file"><parameter name="dataset_id">a</parameter></invoke></function_calls>',
      'Paper A uses Ni-NTA capture.',
      'Now paper B.',
      '<function_calls><invoke name="read_file"><parameter name="dataset_id">b</parameter></invoke></function_calls>',
      'Paper B uses size-exclusion chromatography.',
    ].join('\n');
    const out = stripNarratedToolCalls(t);
    expect(out).not.toMatch(/<function_calls|<invoke|dataset_id/);
    expect(out).toContain('Paper A uses Ni-NTA capture.');
    expect(out).toContain('Paper B uses size-exclusion chromatography.');
    expect(out).toContain('First, paper A.');
    expect(out).toContain('Now paper B.');
  });

  // Simulate a 3-round conversation where each round's raw completion leaks.
  // The sanitized text is what gets persisted to history, so replayed history
  // must never accumulate tool-call XML (the self-reinforcement loop).
  it('keeps replayed history clean across 3 rounds', () => {
    const rawRounds = [
      'Round 1 answer.\n<function_calls><invoke name="run_code"><parameter name="code">x=1</parameter></invoke></function_calls>',
      '<function_calls><invoke name="read_file"><parameter name="dataset_id">p</parameter></invoke></function_calls>\nRound 2 answer.',
      'Round 3 answer, no tools.',
    ];
    const persistedHistory: string[] = [];
    for (const raw of rawRounds) {
      // This mirrors what generateResponse persists: the sanitized message.
      persistedHistory.push(stripNarratedToolCalls(raw));
    }
    const joined = persistedHistory.join('\n---\n');
    expect(joined).not.toMatch(/<function_calls|<invoke|<parameter|run_code|dataset_id/);
    expect(persistedHistory[0]).toBe('Round 1 answer.');
    expect(persistedHistory[1]).toBe('Round 2 answer.');
    expect(persistedHistory[2]).toBe('Round 3 answer, no tools.');
  });

  it('streaming filter handles two leak blocks split across tiny chunks', () => {
    const t = 'A.\n<function_calls><invoke name="read_file"></invoke></function_calls>\nB.\n<function_calls><invoke name="run_code"></invoke></function_calls>\nC.';
    const f = new StreamToolCallFilter();
    let out = '';
    for (const ch of t) out += f.push(ch);
    out += f.flush();
    expect(out).not.toMatch(/<function_calls|<invoke/);
    expect(out).toContain('A.');
    expect(out).toContain('B.');
    expect(out).toContain('C.');
  });
});
