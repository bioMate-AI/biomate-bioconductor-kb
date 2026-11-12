import { describe, expect, it } from 'vitest';
import { chatOutputFolderName, formatStamp } from './chat-output-folder';

describe('per-chat output folder (founder: outputs of different chats were indistinguishable)', () => {
  const at = new Date('2026-11-12T08:28:00Z');
  it('chat title + start time in the user time zone', () => {
    expect(chatOutputFolderName({ title: 'ground_truth_admet.csv：对此文件运行质量控制', createdAt: at, timeZone: 'Asia/Shanghai', zh: true }))
      .toBe('ground_truth_admet.csv：对此文件运行质… · 2026-11-12 16.28');
  });
  it('unsafe characters removed; generic titles get a neutral name; bad zone → UTC', () => {
    expect(chatOutputFolderName({ title: 'a/b:c', createdAt: at, timeZone: 'Not/AZone' })).toBe('a b c · 2026-11-12 08.28');
    expect(chatOutputFolderName({ title: 'New Chat', createdAt: at, zh: true })).toBe('对话 · 2026-11-12 08.28');
    expect(formatStamp(at, 'America/Chicago')).toBe('2026-11-12 02.28');
  });
});
