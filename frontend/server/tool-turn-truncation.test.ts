import { describe, it, expect } from 'vitest';
import { FINAL_ANSWER_INSTRUCTION, TRUNCATED_REPLY_INSTRUCTION, finalAnswerRequest, toolCallDisplayFor, truncatedTurnFollowUp } from './galaxy-assistant';

describe('truncatedTurnFollowUp (turn stopped on max_tokens)', () => {
  // Live shape (dev 2026-11-12, GLM via OpenRouter): narration + a tool_use cut mid-input.
  const cut = [
    { type: 'text', text: '现在让我生成可视化的 QC 报告：' },
    { type: 'tool_use', id: 'call_5', name: 'run_code', input: {} },
  ];
  it('keeps only the text (an unrun tool_use would need a tool_result) and asks to continue', () => {
    const [assistant, user] = truncatedTurnFollowUp(cut);
    expect(assistant).toEqual({ role: 'assistant', content: [{ type: 'text', text: '现在让我生成可视化的 QC 报告：' }] });
    expect(user).toEqual({ role: 'user', content: TRUNCATED_REPLY_INSTRUCTION });
  });
  it('an empty truncated turn still yields a valid assistant entry', () => {
    expect(truncatedTurnFollowUp([{ type: 'tool_use', id: 'x', name: 'run_code', input: {} }])[0].content).toEqual([{ type: 'text', text: ' ' }]);
    expect(truncatedTurnFollowUp(undefined)[0].content).toEqual([{ type: 'text', text: ' ' }]);
  });
  it('the final-answer turn after a truncation merges into the follow-up (no two user turns in a row)', () => {
    const transcript = [{ role: 'user', content: 'QC this image' }, ...truncatedTurnFollowUp(cut)];
    const req = finalAnswerRequest({ model: 'm', messages: [] }, transcript, [{ name: 'run_code' }]);
    expect(req.messages).toHaveLength(3);
    expect(req.messages[2]).toEqual({ role: 'user', content: [
      { type: 'text', text: TRUNCATED_REPLY_INSTRUCTION }, { type: 'text', text: FINAL_ANSWER_INSTRUCTION },
    ] });
    expect(transcript[2].content).toBe(TRUNCATED_REPLY_INSTRUCTION); // caller's transcript not mutated
  });
});

describe('toolCallDisplayFor — the chat card never shows raw tool input', () => {
  const context = { sessionDatasets: [{ id: 'b9ce582c-fded-4db5-838f-bdd96820f72c', name: '0.jpeg', type: 'jpeg' }] };
  it('a dataset id becomes the dataset name (live screenshot input)', () => {
    expect(toolCallDisplayFor({ galaxy_dataset_id: 'b9ce582c-fded-4db5-838f-bdd96820f72c' }, context)).toBe('0.jpeg');
  });
  it('an unknown id is dropped, never shown', () => {
    expect(toolCallDisplayFor({ galaxy_dataset_id: 'f0f0f0f0-1111-2222-3333-444455556666' }, context)).toBe('');
    expect(toolCallDisplayFor({ dataset_id: '0123456789abcdef0123' }, context)).toBe('');
  });
  it('storage URIs reduce to the file name; queries are kept; code is skipped', () => {
    expect(toolCallDisplayFor({ path: 's3://bucket/uploads/u1/sample_metadata.csv' })).toBe('sample_metadata.csv');
    expect(toolCallDisplayFor({ query: 'CRISPR screen QC metrics', n_results: 5 })).toBe('CRISPR screen QC metrics');
    expect(toolCallDisplayFor({ code: 'import os\nprint(1)', language: 'python' })).toBe('python');
  });
});

import { attachmentLocalId, modelFacingUploads } from './galaxy-assistant';
import { redactInternalBackend, userFacingToolOutput } from '../shared/tool-call-display';
import { redactStoragePaths } from './execution-integrity';

