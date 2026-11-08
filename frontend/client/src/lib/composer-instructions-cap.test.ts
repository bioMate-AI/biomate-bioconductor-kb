import { describe, it, expect } from 'vitest';
import fs from 'fs';
import path from 'path';

// Guard: the composer textarea's maxLength (client) must equal the server's trim cap, or a long
// paste is hard-stopped at one length and silently sliced at another. Mirror-test pattern (see
// chat-input.attached-count.test.tsx for MAX_DATASET_REFS). Underscore digit separators normalised.
describe('composer instructions cap — client maxLength mirrors the server trim', () => {
  it('COMPOSER_INSTRUCTIONS_MAX === MAX_COMPOSER_INSTRUCTIONS_LENGTH', () => {
    const clientSrc = fs.readFileSync(path.join(__dirname, '..', 'components', 'chat-input.tsx'), 'utf-8');
    const serverSrc = fs.readFileSync(path.join(__dirname, '..', '..', '..', 'server', 'chat-context.ts'), 'utf-8');
    const client = clientSrc.match(/COMPOSER_INSTRUCTIONS_MAX\s*=\s*([\d_]+)/)?.[1]?.replace(/_/g, '');
    const server = serverSrc.match(/MAX_COMPOSER_INSTRUCTIONS_LENGTH\s*=\s*([\d_]+)/)?.[1]?.replace(/_/g, '');
    expect(client).toBeDefined();
    expect(server).toBeDefined();
    expect(client).toBe(server);
  });
});