describe('the response model never sees the backend name (founder 2026-11-12: "there should not have galaxy in output")', () => {
  const block = '分析一下这张图\n\n[Uploaded datasets: 0.jpeg: dataset_id=11111111-2222-3333-4444-555555555555, galaxy_dataset_id=b9ce582c-fded-4db5-838f-bdd96820f72c, s3_uri=s3://bucket/uploads/u/0.jpeg; notes.txt: dataset_id=n/a, galaxy_dataset_id=f00df00df00df00d]';
  it('upload block: one neutral dataset_id per file (the backend id, as staging uses), no galaxy key', () => {
    const out = modelFacingUploads(block);
    expect(out).not.toMatch(/galaxy/i);
    expect(out).toContain('0.jpeg: dataset_id=b9ce582c-fded-4db5-838f-bdd96820f72c, s3_uri=s3://bucket/uploads/u/0.jpeg');
    expect(out).toContain('notes.txt: dataset_id=f00df00df00df00d');
    expect(out.startsWith('分析一下这张图')).toBe(true);
  });
  it('a block with only a BioMate dataset id keeps it', () => {
    expect(modelFacingUploads('[Uploaded datasets: a.csv: dataset_id=abc-1]')).toBe('[Uploaded datasets: a.csv: dataset_id=abc-1]');
  });
  it('read_file maps the model-facing id back to the local copy, this turn or an earlier one', () => {
    expect(attachmentLocalId('b9ce582c-fded-4db5-838f-bdd96820f72c', { turnMessage: block })).toBe('11111111-2222-3333-4444-555555555555');
    expect(attachmentLocalId('b9ce582c-fded-4db5-838f-bdd96820f72c', { turnMessage: 'next question', previousMessages: [{ role: 'user', content: block }] }))
      .toBe('11111111-2222-3333-4444-555555555555');
    expect(attachmentLocalId('unknown', { turnMessage: block })).toBeUndefined();
  });
});

describe('reply guard: the backend is never named to the user', () => {
  it('strips backend id fields and neutralises backend nouns (en + zh)', () => {
    expect(redactInternalBackend('Reading galaxy_dataset_id=b9ce582c-fded-4db5-838f-bdd96820f72c now')).toBe('Reading now');
    expect(redactInternalBackend('Your file is in the Galaxy history.')).toBe('Your file is in your data.');
    expect(redactInternalBackend('The Galaxy history holds it; the Galaxy backend stores it.')).toBe('Your data holds it; BioMate stores it.');
    expect(redactInternalBackend('我已把文件存入 Galaxy 历史', true)).toBe('我已把文件存入 你的数据');
    expect(redactInternalBackend('the galaxy_dataset_id field')).toBe('the dataset ID field');
  });
  it('leaves the Galaxy platform itself alone (a user may ask about it)', () => {
    expect(redactInternalBackend('You can import a Galaxy workflow (.ga) from Settings.')).toBe('You can import a Galaxy workflow (.ga) from Settings.');
  });
  it('runs inside redactStoragePaths, the reply choke point, outside code blocks only', () => {
    expect(redactStoragePaths('Saved to the Galaxy history: s3://b/u/x/report.png\n```\ngalaxy_dataset_id = 1\n```'))
      .toBe('Saved to your data: report.png\n```\ngalaxy_dataset_id = 1\n```');
  });
  it('tool output in the card: id / backend keys dropped, UUIDs and storage URIs cleaned', () => {
    expect(userFacingToolOutput({ galaxy_dataset_id: 'b9ce582c-fded-4db5-838f-bdd96820f72c', name: 'x.csv', path: 's3://b/k/x.csv', lines: ['a,b'] }))
      .toEqual({ name: 'x.csv', path: 'x.csv', lines: ['a,b'] });
    expect(userFacingToolOutput('Dataset not found in Galaxy history')).toBe('Dataset not found in your data');
  });
});

describe('legacy attachment lines in older histories', () => {
  it('[Galaxy dataset: …] is rewritten before it reaches the model', () => {
    expect(modelFacingUploads('[Galaxy dataset: gse22055_expression.csv (id: f796f3f2)]'))
      .toBe('[Dataset: gse22055_expression.csv (dataset_id: f796f3f2)]');
  });
});
